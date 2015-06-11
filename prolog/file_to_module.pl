/*  Part of Refactoring Tools for SWI-Prolog

    Author:        Edison Mera Menendez
    E-mail:        efmera@gmail.com
    WWW:           https://github.com/edisonm/refactor, http://www.swi-prolog.org
    Copyright (C): 2015, Process Design Center, Breda, The Netherlands.

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

:- module(file_to_module, [file_to_module/1, file_to_module/2]).

:- use_module(library(clambda)).
:- use_module(library(normalize_head)).
:- use_module(library(extra_location)).
:- use_module(library(location_utils)).
:- use_module(library(from_utils)).
:- use_module(library(infer_alias)).
:- use_module(library(implementation_module)).
:- use_module(library(list_sequence)).
:- use_module(library(sequence_list)).
:- use_module(library(module_files)).
:- use_module(library(audit/audit_codewalk)).

:- dynamic
    module_to_import_db/5.

file_to_module(Alias) :-
    file_to_module(Alias, []).

implementation_decl(dynamic).
implementation_decl(discontiguous).
implementation_decl(volatile).
implementation_decl(thread_local).
implementation_decl(clause(_)).

collect_not_exported(M, FileL, PIL, PIEx) :-
    findall(PI,
	    ( PI=F/A,
	      member(PI, PIL),
	      functor(H, F, A),
	      \+ ( loc_declaration(H, M, export, From),
		   from_to_file(From, File),
		   memberchk(File, FileL)
		 )
	    ), PIEx).

files_to_move(M, File, [File|FileL]) :-
    module_file(M, File),
    findall(IFile, file_includes(File, IFile), FileL).

file_includes(File, IFile) :-
    source_file_property(File, includes(Incl, _)),
    ( IFile = Incl
    ; file_includes(Incl, IFile)
    ).

file_to_module(Alias, OptionL0 ) :-
    select_option(module(M),         OptionL0, OptionL1, M),
    select_option(exclude(ExcludeL), OptionL1, OptionL2, []),
    select_option(addcl(AddL),       OptionL2, OptionL3, []),
    select_option(delcl(DelL),       OptionL3, _,        []),
    absolute_file_name(Alias, File, [file_type(prolog), access(read)]),
    files_to_move(M, File, FileL),
    format('% from context ~a~n', [M]),
    collect_predicates_to_move(FileL, M, ExcludeL, PIL),
    report_dispersed_assertions(PIL, FileL, M),
    collect_multifile(M, FileL, PIL, PIM),
    declare_multifile(PIM, FileL),
    directory_file_path(_, Name, File),
    file_name_extension(Base, _, Name),
    add_qualification_head(FileL, M, PIM),
    file_to_module(FileL, M, PIL, ExcludeL, MDL),
    collect_not_exported(M, FileL, PIL, PIEx),
    append(AddL, MDL, CL),
    replace_sentence([], [(:- module(Base, PIEx))|CL], [file(File)]),
    forall(member(C, DelL), replace_sentence(C, [], [file(File)])),
    decl_to_use_module(consult, M, FileL, PIL, Alias),
    decl_to_use_module(include, M, FileL, PIL, Alias),
    add_use_module(M, FileL, ExcludeL, Alias),
    add_use_module_ex(M, FileL),
    del_use_module_ex(M, FileL).

collect_multifile(M, FileL, PIL, PIM) :-
    findall(F/A, ( member(F/A, PIL),
		   functor(H, F, A),
		   findall(DFile,
			   ( property_from((M:H)/_, clause(_), PFrom),
			     from_to_file(PFrom, DFile)
				% DFile \= File
			   ), DFileU),
		   once(( member(File, FileL),
			  memberchk(File, DFileU)
			)),
		   sort(DFileU, DFileL),
		   DFileL = [_, _|_],
		   \+ ( loc_declaration(H, M, multifile, From),
			from_to_file(From, File)
		      )
				% \+ predicate_property(M:H, multifile)
		 ), PIM).

declare_multifile(PIM, FileL) :-
    ( PIM \= []
    ->replace_sentence((:- multifile PIL),
		       (:- multifile(NPIM)),
		       append(PIL, '$LIST,NL'(PIM), NPIM),
		       [max_changes(1), changes(C), files(FileL)]),
      ( C = 0
      ->replace_sentence([],
			 (:- multifile('$LIST,NL'(PIM))),
			 [max_changes(1), files(FileL)])
      ; true
      )
    ; true
    ).

add_qualification_head(FileL, M, PIM) :-
    forall(member(F/A, PIM),
	   ( functor(H, F, A),
	     replace_head(H, M:H, [module(M), files(FileL)])
	   )).

add_use_module(M, FileL, ExcludeL, Alias) :-
    findall(CM-(F/A),
	    ( ( module_to_import_db(F, A, M, CM, File),
		memberchk(File, FileL)
	      ; implem_to_export(FileL, F, A, M, CM)
	      ),
	      \+ memberchk(F/A, ExcludeL),
	      CM \= M
	    ),
	    CMPIU),
    sort(CMPIU, CMPIL),
    group_pairs_by_key(CMPIL, CMPIG),
    forall(member(CM-PIL, CMPIG),
	   add_use_module_cm(M, Alias, CM, PIL)).

add_use_module_cm(M, Alias, CM, PIL) :-
    module_property(CM, file(MFile)),
    replace_sentence((:- module(CM, MEL)),
		     [(:- module(CM, MEL)),
		      (:- use_module(Alias))],
		     [file(MFile)]),
    module_property(M, file(MainF)),
    replace_sentence((:- use_module(MainA, ExL)),
		     Into,
		     ( absolute_file_name(MainA,
					  MainF1,
					  [file_type(prolog),
					   access(read)]),
		       MainF1=MainF,
		       subtract(ExL, PIL, ExL2),
		       ( ExL2 \= []
		       ->Into = (:- use_module(MainA, '$LISTB,NL'(ExL2)))
		       ; Into = []
		       )
		     ),
		     [module(CM)]).

declared_use_module(F, A, IM, M, EA, File) :-
    module_property(IM, file(ImplFile)),
    ( module_property(IM, exports(ExL)),
      loc_declaration(EA, M, use_module, From)
    ; loc_declaration(use_module(EA, ExL), M, use_module_2, From)
    ),
    absolute_file_name(EA, EFile, [file_type(prolog), access(read)]),
    EFile = ImplFile,
    memberchk(F/A, ExL),
    from_to_file(From, File).

del_use_module_ex(M, FileL) :-
    replace_sentence((:- use_module(EA)),
		     [],
		     ( absolute_file_name(EA,
					  ImplementFile,
					  [file_type(prolog),
					   access(read)]),
		       module_property(IM, file(ImplementFile)),
		       \+ ( module_to_import_db(F, A, IM, M, File),
			    memberchk(File, FileL)
			  )
		     ),
		     [files(FileL)]),
    replace_sentence((:- use_module(EA, IL)),
		     Into,
		     ( absolute_file_name(EA,
					  ImplementFile,
					  [file_type(prolog),
					   access(read)]),
		       module_property(IM, file(ImplementFile)),
		       findall(F/A,
			       ( module_to_import_db(F, A, IM, M, File),
				 memberchk(File, FileL)
			       ), PIL),
		       intersection(IL, PIL, NIL),
		       ( NIL = []
		       ->Into = []
		       ; Into = (:- use_module(EA, NIL))
		       )
		     ),
		     [files(FileL)]).

add_use_module_ex(M, FileL) :-
    findall(ImportingFile-((IM:EA)-(F/A)),
	    [M, FileL, ImportingFile, IM, EA, F, A] +\
	    ( module_to_import_db(F, A, IM, M, ImportingFile),
	      \+ declared_use_module(F, A, IM, M, _, ImportingFile),
	      declared_use_module(F, A, IM, M, EA, File),
	      memberchk(File, FileL),
	      absolute_file_name(EA,
				 ImplementFile,
				 [file_type(prolog),
				  access(read)]),
	      module_property(IM, file(ImplementFile))
	    ),
	    FileAliasPIU),
    sort(FileAliasPIU, FileAliasPIL),
    group_pairs_by_key(FileAliasPIL, FileAliasPIG),
    forall(member(ImFile-AliasPIL, FileAliasPIG),
	   add_use_module_ex_1(M, ImFile, AliasPIL)).

add_use_module_ex_1(M, ImFile, AliasPIL) :-
    group_pairs_by_key(AliasPIL, AliasPIG),
    findall(Decl,
	    ( member((IM:Alias)-PIL, AliasPIG),
	      module_property(IM, exports(ExL)),
	      ( member(F/A, ExL),
		module_to_import_db(F, A, OM, M, ImFile),
		OM \= IM
	      ->Decl = (:- use_module(Alias, PIL))
	      ; Decl = (:- use_module(Alias))
	      )
	    ),
	    DeclL, Tail),
    ( DeclL == Tail
    ->true
    ; Tail = [],
      replace_sentence((:- module(ImM, Ex)),
		       [(:- module(ImM, Ex))|DeclL],
		       [max_changes(1), changes(C), file(ImFile)]),
      C \= 0
    ->true
    ; Term = (:- Decl),
      Tail = [Term],
      replace_sentence(Term, DeclL,
		       memberchk(Decl, [use_module(_), use_module(_,_)]),
		       [max_changes(1), changes(C), file(ImFile)]),
      C \= 0
    ->true
    ; Tail = [],
      replace_sentence([], DeclL, [max_changes(1), file(ImFile)])
    ).

decl_to_use_module(Decl, M, FileL, PIL, Alias) :-
    findall(DFile, ( extra_location(Alias, M, Decl, DFrom),
		     from_to_file(DFrom, DFile)
		   ), DFileU),
    sort(DFileU, DFileL),
    Patt =.. [Decl, Alias],
    module_property(M, exports(EL1)),
    findall(PI, ( PI=F/A,
		  member(PI, EL1),
		  functor(H, F, A),
		  loc_declaration(H, M, export, From),
		  from_to_file(From, FileX),
		  \+ memberchk(FileX, FileL)
		), EL),
    intersection(PIL, EL, ReexportL),
    ( ReexportL = []
    ->Into = (:- use_module(Alias))
    ; module_property(M, file(MFile)),
      replace_sentence((:- module(M, MEL)), (:- module(M, '$LISTB,NL'(NL))),
			( subtract(MEL, ReexportL, NL),
			  NL \= MEL
			), [file(MFile)]),
      ( PIL = ReexportL
      ->Into = (:- reexport(Alias))
      ; subtract(PIL, ReexportL, ExportL),
	( ExportL = []
	->Into = (:- reexport(Alias, '$LISTB,NL'(ReexportL)))
	; Into = [(:- use_module(Alias)),
		  (:- reexport(Alias, '$LISTB,NL'(ReexportL)))]
	)
      )
    ),
    replace_sentence((:- Patt), Into, [files(DFileL)]).

implem_to_export(FileL, F, A, M, CM) :-
    ( loc_dynamic(H, M, dynamic(_, CM, _), FromD),
      from_to_file(FromD, FileD),
      \+ memberchk(FileD, FileL),
      ( loc_declaration(H, M, D, From),
	implementation_decl(D),
	from_to_file(From, File),
	memberchk(File, FileL)
      ->true
      ; loc_declaration(H, M, D, From),
	implementation_decl(D),
	from_to_file(From, FileE),
	\+ memberchk(FileE, FileL)
      ->fail
      ; loc_dynamic(H, M, dynamic(_, M, _), From),
	from_to_file(From, File),
	memberchk(File, FileL)
      ->true
      )
    ; loc_declaration(H, M, export, From),
      from_to_file(From, FileX),
      \+ memberchk(FileX, FileL),
      once(( property_from((M:H)/_, clause(_), PFrom),
	     from_to_file(PFrom, File),
	     memberchk(File, FileL)
	   )),
      M=CM
    ),
    functor(H, F, A).

report_dispersed_assertions(PIL, FileL, M) :-
    collect_dispersed_assertions(PIL, FileL, M, PIA),
    ( PIA \= []
    ->print_message(warning,
		    format('Assertions for ~w needs to be relocated', [PIA]))
    ; true
    ).

collect_dispersed_assertions(PIL, FileL, M, PIA) :-
    findall(F/A, ( member(F/A, PIL),
		   functor(H, F, A),
		   loc_declaration(H, M, assertion(_, _), FromD),
		   once(( property_from((M:H)/_, clause(_), PFrom),
			  from_to_file(PFrom, File),
			  memberchk(File, FileL)
			)),
		   from_to_file(FromD, FileD),
		   \+ memberchk(FileD, FileL)
		 ), PIUA),
    sort(PIUA, PIA).

collect_predicates_to_move(FileL, M, ExcludeL, PIL) :-
    OptionL = [source(false), trace_reference(_)],
    retractall(module_to_import_db(_, _, _, _, _)),
    audit_walk_code(OptionL, collect_dynamic_locations(M, File), _, _),
    audit_walk_code(OptionL, collect_file_to_module, _, _),
    findall(F/A, ( module_to_import_db(F, A, M, _, IFile),
		   \+ memberchk(IFile, FileL),
		   implemented_in_file(F, A, M, File),
		   memberchk(File, FileL)
		 ; implem_to_export(FileL, F, A, M, _)
		 ), PIU),
    sort(PIU, PIS),
    subtract(PIS, ExcludeL, PIL).

implemented_in_file(F, A, M, File) :-
    functor(Goal, F, A),
    property_from((M:Goal)/_, Decl, PFrom),
    implementation_decl(Decl),
    from_to_file(PFrom, File).

% file_to_module(+list(atm),+atm,+list,+list,-list) is det.
%
file_to_module(FileL, M, PIL, ExcludeL, MDL) :-
    findall(EM-(F/A), ( module_to_import_db(F, A, EM, M, File),
			memberchk(File, FileL),
			functor(H, F, A),
			implemented_in_file(F, A, EM, IFile),
			\+ memberchk(IFile, FileL),
			\+ memberchk(F/A, PIL),
			\+ memberchk(F/A, ExcludeL)
		      ), MU, MD),
    findall(EM-(F/A), ( loc_dynamic(H, EM, dynamic(_, M, _), From),
			from_to_file(From, File),
			memberchk(File, FileL),
			( loc_declaration(H, EM, D, FromD),
			  implementation_decl(D),
			  from_to_file(FromD, FileD),
			  memberchk(FileD, FileL)
			->fail
			; ( loc_declaration(H, EM, D, FromD),
			    implementation_decl(D)
			  ; loc_dynamic(H, EM, dynamic(Type, _, _), FromD),
			    memberchk(Type, [retract, def])
			  ),
			  from_to_file(FromD, FileD),
			  \+ memberchk(FileD, FileL)
			->true
			),
			functor(H, F, A)
		      ), MD),
    sort(MU, ML),
    group_pairs_by_key(ML, GL),
    findall(F/A, ( loc_dynamic(H, M, dynamic(_, _, _), FromD),
		   from_to_file(FromD, FileD),
		   \+ memberchk(FileD, FileL),
		   ( loc_declaration(H, M, D, _),
		     implementation_decl(D)
		   ->fail
		   ; loc_dynamic(H, M, dynamic(_, M, _), From),
		     from_to_file(From, File),
		     memberchk(File, FileL)
		   ->true
		   ),
		   functor(H, F, A)
		 ), PIUD),
    sort(PIUD, PID),
    ( PID = []
    ->DYL = []
    ; list_sequence(PID, PIS),
      DYL = [(:- dynamic(PIS))]
    ),
    findall((:- Decl),
	    ( member(EM-PEL, GL),
	      findall(PPI,
		      ( PPI=FF/AA,
			member(PPI, PEL),
			functor(HH, FF, AA),
			\+ predicate_property(EM:HH, exported),
			( predicate_property(EM:HH, D),
			  implementation_decl(D)
			->true
			; property_from((EM:HH)/_, clause(_), PFrom),
			  from_to_file(PFrom, _PFile)
			->true
			)
		      ), REL),
	      current_module(EM, EF),
	      smallest_alias(EF, EA),
	      \+ black_list_um(EA),
	      add_export_declarations_to_file(REL, FileL, EM),
	      ( EM=M, REL \= []
	      ->print_message(warning,
			      format("Back imports is a bad sign: ~w",
				     [(:- use_module(EA, REL))]))
	      ; true
	      ),
	      \+ ( loc_declaration(EA, _, use_module, UMFrom),
		   from_to_file(UMFrom, File),
		   memberchk(File, FileL)
		 ),
	      ( Decl = use_module(EA)
	      ; ( EM = M,
		  PEL \= REL,
		  REL \= []
		->Decl=use_module(EA, REL) % Explicit imports --EMM
		)
	      )
	    ), MDL, DYL).

add_export_declarations_to_file(REL, FileL, M) :-
    findall(File-PI,
	    ( PI = F/A,
	      member(PI, REL),
	      functor(H, F, A),
	      property_from(M:H, _, From),
	      from_to_file(From, File),
	      \+ memberchk(File, FileL)
	    ), FilePIU),
    sort(FilePIU, FilePIL),
    group_pairs_by_key(FilePIL, FilePIG),
    forall(member(File-PIL, FilePIG),
	   ( module_property(M, file(File))
	   ->replace_sentence((:- module(M, L0 )),
			      (:- module(M, L)),
			      append(L0, PIL, L),
			      [file(File)])
	   ; replace_sentence((:- export(S)),
			      (:- export('$LIST,NL'([S|PIL]))),
			      [max_changes(1), changes(C), file(File)]),
	     C \= 0
	   ->true
	   ; replace_sentence([],
			      (:- export('$LIST,NL'(PIL))),
			      [file(File)])
	   )).

black_list_um(swi(_)).		% Ignore internal SWI modules
black_list_um(library(dialect/_)).

collect_dynamic_locations(M, File, MGoal, _, From) :-
    nonvar(MGoal),
    from_to_file(From, File),	% match the file
    record_location_dynamic(MGoal, M, From).

collect_file_to_module(Callee, _Caller, From) :-
    Callee = CM:Goal,
    implementation_module(Callee, IM),
    functor(Goal, F, A),
    from_to_file(From, File),
    ( module_to_import_db(F, A, IM, CM, File) -> true
    ; assertz(module_to_import_db(F, A, IM, CM, File))
    ). 
