# haxe-plus

haxe-plus is a set of forks of Haxe releases that make the **eval** target — the interpreter that
runs macros, `--interp` and `--run` — much faster, without changing what any program computes.
Each branch is one Haxe release plus the changes this file describes.

| Branch | Base | State |
|---|---|---|
| `haxe4` | 4.3.7, the latest Haxe 4 release | done and verified |
| `haxe5` | 5.0.0-preview.1, the latest Haxe 5 release | ported from `haxe4` (this file describes it) |

The repository ([barisyild/haxe-plus](https://github.com/barisyild/haxe-plus)) is a GitHub fork of
HaxeFoundation/haxe, so upstream tags and history are one fetch away. Only the branches above are
haxe-plus; the others (`development` and pull-request branches for upstream) are not.

**This file is the project's memory.** It records every change: where it is, what it does, why it
cannot change a program's behaviour, what it bought, and what to check when carrying it to another
Haxe version. Any commit that changes haxe-plus updates this file in the same commit.

`haxe -version` still prints the base version (5.0.0-preview.1), so that version checks in
libraries and build tools keep working.

This branch is `haxe4`'s changes carried to Haxe 5.0.0-preview.1: the same catalog, with what the
port had to change noted under each entry (**Haxe 5**) and gathered in
[The port from haxe4](#the-port-from-haxe4).

Contents: [Results](#results) · [The rule: exact](#the-rule-exact) · [Using it](#using-it) ·
[Verification](#verification) · [The port from haxe4](#the-port-from-haxe4) ·
[Change catalog](#change-catalog) · [Rejected ideas](#rejected-ideas) ·
[Pitfalls](#pitfalls-learned) · [Porting](#porting-to-another-haxe-version) · [Future work](#future-work) ·
[History](#history)

## Results

### Haxe 5

Two eval workloads, on an Apple M3 Pro (macOS 27, 18 GB), in one session of interleaved runs, every
output compared byte for byte with the unchanged build's:

| | recompsx's recompiler (`--run`: Crash Bash to Haxe) | Haxe's tests/unit (`compile-macro.hxml`) |
|---|---|---|
| Haxe 5.0.0-preview.1, built here | 7.52 / 6.84 / 6.84 s | 23.85 / 23.89 / 22.75 s |
| haxe-plus `haxe5`, JIT off (R*, G1) | 6.40 / 6.40 / 6.52 s | 22.10 / 21.61 / 20.36 s |
| haxe-plus `haxe5` | **3.19 / 3.20 / 3.23 s** | **10.29 / 10.65 / 10.22 s** |

The recompiler generated the same files in every run, and the same as Haxe 4.3.7 does; tests/unit
passed in every run. A project's first compilation runs closure-compiled and learns that it is
heavy (J2), at no measurable cost (recompiler: 6.44 / 6.52 / 6.41 s, JIT off 6.58 / 6.38 / 6.46 s);
the next compiles its units once per build of the compiler: the recompiler's 61 units took 11.7 s
of ocamlopt 5.3, tests/unit's 1693 units about 90 s.

The reflaxe.CPP build `haxe4` was tuned on (331 s to 40.5 s) does not compile on Haxe 5:
reflaxe.CPP's standard library overrides are 4.3's (`haxe.ds.StringMap.size`: "Public field size is
not part of core type"). The tables below are `haxe4`'s: how each change was found and what it
bought on 4.3.7. The same changes are in this branch.

### On haxe4 (4.3.7), where the changes were made

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

`haxe5` builds like Haxe 5.0.0-preview.1 (`extra/BUILDING.md`): an OCaml 5.3 switch with
haxe.opam's dependencies, plus pcre2, zlib, neko and mbedtls 2.x. Verified with: OCaml 5.3.0 (no
flambda), opam 2.3.0, dune 3.24.2, ocamlfind 1.9.8, sedlex 3.7, ppx_parser 0.2.1, xml-light 2.5,
extlib 1.8.0, sha 1.15.4, camlp-streams 5.0.1, luv 0.5.14, ctypes 0.24.0, integers 0.8.0, ipaddr
5.6.2, terminal_size 0.2.0, domainslib 0.5.2, saturn 1.0.0, thread-local-storage 0.2; pcre2 10.47,
neko 2.4.1, mbedtls 2.28.9; macOS 27 on arm64. `opam install haxe --deps-only --assume-depexts`
after `opam pin add haxe . --no-action` installs the libraries without asking Homebrew for neko and
zlib.

**On macOS, give the mbedtls headers with `CPATH` (or `-I`), not `C_INCLUDE_PATH`**, when another
mbedtls is installed in `/usr/local`: clang searches `/usr/local/include` before `C_INCLUDE_PATH`.
Here that was mbedtls 3.6.3, so `libs/mbedtls`'s stubs were compiled against its headers and linked
with the 2.28 library, whose structures differ (`mbedtls_entropy_context`: 904 bytes against 1032).
The stubs allocate the smaller size and the library initializes the larger: a heap overflow that
crashed eval's TLS (the unit suite's `unitstd/Https.unit.hx`) in 10–40% of runs, in malloc, with the
unchanged 5.0.0-preview.1 built this way too (and 5 in 20 plain HTTPS requests with `haxe4`'s local
build), never with the official 4.3.7 binary.
Guard Malloc (`DYLD_INSERT_LIBRARIES=/usr/lib/libgmalloc.dylib`) stops it at the overflowing
`memset` in `mbedtls_entropy_init` every time. `echo | cc -E -v -x c -` prints the search order.

On macOS with a recent clang, luv 0.5.13 fails to build with `incompatible-function-pointer-types`
errors; `haxe4` installs it with `CC` pointing to a wrapper script that runs
`cc -Wno-error=incompatible-function-pointer-types "$@"`. luv 0.5.14 was installed here with that
wrapper in `PATH` too; whether 0.5.14 needs it was not checked.

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

`haxe5` was checked as `haxe4` was, against the unchanged 5.0.0-preview.1 built the same way:

1. **A real project, byte for byte.** recompsx's recompiler (`--run`, the Haxe 5 benchmark above):
   its generated Haxe compared with `diff -r` against the unchanged build's, in every run of every
   mode; it is also identical to what Haxe 4.3.7 generates.
2. **Haxe's own eval suites**, in the same three modes as `haxe4`'s (JIT off; strict, every class
   native, with a cold cache; the defaults), and the unchanged build for reference:

       HAXE_PLUS_TESTS=<copy>/tests extra/haxe-plus/test-suites.sh ./haxe <log dir>

   | Suite (in tests/) | Command | Unchanged 5.0.0-preview.1 | `haxe5`, every mode |
   |---|---|---|---|
   | unit | `haxe compile-macro.hxml` | ALL TESTS OK | ALL TESTS OK |
   | misc | `haxe compile.hxml` | 727 tests, 0 failures | 727 tests, 0 failures |
   | sys | `EXISTS=1 haxe compile-macro.hxml` | ALL TESTS OK | ALL TESTS OK |
   | threads | `haxe build.hxml --interp` | ALL TESTS OK | ALL TESTS OK |
   | nullsafety | `haxe test.hxml` | exit 0 | exit 0 |

   utest 424a718 (the commit tests/RunCi.hx installs), haxeserver and hxnodejs as dev libraries in
   a repository of Haxe 5's own haxelib (`make haxelib`), which is what `HAXELIB_PATH` points to.
   The suites ran on a copy of tests/ outside the tree (`HAXE_PLUS_TESTS`), because a local
   `.haxelib` in a parent directory hides `HAXELIB_PATH`; the copy must itself be called `tests/`:
   misc/projects/Issue11852 checks that paths end in `tests/misc/...`.
   The compilation server's tests (tests/server, 1401 assertions) pass with the unchanged build and
   in the three modes (27, 29, 28 and 26 s). They need hxjava too (`--jvm` cases), and `std/` next
   to the copy of `tests/` (`ServerTests.test12289` reads `../../std`); the servers they start are
   the `haxe` in `PATH` and inherit the JIT's variables.
3. **Differential tests**: `extra/haxe-plus/tests/run.sh ./haxe`, the same programs as `haxe4`'s.
   The unchanged 5.0.0-preview.1 gives exactly the expected output of `jit-smoke` and `big-arrays`
   (the files are `haxe4`'s, unchanged); `gc-settings` checks G1, which it does not have. All nine
   pass (three programs in three modes).
4. **Measurements**, interleaved, on the recompiler and tests/unit.

## The port from haxe4

Haxe 5.0.0-preview.1 (July 2025) came out of `development`, which left the 4.3 line in 2023. Its
eval runtime changed only moderately since (src/macro/eval: 26 files, +603 −413 lines), so
`haxe4`'s code commits were cherry-picked in their order (J, R, G1, J2) and adapted, each commit
building on its own. What had to change, and why:

- **Build.** OCaml 5.3.0, as the tag's CI uses, with dune ≥ 3.17 and Haxe 5's new libraries
  domainslib, saturn and thread-local-storage, which need OCaml 5. A `src/compiler/version.ml`
  left by a 4.3 build must be deleted: Haxe 5 generates it with dune ("Multiple rules generated").
- **J, Haxe 5's API.** `TFor` is gone (for loops are lowered while typing); `TSwitch` carries a
  record, which the generator turns back into 4.3's (subject, cases, default) triple
  (`switch_parts`); eval's int-keyed tables are `Globals.IntHashtbl` (`caught_types`, the capture
  tables of environment infos, constructor builtins); `build_exception_stack` takes the eval state.
- **J, Haxe 5's semantics**: what evalJit and its emitters changed, compiled code follows.
  - `create_function` and `create_closure` run the arguments and the body under `Std.finally`, which
    pops the environment also when an exception leaves the function (4.3 left that to the `try`
    that caught it). Compiled functions do the same, with `match ... with exception` instead of the
    two closures `Std.finally` would take.
  - `process_arguments` reports arguments left over as `Bad number of arguments: 0 vs. n` (4.3:
    `Something went wrong`): `EvalJitRt.too_many_arguments` takes them.
  - Reification in macros emits `$__mk_pos__` alone, which evalJit evaluates to `encode_pos` of the
    identifier's own position (4.3 called it with file, min and max): compiled as `N.encode_pos` of
    a position requirement, a new value each time. As a callee it is an ordinary identifier now.
  - `push_environment` gives `EKEntrypoint` environments no parent; compiled functions are never
    `EKEntrypoint`, so `EvalJitRt.push_env` is unchanged.
- **R5.** Haxe 5 moved MacroContext's local `Eval` module to `src/macro/eval/eval.ml`. The cached
  `encode_string` goes into a local `module Eval = struct include Eval ... end` in macroContext.ml,
  so eval's own `encode_string` stays as it is.
- **R9.** Upstream rewrote `decode_ast_path` (it decodes the path's own position too) and `define`;
  `== vnull` is applied to the new code. Upstream's `encode_meta` no longer turns `Invalid_expr`
  into `Invalid expression` in `add`, and the shared closure follows.
- **R11 is dropped**: Haxe 5's `get_eval` reads a `Thread_local_storage`, with neither the
  `Thread.id` call nor the map lookup R11 avoided.
- **R12 is kept**: OCaml 5.3's `caml_uniform_array_make` still forces a minor collection for a young
  initial value past `Max_young_wosize`.
- **G1** is unchanged. OCaml 5 gives every domain a minor heap of that size, which matters only
  with `-D enable_parallelism` (off by default: no domain pool otherwise).
- **J2.** The project's signature takes `class_paths#as_string_list` (Haxe 5's `ClassPaths` object
  replaces 4.3's `class_path` list).
- **Tests.** Haxe 5's suites use utest 424a718, and Haxe 5's own haxelib: 4.3's rejects
  `5.0.0-preview.1` as a version string. `make haxelib` builds it (`extra/haxelib_src`).

## Change catalog

The commits of each branch follow these groups, so each can be taken on its own. On `haxe5`:
"eval: native JIT" (J), "eval: exact run-time caches and fewer allocations" (R1–R12),
"compiler: GC settings for macro-heavy builds" (G1), "eval: native code only for heavy projects"
(J2), "ci: run the CI workflow by hand only" (C1), "ci: attach the packages to a published
release" (C3), "ci: today's runners and tools" and the commits after it (C4), and "haxe-plus:
documentation, scripts, differential tests". The code comments at each change repeat the
essentials.

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

**Haxe 5.** Ported to Haxe 5's typed AST (no `TFor`; `TSwitch` a record, read through
`switch_parts`) and to what its evalJit and emitters changed, which compiled code follows: functions
pop their environment under `Std.finally` semantics (`match ... with exception`), extra arguments
raise `Bad number of arguments: 0 vs. n`, `$__mk_pos__` is an identifier evaluated to `encode_pos`
of its own position, and eval's int-keyed tables are `IntHashtbl`. Details in
[The port from haxe4](#the-port-from-haxe4). Units compile with the OCaml 5.3 switch's ocamlopt, and
`jit-conf.sh` adds the libraries Haxe 5's eval interfaces mention (domainslib, saturn,
thread-local-storage, ipaddr, terminal_size, with their dependencies).

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

**Haxe 5.** The same; the project's class paths come from `class_paths#as_string_list`.

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

**Haxe 5.** Unchanged (the same patch).

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

**Haxe 5.** Unchanged (the same patch).

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

**Haxe 5.** Unchanged (the same patch).

### R4: literal arrays — `values_of_list`, `make_fields` in `src/macro/eval/evalEncode.ml`

**What.** `encode_array` and `encode_enum` turned lists into arrays with `Array.of_list`, which
fills through the write barrier (a C call per element). Lists of up to 16 values become array
literals (allocated inline, initializing stores); 17–32 and more than 256 fill a fresh array of
nulls; 33–256 keep `Array.of_list` (R12 explains the 256). Loops are top-level functions taking
everything they use, so that calling them allocates no closure.

**Exact because** the array has the same values in the same order and is fresh either way.

**Haxe 5.** Unchanged (the same patch).

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

**Haxe 5.** Haxe 5 moved MacroContext's local `Eval` module to `src/macro/eval/eval.ml`;
macroContext.ml defines `module Eval = struct include Eval let encode_string = ... end` in its place.

### R6: ASCII scan — `create_unknown_vstring` in `src/macro/eval/evalString.ml`

**What.** A string that is all ASCII (most are) has as many characters as bytes. `is_ascii` checks
eight bytes at a time (`String.get_int64_ne`, mask `0x8080808080808080`), and only other strings go
through `UTF8.length` (with its exception fallback to the byte length, as before).

**Exact because** for ASCII strings `UTF8.length` returns the byte count.

**Haxe 5.** Unchanged (the same patch).

### R7: shared prototypes for opaque values — `encode_pos`, `encode_lazytype`, `encode_tdecl`, `encode_unsafe` in `src/macro/eval/evalEncode.ml`

**What.** Each opaque macro value (positions, lazy types, type declarations, unsafe refs) got a
freshly made fake prototype; now each kind has one, created eagerly at module initialization (so
eval threads never race on forcing it).

**Exact because** nothing tells the prototypes apart: an instance's prototype is only read for its
content (names, path, kind, parent), and `Type.getClass`/`Type.typeof` look classes up by path.

**Porting.** Recheck that no code compares these prototypes physically or mutates them.

**Haxe 5.** Unchanged (the same patch).

### R8: encode_ref's closures — `encode_ref` in `src/macro/eval/evalEncode.ml`

**What.** The two methods of a `Ref` were `vifun0` of a function ignoring its argument (two
closures each); now one closure each with the same argument handling (none or one argument calls;
more raises `invalid_call_arg_number 1`).

**Haxe 5.** Unchanged (the same patch).

### R9: macro API equality and metadata — `src/macro/macroApi.ml`

**What.** (1) `v = vnull` became `v == vnull` (12 places): `vnull` is an immediate, so the result
is the same and there is no call to the generic comparison. (2) `meta_equal` compares
`Meta.strict_meta` values without the generic comparison: `Custom` and `Dollar` compare their
strings, other constructors are constants compared physically; used in `extract`, `remove`, `has`.
(3) `encode_meta`'s five functions are defined with one `let rec`, sharing one closure. (4)
`encode_mtype` conses its fields onto the list it is given instead of appending with `@`.

**Porting.** Check that `Meta.strict_meta`'s only constructors with arguments are still `Custom` and
`Dollar` of string; if one is added, extend `meta_equal`.

**Haxe 5.** The same changes, on upstream's rewritten `decode_ast_path` (which also decodes
the path's position) and `define`. Haxe 5's `encode_meta` no longer catches `Invalid_expr` in
`add`, and the shared closure follows it.

### R10: `EvalContext.is` — `src/macro/eval/evalContext.ml`

**What.** `v <> vnull` became `v != vnull`, and `List.mem path interfaces` became
`List.exists (fun (i : int) -> i = path) interfaces`: same results without the generic comparison.

**Haxe 5.** Unchanged (the same patch).

### R11: `get_eval` — `src/macro/eval/evalContext.ml`

**What.** Every Haxe call finds its thread's eval with `get_eval`, which asked for the thread's id
(two C calls). Now it compares the thread's descriptor physically with the main thread's (captured
when modules are initialized, on the main thread, id 0) and is `[@inline]`; other threads take the
original path (`get_other_eval`).

**Exact because** the main thread is the one with id 0, and descriptors are unique per thread.

**Haxe 5.** Not applied: Haxe 5's `get_eval` reads a `Thread_local_storage`, with neither the
`Thread.id` call nor the map lookup this avoided.

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

**Haxe 5.** The same patch. OCaml 5.3 still forces the minor collection
(`caml_uniform_array_make`, runtime/array.c).

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

**Haxe 5.** The same values, not measured again on OCaml 5.3. OCaml 5 gives each domain a
minor heap of this size; Haxe 5 starts domains only with `-D enable_parallelism` (off by default).

### C1: CI by hand — `.github/workflows/main.yml`, `extra/github-actions/workflows/main.yml`

**What.** Haxe's own CI workflow ran its whole matrix on every push and pull request; on haxe-plus
branches it runs only when started from the Actions tab (`workflow_dispatch`), or for a published
release (C3). Changed in the template and in the file generated from it. It builds and tests the
base release's targets, with the JIT off (no eval-jit.conf there).

Haxe 5's workflow keeps one run per branch (`concurrency` with `cancel-in-progress`): starting a
run cancels the branch's run still in progress, even one of the same commit ("Canceling since a
higher priority waiting request for CI-refs/heads/haxe5 exists"). Let a run finish before starting
the next.

### C2: CI runners and OCaml versions

**Nothing to change**: the tag's CI builds everything with OCaml 5.3.0, the version `haxe5` was
verified with (on 4.3.7 this entry moved every build to 4.14). The runners it names that no longer
exist are C4's.

**Packages.** The CI builds every release package (Windows 64 zip, installer and nupkg, Linux
x64/arm64 tar.gz, macOS universal tar.gz and installer) and keeps them as the run's artifacts;
upstream's `deploy` job uploads to its S3 and runs only in HaxeFoundation. Packages have the JIT off
(no eval-jit.conf, no OCaml): the run-time changes and G1 only (the recompiler: 6.40 s against the
unchanged build's 6.84 s). C3 attaches them to a release. A build made on a developer's Mac is not a
package: it needs `MACOSX_DEPLOYMENT_TARGET` (it otherwise requires the build machine's macOS) and
static pcre2/mbedtls, which is what the CI does.

### C3: packages attached to a published release — job `release` in `.github/workflows/main.yml`

**What.** As on `haxe4` (its entry tells how upstream releases, with hxgithub's `release.n` and its
build server, which haxe-plus has neither of): the workflow also runs when a release is published
(`release: published`), and after the build jobs the `release` job attaches that run's packages to
the release, named and unpacked as upstream's tool does. Haxe 5's CI names its artifacts as 4.3.7's
did (`linuxBinaries`, `linuxArm64Binaries`, `macBinaries`, `win64Binaries`), so the job is the same.

**Releasing.** On GitHub, publish a release of the `haxe5` branch with a new tag
`5.0.0-preview.1-plus.<n>` and its notes (what changed since the last one, from this file). The run
builds the tag (no revision in `haxe -version`) and attaches `haxe-<tag>-linux64.tar.gz`,
`-linux-arm64.tar.gz`, `-osx.tar.gz`, `-osx-installer.pkg`, `-win64.zip` and `-win64.exe`. Check
the run's tests before announcing. The tag's commit must contain this workflow.

### C4: today's runners and tools — `.github/workflows/main.yml`, `tests/Brewfile`, `tests/runci/targets/{Cpp,Lua}.hx`

**Trial run** ([run 36648151183](https://github.com/barisyild/haxe-plus/actions/runs/36648151183),
the tag's CI as it is, but C1 and C3): the Linux x64 and arm64 builds and the arm64 mac build
passed, and every Linux test but cpp and lua (x64) and cpp (arm64). Failed or never started:
- `mac-build (macos-13)` and `mac-test` (macos-13): the runners are retired; the job waits for one
  forever, and the universal mac package and every mac test with it.
- cpp tests (x64, arm64) and `test-docgen`: `'::__hxcpp_lock_create' has not been declared`. The CI
  installs hxcpp's git master, which since its #1345 (2026-05-31) declares the old thread functions
  only below `HXCPP_API_LEVEL` 500; 5.0.0-preview.1 compiles for API level 500 and still calls them.
- lua (x64): the released hererocks can no longer fetch LuaJIT 2.0, as on `haxe4`.
- `windows64-build`: installing ocamlfind 1.9.8 fails in the opam switch (`install: cannot change
  permissions of 'D:\a/.../_opam/bin': Permission denied`) on today's windows-latest.

**What.** Where the cause is the one `haxe4` met, the fix is the same:
- mac builds on `macos-14` and `macos-15-intel`, mac tests on `macos-15-intel`; opam from its
  release binary (2.6.0) instead of Homebrew's, which has no bottles for Intel macOS 15 and would
  build OCaml and OpenSSL from source; `tests/Brewfile` no longer lists it.
- `HXCPP_COMPILE_CACHE` is `${{ github.workspace }}/hxcache` in every job: hxcpp hands the `~` of
  `~/hxcache` to the linker as it is.
- hererocks is installed from its git repository with pipx, on Linux and (new in Haxe 5's matrix)
  mac, where pipx comes from Homebrew if missing and `~/.local/bin` is added to `PATH`.
- PHP tests on mac and Windows: PHP 8.4 instead of the runners' 8.5, whose warnings on float-to-int
  casts it cannot represent 5.0.0-preview.1's PHP runtime turns into exceptions, as 4.3.7's does
  (`Issue7533`, `TestReflect.testIs`).

New with Haxe 5:
- Flash on mac runs on `macos-14` (arm64, the player under Rosetta), as upstream's mac tests do: on
  the slow `macos-15-intel` runners `TestBigInt.testBigIntRandomPrime`, new in Haxe 5, ran past the
  player's script limit (`Error #1502`), also compiled with `-D swf-script-timeout=60`, the most
  the player allows. It passes on Linux and Windows. That job installs mac-arm64's Neko: the
  universal package's arm64 haxelib cannot load an x86_64 `libneko.2.dylib`.
- hxcpp is pinned to a428509569 (2025-06-05), its last commit before the tag, in
  `tests/runci/targets/Cpp.hx` and in `test-docgen`.
- Windows builds with today's `ocaml/setup-ocaml@v3`, as upstream does, instead of the 3.2.19 the
  tag locked (against 32-bit libraries getting installed, which upstream now keeps out with
  `OPAMEXTERNALSOLVER=builtin-mccs+glpk`): with 3.2.19, installing ocamlfind 1.9.8 fails, on
  windows-2022 as on windows-latest. haxe is pinned explicitly, and Cygwin, now under `C:\.opam`,
  is reached through `opam exec` (`CYG_ROOT` follows it).

**Result.** [Run 36660917877](https://github.com/barisyild/haxe-plus/actions/runs/36660917877)
(110bd2edb): all 44 jobs pass (the release job and the two deploy jobs skip), in 57 minutes. On the
way: the trial run, then [36650048226](https://github.com/barisyild/haxe-plus/actions/runs/36650048226)
(Windows build, mac php and Flash left), [36655754808](https://github.com/barisyild/haxe-plus/actions/runs/36655754808)
(mac Flash, and mac lua on a network timeout while hererocks cloned luarocks) and a fourth one
cancelled by the fifth. The slowest job is the mac HashLink test, 35 minutes: HashLink master's
Brewfile, built from source on Intel. It passes; if it grows, `haxe4`'s C4 fix (install only what
the CI's HashLink build uses) applies here too.

**Porting.** Take the next release's own CI and run it by hand first: what broke here is the world
the CI runs in (runners, Homebrew, git masters of dependencies), not the compiler.

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

As `haxe5` was made from `haxe4` (the details: [The port from haxe4](#the-port-from-haxe4)):

1. Branch from the release tag: `git switch -c <branch> <tag>`. In a tree built for 4.3, delete
   the generated `src/compiler/version.ml` first: Haxe 5 generates it with dune.
2. Toolchain: read the new haxe.opam and the tag's CI (its `OCAML_VERSION`), and make an opam switch
   of that OCaml next to the old one; `opam pin add haxe . --no-action` then
   `opam install haxe --deps-only --assume-depexts`. On macOS pass the mbedtls headers with `CPATH`
   ([Building](#building)). On OCaml 5, `Dynlink.loadfile_private`, `-linscan` and R12's forced
   collection were checked for `haxe5`; G1's values were not re-measured.
3. Build the unchanged release the same way and keep it next to the new branch: every test and
   measurement is compared with it, not with the official binaries.
4. Cherry-pick the code commits in their order (J, R, G1, J2), each building on its own before the
   next is taken, then C1 and C3, then the documentation commit. Resolve every conflict by
   re-deriving the change from its entry in this file, never by taking either side blindly.
5. For each R change, recheck the exactness assumption its entry names against the new code; drop a
   change the new release made unnecessary (R11 for Haxe 5), and say so under its entry.
6. For J, diff between the two bases what compiled code mirrors: `evalJit.ml`, `evalEmitter.ml`
   (above all `create_function`, `create_closure`, `process_arguments`, `emit_try`),
   `evalContext.ml` (`push_environment`, `pop_environment`, `get_eval`), `evalExceptions.ml`,
   `evalValue.ml`, and `texpr_expr` in `tType.ml`. Carry every semantic change into the generator
   and `evalJitRt.ml`; make the generator raise `Unsupported` for any new typed-AST constructor
   until it is handled. The compiler catches changed types, not changed behaviour: a unit that
   fails to compile at run time falls back silently, so run strict.
7. Tests: build the release's own haxelib (`make haxelib`: an older one may reject the version
   string), install the utest commit `tests/RunCi.hx` names, and run on a copy of `tests/` named
   `tests/`, outside any directory with a local `.haxelib`, with `std/` next to it and hxjava in the
   repository for the server tests. Run `test-suites.sh` (off, strict with a cold cache, defaults),
   the server tests, and `tests/run.sh`; if an expected output differs, compare with the unchanged
   release: update `expected.txt` only to what it gives.
8. A real eval workload: byte-identical output against the unchanged build, interleaved timings.
   reflaxe.CPP does not build on Haxe 5; recompsx's recompiler and tests/unit did for `haxe5`.
9. Run the CI by hand on the new branch, and fix what today's runners broke (as C4 did for 4.3.7).
10. Re-tune G1 when the OCaml version changes.
11. Update this file: branch table, results, verification, catalog notes, CI, history, and the
    other branch's branch table.

## Future work

In the order of what they may be worth:

1. **GC (~17%)**: find what keeps ~5 GB alive (`Gc.Memprof`), stop retaining encoded values where
   possible; re-tune G1 after every large change.
2. **Macro API encoders (~15%)**: fewer allocations per encoded object; `encode_meta`,
   `encode_tabstract`, `encode_mtype`, `encode_ref`. Lazy metadata objects would be observable:
   only with care.
3. **flambda**: the release binary was 7% faster than our non-flambda local build of the same
   source (on 4.3.7). Try an OCaml 5.3 flambda switch (the JIT then compiles with that ocamlopt).
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
   (identity is observable, so the value must stay), and units compiled in the background, by
   ocamlopt processes the main thread polls (no OCaml thread needed). Worth it with the JIT kit
   (5), when every CI build and every user's first build is a first compilation (owner's call,
   2026-09-30): about 48 s instead of 82 s estimated.
8. **G1 on OCaml 5.3**: the values are 4.14's; OCaml 5's minor heap is per domain and its major GC
   differs. Re-measure on a heavy Haxe 5 workload.
9. **Cold units on OCaml 5.3**: ocamlopt 5.3 took 11.7 s for the recompiler's 61 units and about 90 s
   for tests/unit's 1693 (once per build of the compiler). Check its flags and `jobs`.
10. **Upstream, not haxe-plus**: `ml_mbedtls_x509_next` (libs/mbedtls, 4.3.7 and 5.x) wraps a
   certificate chain's inner node in a custom block whose finalizer frees it and every node after
   it, which the chain still links to: a double free once both are collected, parent first. Found
   while chasing the crash under [Building](#building); worth an upstream report.

## History

- 2026-09-29 — `haxe4` created from 4.3.7 with J, R1–R12, G1 and C1; verified as above on recompsx
  (Crash Bash through reflaxe.CPP, 331 → 40.5 s; recompiler 6.8 → 2.8 s). The repository became
  a fork of HaxeFoundation/haxe (renamed from barisyild/haxe). C2: CI brought up to date for a
  trial run of the release packages. J2: native code only for heavy projects, after measuring the
  JIT's fixed cost on Haxe's tests/unit and hxcpp (4.3.171).
- 2026-09-30 — C4: the CI passes on today's runners (46 jobs, 32 minutes), after seven runs; the
  Windows display test failure of HaxeFoundation/haxe#11756 stays known.
- 2026-09-30 — `haxe5` created from 5.0.0-preview.1 by porting `haxe4`: J, R1–R12 without R11, G1
  and J2, then C1 and C3 ([The port from haxe4](#the-port-from-haxe4)). Verified against the
  unchanged 5.0.0-preview.1 built the same way: Haxe's eval suites and server tests in three modes,
  the differential tests, the recompiler byte for byte (6.84 → 3.20 s; tests/unit 23.5 → 10.4 s).
  The local builds of both branches had compiled the mbedtls stubs against another mbedtls's
  headers (`C_INCLUDE_PATH` loses to `/usr/local/include`), which crashed eval's TLS now and then:
  `CPATH` ([Building](#building)). C4: the tag's CI on today's runners, green after five runs (44
  jobs, 57 minutes).
