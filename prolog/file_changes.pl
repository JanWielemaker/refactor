/*  Part of Refactor Tools for SWI-Prolog

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

:- module(file_changes, [do_file_change/2, do_file_changes/2]).

do_file_changes(diff(DiffFile), FileChanges) :- !,
    tell(DiffFile),
    do_file_changes(show, FileChanges),
    told.
do_file_changes(Action, FileChanges) :-
    maplist(do_file_change(Action), FileChanges).

do_file_change(save, File-Changes) :-
    ( \+ exists_file(File), Changes==[] -> true
    ; open(File, write, Fd, []),
      format(Fd, '~s', [Changes]),
      close(Fd)
    ).
do_file_change(show, File-Changes) :-
    catch(diff_file_change(File, Changes),
	  error(process_error(_,(exit(1))), _),
	  true).

make_relative(File, RFile) :-
    ( absolute_file_name('',WD),
      atom_concat(WD, RFile, File) -> true
    ; RFile = File
    ).

diff_file_change(File, Changes) :-
    make_relative(File, RFile),
    atomic_list_concat([RFile, ' (source)'], FLabel),
    atomic_list_concat([RFile, ' (target)'], TLabel),
    process_create(path(diff),
		   ['-ruN',
		    '--label', FLabel, File,
		    '--label', TLabel, '-'
		   ],
		   [stdin(pipe(SIn)), stdout(pipe(Out))]),
    with_output_to(SIn, format('~s', [Changes])),
    close(SIn),
    dump_output(Out).

dump_output(Out) :-
    read_line_to_codes(Out, Line1),
    dump_output(Line1, Out).

dump_output(end_of_file, _) :- !.
dump_output(Codes, Out) :-
    format('~s~n', [Codes]),
    dump_output(Out).
    
