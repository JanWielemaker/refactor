/*  Part of Refactoring Tools for SWI-Prolog

    Author:        Edison Mera Menendez
    E-mail:        efmera@gmail.com
    WWW:           https://github.com/edisonm/refactor, http://www.swi-prolog.org
    Copyright (C): 2013, Process Design Center, Breda, The Netherlands.

    This program is free software; you can redistribute it and/or
    modify it under the terms of the GNU General Public License
    as published by the Free Software Foundation; either version 2
    of the License, or (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public
    License along with this library; if not, write to the Free Software
    Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301  USA

    As a special exception, if you link this library with other files,
    compiled with a Free Software compiler, to produce an executable, this
    library does not by itself cause the resulting executable to be covered
    by the GNU General Public License. This exception does not however
    invalidate any other reasons why the executable file might be covered by
    the GNU General Public License.
*/

:- module(refactor, [refactor/2,
		     rename_variable/4,
		     replace_term/4,
		     replace_goal/4,
		     replace_sentence/3,
		     expand_term/5,
		     expand_goal/5,
		     expand_sentence/4,
		     replace_term_id/4,
		     unfold_goal/3,
		     rename_predicate/3,
		     rename_functor/4,
		     refactor_context/2,
		     remove_useless_exports/2,
		     replace_conjunction/4,
		     replace_conjunction/5
		    ]).

:- use_module(library(readutil)).
:- use_module(library(prolog_codewalk)).
:- use_module(library(file_changes)).
:- use_module(library(term_info)).
:- use_module(library(gcb)).
:- use_module(library(maplist_dcg)).

:- thread_local file_commands_db/2.

:- meta_predicate
	refactor(1,+),
	expand_term(+,+,-,0,+),
	expand_sentence(+,-,0,+),
	expand_goal(?,:,-,0,+),
	unfold_goal(?,0,+).

refactor(Rule, Action) :-
    call(Rule, FileChanges),
    do_file_changes(Action, FileChanges).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Most used refactoring scenarios:
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
remove_useless_exports(Module, Action) :-
    expand_sentence(Module:(:-module(M,L)), (:- module(M,N)),
		    ( include(being_used(Module), L, N),
		      L \= N
		    ), Action),
    expand_sentence(Module:(:-export(K)), Exp,
		    ( once(list_sequence(L, K)),
		      include(being_used(Module), L, N),
		      ( N = []           -> Exp = '$RM'
		      ; L \= N, list_sequence(N,S), Exp = (:- export(S))
		      )
		    ), Action).

list_sequence([], []).
list_sequence([E|L], S) :- list_sequence_2(L, E, S).

list_sequence_2([E|L], E0, (E0, S)) :- list_sequence_2(L, E, S).
list_sequence_2([], E, E).

being_used(M, F/A) :-
    functor(H, F, A),
    predicate_property(C:H, imported_from(M)), C \== user.

% :- regtype t_action/1.
% t_action(save).
% t_action(show).

%% rename_variable(?Sentence, +Name0:atom, +Name:atom, +Action:t_action) is det.

rename_variable(M:Sent,Name0,Name,Action) :-
    expand_sentence(M:Sent, Sent,
		    ( refactor_context(variable_names, Dict),
		      \+ memberchk(Name =_,Dict),
		      memberchk(Name0='$VAR'(Name),Dict)
		    ), Action).

/*
rename_variable(MSent,Name0,Name,Action) :-
    expand_term(MSent,Var,'$VAR'(Name),
		( refactor_context(variable_names, Dict),
		  \+ memberchk(Name =_,Dict), var(Var),
		  memberchk(Name0=V,Dict),V==Var
		), Action).
*/

rename_functor(Caller, Functor/Arity, NewName, Action) :-
    functor(Term, Functor, Arity),
    Term =.. [_|Args],
    Expansion =.. [NewName|Args],
    replace_term_id(Caller, Term, Expansion, Action).

replace_term_id(Caller, Term, Expansion, Action) :-
    replace_term(Caller, Term, Expansion, Action),
    functor(Term, F0, A0),
    functor(Expansion, F, A),
    replace_term(Caller, F0/A0, F/A, Action).

% BUG: This have to be applied only once --EMM
:- meta_predicate rename_predicate(+,+,+).
rename_predicate(M:Name0/Arity, Name, Action) :-
    functor(H0, Name0, Arity),
    H0 =.. [Name0|Args],
    H  =.. [Name|Args],
    replace_goal(_, M:H0, H, Action), % Replace calls
    % Replace heads:
    expand_sentence(_:(  H0 :- B),   (H :- B), true, Action),
    expand_sentence(_:(M:H0 :- B), (M:H :- B), true, Action),
    expand_sentence(_:H0, H, true, Action),
    expand_sentence(_:(M:H0), (M:H), true, Action),
    replace_term(M:_, Name0/Arity, Name/Arity, Action). % Replace PIs

replace(Level, Sentence, From, Into, Action) :-
    expand(Level, Sentence, From, Into, true, Action).

:- meta_predicate replace_term(?,?,?,+).
replace_term(Caller, Term, Expansion, Action) :-
    replace(term, Caller, Term, Expansion, Action).

replace_sentence(M:Term, Expansion, Action) :-
    replace(sent, M:Term, Term, Expansion, Action).

:- meta_predicate replace_goal(?,0,?,+).
replace_goal(Caller, Term, Expansion, Action) :-
    replace(goal, Caller, Term, Expansion, Action).

:- meta_predicate expand(+,?,?,?,0,-).
% Expander(+Caller, ?Term, -Pattern, -Expansion)
expand(Level, Caller, Term, Into, Expander, Action) :-
    refactor(meta_expansion(Level, Caller, Term, Into, Expander), Action).

%%	expand_term(?Sentence, ?Term, ?Replacement, :Expander, +Action)

expand_term(Caller, Term, Into, Expander, Action) :-
    expand(term, Caller, Term, Into, Expander, Action).

%%	expand_sentence(?Sentence, ?Into, :Expander, +Action).
%
% TODO:
% \footnote{Further versions will allow
%   \predref{expand\_sentence}{3} to return a list, as
%   \predref{term\_expansion}{2} does in many Prolog dialects.}

expand_sentence(M:Term, Into, Expander, Action) :-
    expand(sent, M:Term, Term, Into, Expander, Action).

expand_goal(Caller, Goal, Into, Expander, Action) :-
    expand(goal, Caller, Goal, Into, Expander, Action).

% NOTE: Only works if exactly one clause match
unfold_goal(Module, MGoal, Action) :-
    findall(clause(MGoal, Body0), clause(MGoal, Body0), [clause(MGoal, Body0)]),
    MGoal = M:_,
    (Module == M -> Body = Body0 ; Body = M:Body),
    replace_goal(Module:_, MGoal, Body, Action).

:- meta_predicate replace_conjunction(?, ?, ?, 0, +).
replace_conjunction(Sentence, Conj, Replacement, Expander, Action) :-
    expand_term(Sentence, Conj, Replacement, Expander, Action),
    extend_conj(Conj, Rest, Conj2),
    extend_conj(Replacement, Rest, Replacement2),
    expand_term(Sentence, Conj2, Replacement2, Expander, Action).

replace_conjunction(Sentence, Conj, Replacement, Action) :-
    replace_conjunction(Sentence, Conj, Replacement, true, Action).

extend_conj(Var, Rest, (Var,Rest)) :- var(Var), !.
extend_conj((A,C0), Rest, (A,C)) :- !, extend_conj(C0, Rest, C).
extend_conj(Last, Rest, (Last,Rest)).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

curr_style(Style, CurrStyle) :-
    arg(1, Style, Name),
    ( style_check(?(Name))
    ->CurrStyle = +Name
    ; CurrStyle = -Name
    ).

:- meta_predicate with_styles(0, +).
with_styles(Goal, StyleL) :-
    maplist(curr_style, StyleL, OldStyleL),
    setup_call_cleanup(maplist(style_check, StyleL),
		       Goal,
		       maplist(style_check, OldStyleL)).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% RULES (1st argument of refactor/2):
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

:- meta_predicate meta_expansion(+,?,?,-,0,-).

%%	meta_expansion(+Level, +Sentence, +Term, +Into,
%%		       :Expander, -FileChanges) is det
%
%	Expand  terms  that  subsume  Term  in  sentences  that  subsume
%	Sentence into Into if Expander is true.

meta_expansion(Level, Caller, Term, Into, Expander, FileChanges) :-
    with_styles(collect_expansion_commands(Level, Caller, Term, Into,
					   Expander, FileCommands),
		[-atom, -singleton]), % At this point we are not interested in styles
    apply_file_commands(FileCommands, FileChanges).

collect_expansion_commands(goal, Caller, Term, Into, Expander, FileCommands) :-
    prolog_walk_code(
	[ trace_reference(Term),
	  infer_meta_predicates(false),
	  evaluate(false),
	  on_trace(collect_file_commands(Caller, Term, Into, Expander))
	]),
    findall(F-C, retract(file_commands_db(F, C)), FileCommands).
collect_expansion_commands(term, Caller, Term, Into, Expander, FileCommands) :-
    collect_ec_term_level(term, Caller, Term, Into, Expander, FileCommands).
collect_expansion_commands(sent, Caller, Term, Into, Expander, FileCommands) :-
    collect_ec_term_level(sent, Caller, Term, Into, Expander, FileCommands).

collect_ec_term_level(Level, Caller, Term, Into, Expander, FileCommands) :-
    findall(File-Commands, ec_term_level_each(Level, Caller, Term, Into,
					      Expander, File, Commands),
	    FileCommands).

ec_term_level_each(Level, M:SentPattern, Term, Into, Expander,
		   File, Commands) :-
    refactor_module(M),
    get_term_info(M, SentPattern, Sent, File,
		  [ variable_names(Dict),
		    subterm_positions(TermPos)
		  ]),
    with_sentence(with_dict(phrase(substitute_term_level(Level, Sent, 1200, Term,
							 Into, Expander, TermPos),
				   Commands, []),
			    Dict),
		  Sent-SentPattern).

substitute_term_level(term, Sent, Priority, Term, Into, Expander, TermPos) -->
    substitute_term_rec(Sent, Priority, Term, Into, Expander, TermPos).
substitute_term_level(sent, Sent, Priority, Term, Into, Expander, TermPos) -->
    substitute_term_norec(Sent, Priority, Term, Into, Expander, TermPos).

:- meta_predicate with_dict(0, +).
with_dict(Goal, Dict) :-
    with_context_vars(Goal, [refactor_variable_names], [Dict]).

:- meta_predicate with_pattern_into(0, ?, ?).
with_pattern_into(Goal, Pattern, Into) :-
    with_context_vars(Goal, [refactor_pattern, refactor_into], [Pattern, Into]).

:- meta_predicate with_sentence(0, ?).
with_sentence(Goal, Sent) :-
    with_context_vars(Goal, [refactor_sentence], [Sent]).

:- meta_predicate with_context_vars(0, +, +).
with_context_vars(Goal, NameL, ValueL) :-
    setup_call_cleanup(maplist(b_setval, NameL, ValueL),
		       Goal,
		       maplist(nb_delete, NameL)).


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% ANCILLARY PREDICATES:
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

apply_file_commands(Pairs, FileChanges) :-
    keysort(Pairs, Sorted),
    group_pairs_by_key(Sorted, Grouped),
    findall(Compact, ( member(Group, Grouped),
		       compact_group(Group, Compact)),
	    Compacted),
    maplist(apply_commands, Compacted, FileChanges).

compact_group(Key-LList, Key-Uniques) :-
    append(LList, List),
    List \== [],
    sort(List, Uniques).

apply_commands(File-Commands, File-Changes) :-
    read_file_to_codes(File, Text, []),
    with_context_vars(maplist_dcg(apply_change,
				  Commands,
				  text_desc(0, Text, Changes),
				  text_desc(_, Remaining, Remaining)),
		      [refactor_text, refactor_file],
		      [Text, File]).

% apply_pos_changes(Changes) -->
%     maplist_dcg(apply_change, Changes).

%%	refactor_module(?M)
%
%	True when M is a module we should refactor.

refactor_module(M) :-
    current_module(M),
    M \= user,			% Dubious --JW
    module_property(M, class(user)).


%%	refactor_context(?Name, ?Value) is nondet.

refactor_context(variable_names, VarNames) :-
    b_getval(refactor_variable_names, VarNames).
refactor_context(pattern, Pattern) :-
    b_getval(refactor_pattern, Pattern).
refactor_context(into, Into) :-
    b_getval(refactor_into, Into).
refactor_context(sentence, Sentence) :-
    b_getval(refactor_sentence, Sentence).

:- meta_predicate with_context(?, ?, ?, ?, ?, 0).
with_context(Src, Pattern0, Into0, Pattern1, Into2, Goal) :-
    copy_term(Pattern0-Into0, Pattern1-Into1),
    refactor_context(sentence, Sent-Sent),
    Pattern0 = Src,
    with_pattern_into(Goal, Pattern1, Into1), % Allow changes in Pattern/Into
    term_variables(Pattern1, Vars), % Variable bindings in Pattern
    copy_term(Pattern1-Vars, Pattern0-Vars0),
    pairs_keys_values(Pairs, Vars0, Vars),
    map_subterms(Pairs, Into0, Into1, Into2).

map_subterms(Pairs, T0, T1, T) :-
    ( member(X0-X, Pairs),
      X==T1
    ; member(X0-X, Pairs),
      same_term(X0, T0) % ===/2
    ),
    !,
    (T0==T1 -> T = X0 ; T = X).
map_subterms(Pairs, T0, T1, T) :-
    compound(T0), !,
    functor(T0, F, N),
    functor(T1, F, N),
    functor(T,  F, N),
    T0 =.. [F|Args0],
    T1 =.. [F|Args1],
    T  =.. [F|Args],
    maplist(map_subterms(Pairs), Args0, Args1, Args).
map_subterms(_, T, _, T).

select_multi(Term, Var) --> ({occurrences_of_var(Var, Term, 1)} -> [] ; [Var]).

%%	substitute_term_norec(+Term, +Priority, +Pattern, -Into, :Expander, +TermPos)// is nondet.
%
%	None-recursive version of substitute_term_rec//6.

substitute_term_norec(Term, Priority, Pattern, Into, Expander, TermPos) -->
    { refactor_context(sentence, Sent-SentPattern),
      subsumes_term(SentPattern-Pattern, Sent-Term),
      copy_term(Term, Term2),
      with_context(Term, Pattern, Into, Pattern1, Into1, Expander),
      greatest_common_binding(Pattern1, Into1, Pattern2, Into2, [], Unifier, []),
      unlinked_vars(Pattern2-Unifier, Into2, UVars),
      maplist_dcg(select_multi(Into2), UVars, MVars, []),
      numbervars(UVars-MVars, 0, _, [singletons(true)])
    },
    substitute_term(Priority, Term, Term2, Pattern2, Into2, Unifier, TermPos).

%%	substitute_term(+Priority, +SrcTerm, +Pattern, +Into, +Unifier, +TermPos)
%
%	Substitute occurences of Pattern with Into after calling
%	expansion.
%
%	@param SrcTerm is the term as read from the source
%	@param TermPos is the term layout of SrcTerm
%	@param Priority is the environment operator priority
%	@param Unifier contains bindings between Pattern and Into

non_singleton(L, V1-V2) -->
    ( { var(V1),
	var(V2),
	( occurrences_of_var(V2, L, 1)
	; occurrences_of_var(V1, L, 1)
	)
      }
    ->{V1=V2}
    ; [V1=V2]
    ).

unifier(Term1, Term2, L) :-
    term_variables(Term1, Var1),
    copy_term(Term1-Var1, Term2-Var2),
    pairs_keys_values(L, Var1, Var2).

gcbl(V=T0, V=T, gcb(Term0, BL0), gcb(Term, BL)) :-
    greatest_common_binding(Term0, T0, Term, T, [], BL0, BL).

get_position_gterm(Term, Pos, GTerm, T, GPos, G) :-
    subterm_location_eq(L, T, Term),
    subpos_location(L, Pos, GPos),
    subterm_location(L, G, GTerm).

substitute_term(Priority, Term, Term2, Pattern2, Into2, BindingL, TermPos) -->
    { copy_term(Term2, GTerm),
      unifier(Term2, Term, UL0),
      maplist_dcg(non_singleton(UL0), UL0, UL1, []),
      maplist_dcg(gcbl, UL1, UL2, gcb(Term2, UL), gcb(Term3, UL2)),
      with_context_vars(subst_term(TermPos, Pattern2, GTerm, Term3),
			[refactor_bind],
			[BindingL]),
      maplist(subst_unif(Term3, TermPos, GTerm), UL),
      maplist(subst_fvar(Term3, TermPos, GTerm), UL0)
    },
    !,
    [print(TermPos, Priority, Pattern2, Into2)].

subst_unif(Term, Pos, GTerm, V=T) :-
    ( get_position_gterm(Term, Pos, GTerm, V, GPos, G),
      GPos \= none
    ->V='$sb'(GPos, G, T)
    ; V=T
    ).

subst_fvar(Term, Pos, GTerm, V-T) :-
    ( var(V),
      V==T,
      get_position_gterm(Term, Pos, GTerm, V, GPos, G) ->
      V='$sb'(GPos, G)
    ; true
    ).
    
subtract_eq([], _, []).
subtract_eq([Elem0|T], L, Set0) :-
    ( member(Elem, L),
      Elem0 == Elem ->
      Set0 = Set
    ; Set0 = [Elem0|Set]
    ),
    subtract_eq(T, L, Set).

unlinked_vars(Term, Into, Vars) :-
    term_variables(Term, VTerm),
    term_variables(Into, VInto),
    subtract_eq(VInto, VTerm, Vars).

subst_args(N, Term, GTerm, CTerm, [ArgPos|SubPos]) :-
    arg(N, Term,  Arg),
    !,
    arg(N, GTerm, GArg),
    arg(N, CTerm, CArg),
    subst_term(ArgPos, Arg, GArg, CArg),
    succ(N, N1),
    subst_args(N1, Term, GTerm, CTerm, SubPos).
subst_args(_, _, _, _, _).

subst_list([], _, Tail, E, G, C) :-
    subst_term(Tail, E, G, C).
subst_list([Pos|Poss], To, Tail, Term, GTerm, CTerm) :-
    ( var(Term) ->
      arg(1, Pos, EFrom),
      succ(From, EFrom),
      PosL = list_position(From, To, [Pos|Poss], Tail),
      subst_var(PosL, Term, GTerm, CTerm)
    ; Term  = [E|Es],
      GTerm = [G|Gs],
      CTerm = [C|Cs],
      subst_term(Pos, E, G, C),
      subst_list(Poss, To, Tail, Es, Gs, Cs)
    ).

subst_var(Pos, Var, GTerm, CTerm) :-
    ( b_getval(refactor_bind, BindingL),
      member(V=T, BindingL),
      V==Var
    ->subst_term(Pos, T, GTerm, CTerm)
    ; true
    ),
    Var = '$sb'(Pos, GTerm, CTerm).

%%	subst_term(+Position, +Pattern, +Vars, +Term)
%
%	Here, Pattern is a term  that   holds  variables.  It is matched
%	against a position term and  if  there   is  a  variable  in the
%	pattern, this is unified to   a  '$sb'(Pos, SubTerm),
%	indicating that this position currently holds SubTerm.
%
%	@param Position is a subterm-position term for Term
%	@param Term is a source term
%	@param Pattern is a substitution pattern

subst_term(none, T, _, T) :- !.
subst_term(Pos, Term, GTerm, CTerm) :-
    var(Term),
    !,
    subst_var(Pos, Term, GTerm, CTerm).
subst_term(_, '$sb'(_, _, _), _, _) :- !. % Avoid aliasing loops
subst_term(term_position(_, _, _, _, CP), Term, GTerm, CTerm) :-
    compound(CTerm), % Would have been substituted
    !,
    subst_args(1, Term, GTerm, CTerm, CP).
subst_term(brace_term_position(_, _, CP), {Term}, {GTerm}, {CTerm}) :- !,
    subst_term(CP, Term, GTerm, CTerm).
subst_term(list_position(_, To, Elms, Tail), Term, GTerm, CTerm) :- !,
    subst_list(Elms, To, Tail, Term, GTerm, CTerm).
subst_term(_, _, _, _).

%%	substitute_term_rec(+SrcTerm, +Priority, +Pattern, -Into, :Expander, +TermPos)// is nondet.
%
%	True when the DCG list contains   a  substitution for Pattern by
%	Into in SrcTerm. This predicate must  be cautious about handling
%	bindings:
%
%	  - Overall bindings do not affect further substitutions because
%	    we are managed by findall/3 in collect_expansion_commands/6.
%	  - Pattern must not be instantiated by either unification with
%	    SrcTerm or the execution of Expander.  This is needed for
%	    substitute_term/7 to find the correct replacements.
%
%	To avoid binding Pattern, we need to copy Pattern and Into while
%	maintaining sharing with Expander.  Next,   we  can safely unify
%	Pattern with the SrcTerm.

substitute_term_rec(Term, Priority, Pattern, Into, Expander, TermPos) -->
    substitute_term_norec(Term, Priority, Pattern, Into, Expander, TermPos),
    !.
substitute_term_rec(Term, _, Ref, Into, Expander, TermPos) -->
    substitute_term_into(TermPos, Term, Ref, Into, Expander).

substitute_term_into(brace_term_position(_, _, Pos), {Term},
		     Ref, Into, Expander) -->
    substitute_term_rec(Term, 1200, Ref, Into, Expander, Pos).
substitute_term_into(term_position(_, _, _, _, CP), Term, Ref,
		     Into, Expander) --> !,
    substitute_term_args(CP, 1, Term, Ref, Into, Expander).
substitute_term_into(list_position(_, _, EP, TP), Term, Ref,
		     Into, Expander) --> !,
    substitute_term_list(EP, TP, Term, Ref, Into, Expander).

:- use_module(library(listing), []).

term_priority(Term, N, Priority) :-
    nonvar(Term),
    functor(Term, F, A),
    ( ( A == 1 ->
	( prolog_listing:prefix_op(F, Priority) -> true
	; prolog_listing:postfix_op(F, Priority) -> true
	)
      ; A == 2 ->
	prolog_listing:infix_op(F, Left, Right),
	( N==1 -> Priority = Left
	; N==2 -> Priority = Right
	)
      ) -> true
    ; Priority = 1200
    ).

substitute_term_args([PA|PAs], N0, Term, Ref, Into, Expander) -->
    ( {arg(N0, Term, Arg)},
      {term_priority(Term, N0, Priority)},
      substitute_term_rec(Arg, Priority, Ref, Into, Expander, PA)
    ; {N is N0 + 1},
      substitute_term_args(PAs, N, Term, Ref, Into, Expander)
    ).

substitute_term_list([EP|EPs], TP, [Elem|Term], Ref, Into, Expander) -->
    ( {term_priority([_|_], 1, Priority)},
      substitute_term_rec(Elem, Priority, Ref, Into, Expander, EP)
    ; substitute_term_list(EPs, TP, Term, Ref, Into, Expander)
    ).
substitute_term_list([], TP, Tail, Ref, Into, Expander) -->
    {term_priority([_|_], 2, Priority)},
    substitute_term_rec(Tail, Priority, Ref, Into, Expander, TP).

:- public collect_file_commands/7.
:- meta_predicate collect_file_commands(?,?,0,?,?,?).

%%	collect_file_commands(+Sentence, +Pattern, +Into, :Expander,
%%			      +Callee, +Caller, +Location)
%
%	Called from prolog_walk_code/1 on a call  from Caller to Callee.
%	The parameters Sentence to Expander are provided by the on_trace
%	closure  passed  to  prolog_walk_code/1.    Callee,  Caller  and
%	Location are added by prolog_walk_code/1.

collect_file_commands(CallerPattern, Pattern, Into, Expander,
		      Callee, Caller, From) :-
    subsumes_term(CallerPattern-Pattern, Caller-Callee),
    ( From = clause_term_position(ClauseRef, TermPos0) ->
      clause_property(ClauseRef, file(File))
    ; From = file_term_position(File, TermPos0) -> true
    ; print_message(error, acheck(refactor(Callee, From))),
      fail
    ),
    Callee = M:Term0,
    trim_term(Term0, Term, TermPos0, TermPos),
    Pattern = M:Pattern2,
    with_sentence(with_dict(substitute_term_norec(Term, 1200, Pattern2, Into,
						  Expander, TermPos, Commands,
						  []),
			    []),
		  Caller-CallerPattern),
    assertz(file_commands_db(File, Commands)).

:- multifile
    prolog:message//1,
    prolog:message_location//1.

prolog:message(acheck(refactor(Goal, From))) -->
    prolog:message_location(From),
    ['Unable to refactor ~w, no term position information available'-[Goal], nl].

trim_term(Term, TTerm,
	  term_position(From, To, FFrom, FTo, SubPos),
	  term_position(From, To, FFrom, FTo, TSubPos)) :-
    Term =.. [F|Args],
    trim_term_list(SubPos, Args, TSubPos, TArgs),
    TTerm =.. [F|TArgs].

trim_term_list([], ArgsL, [], ArgsL).
trim_term_list([0-0|SubPosL], [_|Args], TSubPosL, TArgsL) :- !,
    trim_term_list(SubPosL, Args, TSubPosL, TArgsL).
trim_term_list([SubPos|SubPosL], [Arg|Args], [SubPos|TSubPosL], [Arg|TArgsL]) :-
    trim_term_list(SubPosL, Args, TSubPosL, TArgsL).

valid_op_type_arity(xf,  1).
valid_op_type_arity(yf,  1).
valid_op_type_arity(xfx, 2).
valid_op_type_arity(xfy, 2).
valid_op_type_arity(yfx, 2).
valid_op_type_arity(fy,  1).
valid_op_type_arity(fx,  1).

refactor_hack('$LIST'(_)).
refactor_hack('$LIST,'(_)).
refactor_hack('$LIST,_'(_)).
refactor_hack('$TEXT'(_)).
refactor_hack('$TEXT'(_,_)).
refactor_hack('$BODY'(_)).
refactor_hack('$BODY'(_,_)).
refactor_hack('$NL'(_)).
refactor_hack('$,NL'(_)).
refactor_hack('$RM').

cut_text(Pos0, Pos, Remaining0, Remaining, Text) :-
    ( Pos > Pos0 ->
      Seek is Pos - Pos0,
      length(Text, Seek),
      append(Text, Remaining, Remaining0)
    ; Remaining0 = Remaining,
      Text = ""
    ).

:- public rportray/2.
rportray('$sb'(ArgPos, GTerm, Term), Opt) :-
    Pos0=0,
    b_getval(refactor_text, Text),
    memberchk(priority(Priority), Opt),
    (prolog_listing:term_needs_braces(Term, Priority) -> write('(') ; true),
    print_expansion('$sb'(ArgPos, GTerm, Term), _, _,
		    Priority, Pos0, Text),
    (prolog_listing:term_needs_braces(Term, Priority) -> write(')') ; true),
    !.
rportray('$sb'(TermPos, _GTerm), _Opt) :-
    Pos=0,
    b_getval(refactor_text, Text),
    print_subtext(TermPos, Pos, Text).
rportray('$sb'(_, _, _), _) :- !.
rportray('$LIST'(L), Opt) :- !,
    maplist(term_write(Opt), L).
rportray('$LIST,'(L), Opt) :- !,
    term_write_comma_list(L, Opt).
rportray('$LIST,_'(L), Opt) :- !,
    maplist(term_write_comma_2(Opt), L).
rportray('$TEXT'(T), Opt0) :- !,
    subtract(Opt0, [quoted(true), portray_goal(_), priority(_)], Opt),
    write_term(T, Opt).
rportray('$BODY'(B, Offs), Opt) :- !,
    memberchk(priority(N), Opt),
    Pos = 0,
    write_b(B, N, Offs, Pos).
rportray('$BODY'(B), Opt) :- !,
    memberchk(priority(N), Opt),
    Pos = 0,
    write_b(B, N, 0, Pos).
rportray([E|T0], Opt) :- !,
    append(H, T1, [E|T0]),
    ( var(T1) -> !,
      fail
    ; T1 = '$sb'(TermPos, GTerm, Term),
      is_list(Term),
      compound(TermPos),
      !,
      arg(1, TermPos, TFrom),
      arg(2, TermPos, TTo),
      succ(TFrom, From),
      succ(To, TTo),
      T2 = '$sb'(From-To, GTerm, Term),
      ( Term == []
      ->T = H,
	write('['),
	term_write_comma_list(T, Opt),
	write_term(T2, Opt),
	write(']')
      ; append(H, [T2], T),
	write_term(T, Opt)
      )
    ).

term_write(Opt, Term) :- write_term(Term, Opt).

term_write_comma_list([], _).
term_write_comma_list([T|L], Opt) :-
    write_term(T, Opt),
    maplist(term_write_comma_(Opt), L).

term_write_comma_(Opt, Term) :- write(', '), write_term(Term, Opt).

term_write_comma_2(Opt, Term) :- write_term(Term, Opt), write(', ').

:- use_module(library(listing),[]).

apply_change(print(TermPos, Priority, Pattern, Term),
	     text_desc(Pos0, Text0, Tail0),
	     text_desc(To,   Text,  Tail)) :-
    with_output_to(codes(Tail1, Tail),
		   print_expansion_0(Term, Pattern, TermPos, Priority,
				     Pos0, Text0, From, To)),
    cut_text(Pos0, From, Text0, Text1, CutText),
    append(CutText, Tail1, Tail0), % Accept
    cut_text(From, To, Text1, Text, _). % Skip

print_expansion_0(Term, Pattern, TermPos, Priority, Pos, Text, From, To) :-
    ( nonvar(Term) ->
      print_expansion_1(Term, Pattern, TermPos, Priority, Pos, Text, From, To)
    ; print_expansion_2(Term, Pattern, TermPos, Priority, Pos, Text, From, To)
    ).

% Hacks that can only work at 1st level:
% BUG: assuming no spaces between Term, full stop and new line:
print_expansion_1('$RM', _, TermPos, _, _, _, From, To) :- !,
    arg(1, TermPos, From),
    arg(2, TermPos, To0),
    To is To0 + 2.
print_expansion_1('$TEXT'(Term, Delta), _, TermPos, _, _, _, From, To) :- !,
    arg(1, TermPos, From),
    arg(2, TermPos, To0),
    write_t(Term),
    To is To0 + Delta.
print_expansion_1(Term, Pattern, TermPos, Priority, Pos, Text, From, To) :-
    print_expansion_2(Term, Pattern, TermPos, Priority, Pos, Text, From, To).

print_expansion_2(Term, Pattern, TermPos, Priority, Pos, Text, From, To) :-
    arg(1, TermPos, From),
    arg(2, TermPos, To),
    print_expansion(Term, Pattern, TermPos, Priority, Pos, Text).

%% print_expansion(?Term:term, N:integer, File:atom, Pos0:integer, SkipTo:integer, Pos:integer).

print_expansion(Var, _, RefPos, _, Pos0, Text) :-
    var(Var),
    !,
    print_subtext(RefPos, Pos0, Text).
print_expansion('$sb'(RefPos, _), _, _, _, Pos0, Text) :-
    print_subtext(RefPos, Pos0, Text).
print_expansion('$sb'(RefPos, GTerm, Term), _, _, Priority, Pos0, Text) :-
    !,
    ( \+subsumes_term(Term, GTerm)
    ->print_expansion(Term, Term, RefPos, Priority, Pos0, Text)
    ; print_subtext(RefPos, Pos0, Text)
    ).
print_expansion('$,NL', Pattern, RefPos, Priority, Pos0, Text) :-
				% Print a comma + indented new line
    write(','),
    print_expansion('$NL', Pattern, RefPos, Priority, Pos0, Text).
print_expansion('$NL', _, _, _, Pos0, _) :- % Print an indented new line
    b_getval(refactor_file, File),
    prolog_codewalk:filepos_line(File, Pos0, _, LinePos),
    nl,
    line_pos(LinePos).
print_expansion(Term, Pattern, RefPos0, Priority, Pos0, Text) :-
    compound(Term),
    Term \== Pattern,
    subterm_location_eq(L, Term, Pattern),
    subpos_location(L, RefPos0, RefPos),
    !,
    print_expansion(Term, Term, RefPos, Priority, Pos0, Text).
print_expansion(Term, Pattern, RefPos, Priority, Pos0, Text) :-
    ( print_expansion_pos(RefPos, Term, Pattern, Priority, Pos0, Text)
    ->true
    ; write_r(Priority, Term)
    ).

print_expansion_pos(term_position(From, To, _, _, PosL),
		    Term, Pattern, Priority, Pos0, Text) :-
    compound(Term),
    functor(Term,    F, A),
    functor(Pattern, F, A),
    from_to_pairs(PosL, From, FTo, FromToL),
    Term    =.. [_|ArgL0],
    Pattern =.. [_|PatL0],
    length(PosL, N),
    trim_list(N, ArgL0, ArgL),
    trim_list(N, PatL0, PatL),
    !,
    maplist(print_expansion_arg(Priority, Pos0, Text), FromToL, PosL, ArgL, PatL),
    display_subtext(Pos0, Text, FTo, To).
print_expansion_pos(list_position(From, To, PosL, PosT),
		    Term, Pattern, Priority, Pos0, Text) :-
    from_to_pairs(PosL, From, FTo, FromToL),
    length(PosL, N),
    trim_list(N, Term,    ArgL, ATail),
    trim_list(N, Pattern, PatL, PTail),
    !,
    maplist(print_expansion_arg(Priority, Pos0, Text), FromToL, PosL, ArgL, PatL),
    ( PosT \= none ->
      arg(1, PosT, PTo),
      print_expansion_arg(Priority, Pos0, Text, FTo-PTo, PosT, ATail, PTail),
      arg(2, PosT, PFrom),
      display_subtext(Pos0, Text, PFrom, To)
    ; display_subtext(Pos0, Text, FTo, To)
    ).
print_expansion_pos(brace_term_position(From, To, TermPos),
		    {Term}, {Pattern}, Priority, Pos, Text) :-
    arg(1, TermPos, AFrom),
    arg(2, TermPos, ATo),
    print_expansion_arg(Priority, Pos, Text, From-AFrom, TermPos, Term, Pattern),
    display_subtext(Pos, Text, ATo, To).

print_subtext(RefPos, Pos0, Text) :-
    arg(1, RefPos, From),
    arg(2, RefPos, To),
    display_subtext(Pos0, Text, From, To).

trim_list(N, L0, L) :-
    trim_list(N, L0, L, _).

trim_list(N, L0, L, T) :-
    length(L, N),
    append(L, T, L0).

print_expansion_arg(Priority, Pos0, Text, From-To, RefPos, Term, Pattern) :-
    display_subtext(Pos0, Text, From, To),
    print_expansion(Term, Pattern, RefPos, Priority, Pos0, Text).

from_to_pairs([], To, To, []).
from_to_pairs([Pos|PosL], From0, To, [From0-To0|FromToL]) :-
    arg(1, Pos, To0),
    arg(2, Pos, From1),
    from_to_pairs(PosL, From1, To, FromToL).

subterm_location_eq([],    Find, Term) :- Find==Term.
subterm_location_eq([N|L], Find, Term) :-
    compound(Term),
    arg(N, Term, SubTerm),
    subterm_location_eq(L, Find, SubTerm).

subterm_location([],    Term, Term).
subterm_location([N|L], Find, Term) :-
    compound(Term),
    arg(N, Term, SubTerm),
    subterm_location(L, Find, SubTerm).

location_subpos(term_position(_, _, _, _, PosL), N, Pos) :-
    nth1(N, PosL, Pos).
location_subpos(list_position(From, To, PosL, Tail), N, Pos) :-
    ( N = 1
    ->PosL = [Pos|_]
    ; N = 2
    ->( PosL = [_]
      ->Pos = Tail
      ; PosL = [_|PosL1],
	Pos = list_position(From, To, PosL1, Tail)
      )
    ).
location_subpos(brace_term_position(_, _, Pos), 1, Pos).

subpos_location([],    Pos,    Pos).
subpos_location([N|L], SubPos, Pos) :-
    location_subpos(SubPos, N, Pos0),
    subpos_location(L, Pos0, Pos).

display_subtext(Pos0, Text0, From, To) :-
    PosCut is From - Pos0,
    length(Cut, PosCut),
    append(Cut, Text1, Text0),
    LPaste is To - From,
    length(Paste, LPaste),
    append(Paste, _, Text1),
    maplist(put_char, Paste).

bin_op(Term, Op, Left, Right, A, B) :-
    nonvar(Term),
    functor(Term, Op, N),
    N == 2,
    prolog_listing:infix_op(Op, Left, Right),
    arg(1, Term, A),
    arg(2, Term, B).

write_b(Term, N, Offs, Pos0) :-
    ( prolog_listing:term_needs_braces(Term, N)
    -> write('( '),
      Pos is Pos0 + 2,
      write_b1(Term, N, Offs, Pos),
      write(')')
    ; write_b1(Term, N, Offs, Pos0)
    ).

and_layout(T) :- T = (_,_).

write_b1(Term, _, Offs, Pos) :-
    prolog_listing:or_layout(Term), !,
    write_b_layout(Term, or,  Offs, Pos).
write_b1(Term, _, Offs, Pos) :-
    and_layout(Term), !,
    write_b_layout(Term, and, Offs, Pos).
write_b1(Term, N, _, _) :- write_r(N, Term).

write_b_layout(Term, Layout, Offs, Pos) :-
    bin_op(Term, Op, Left, Right, A, B),
    !,
    write_b(A, Left, Offs, Pos),
    b_getval(refactor_file, File),
    prolog_codewalk:filepos_line(File, Pos, _, LinePos0),
    LinePos is Offs + LinePos0,
    nl_indent(Layout, Op, LinePos),
    write_b(B, Right, Offs, Pos).

nl_indent(or, Op, LinePos0) :-
    nl,
    LinePos is max(0, LinePos0 - 2),
    line_pos(LinePos),
    write(Op),
    write(' ').
nl_indent(and, Op, LinePos) :-
    write(Op),
    nl,
    line_pos(LinePos).

line_pos(0) :- !.
line_pos(LinePos) :-
    LinePos >= 8,
    !,
    write('\t'),
    LinePos1 is LinePos - 8,
    line_pos(LinePos1).
line_pos(LinePos) :-
    LinePos >= 1,
    write(' '),
    LinePos1 is LinePos - 1,
    line_pos(LinePos1).

write_t(Term) :-
    write_term(Term, [spacing(next_argument), numbervars(true)]).

write_r(N, Term) :-
    Options = [portray_goal(rportray),
	       spacing(next_argument),
	       numbervars(true),
	       quoted(true),
	       priority(N)],
    write_term(Term, Options).



/*
  set_position_if_available(GVar) :-
    b_getval(refactor_gterm, GTerm),
    subterm_location_eq(L, GVar, GTerm),
    b_getval(refactor_pos, Pos),
    subpos_location(L, Pos, GPos),
    b_getval(refactor_term, Term),
    subterm_location(L, CVar, Term),
    CVar = '$sb'(GPos, GVar, _).

% mapterm(Goal, Term) :-
%     ( call(Goal, Term) *-> true
%     ; mapterm_into(Goal, Term)
%     ).
    
% mapterm_into(Goal, Term) :-
%     compound(Term),
%     !,
%     mapterm_arg(1, Term, Goal).

% mapterm_arg(N, Term, Goal) :-
%     arg(N, Term, Arg),
%     !,
%     mapterm(Goal, Arg),
%     N1 is N + 1,
%     mapterm_arg(N1, Term, Goal).
% mapterm_arg(_, _, _).

      %% Although the next options are a bit clumsy, work:
      % ; get_position(CTerm, GPos) ->
      % 	Var = '$sb'(GPos, GTerm, GTerm)
      ; 
	member(V-T, Unifier),
      	V==CTerm,
      	( get_position_gterm(T, GPos, G)
	->subst_term(GPos, CTerm, G, T)
	% ; subst_into(T, V)
	)
      ; member(V-T, Unifier),
	contains_var(V, CTerm) ->
	( get_position_gterm(T, GPos, G)
	->subst_term(GPos, V, G, T)
	)
	% subterm_location_eq(L, V, CTerm),
	% get_position_gterm(T, GPos, G)
      
	
	% term_variables(GTerm, GVars),
      	% maplist(set_position_if_available, GVars)
      % ; term_variables(CTerm, CVars),
      % 	maplist(set_position_if_available, CVars),
      % 	Var = '$sb'(Pos, GTerm, CTerm)
      ) -> true
*/

/*
get_position_gterm(T, GPos, G) :-
    b_getval(refactor_term, Term),
    b_getval(refactor_pos, Pos),
    b_getval(refactor_gterm, GTerm),
    get_position_gterm(Term, Pos, GTerm, T, GPos, G).

subst_term2(CTerm0, CTerm) :-
    b_getval(refactor_unif, Unifier),
    ( member(V-T, Unifier),
      ( occurrences_of_var(V, CTerm0, N)
      ; occurrences_of_var(T, CTerm0, N)
      ),
      N > 0
    ->( member(V-T, Unifier),
	V==CTerm0
      ->subst_term2(T,      CTerm)
      ; subst_term2_(CTerm0, CTerm)
      )
    ; CTerm0 = CTerm
    ).

subst_term2_(CTerm0, CTerm) :-
    ( get_position_gterm(CTerm0, GPos, G),
      GPos \= none
    ->subst_term2__(CTerm0, CTerm1),
      CTerm = '$sb'(GPos, G, CTerm1)
    ; subst_term2__(CTerm0, CTerm)
    ).

subst_term2__(CTerm0, CTerm) :-
    compound(CTerm0),
    !,
    functor(CTerm0, F, A),
    functor(CTerm,  F, A),
    CTerm0 =.. [_|CArgL0],
    CTerm  =.. [_|CArgL],
    maplist(subst_term2, CArgL0, CArgL).
subst_term2__(T, T).

print_expansion(Term,   N, _) --> {var(Term), !, write_r(N, Term)}, [].
print_expansion('$BODY'(Term), N, Pos) --> % Print as a body
    {write_b(Term, N, 0, Pos)}.
print_expansion('$LIST'(List), N, Pos0) -->
    print_expansion_list(List, N, Pos0).
print_expansion('$LIST,'(List), N, Pos0) -->
    print_expansion_list_comma(List, N, Pos0).
print_expansion('$LIST,_'(List), N, Pos0) -->
    print_expansion_list_comma_2(List, N, Pos0).
print_expansion('$TEXT'(Term), N, Pos0) -->
    print_expansion('$TEXT'(Term, 0), N, Pos0).
print_expansion(Term, N, _) --> {write_r(N, Term)}.

print_expansion_list([], _, _) --> [].
print_expansion_list([T|L], N, Pos0) -->
    print_expansion(T, N, Pos0),
    print_expansion_list(L, N, Pos0).

print_expansion_list_comma([], _, _) --> [].
print_expansion_list_comma([T|L], N, Pos0) -->
    print_expansion(T, N, Pos0),
    print_expansion_list_comma_(L, N, Pos0).

print_expansion_list_comma_2([], _, _) --> [].
print_expansion_list_comma_2([T|L], N, Pos0) -->
    print_expansion(T, N, Pos0),
    {write(', ')},
    print_expansion_list_comma_2(L, N, Pos0).

print_expansion_list_comma_([], _, _) --> [].
print_expansion_list_comma_([T|L], N, Pos0) -->
    {write(', ')},
    print_expansion(T, N, Pos0),
    print_expansion_list_comma_(L, N, Pos0).

o_length(T, N) :-
    o_length(T, 0, N).

o_length(V, N, N) :- var(V), !.
o_length([_|T], N0, N) :- !,
    N1 is N0 + 1,
    o_length(T, N1, N).
o_length(_, N, N).
*/
/*
expansion_commands_term(_, _, _, Pattern, Expansion) --> {Pattern==Expansion}, !.
expansion_commands_term(brace_term_position(_, _, ArgPos), {Term}, Priority,
			{Pattern}, Expansion) -->
    { nonvar(Expansion),
      {Arg} = Expansion
    },
    !,
    expansion_commands_term(ArgPos, Term, Priority, Pattern, Arg).
expansion_commands_term(term_position(From, _, _, FTo, _),
			(_, Term), Priority, (_, Pattern), Expansion) -->
    {write(Term),nl,Pattern == Expansion}, !,
    [From-[print(Priority, '$TEXT'(''), [], FTo)]].
expansion_commands_term(term_position(_, _, FFrom, FTo, SubPos),
			Term, Priority, Pattern, Expansion) -->
    { nonvar(Expansion),
      Expansion \= '$sb'(_, _),
      functor(Term, FP, A),
      functor(Pattern, FP, A),
      Pattern \= '$sb'(_, _),
      \+ refactor_hack(Expansion),
      functor(Expansion, FE, A)
    },
    ( {FP==FE}
    ->[] %% Do nothing to preserve functor layout
    ; { FP\=FE,
	valid_op_type_arity(TypeOp, A),
	current_op(PrecedenceP, TypeOp, FP),
	current_op(PrecedenceE, TypeOp, FE),
	( PrecedenceP >= PrecedenceE
	; \+ current_op(PrecedenceP, _, FP),
	  \+ current_op(PrecedenceE, _, FE)
	)
      }
    ->{refactor_context(variable_names, Dict)},
      [FFrom-[print(Priority, FE, Dict, FTo)]]
    ),
    expansion_commands_args(1, Term, Pattern, Expansion, SubPos).
expansion_commands_term(list_position(_, _, Elms, TailPos), Term, _, Pattern,
			Expansion) -->
    { nonvar(Expansion),
      Expansion \= '$sb'(_, _),
      functor(Term, FP, A),
      functor(Pattern, FP, A),
      Pattern \= '$sb'(_, _),
      term_priority([_|_], 1, Priority)
    },
    expansion_commands_list(Elms, TailPos, Term, Priority, Pattern, Expansion),
    !.
expansion_commands_term(none, _, _, _, _) --> !, [].
expansion_commands_term(TermPos, Bindings, Term, Priority, Pattern, Expansion) -->
				% Overwrite layout
    ( { arg(1, TermPos, From),	% BUG: can drop comments
	arg(2, TermPos, To),
	refactor_context(variable_names, Dict),
	maplist(apply_name, Dict),
	numbervars(Term, 0, _, [singletons(true)])
      },     % No minimization is possible, rewrite the hole expansion:
      [From-[print(TermPos, Bindings, Term, Priority, Pattern, Expansion, To)]]
    ).

apply_name(Name=Value) :- ignore(Value='$VAR'(Name)).


% expansion_commands_list(_TermPos, _TailPos, Term, _, _Pattern, Expansion) -->
%     {Term == Expansion}, !, [].
expansion_commands_list([], TailPos, Term, _, Pattern, Expansion) -->
    {term_priority([_|_], 2, Priority)},
    !,
    expansion_commands_term(TailPos, Term, Priority, Pattern, Expansion).
expansion_commands_list([Pos|Poss], TailPos, Term, Priority, Pattern, Expansion) -->
    { nonvar(Expansion),
      Term = [T|Ts],
      Pattern = [P|Ps],
      Expansion = [E|Es]
    },
    !,
    expansion_commands_term(Pos,  T,           Priority, P,  E),
    expansion_commands_list(Poss, TailPos, Ts, Priority, Ps, Es).

expansion_commands_args(N, Term, Pattern, Expansion, [ArgPos|SubPos]) -->
    { arg(N, Pattern, PArg), !,
      arg(N, Expansion, EArg),
      arg(N, Term, TArg),
      term_priority(Term, N, Priority)
    },
    expansion_commands_term(ArgPos, TArg, Priority, PArg, EArg),
    {succ(N, N1)},
    expansion_commands_args(N1, Term, Pattern, Expansion, SubPos).
expansion_commands_args(_, _, _, _, _) --> [].
*/

