/*  Part of Refactoring Tools for SWI-Prolog

    Author:        Edison Mera Menendez
    E-mail:        efmera@gmail.com
    WWW:           https://github.com/edisonm/refactor
    Copyright (C): 2017, Process Design Center, Breda, The Netherlands.
    All rights reserved.

    Redistribution and use in source and binary forms, with or without
    modification, are permitted provided that the following conditions
    are met:

    1. Redistributions of source code must retain the above copyright
       notice, this list of conditions and the following disclaimer.

    2. Redistributions in binary form must reproduce the above copyright
       notice, this list of conditions and the following disclaimer in
       the documentation and/or other materials provided with the
       distribution.

    THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
    "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
    LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS
    FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE
    COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT,
    INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING,
    BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
    LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
    CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
    LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN
    ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
    POSSIBILITY OF SUCH DAMAGE.
*/

:- module(i18n_trans, [translate/4,
                       translate/5,
                       translate_po/4,
                       rename_id/4,
                       replace_entry_po/4,
                       i18n_refactor/4]).

:- use_module(library(ref_changes)).
:- use_module(library(ref_replacers)).
:- use_module(library(i18n/i18n_file_utils)).
:- use_module(library(i18n/i18n_parser)).
:- use_module(library(i18n/i18n_support)).

% :- pred translate(+,+,?,?,+).
translate(M, Lang, TermEngl, TermLang, OptionL) :-
    translate_po(M, Lang, TermEngl, TermLang),
    replace_term(TermLang, TermEngl, [module(M)|OptionL]).

translate(M, Lang, EnglLangL, OptionL) :-
    forall(member(Engl-Lang, EnglLangL),
           translate_po(M, Lang, Engl, Lang)),
    replace_term(TermLang, TermEngl,
                 ( member(TermEngl-Lang, EnglLangL),
                   TermLang=@=Lang,
                   TermLang=Lang
                 ), [module(M)|OptionL]).

translate_po(M, Lang, TermEngl, TermLang) :-
    i18n_refactor(update_po_entry(Lang), M, TermLang, TermEngl).

%!  rename_id(?Module, +OldTerm, +NewTerm, +OptionL) is det.
%
%   Change an English Term by another and update its key in the po files.
rename_id(M, OldTerm, NewTerm, OptionL) :-
    i18n_refactor(rename_id_lang, M, OldTerm, NewTerm),
    replace_term(OldTerm, NewTerm, [module(M)|OptionL]).

% TODO: optimize
:- meta_predicate replace_entry_po(+,+,+,2).
replace_entry_po(M, MsgId0, MsgId, StrReplacer) :-
    freeze(MsgStr0, call(StrReplacer, MsgStr0, MsgStr)),
    findall(PoFile-Codes,
            ( current_po_file(M, '??', PoFile),
              read_po_file(PoFile, Entries0),
              replace_entry(M, MsgId0, MsgStr0, MsgId, MsgStr, Entries0, Entries),
              parse_po_entries(Entries, Codes, [])
            ), FileCodes),
    save_changes(FileCodes).

:- meta_predicate i18n_refactor(3,+,+,+).

i18n_refactor(PoUpdater, M, Term0, Term) :-
    i18n_to_translate(Term0, _, KeysValues, []),
    i18n_to_translate(Term,  _, ValuesKeys, []),
    pairs_keys_values(KeysValues, MsgId0, MsgId),
    pairs_keys_values(ValuesKeys, MsgId,  MsgId0),
    call(PoUpdater, M, MsgId0, MsgId).

update_po_entry(Lang, M, MsgStr, MsgId) :-
    update_po_entry(Lang, M, MsgStr, MsgId, MsgStr).

update_po_entry(Lang, M, MsgId0, MsgId, MsgStr) :-
    current_po_file(M, Lang, PoFile),
    read_po_file(PoFile, Entries0),
    replace_entry(M, MsgId0, _, MsgId, MsgStr, Entries0, Entries),
    save_to_po_file(Entries, PoFile).

rename_id_lang(MsgId0, MsgId, M) :-
    findall(PoFile-Codes,
            ( current_po_file(M, '??', PoFile),
              rename_id_po_file(PoFile, MsgId0, MsgId, M, Codes)
            ), FileCodes),
    save_changes(FileCodes).

rename_id_po_file(PoFile, MsgId0, MsgId, M, Codes) :-
    read_po_file(PoFile, Entries0),
    replace_entry(M, MsgId0, MsgStr, MsgId, MsgStr, Entries0, Entries),
    parse_po_entries(Entries, Codes, []).

replace_entry(M, MsgId0, MsgStr0, MsgId, MsgStr, Entries0, Entries) :-
    reference(M, Ref),
    ( member(Entry0, Entries0),
      Entry0 = entry(_, _, Ref, _, MsgId0, MsgStr0) ->
      setarg(5, Entry0, MsgId),
      setarg(6, Entry0, MsgStr),
      Entries = Entries0
    ; MsgId0 \== MsgId,
      member(Entry, Entries0),
      Entry =  entry(_, _, Ref, _, MsgId, MsgStr1) ->
      ( MsgStr = MsgStr1 -> true
      ; setarg(6, Entry, MsgStr)
      ),
      Entries = Entries0
    ; nonvar(MsgStr) ->
      Entry =  entry([], [], Ref, [], MsgId, MsgStr),
      append(Entries0, [Entry], Entries)
    ; Entries = Entries0
    ).
