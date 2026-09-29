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

open EvalValue

let create values = {
	avalues = values;
	alength = Array.length values;
}

(* OCaml makes the result of Array.map, Array.init and Array.of_list with Array.make and the first
   value, and Array.make forces a minor collection when that value is young and the array is longer
   than Max_young_wosize (256 words): the whole young heap is promoted, once for every such array.
   With a large minor heap that is most of the collector's work. The functions below build those
   arrays from nulls instead, calling [f] on the same values in the same order. *)
let max_young_wosize = 256

let map_values (f : 'a -> value) (a : 'a array) : value array =
	let n = Array.length a in
	if n <= max_young_wosize then
		Array.map f a
	else begin
		let r = Array.make n vnull in
		for i = 0 to n - 1 do
			Array.unsafe_set r i (f (Array.unsafe_get a i))
		done;
		r
	end

let array_join a f sep =
	let n = Array.length a in
	let l = if n <= max_young_wosize then
		Array.to_list (Array.map f a)
	else begin
		let acc = ref [] in
		for i = 0 to n - 1 do
			acc := f (Array.unsafe_get a i) :: !acc
		done;
		List.rev !acc
	end in
	EvalString.join sep l

let to_list a = Array.to_list (Array.sub a.avalues 0 a.alength)

let make len =
	try Array.make len vnull with _ -> EvalContext.error_message "Array allocation is too large"

let set_length a l =
	a.alength <- l;
	if a.alength > Array.length a.avalues then begin
		let values' = make (a.alength * 2) in
		Array.blit a.avalues 0 values' 0 (Array.length a.avalues);
		a.avalues <- values'
	end

let unsafe_get a i = a.avalues.(i)
let unsafe_set a i v = a.avalues.(i) <- v

let concat a a2 =
	let values' = make (a.alength + a2.alength) in
	Array.blit a.avalues 0 values' 0 a.alength;
	let values2 = (Obj.magic a2.avalues) in
	Array.blit values2 0 values' a.alength a2.alength;
	create values'

let copy a =
	create (Array.sub a.avalues 0 a.alength)

let filter a f =
	let values = Array.sub a.avalues 0 a.alength in
	let n = Array.length values in
	if n <= max_young_wosize then
		create (ExtArray.Array.filter f values)
	else begin
		(* ExtArray's filter: [f] on every value in order, then the kept ones copied out *)
		let keep = Bytes.make n '\000' in
		let count = ref 0 in
		for i = 0 to n - 1 do
			if f (Array.unsafe_get values i) then begin
				Bytes.unsafe_set keep i '\001';
				incr count
			end
		done;
		let r = Array.make !count vnull in
		let j = ref 0 in
		for i = 0 to n - 1 do
			if Bytes.unsafe_get keep i <> '\000' then begin
				Array.unsafe_set r !j (Array.unsafe_get values i);
				incr j
			end
		done;
		create r
	end

let get a i =
	if i < 0 || i >= a.alength then vnull
	else Array.unsafe_get a.avalues i

let rec indexOf a equals x fromIndex =
	if fromIndex >= a.alength then -1
	else if equals x (Array.get a.avalues fromIndex) then fromIndex
	else indexOf a equals x (fromIndex + 1)

let insert a pos x =
	if a.alength + 1 >= Array.length a.avalues then begin
		let values' = make (Array.length a.avalues * 2 + 5) in
		Array.blit a.avalues 0 values' 0 a.alength;
		a.avalues <- values'
	end;
	Array.blit a.avalues pos a.avalues (pos + 1) (a.alength - pos);
	Array.set a.avalues pos x;
	a.alength <- a.alength + 1

let iterator a =
	let i = ref 0 in
	let a = Array.sub a.avalues 0 a.alength in
	let length = Array.length a in
	(fun () ->
		!i < length
	),
	(fun () ->
		if !i >= length then
			vnull
		else begin
			let v = a.(!i) in
			incr i;
			v
		end
	)

let join a f sep =
	array_join (Array.sub a.avalues 0 a.alength) f sep

let lastIndexOf a equals x fromIndex =
	let rec loop i =
		if i < 0 then -1
		else if equals x (Array.get a.avalues i) then i
		else loop (i - 1)
	in
	if a.alength = 0 then -1 else loop fromIndex

let map a f =
	create (map_values f (Array.sub a.avalues 0 a.alength))

let pop a =
	if a.alength = 0 then
		vnull
	else begin
		let v = get a (a.alength - 1) in
		unsafe_set a (a.alength - 1) vnull;
		a.alength <- a.alength - 1;
		v
	end

let push a v =
	if a.alength + 1 >= Array.length a.avalues then begin
		let values' = make (Array.length a.avalues * 2 + 5) in
		Array.blit a.avalues 0 values' 0 a.alength;
		Array.set values' a.alength v;
		a.avalues <- values'
	end else begin
		Array.set a.avalues a.alength v;
	end;
	a.alength <- a.alength + 1;
	a.alength

let remove a equals x =
	let i = indexOf a equals x 0 in
	if i < 0 then
		false
	else begin
		Array.blit a.avalues (i + 1) a.avalues i (a.alength - i - 1);
		a.alength <- a.alength - 1;
		true
	end

let contains a equals x =
	let i = indexOf a equals x 0 in
	i >= 0

let reverse a =
	a.avalues <- ExtArray.Array.rev (Array.sub a.avalues 0 a.alength)

let set a i v =
	if i >= a.alength then begin
		if i >= Array.length a.avalues then begin
			let values' = make (max (i + 5) (Array.length a.avalues * 2 + 5)) in
			Array.blit a.avalues 0 values' 0 a.alength;
			a.avalues <- values';
		end;
		a.alength <- i + 1;
	end;
	Array.unsafe_set a.avalues i v

let shift a =
	if a.alength = 0 then
		vnull
	else begin
		let v = get a 0 in
		a.alength <- a.alength - 1;
		Array.blit a.avalues 1 a.avalues 0 a.alength;
		v
	end

let slice a pos end' =
	if pos > a.alength || pos >= end' then
		create [||]
	else
		create (Array.sub a.avalues pos (end' - pos))

let sort a f =
	a.avalues <- Array.sub a.avalues 0 a.alength;
	Array.sort f a.avalues

let splice a pos len end' =
	(* StdArray.splice keeps pos and len within the array, so this is Array.sub *)
	let values' = if len <= max_young_wosize then Array.init len (fun i -> Array.get a.avalues (pos + i)) else Array.sub a.avalues pos len in
	Array.blit a.avalues (pos + len) a.avalues pos (a.alength - end');
	a.alength <- a.alength - len;
	create values'

let unshift a v =
	if a.alength + 1 >= Array.length a.avalues then begin
		let values' = make (Array.length a.avalues * 2 + 5) in
		Array.blit a.avalues 0 values' 1 a.alength;
		a.avalues <- values'
	end else begin
		Array.blit a.avalues 0 a.avalues 1 a.alength;
	end;
	Array.set a.avalues 0 v;
	a.alength <- a.alength + 1

let resize a l =
	if a.alength < l then begin
		set a (l - 1) vnull;
		()
	end else if a.alength > l then begin
		Array.fill a.avalues l (a.alength - l) vnull;
		a.alength <- l;
	end else ()
