:- module(gcb, [greatest_common_binding/6, substitute_list/3]).

greatest_common_binding(Term0, Into0, Term, Into) -->
    ( {var(Term0);var(Into0)} ->
      {Term=Term0, Into=Into0}
    ; {substitute(Var=Term0, Into0, Into),
       Into0\==Into} ->
      [Var=Term0],
      {Term=Var}
    ; greatest_common_binding(1, Term0, Into0, Term, Into),
      {Into0\==Into}
    ->[]
    ; {Term=Term0, Into=Into0}
    ).

greatest_common_binding(N, Term0, Into0, Term, Into) -->
    {arg(N, Term0, Arg)},
    !,
    pick_tail(Tail),
    greatest_common_binding(Arg, Into0, _, Into1),
    {substitute_olist(Tail, Term0, Term1)},
    {succ(N, N1)},
    greatest_common_binding(N1, Term1, Into1, Term, Into).
greatest_common_binding(_, Term, Into, Term, Into) --> [].

substitute_olist(Tail) --> {var(Tail)}, !.
substitute_olist([Subst|Tail]) -->
    substitute(Subst),
    substitute_olist(Tail).

substitute(Var=Val, Term0, Term) :-
    ( Term0 == Val -> Term = Var
    ; var(Term0) -> Term = Term0
    ; functor(Term0, F, A),
      functor(Term,  F, A),
      substitute(1, Var=Val, Term0, Term)
    ).

substitute(N, Subst, Term0, Term) :-
    arg(N, Term0, Arg0),
    !,
    substitute(Subst, Arg0, Arg),
    arg(N, Term, Arg),
    succ(N, N1),
    substitute(N1, Subst, Term0, Term).
substitute(_, _, _, _).

substitute_list([Subst|Tail]) -->
    substitute(Subst),
    substitute_list(Tail).
substitute_list([]) --> [].

pick_tail(Tail, Tail, Tail).
