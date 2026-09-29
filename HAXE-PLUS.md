# haxe-plus

haxe-plus is a set of forks of Haxe releases that make the **eval** target — the interpreter that
runs macros, `--interp` and `--run` — much faster, without changing what any program computes.
Each branch is one Haxe release plus the changes this file describes.

| Branch | Base | State |
|---|---|---|
| `haxe4` | 4.3.7, the latest Haxe 4 release | done and verified (this file describes it) |
| `haxe5` | 5.0.0-preview.1, the latest Haxe 5 release | planned: port with the checklist in [Porting](#porting-to-another-haxe-version) |

The repository ([barisyild/haxe-plus](https://github.com/barisyild/haxe-plus)) is a GitHub fork of
HaxeFoundation/haxe, so upstream tags and history are one fetch away. Only the branches above are
haxe-plus; the others (`development` and pull-request branches for upstream) are not.

**This file is the project's memory.** It records every change: where it is, what it does, why it
cannot change a program's behaviour, what it bought, and what to check when carrying it to another
Haxe version. Any commit that changes haxe-plus updates this file in the same commit.

`haxe -version` still prints the base version (4.3.7), so that version checks in libraries and
build tools keep working.

Contents: [Results](#results) · [The rule: exact](#the-rule-exact) · [Using it](#using-it) ·
[Verification](#verification) · [Change catalog](#change-catalog) · [Rejected ideas](#rejected-ideas) ·
[Pitfalls](#pitfalls-learned) · [Porting](#porting-to-another-haxe-version) · [Future work](#future-work) ·
[History](#history)

## Results

Measured on one real macro-heavy build: a PlayStation game statically recompiled to Haxe
([recompsx](https://github.com/barisyild/recompsx), Crash Bash) and compiled to C++ by
[reflaxe.CPP](https://github.com/SomeRanDev/reflaxe.CPP), whose whole code generator runs as macros
in eval. Apple M3 Pro, macOS, 18 GB. In every measurement the generated C++ was byte-identical to
what the release binary generates.

| | Game through reflaxe.CPP | recompsx's recompiler (`--run`) |
|---|---|---|
| Haxe 4.3.7 release binary | 331 s | 6.8 s |
| haxe-plus `haxe4` | **40.5 s** (max RSS 4.2–4.6 GB) | **2.8 s** |
| haxe-plus `haxe4`, JIT off (no eval-jit.conf, as in CI packages) | 87.5–95.4 s (max RSS 2.0–2.7 GB) | |

The same build step by step (seconds; each row adds to the rows above it; the IDs are those of the
[catalog](#change-catalog)):

| Change | Time |
|---|---|
| Local build of unchanged 4.3.7 (OCaml 4.14.2, no flambda) | 355 |
| J: native JIT, first version | 282 |
| G1: GC settings, first version (minor heap 64M words, space_overhead 200) | 254 |
| R5: UTF-8 length cache for the macro API's strings | 198 |
| R1, R2: hash cache and prototype-name cache, first versions | 121 |
| R1: skip rewrites, collisions stamp; R2: object shapes | 93.4 |
| R3: named shapes; R9: macro API equality and metadata | 61.3 |
| smaller refinements | 59.8 |
| J: inline caches for field reads | 56.9 |
| smaller refinements | 55.3 |
| R4: literal arrays for small lists | 52.2 |
| R3, R4: loops as top-level functions (no closure per call) | 51.0 |
| R6: ASCII scan eight bytes at a time | 49.9 |
| R3: literal field arrays for shapes of up to 12 fields | ~47 |
| R7: shared prototypes for opaque values; R8: encode_ref closures | ~45.9 |
| J: cheaper environments; R9: encode_meta's closures | 44.9 |
| J: enum-index switches, unboxed Array.length comparisons | 44.3 |
| R12: no forced minor collections; J: inlined env push/pop; R11: get_eval | ~43.8 |
| G1: minor heap 32M words | 42.9 |
| G1: space_overhead 400 | 42.1 |
| G1: space_overhead 600 | **40.5** |

The local build of the unchanged release was 7% slower than the official binary (355 s against
331 s); the cause was not investigated ([Future work](#future-work)).

With Haxe's own generators, whose code is OCaml that haxe-plus does not touch, only the macro and
GC share of a build gets faster (same machine, output byte-identical in every case):

| Build | Release 4.3.7 | haxe-plus | JIT off |
|---|---|---|---|
| The same game to JavaScript (12 MB) | 7.84 / 7.79 s | 7.23 / 7.38 s | 7.25 / 7.33 s |
| Haxe's tests/unit to C++, generation only (2165 .cpp) | 3.15 / 3.07 s | 2.20 / 2.22 / 2.20 s (J2) | 2.24 / 2.25 / 2.22 s |
| The same through hxcpp 4.3.171, end to end | 77.0 s | 80.0 s | |

The hxcpp build is the C++ compiler's time (identical sources, so identical work; the 3 s is that
build's noise). Before J2, compiling every class natively cost tests/unit 0.1–0.5 s more than no
JIT at all; J2 leaves light projects closure-compiled. hxcpp 4.3.2 from lib.haxe.org does not
build on the macOS 27 SDK (its zlib 1.2.11 defines `fdopen` as a macro); the GitHub builds
(4.3.171, zlib 1.3.1) do.

Where the time goes now (sampling profile of the last build): GC about 17% (a live heap of ~5 GB,
mostly the typed AST the macros keep), the macro API's encoders about 15%, JIT-compiled Haxe code
about 14% (hottest: the standard library's `haxe.macro.TypedExprTools.map` and `iter`, then
reflaxe.CPP's own classes), write barriers about 5%, and a flat tail.

## The rule: exact

1. **No change may alter anything a program can observe**: values, output, evaluation order,
   exceptions with their messages and positions, stack traces, the identity of objects user code
   can compare. The reference is Haxe's own closure compiler (`evalJit.ml`): "what would have run
   anyway". Speed is only ever bought by doing the same work cheaper.
2. **Caches are validated on every use**: by physical equality with the objects they were computed
   from, by stamps such as `EvalHash.collisions`, by the context id and the very map of prototypes
   they were found in. Where the original creates a fresh value, the cached path creates a fresh
   value too. Cache entries are immutable values replaced in one write, so an eval thread switch
   never sees half an update.
3. **Every change is verified** ([Verification](#verification)): byte-identical output of a large
   real project and the differential tests as it is made; Haxe's eval suites in three JIT modes
   before a branch is pushed.
4. **Measure with interleaved repeated runs** (A B A B), never while anything else runs; noise on
   one machine is about ±1%.

## Using it

### Building

`haxe4` builds like Haxe 4.3.7 (`extra/BUILDING.md`): an OCaml 4.14 switch with haxe.opam's
dependencies, plus pcre2, zlib, neko and mbedtls 2.x. Verified with: OCaml 4.14.2 (no flambda),
opam 2.3.0, dune 3.15.3, camlp5 8.03.04, ocamlfind 1.9.1, sedlex 3.7, xml-light 2.5, extlib 1.8.0,
ptmap 2.0.5, sha 1.15.4, camlp-streams 5.0.1, luv 0.5.13 (0.5.14 in the Windows CI: C4), ctypes
0.24.0, integers 0.8.0; pcre2 10.47, zlib 1.2.12, neko 2.4.1, mbedtls 2.28.9; macOS 27 on arm64.
OCaml 5 has not been tried.

On macOS with a recent clang, luv 0.5.13 fails to build with
`incompatible-function-pointer-types` errors: install it with `CC` pointing to a wrapper script
that runs `cc -Wno-error=incompatible-function-pointer-types "$@"`.

Then, in the switch's environment:

    extra/haxe-plus/build.sh           # make haxe, and eval-jit.conf for ./haxe
    extra/haxe-plus/install.sh <dir>   # copy ./haxe to <dir> with a snapshot of its objects

Without eval-jit.conf the JIT is off and only the run-time changes (R*) and the GC settings (G1)
apply.

### The JIT's configuration

The JIT reads `eval-jit.conf` from the directory of the real path of the running haxe executable.
One `key=value` per line, `#` comments:

| Key | Meaning |
|---|---|
| `ocamlopt` | the ocamlopt of the switch that built the binary |
| `include` | a directory of .cmi/.cmx files the binary was built from (repeated) |
| `flag` | an extra ocamlopt flag (repeated); `-linscan` |
| `cache` | cache root; each binary uses `<cache>/<build id>` |
| `jobs` | parallel ocamlopt processes |

`extra/haxe-plus/jit-conf.sh <bin dir> <objs root> [cache]` writes it. The objects must be the very
ones the binary was linked from: units are compiled against their interfaces and inlining data.
`build.sh` points ./haxe at `_build/default` (which the next build changes); `install.sh` copies
them next to the installed binary (`jit-objs/`).

Environment variables:

| Variable | Effect |
|---|---|
| `HAXE_EVAL_JIT=0` | JIT off (also `off`, `false`, `no`) |
| `HAXE_EVAL_JIT_STRICT=1` | a unit that fails to compile, load or link is fatal (testing the JIT itself) |
| `HAXE_EVAL_JIT_LOG=1` | log units compiled and every fallback, to stderr |
| `HAXE_EVAL_JIT_STATS=1` | counters and times at exit |
| `HAXE_EVAL_JIT_DUMP=dir` | also write the source of every unit compiled (compiled only: use a cold cache) |
| `HAXE_EVAL_JIT_MAX_FUNCTION=n` | largest function compiled, in typed expressions (default 3000) |
| `HAXE_EVAL_JIT_SIZES=1` | print the size of every function over 1000 typed expressions |
| `HAXE_EVAL_JIT_THRESHOLD=n` | calls in one compilation that make its project heavy (J2; default 1000000); 0 = every class native, the default under `HAXE_EVAL_JIT_STRICT` |
| `HAXE_EVAL_JIT_COUNTS=n` | at exit, the project's calls and the n classes with most calls, while not heavy |

The JIT is also off under the eval debugger (`-D eval-debugger`, debug socket). With
`-D eval-times` compiled functions take the general environment path so that timers still work.

### GC settings

Built in: minor heap 32M words (256 MB) and `space_overhead` 600, unless `OCAMLRUNPARAM` or
`CAMLRUNPARAM` is set, in which case the environment decides everything. To measure GC settings,
pass them the same way: `OCAMLRUNPARAM="v=0x400,s=32M,o=600"` also prints the GC's counters at exit.

## Verification

Each change was checked as it was made against the real project's output (1) and the differential
tests (3); the whole set ran at checkpoints along the way and on the final state of the branch:

1. **A real project, byte for byte.** The recompsx build above: its generated C++ and its
   recompiler's generated Haxe compared with `diff -r` against the output of the release binary.
   recompsx's full test gate (`scripts/test.sh`, which also builds and runs both of its targets)
   passed with the final binary.
2. **Haxe's own eval suites**, in three modes — JIT off; strict (every class native, threshold 0)
   with a cold cache, so that every unit is compiled; the defaults (J2: these suites are light
   projects, so their functions run closure-compiled behind the counting wrapper):

       extra/haxe-plus/test-suites.sh ./haxe <log dir>

   | Suite (in tests/) | Command | Result, every mode |
   |---|---|---|
   | unit | `haxe compile-macro.hxml` | ALL TESTS OK |
   | misc | `haxe compile.hxml` | 593 tests, 0 failures |
   | sys | `EXISTS=1 haxe compile-macro.hxml` | ALL TESTS OK |
   | threads | `haxe build.hxml --interp` | ALL TESTS OK |
   | nullsafety | `haxe test.hxml` | exit 0 |

   utest a94f881 installed as a dev library in the haxelib repository of `HAXELIB_PATH`. The sys
   suite runs with `EXISTS=1` as RunCi does; on APFS, file names with invalid Unicode cannot exist,
   so the script comments out `-D TEST_INVALID_UNICODE_FS` in `tests/sys/compile-fs.hxml` for the
   run, as that file says to.
   The compilation server's tests (tests/server, 446 assertions) pass in the same three modes (JIT
   off 16 s, defaults 17 s, strict 36 s). Run them outside any directory with a local `.haxelib`,
   which would hide `HAXELIB_PATH`: copy tests/server and tests/display next to each other, add
   hxnodejs, haxeserver and utest to the repository, then `haxe build.hxml && node test.js` in
   server/; with the JIT's variables set, the spawned servers inherit them.
   **Not run yet:** tests/display, tests/optimization, the other targets' suites (the CI runs those
   with the JIT off).
3. **Differential tests**: `extra/haxe-plus/tests/run.sh ./haxe` runs each program with the JIT off
   and on (strict) and compares with the output the release's semantics give. `jit-smoke` covers
   the language constructs the JIT compiles; `big-arrays` the R12 paths (arrays past 256 elements:
   map, filter, splice, join, split, Vector.map, printing, macro encoding of long lists, side-effect
   order, exceptions midway); `gc-settings` checks G1.
4. **Measurements**, interleaved, on the real project.

## Change catalog

The commits of each branch follow these groups, so each can be taken on its own:
"eval: native JIT" (J), "eval: exact run-time caches and fewer allocations" (R1–R12),
"compiler: GC settings for macro-heavy builds" (G1), "ci: run the CI workflow by hand only" (C1),
"haxe-plus: documentation, scripts, differential tests", "ci: runners and OCaml 4.14 for every
build" (C2), "ci: attach the packages to a published release" (C3), "eval: native code only
for heavy projects" (J2) and "ci: today's runners and tools" (C4). The code comments at each
change repeat the essentials.

### J: native JIT — `src/macro/eval/evalJitNative.ml`, `evalJitRt.ml`

**What.** Haxe's closure compiler (`evalJit.ml`) turns every typed expression into an OCaml
closure and runs the tree of closures. The native JIT compiles the same typed functions to machine
code: each class becomes one OCaml compilation unit whose functions are the direct-style
equivalent of what evalJit would build; ocamlopt compiles it; Dynlink loads it into the running
compiler. The generated code calls the very run-time functions evalJit's emitters call, so values,
prototypes, environments and exceptions are shared with the rest of eval. What goes away is the
indirect call per node, the locals array (locals become OCaml variables) and most boxing of
intermediate booleans and integers.

**Hooks.**
- `evalPrototype.ml`: where constructors, static methods and instance methods were made with
  `EvalJit.jit_tfunction`, they are made with `EvalJitNative.jit_method ctx c key name tf static pos`
  (same arguments plus the class). `add_types` calls `EvalJitNative.prepare ctx new_types` once
  the prototypes exist and before any field is initialized, so a batch of classes is compiled and
  loaded together.
- `evalEmitter.ml`: `check_stack_depth` is `[@inline]`, like `EvalJitRt.push_env`/`pop_env`, so
  compiled code calls no stub for them (about 1%).

**Pipeline.**
1. `prepare`: for each non-extern class, `generate_unit` writes one unit with a function per method
   (constructor, instance methods, static methods, in `class_methods` order, as EvalPrototype
   creates them). A unit's key is the MD5 of `jit_version` and its source.
2. A unit already registered in this process, or indexed in the cache (`units/<key>`), is loaded.
   One marked `units/<key>.failed` falls back. The others are compiled together
   (`compile_units`): `ocamlopt -c -w -a <include...> <flag...> jit_<key>.ml` for each, `jobs` at a
   time, then `ocamlopt -shared -o bundles/b_<md5>.cmxs <cmx...>`; each unit gets an index file
   naming its bundle, written under a temporary name and renamed. A unit whose ocamlopt exits with
   an error is marked `.failed` (not when killed by a signal); units with the same source are
   compiled once.
3. `load_unit`: `Dynlink.loadfile_private` of the bundle, once per bundle and process; the unit's
   initializer calls `EvalJitRt.register key [| jfun0; ... |]`.
4. `jit_method`: finds the method's link function and requirements, resolves the requirements in
   order and calls `jfunN resolved`, which returns the `vfunc`. Any exception on the way falls back
   to `EvalJit.jit_tfunction` for that function.

**Rules that keep units reusable across compilations** (they are cached on disk by the digest of
their source):
- The source depends only on the structure of the typed AST: names, operators, integer constants.
  Everything else a function needs (positions, prototypes, field indices, strings, floats, call-site
  caches, environment infos) is a *requirement*, resolved when the function is linked and handed
  over in an array, in the order recorded while generating (`type req`: `RCtx`, `RPos`, `RSomePos`,
  `RString`, `RFloat`, `RStaticProto`, `RStaticProtoValue`, `RInstanceProto`, `RObjectProto`,
  `RProtoFieldIndex`, `RInstanceFieldIndex`, `RLazyProtoField`, `RCtorLazy`, `RSpecialCtor`,
  `REnvInfo`, `ROProto`, `RCallCache`, `RFieldCache`). Requirements evalJit creates per occurrence
  (call-site caches, constants, environment infos, `Some pos`) are never shared (`req_shareable`).
- Variables are renamed in declaration order, never by their global ids.

**Semantics are evalJit's, not the language's.** Every construct evaluates its operands, checks
their values and records positions (`env_leave_pmin/pmax`) in the order evalJit's emitter does,
because that order is observable through exceptions and stack traces. Local functions are numbered
in the order evalJit compiles them (it shows in stack traces). Default argument values are added
with `Texpr.set_default` as evalJit does. Wrappers evalJit skips (`TParenthesis`, `TMeta`,
`TCast(_, None)`) are skipped the same way, also around declarations in blocks.

**Generated code.** Header: `open Globals`, `EvalValue`, `EvalContext` and the aliases `E`
EvalEmitter, `M` EvalMisc, `R` EvalJitRt, `F` EvalField, `P` EvalPrinting, `X` EvalExceptions, `A`
EvalArray, `N` EvalEncode, `C` EvalContext. Each method is
`let jfunN (jl : Obj.t array) : vfunc = let jk0 : T0 = Obj.obj jl.(0) in ... (fun jvl -> body)`;
the body is `let jenv = R.push_env ctx info in`, the arguments taken from `jvl` as evalJit does
(missing ones are null, extra ones raise), the function body, then `R.pop_env ctx jenv` and the
result, inside `try ... with X.Return v -> v` only when a `return` is not in final position. Names:
`jvN` locals (`ref` only when written), `jtN` temporaries, `jwN` copies of captured variables the
function writes, `jkN` requirements, `jx_*` fixed helpers. Integer arithmetic and comparisons have
fast paths for two `VInt32` operands, with the generic `EvalMisc` operation otherwise. Switches on
enums dispatch on `eindex` through a jump table; `Array.length` comparisons are done unboxed. Array
literals with many elements are filled in place.

**Run-time helpers (`evalJitRt.ml`).** `push_env`/`pop_env` (EvalContext's, without the locals and
captures arrays compiled functions do not use), `try_catch` (as `emit_try`), and exact inline caches:
- `method_field_cached` (call sites of overridable methods): remembers, for the receiver's
  prototype, which prototype holds the field and at which index; the value is read from that
  prototype on every call, as the lookup would.
- `field_cached`, `object_field_cached`, `dynamic_field_cached`, `anon_field_read_cached` (field
  reads by name): remember where the field was for the last prototype seen (`FSObject`,
  `FSInstance`, `FSProto`, `FSMissing`); values are read every time. Valid because a prototype's
  field names and parent never change.
- each cache is one immutable tuple replaced in one write.

**Fallbacks are exact**: anything the generator does not handle raises `Unsupported` and that
function stays with evalJit — what would have run anyway. Not compiled: functions over
`HAXE_EVAL_JIT_MAX_FUNCTION` typed expressions (default 3000: ocamlopt's time grows faster than
linearly with function size, and the largest functions are straight-line code run once), `TIdent`,
postfix spread, some assignment targets and `super` forms, `fastCodeAt`/`unsafeCodeAt` with an
unusual arity; `HAXE_EVAL_JIT_LOG=1` lists every fallback.

**Cache layout.** `<cache>/<build id>/` with `units/<key>` (the bundle's name), `units/<key>.failed`,
`bundles/b_<md5>.cmxs` and `tmp-<pid>-<n>/` for compilations in progress. The build id is the MD5
of `jit_version`, the executable's path, size, mtime and inode: every build gets a fresh cache,
since units are compiled against that build's objects. Other builds' directories are removed once
they are an hour old; temporary directories of interrupted compilations are pruned.

**Platform notes.** macOS takes about 165 ms for the first load of any new shared object, whatever
its size: that is why units compiled together are linked into one bundle. On arm64, ocamlopt
cannot address stack frames past 32 KB (`str x0, [sp, #32768]` fails to assemble): hence the size
cap, in-place array literals and `-linscan`. Only the compiler's own children are waited for
(`waitpid`): `Unix.wait` would reap processes the compiler spawned for other reasons. Unix is
assumed (pruning runs `rm -rf`); Windows is untested.

**Measured.** 355 → 282 s alone at first (−21%): interpretation was not the main cost; the
run-time work (R*) and the GC (G1) were. Later JIT refinements: field caches 59.8 → 56.9 s,
environments 45.9 → 44.9 s (with R9), enum switches and unboxed comparisons 44.9 → 44.3 s,
inlined push/pop about 1%.

**Porting.** The generator mirrors the base version's evalJit semantics. Diff `evalJit.ml`,
`evalEmitter.ml`, `evalMisc.ml`, `evalField.ml`, `evalExceptions.ml`, `evalContext.ml` (env,
`push_environment`), `evalPrototype.ml`, `evalValue.ml` and `evalPrinting.ml` between the old and
the new base, and carry every semantic change into `evalJitNative.ml`/`evalJitRt.ml`. Check the
typed AST (`texpr_expr` and friends) for new or changed constructors: the generator must raise
`Unsupported` for anything it does not know, never guess. The cache is per binary, so a rebuilt
compiler never reuses units compiled for another build; `jit_version` is part of every key, for
changes of the scheme itself. Check that the OCaml version still has `Dynlink.loadfile_private`
and the flags in use.

### J2: native code only for heavy projects — "Tiers" in `evalJitNative.ml`

**Why.** Making the classes native costs a fixed amount in every compilation — each unit's source
generated to find its cache key, the bundles loaded (the first load of a new bundle more), the
functions linked — which compilations running few macros never pay back. Haxe's tests/unit to
C++: 2.3 s without the JIT, 2.4–2.9 s with every class native.

**What.** Every compilation belongs to a *project*: the kind of context (macro or interp) and the
class paths — not the defines or the main class, so the variants of one build (outputs, profiles)
and the programs of one test suite share it. In a project not known to be heavy, every function is the closure compiler's,
exactly as without the JIT, behind a wrapper that counts the calls and then calls it in tail
position; nothing is generated or loaded. When a compilation makes `HAXE_EVAL_JIT_THRESHOLD` calls
(default 1,000,000), the project is recorded as heavy: a file `heavy-<digest>` in the cache root.
Every later compilation of a heavy project prepares all its classes natively up front, exactly as
with threshold 0 (and as J did before J2): no wrapper there. A function's tier is fixed when it is
created; nothing is ever swapped.

**Why the project and not the class.** The first version counted calls per class and made the hot
classes native: on the reflaxe.CPP build it was 5% slower than all-native (46.3 s against 44.2 s,
same binary, interleaved), because driver classes (`reflaxe.ReflectCompiler`,
`cxxcompiler.helpers.Sort`, `reflaxe.output.OutputManager`, ...) are called rarely yet run much of
the work in loops and local functions, which a class's call count does not see. Native code saves
about 120 ns a call on that build (329 million calls, 82 s closure-compiled against 44 s native)
and preparing every class costs a few tenths of a second: it pays from a few million calls.

**Exact because** the tier-0 function is the very closure the JIT-off path creates, called in tail
position by a wrapper that only counts; heavy projects run J's code as before.

**Measured.** tests/unit to C++ (61,678 calls, light): 2.20 / 2.22 / 2.20 s, JIT off 2.24 / 2.25 /
2.22 s, all-native 2.30 / 2.29 / 2.33 s. The reflaxe.CPP game build (the step recompsx's PC and
Dreamcast builds share): first compilation 81.9 s (closure-compiled, becomes heavy), second 48.6 s
(its units compiled for a new binary), then 44.31 / 44.49 s against 44.60 / 44.33 s all-native.
recompsx's recompiler (`--run`, 18 million calls): first 6.12 s (= JIT off), then 3.02 / 3.01 s.
The price is that one first compilation per project, per cache root; heavy files outlive rebuilds
of the compiler (they are keyed by the project, not the binary).

**Porting.** Needs the `curapi` of the context when the first class is added (the project is read
from the compiler's `class_path`). Keep the wrapper a tail call.

### R1: EvalHash — `src/macro/eval/evalHash.ml`

**What.** (1) `reverse_map` is a `Hashtbl.Make` table on ints instead of the generic `Hashtbl`,
which hashes and compares through C calls. (2) `set_name` does not rewrite an entry that already
holds the same name (physically or `String.equal`), and counts in `collisions` every time a
different name takes a hash's place. (3) `hash` has a direct-mapped cache of 4096
`(string, hash, collisions stamp)` triples, indexed by length and first and last characters: a hit
needs the very same string (physical equality) and a current stamp, and skips both hashing and
registering. (4) `register i f` records a name known to hash to `i`, as `hash` would.

**Exact because** the hash of a string is a pure function (`Hashtbl.hash`), registering the same
name again changes nothing, and any displacement of a name bumps `collisions`, which invalidates
every stamped cache (this one, R2's names, R3's shapes). `rev_hash` returns an equal string in all
cases.

**Porting.** Check that eval still hashes names with `Hashtbl.hash` and that `reverse_map` is still
"last writer wins".

### R2: object shapes — `get_object_prototype` in `src/macro/eval/evalPrototype.ml`

**What.** Every object the macro API encodes goes through `get_object_prototype`, which sorted the
fields, formatted the prototype's name (`eval.object.Object[:a,:b,...]`), hashed it and looked the
prototype up. Objects come from few shapes (their field hashes in the order given), so a shape
(`object_shape`, 4096 buckets of at most 8) remembers: the permutation that sorts its fields,
found by sorting `(hash, position)` pairs with the same comparison, so it is `List.sort`'s order
even for equal hashes; the prototype's name, with the field names exactly as `rev_hash` returned
them, used only while `collisions` is unchanged or `rev_hash` still returns those very strings
(then registered again as hashing it would); and the prototype, for one context id, one name and the
very map of prototypes it was found in.

**Exact because** each cached part is recomputed whenever what it was computed from may differ.

**Porting.** Compare with the new `get_object_prototype`: same sort, same name format, same
registration.

### R3: named shapes — `encode_obj_s` in `src/macro/eval/evalEncode.ml`

**What.** The macro API builds objects from `(string * value)` lists whose names are string
constants. A named shape (keyed by the name strings, compared physically; bucket hash from the
first two names and the count; buckets of at most 8, most recent first) remembers where each field
goes (`ns_slot`, `ns_order`) and the object prototype, and is used only in the same context, for the
very map of prototypes it was found in, and while `collisions` is unchanged: then hashing the names
would give the same hashes, the same sorted order and the same prototype. Shapes of up to 12 fields
build their `ofields` as an array literal, choosing each element through the order with `selN`;
larger ones fill a fresh array. The first object of a shape takes the original path and records
the shape.

**Exact because** the result is a fresh object with the same prototype and fields in the same
slots as `encode_obj (List.map (fun (s,v) -> hash s, v) l)` would give. Names built on the fly
never match physically, so they only ever take the original path.

**Porting.** Check that `encode_obj_s` is still `encode_obj` of the hashed names, and
`get_object_prototype`'s sort.

### R4: literal arrays — `values_of_list`, `make_fields` in `src/macro/eval/evalEncode.ml`

**What.** `encode_array` and `encode_enum` turned lists into arrays with `Array.of_list`, which
fills through the write barrier (a C call per element). Lists of up to 16 values become array
literals (allocated inline, initializing stores); 17–32 and more than 256 fill a fresh array of
nulls; 33–256 keep `Array.of_list` (R12 explains the 256). Loops are top-level functions taking
everything they use, so that calling them allocates no closure.

**Exact because** the array has the same values in the same order and is fresh either way.

### R5: UTF-8 length cache — `encode_string_cached` in `src/macro/eval/evalEncode.ml`, `src/typing/macroContext.ml`

**What.** The macro API encodes the same compiler strings again and again (class documentation
every time a type is dereferenced, above all), and computing their UTF-8 length each time
dominated macro-heavy builds. Strings of 64 bytes or more remember their length in a direct-mapped
table of 4096 `(string, length)` pairs keyed by the string itself (physical equality). The macro
API's interpreter module (`MacroContext.Eval`) uses it as its `encode_string`; eval's own
`encode_string` is unchanged.

**Exact because** the value is a fresh `vstring` with the same length every call, and the
compiler's own strings are never mutated.

**Porting.** Check where MacroApi gets `encode_string` from (the `InterpApi` module).

### R6: ASCII scan — `create_unknown_vstring` in `src/macro/eval/evalString.ml`

**What.** A string that is all ASCII (most are) has as many characters as bytes. `is_ascii` checks
eight bytes at a time (`String.get_int64_ne`, mask `0x8080808080808080`), and only other strings go
through `UTF8.length` (with its exception fallback to the byte length, as before).

**Exact because** for ASCII strings `UTF8.length` returns the byte count.

### R7: shared prototypes for opaque values — `encode_pos`, `encode_lazytype`, `encode_tdecl`, `encode_unsafe` in `src/macro/eval/evalEncode.ml`

**What.** Each opaque macro value (positions, lazy types, type declarations, unsafe refs) got a
freshly made fake prototype; now each kind has one, created eagerly at module initialization (so
eval threads never race on forcing it).

**Exact because** nothing tells the prototypes apart: an instance's prototype is only read for its
content (names, path, kind, parent), and `Type.getClass`/`Type.typeof` look classes up by path.

**Porting.** Recheck that no code compares these prototypes physically or mutates them.

### R8: encode_ref's closures — `encode_ref` in `src/macro/eval/evalEncode.ml`

**What.** The two methods of a `Ref` were `vifun0` of a function ignoring its argument (two
closures each); now one closure each with the same argument handling (none or one argument calls;
more raises `invalid_call_arg_number 1`).

### R9: macro API equality and metadata — `src/macro/macroApi.ml`

**What.** (1) `v = vnull` became `v == vnull` (12 places): `vnull` is an immediate, so the result
is the same and there is no call to the generic comparison. (2) `meta_equal` compares
`Meta.strict_meta` values without the generic comparison: `Custom` and `Dollar` compare their
strings, other constructors are constants compared physically; used in `extract`, `remove`, `has`.
(3) `encode_meta`'s five functions are defined with one `let rec`, sharing one closure. (4)
`encode_mtype` conses its fields onto the list it is given instead of appending with `@`.

**Porting.** Check that `Meta.strict_meta`'s only constructors with arguments are still `Custom` and
`Dollar` of string; if one is added, extend `meta_equal`.

### R10: `EvalContext.is` — `src/macro/eval/evalContext.ml`

**What.** `v <> vnull` became `v != vnull`, and `List.mem path interfaces` became
`List.exists (fun (i : int) -> i = path) interfaces`: same results without the generic comparison.

### R11: `get_eval` — `src/macro/eval/evalContext.ml`

**What.** Every Haxe call finds its thread's eval with `get_eval`, which asked for the thread's id
(two C calls). Now it compares the thread's descriptor physically with the main thread's (captured
when modules are initialized, on the main thread, id 0) and is `[@inline]`; other threads take the
original path (`get_other_eval`).

**Exact because** the main thread is the one with id 0, and descriptors are unique per thread.

### R12: no forced minor collections — `src/macro/eval/evalArray.ml` and callers

**What.** OCaml's `Array.map`, `Array.init` and `Array.of_list` build their result with `Array.make`
and the first value, and `Array.make` (`caml_make_vect`) forces a minor collection when that value
is young and the array is longer than `Max_young_wosize` (256 words): the whole young heap is
promoted, once per such array. That was 85% of all minor collections (3466 → 555). These now start
from nulls and call the function on the same values in the same order:
- `EvalArray.map_values` (new, used by `EvalArray.map`, `StdEvalVector.map`,
  `StdFileSystem.readDirectory`, `EvalEmitter.emit_array_declaration`), `EvalArray.array_join`
  (builds its list in order and reverses it), `EvalArray.filter` (predicate on every value in
  order, then the kept ones copied, as ExtArray's filter), `EvalArray.splice` (`Array.sub`: the
  caller keeps the range inside the array);
- `StdString.split` (was `DynArray.to_array`);
- `values_of_list` past 256 values (R4).
Arrays of up to 256 elements keep the original functions.

**Exact because** the same function is applied to the same values in the same order, and the result
holds the same values; only the initial contents of a fresh array differ, which nothing sees.

**Measured.** About 1.5% by itself (the promoted data is the same, only split differently), but it
changed the best GC settings (G1).

**Porting.** Look for new `Array.map`/`init`/`of_list`/`DynArray.to_array` on arrays that can be long
in eval's run time.

### G1: GC settings — `src/compiler/haxe.ml`

**What.** Unless `OCAMLRUNPARAM` or `CAMLRUNPARAM` is set: minor heap 32M words (256 MB; pages are
touched only as used) and `space_overhead` 600 (OCaml's default: 256K words and 120). Encoding the
typed AST for macros allocates gigabytes of values that die almost at once; with the default minor
heap most live just long enough to be promoted, and the major GC then marks and sweeps them over
several gigabytes.

**Measured.** At first (minor heap 64M words, `o=200`): 282 → 254 s. After R12, interleaved on the
final code: 32M words beat 16M, 64M and 128M by about 2%; `o=400` beat 200 by 5% and `o=600` beat
400 by 4%, with the same resident set (~4.2 GB); `o=800` was no faster on wall time and grew the
heap to 7 GB.

**Porting.** Re-tune with interleaved runs on a real build: the best values follow the workload and
the OCaml version (OCaml 5's GC differs).

### C1: CI by hand — `.github/workflows/main.yml`, `extra/github-actions/workflows/main.yml`

**What.** Haxe's own CI workflow ran its whole matrix on every push and pull request; on haxe-plus
branches it runs only when started from the Actions tab (`workflow_dispatch`), or for a published
release (C3). Changed in the template and in the file generated from it. It builds and tests the
base release's targets, with the JIT off (no eval-jit.conf there).

Upstream's `.github/workflows/cancel.yml` is kept: starting a run cancels the older runs of the
same branch still in progress at another commit ("The run was canceled by @github-actions[bot]").
Let a run finish before starting one for a newer commit, unless the new one is meant to replace
it.

### C2: CI runners and OCaml versions — `.github/workflows/main.yml`

**What.** So that the packages can be built at all today, with the toolchain haxe-plus was verified
on: mac builds run on `macos-14` (arm64) and `macos-15-intel` (x64; the `macos-13` runners are
retired), mac tests on `macos-15-intel`; OCaml 4.14.2 for Linux x64 (was 4.14.0 plus a 5.3.0
variant), Linux arm64 (was Ubuntu 22.04's system OCaml, 4.13) and macOS (was 5.1.1); Windows keeps
setup-ocaml's 4.14.0. An OCaml 5 variant comes back with haxe5.

In 4.3.7 the template in `extra/github-actions` is older than the generated
`.github/workflows/main.yml` (upstream edited the generated file for the 4.3 releases): edit the
generated file, and never regenerate it from the template.

**Packages.** The CI builds every release package (Windows 32/64 zip, installer and nupkg, Linux
x64/arm64 tar.gz, macOS universal tar.gz and installer) and keeps them as the run's artifacts;
upstream's `deploy` job uploads to its S3 and runs only in HaxeFoundation, and upstream publishes
GitHub releases by hand (`extra/release-checklist.txt`). Packages have the JIT off (no
eval-jit.conf, no OCaml): 87.5–95.4 s on the benchmark instead of 331 s. C3 attaches them to a
release. A build made on a developer's Mac is not a
package: it needs `MACOSX_DEPLOYMENT_TARGET` (it otherwise requires the build machine's macOS) and
static pcre2/mbedtls, which is what the CI does.

**Trial run** (2026-09-29, [run 36584012177](https://github.com/barisyild/haxe-plus/actions/runs/36584012177)):
the Linux x64 and arm64 builds, both mac builds and the universal package passed, and the macro
tests on every platform; 27 jobs in all. What failed is the environment, which moved since May
2025, not the compiler:
- Windows 32 build: `ocaml/setup-ocaml` crashes under the Node.js 24 that runners now force
  (`Cannot read properties of undefined (reading 'parsedURL')`), and its "second chance" step then
  finds the half-made switch.
- Windows 64 build: builds, but the packaging leaves fewer than the three files its check expects
  (zip, installer, nupkg).
- cpp tests (Linux x64, arm64, mac) and the doc generation test: the CI installs hxcpp's git master,
  and `HXCPP_COMPILE_CACHE: ~/hxcache` reaches the linker with the `~` unexpanded
  (`ld: cannot find ~/hxcache/zlib_sources/lib/...`); an absolute path should do.
- lua test: `cp: cannot stat 'non-existent-src'` while setting up its dependencies.
- mac php test: `Issue7533` (`shiftRightUnsigned`) under the runner's newer PHP.
- mac java/jvm test: the test library's `MyClass_MyAnnotation` is not found (the runner's Java).

Upstream's development branch, run in the same fork on the same day, passed everything: the
fixes are in its CI (C4 takes them over).

### C3: packages attached to a published release — job `release` in `.github/workflows/main.yml`

**How upstream releases** (`extra/release-checklist.txt`, and the 4.3.7 release's files): a
maintainer publishes an empty GitHub release, which creates the tag; the tag's push runs the CI,
whose `deploy` job uploads the packages to Haxe's build server (build.haxe.org, S3; the secrets
exist only in HaxeFoundation); then the maintainer runs hxgithub's `release.n`
([Simn/hxgithub](https://github.com/Simn/hxgithub), `scripts/release`) with their GitHub token. It
downloads the packages from the build server, names them `haxe-<version>-<target>` (`linux64`,
`osx`, `win`, `win64`, as .tar.gz or .zip), takes the installers out of their archives
(`osx-installer.pkg`, `win.exe`, `win64.exe`), uploads them to the release, writes the release's
text from `extra/CHANGES.txt` and updates haxe.org's download pages. For 4.3.7 its eight files were
uploaded within 20 seconds, 1 h 45 min after the release was published; `linux-arm64`, which the
tool does not know, was added by hand a year later.

**What.** haxe-plus has neither the build server nor the tool (bound to HaxeFoundation/haxe), so
the CI does the tool's part itself: the workflow also runs when a release is published
(`release: published`), and after the build jobs the `release` job attaches that run's packages to
the release, named and unpacked as the tool does, `linux-arm64` included (32-bit Windows is no
longer built: C4). The tests run in the same run but do not hold the upload back.

**Releasing.** On GitHub, publish a release of the `haxe4` branch with a new tag `<base>-plus.<n>`
(`4.3.7-plus.1`, ...) and its notes (what changed since the last one, from this file). The run
builds the tag (no revision in `haxe -version`) and attaches `haxe-<tag>-linux64.tar.gz`,
`-linux-arm64.tar.gz`, `-osx.tar.gz`, `-osx-installer.pkg`, `-win64.zip` and `-win64.exe`. Check
the run's tests before announcing. The tag's commit must contain this workflow.

### C4: today's runners and tools — `.github/workflows/main.yml`, `haxe.opam`, `tests/Brewfile`, `tests/runci/targets/{Lua,Hl,Cs}.hx`

**What**, for each failure of the trial run (C2), mostly as upstream's current CI does it:
- 32-bit Windows: its build and test jobs are gone. Its OCaml setup (a fork of `setup-ocaml`)
  no longer runs, and upstream stopped building 32-bit Windows too. The packages lose `win.zip`
  and `win.exe`.
- Windows 64: cygwin now ships GCC 14, which makes incompatible pointer types errors: luv 0.5.13
  and the pcre2 bindings 8.0.3 (which camlp5 needs) no longer compile. The job pins luv 0.5.14
  (whose release notes name exactly this) and pcre2 8.0.4, and haxe.opam accepts luv `>= 0.5.13`
  instead of `= 0.5.13`, as upstream does. Its install and build steps now stop at the first
  failing command, where a failure used to surface only at the artifact check. The mac builds pin
  luv 0.5.13: they pin ctypes 0.21.1, with which 0.5.14 does not compile.
- HashLink: the tests build HashLink 1.15, the release 4.3.7 came out with, instead of master,
  which crashes on 4.3.7's output on Windows (`hl.exe bin/unit.hl`, 0xC0000028). Its
  `CMakeLists.txt` asks for CMake < 3.5, which the runners' CMake 4 refuses unless configured with
  `-DCMAKE_POLICY_VERSION_MINIMUM=3.5`. The Windows tests run on `windows-2022` (Visual Studio
  2022, as 4.3.7's did) rather than `windows-latest`, now Visual Studio 2026, which HashLink 1.15
  predates. On mac, the test installs only what the CI's HashLink build uses (jpeg-turbo, libpng,
  libogg, libvorbis, and `mbedtls@3`, keg-only, passed to CMake as `CMAKE_PREFIX_PATH`) instead of
  HashLink's Brewfile: Homebrew's `mbedtls` is 4, whose `entropy.h` and `ctr_drbg.h`, included by
  1.15's `ssl.c`, are private now, and the Brewfile's SDL, OpenAL, libuv and OpenSSL, which the
  build turns off, were built from source on the Intel runner for 25 to more than 50 minutes. 1.15's
  `ssl.hdll` was checked to build against mbedtls 3.6.7 found this way.
- Homebrew no longer supports Intel macOS (Tier 3 since September 2026, as the runners warn): on
  `macos-15-intel` many formulae have no bottle any more (OCaml, OpenSSL, SDL, opam) and are built
  from source. The mac builds install opam from its release binary (2.6.0, the version Homebrew
  had, so the cached `~/.opam` still fits) instead of Homebrew's, which took 40 of the x64 build's
  48 minutes building OCaml 5 and OpenSSL; `tests/Brewfile` no longer lists it. Upstream builds
  both mac packages on arm64 now (x64 under Rosetta), and keeps `macos-15-intel` for HashLink's JIT
  only.
- C# test `tests/misc/cs/csTwoLibs`: its four variants are built into the same `bin/`, and hxcs
  copies a referenced DLL only when it looks newer, to the second: a variant built within the
  second of the previous one kept the previous `haxeboot.dll` (`haxe.root.Array` not found). A
  race of the test that faster compilations hit more often; each variant now starts from a clean
  `bin/`.
- Known and not fixed: the display tests `cases.Issue6405` and `cases.Issue5172` (in the Windows
  macro job) fail now and then with errors from unrelated modules (`ExampleJSGenerator.hx:102:
  Class<haxe.macro.Context> has no field error`, `Lock.hx`, the test's own `src/`). Their `usage`
  request types every module that mentions the name (`SyntaxExplorer.explore_uncached_modules`).
  Upstream's, unresolved there: [HaxeFoundation/haxe#11756](https://github.com/HaxeFoundation/haxe/issues/11756)
  ("randomly failing for a while and nobody knows why"; rerunning the job fails again, the next
  commit passes). Seen here in one of the first three runs with Windows tests, all of the same
  compiler. Rerun all jobs, so that the compiler is built again, not only the failed one.
- The compilation server's tests (in the js job) can time out on the slow `macos-15-intel`
  runners: each test starts a haxe server within utest's 250 ms. They pass locally in every JIT
  mode and passed on the same runners in the first trial run; rerun the job.
- `HXCPP_COMPILE_CACHE` is `${{ github.workspace }}/hxcache` in every test job: hxcpp passes the
  `~` of `~/hxcache` to the linker as it is.
- Lua: hererocks is installed from its git repository with pipx (as upstream does): the released
  one can no longer fetch LuaJIT 2.0, and the runner's pip installs the git one as `UNKNOWN`,
  without its command.
- PHP tests on mac and Windows: PHP 8.4 instead of the runners' 8.5, whose warnings on float-to-int
  casts it cannot represent 4.3.7's PHP runtime turns into exceptions (`php.Boot.shiftRightUnsigned`,
  Issue7533). Changing the runtime would change PHP output, which haxe-plus does not do.
- mac Java test: JDK 11 (as on Linux) instead of the runner's JDK 21, whose class files 4.3.7's
  Java library reader does not fully read (`MyClass_MyAnnotation` not found).

**Porting.** For haxe5, take upstream's CI of that release as it is; C4 is only for 4.3.7's.

## Rejected ideas

- **Stores without write barrier into fresh arrays** (through an `int array` view): OCaml 4.14
  polls at function entries and loop back-edges; a signal or thread switch there can run a minor
  collection, promote the half-filled array, and a later unbarriered store of a young value would
  corrupt the heap.
- **Fusing encode_meta's `vfunN` wrappers into its closures**: about 0.5%, and it needs new
  functions in MacroApi's `InterpApi`. Not worth it alone.
- **Caching encoded values** (metadata objects, types) across calls: the objects are mutable and
  their identity is observable.
- **Skipping environments in leaf functions**: stack traces and error positions read the chain.
- **Assuming no Haxe threads in `get_eval`**: would turn an internal error into silent success.
- **Larger minor heaps after R12** (64M, 128M words): slower than 32M; 16M promotes more.
- **`--times` to split the time**: reflaxe.CPP's work runs in callbacks outside its timers; use a
  sampling profiler.

## Pitfalls learned

- `Array.make` of more than 256 elements with a young initial value forces a minor collection,
  and `Array.map`, `init`, `of_list`, `DynArray.to_array` and `Array.stable_sort` all start that
  way (R12).
- Every store of a pointer into an array or a mutable field calls the write barrier (`caml_modify`,
  a C call), even into a young block; array literals use initializing stores instead (R4, R3).
- Closures that capture variables allocate on every call that creates them; top-level recursive
  functions taking what they use do not.
- The generic `Hashtbl`, `=`, `<>`, `compare` and `List.mem` are C calls; specialize them (R1, R9,
  R10).
- `OCAMLRUNPARAM` set disables the built-in GC settings entirely.
- The macOS `sample` profiler loses callers in OCaml frames (no frame pointers): read self time. To
  map a JIT symbol `camlJit_<key>__fun_N` to Haxe code: copy the binary to a directory of its own
  with its own eval-jit.conf and empty cache, build with `HAXE_EVAL_JIT_LOG=1 HAXE_EVAL_JIT_DUMP=dir`
  (the log names each unit's class), then `ocamlopt -S` the unit and look for `fun_N`.
- Dynlink: a probe function registered through `vfunction` receives `this`; use
  `vstatic_function`.
- Two classes can generate the same unit source: compile each key once.
- reflaxe wraps declarations in `TMeta` (for its `extractStringFromMeta`): peel wrappers wherever
  evalJit does.
- ocamlopt takes minutes on the largest generated functions (and fails on frames past 32 KB on
  arm64): hence the size cap.
- Counting a class's calls says little about its work: rarely called driver classes run loops and
  local functions (J2).
- On a busy machine a 45 s build varies by ±3 s: compare configurations with the same binary where
  possible (a different binary alone moves code layout), interleaved, and several pairs.

## Porting to another Haxe version

For `haxe5` (from `5.0.0-preview.1`) or a newer Haxe 4 release:

1. Branch from the release tag: `git checkout -b haxe5 5.0.0-preview.1`.
2. Toolchain: read the new haxe.opam. Everything was verified on OCaml 4.14.2. On OCaml 5, check
   `Dynlink.loadfile_private`, ocamlopt's flags (`-linscan`), the GC parameters (G1) and
   `caml_make_vect`'s forced collection (R12).
3. Take the groups one at a time, in this order: R (small and independent), G1, C1, J, then the
   documentation commit. Cherry-pick the commit, and resolve every conflict by re-deriving the
   change from its entry above, never by taking either side blindly.
4. For each R change, recheck the exactness assumption its entry names against the new code.
5. For J, diff the files listed under "Porting" in its entry between the two bases, and carry every
   semantic change into the generator and `evalJitRt.ml`; make it raise `Unsupported` for any new
   typed-AST constructor until it is handled.
6. Build and run `test-suites.sh` (off, strict with a cold cache, warm) and `tests/run.sh`. If an
   expected output differs, compare with the new release's own binary: update `expected.txt` only
   to what the release gives.
7. A real macro-heavy project: byte-identical output against the release binary; interleaved
   timings.
8. Re-tune G1.
9. Update this file: branch table, results, catalog, history.

## Future work

In the order of what they may be worth:

1. **GC (~17%)**: find what keeps ~5 GB alive (`Gc.Memprof`), stop retaining encoded values where
   possible; re-tune G1 after every large change.
2. **Macro API encoders (~15%)**: fewer allocations per encoded object; `encode_meta`,
   `encode_tabstract`, `encode_mtype`, `encode_ref`. Lazy metadata objects would be observable:
   only with care.
3. **flambda**: the release binary was 7% faster than our non-flambda local build of the same
   source. Try an OCaml 4.14 flambda switch (the JIT then compiles with that ocamlopt).
4. **Native `TypedExprTools.map`/`iter`** in eval (~1–2%): must keep the call order of `f`, the
   enum values and objects built, and the stack frames.
5. **A JIT kit for the packages** (C3 ships them with the JIT off): the JIT needs, at run time, the
   ocamlopt of the switch that built the binary, the .cmi/.cmx snapshot and a C toolchain; a
   relocatable eval-jit.conf and bundled ocamlopt and libraries would bring package users from ~90 s
   to 40 s on the benchmark. Windows is untested (pruning uses `rm -rf`).
6. **Coverage**: run tests/display and tests/optimization with the JIT.
7. **The first compilation of a heavy project** runs closure-compiled (J2): 82 s instead of 44 s on
   the reflaxe.CPP build, once per project and cache. Removing it needs promotion within the run:
   functions behind a stable function value whose body is swapped once the project turns heavy
   (identity is observable, so the value must stay), and units compiled in the background.

## History

- 2026-09-29 — `haxe4` created from 4.3.7 with J, R1–R12, G1 and C1; verified as above on recompsx
  (Crash Bash through reflaxe.CPP, 331 → 40.5 s; recompiler 6.8 → 2.8 s). The repository became
  a fork of HaxeFoundation/haxe (renamed from barisyild/haxe). C2: CI brought up to date for a
  trial run of the release packages. J2: native code only for heavy projects, after measuring the
  JIT's fixed cost on Haxe's tests/unit and hxcpp (4.3.171).
