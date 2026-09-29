(*
	The Haxe Compiler
	Copyright (C) 2005-2019  Haxe Foundation

	This program is free software; you can redistribute it and/or
	modify it under the terms of the GNU General Public License
	as published by the Free Software Foundation; either version 2
	of the License, or (at your option) any later version.

	This program is distributed in the hope that it will be useful,
	but WITHOUT ANY WARRANTY; without even the implied warranty of
	MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
	GNU General Public License for more details.

	You should have received a copy of the GNU General Public License
	along with this program; if not, write to the Free Software
	Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
 *)

(*
	Conventions:
	- e: expression (typed or untyped)
	- c: class
	- en: enum
	- td: typedef (tdef)
	- a: abstract
	- an: anon
	- tf: tfunc
	- cf: class_field
	- ef: enum_field
	- t: type (t)
	- ct: complex_type
	- v: local variable (tvar)
	- m: module (module_def)
	- mt: module_type
	- p: pos

	"param" refers to type parameters
	"arg" refers to function arguments
	leading s_ means function returns string
	trailing l means list (but we also use natural plurals such as "metas")
	semantic suffixes may be used freely (e.g. e1, e_if, e')
*)
open Server

(* The compiler allocates at a high rate, and macros make it much higher: encoding the typed AST for
   eval allocates gigabytes of values that die almost at once. With OCaml's default minor heap
   (256k words) most of them live just long enough to be promoted, and the major collector then
   marks and sweeps them over a heap of several gigabytes. A larger minor heap lets them die young,
   and a larger space overhead makes the major collector run less often. Measured on a large
   reflaxe.CPP build (eval JIT on, and without the minor collections Array.make used to force, see
   EvalArray.map_values): 32M words (256MB, pages touched only as used) are the fastest now, 2%
   ahead of both 16M and 64M words, and a space overhead of 600 takes about 9% off 200 (400 takes
   5%; 800 was no faster and grew the heap further), for a larger heap but no larger resident set.
   Left alone when OCAMLRUNPARAM or CAMLRUNPARAM is set, so the GC can still be tuned from outside. *)
let () =
	match Sys.getenv_opt "OCAMLRUNPARAM",Sys.getenv_opt "CAMLRUNPARAM" with
	| None,None -> Gc.set { (Gc.get()) with Gc.minor_heap_size = 32 * 1024 * 1024; Gc.space_overhead = 600 }
	| _ -> ()

let other = Timer.timer ["other"];;
Sys.catch_break true;

let args = List.tl (Array.to_list Sys.argv) in
set_binary_mode_out stdout true;
set_binary_mode_out stderr true;
let sctx = ServerCompilationContext.create false in
Server.process sctx (Communication.create_stdio ()) args;
other()
