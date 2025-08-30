https://github.com/user-attachments/assets/78b9050a-dd2a-406b-9c5f-748d41f66ef4

## Example commands

These do not need to be run in any particular order.

```console
  # Download crates.io dependencies
$ buck2 uquery 'kind(crate_download, ...)' | xargs buck2 build

  # Typecheck stage1 compiler using bootstrap compiler with #[cfg(bootstrap)]
$ buck2 build stage1:rustc[check]

  # Build and run stage1 compiler
$ buck2 build stage1:rustc
$ buck2 run stage1:rustc -- --version --verbose

  # Typecheck standard library using stage1 compiler
$ buck2 build stage1:std[check]

  # Build and run stage2 compiler in #[cfg(not(bootstrap))] using stage1 compiler
$ buck2 build stage2:rustc
$ buck2 run stage2:rustc -- --version --verbose

  # Build various intermediate crates (stage1 by default)
$ buck2 build :rustc_ast
$ buck2 build :rustc_ast -m=stage2
$ buck2 build :syn-2.0.106 --target-platforms //platforms/stage1:compiler

  # Document a crate using stage0 or stage1 rustdoc
$ buck2 build :rustc_ast[doc] --show-simple-output
$ buck2 build :rustc_ast[doc] -m=stage2 --show-simple-output

  # Print rustc warnings in rendered or JSON format
$ buck2 build :rustc_ast[diag.txt] --out=-
$ buck2 build :rustc_ast[diag.json] --out=-

  # Run clippy on a crate using stage0 or stage1 clippy
$ buck2 build :rustc_ast[clippy.txt] --out=-
$ buck2 build :rustc_ast[clippy.txt] -m=stage2 --out=-

  # Expand macros
$ buck2 build :rustc_ast[expand] --out=-

  # Report documentation coverage (percentage of public APIs documented)
$ buck2 build :rustc_ast[doc-coverage] --out=- | jq

  # Produce rustc and LLVM profiling data
$ buck2 build :rustc_ast[profile][rustc_stages][raw] --show-output
$ buck2 build :rustc_ast[profile][llvm_passes] --show-output
```

## Configurations

The following platforms are available for use with `--target-platforms`:

| target platform | uses rustc, rustdoc, clippy |
|---|---|
| `//platforms/stage1:compiler-build-script` | downloaded stage0 |
| `//platforms/stage1:compiler` | downloaded stage0 |
| `//platforms/stage1:library-build-script` | downloaded stage0 |
| `//platforms/stage1:library` | built-from-source stage1 |
| `//platforms/stage2:compiler-build-script` | built-from-source stage1 |
| `//platforms/stage2:compiler` | built-from-source stage1 |
| `//platforms/stage2:library-build-script` | built-from-source stage1 |
| `//platforms/stage2:library` | built-from-source stage2 |

The "build-script" platforms compile without optimization. These are used for
procedural macros and build.rs. The non-build-script platforms compile with a
high level of optimization.

The "build-script" and "compiler" platforms provide implicit sysroot
dependencies so that `extern crate std` is available without declaring an
explicit dependency on a crate called `std`. The non-build-script "library"
platforms require explicit specification of dependencies.

Most targets have a `default_target_platform` set so `--target-platforms` should
usually not need to be specified. Use the modifier `-m=stage2` to replace the
default stage1 target platform with the corresponding stage2 one.

## Cross-compilation

This project is set up with a bare-bones C++ toolchain that relies on a system
linker, which usually does not support linking for a different platform. But we
do support type-checking, rustdoc, and clippy for different platforms, including
both stage1 and stage2.

Use the modifiers `aarch64`, `riscv64`, `x86_64`, `linux`, `macos`, `windows`,
or use target platforms like `//platforms/cross:aarch64-unknown-linux-gnu`.

```console
  # Typecheck rustc in stage1 for aarch64 linux (two equivalent ways)
$ buck2 build stage1:rustc[check] --target-platforms //platforms/cross:aarch64-unknown-linux-gnu
$ buck2 build stage1:rustc[check] -m=aarch64 -m=linux

  # Typecheck rustc in stage2 using stage1 rustc built for the host
$ buck2 build stage2:rustc[check] -m=aarch64 -m=linux

  # Build documentation for a different platform
$ buck2 build :rustc_ast[doc] -m=aarch64 -m=linux

  # Perform clippy checks for a different platform
$ buck2 build :rustc_ast[clippy.txt] -m=aarch64 -m=linux --out=-
```

## Whole-repo checks

The commands above like `buck2 build :rustc_ast[clippy.txt]` report rustc
warnings and clippy lints from just a single crate, not its transitive
dependency graph like Cargo usually does. There is a [BXL] script for producing
warnings for a whole dependency graph of a set of targets:

[BXL]: https://buck2.build/docs/bxl

```console
  # Report warnings from every dependency of rustc:
$ buck2 bxl scripts/check.bxl:main -- --target stage1:rustc | xargs cat

  # Run clippy on every dependency of rustc:
$ buck2 bxl scripts/check.bxl:main -- --target stage1:rustc --output clippy.txt | xargs cat

  # Run clippy on every dependency of rustc and report lints in JSON:
$ buck2 bxl scripts/check.bxl:main -- --target stage1:rustc --output clippy.json | xargs cat
```

## "Keep-stage" workflows

The Rust repo's Cargo-based x.py bootstrap system has a pair of flags
`--keep-stage=` and `--keep-stage-std=` to ask it to bypass recompiling a
particular stage. These are useful when iterating on compiler changes that
definitely do not affect the ABI of the standard library, such as a diagnostics
improvement.

Here, the same thing is accomplished using the _./keep/last1_ and _./keep/last2_
directories. Any toolchain written to these directories supplants the
from-source stage1 and stage2 toolchain respectively.

```console
  # Build stage1 rustc + std, write output to ./keep/last1
  # All further builds will use this as their stage1, instead of rebuilding stage1
$ buck2 build stage1:dist --out keep/last1

$ #...Make your compiler code changes

  # Build stage2 using the old stage1 from ./keep/last1, even though rebuilding
  # stage1 from source now would produce something different
$ buck2 build stage2:rustc

  # Old stage1 continues to be used until you make the directory go away
$ git clean -fx keep
$ rm -r keep/last1
$ mv keep/last1 keep/last1.bak
```

The subdirectories "last1" and "last2" are special in that they automatically
become part of every subsequent build command if present. (Any time this
happens, a warning banner is printed as a reminder.) If you prefer an opt-in
model, choose any other directory name and use `-c keep.stage1=` in builds where
you want to use that toolchain.

```console
$ buck2 build stage1:dist --out keep/mine
$ buck2 build stage2:rustc -c keep.stage1=mine
```

To keep only an old stage1 standard library while continuing to rebuild stage1
compilers from source, use `buck2 build stage1:sysroot --out keep/last1`
(instead of `stage1:dist`).

## Build speed

Several factors add to make Buck-based bootstrap consistently faster than the
Rust repo's custom x.py Cargo-based bootstrap system.

On my machine, building stage2 rustc takes about 6.5 minutes with `buck2 clean;
time buck2 build stage2:rustc` and about 8 minutes with `x.py clean && time x.py
build compiler --stage=2`. The Buck build is **20%** faster.

The difference widens when building multiple tools, not only rustc. Buck will
build an arbitrary dependency graph concurrently while x.py is limited to
building each different tool serially. `buck2 build stage2:rustc stage2:rustdoc
stage2:clippy-driver` takes +46 seconds longer than building rustc alone, because
Clippy is the long pole and takes exactly that much longer to build than
rustc\_driver, which it depends on. But the equivalent `x.py build compiler
src/tools/rustdoc src/tools/clippy --stage=2` takes +153 seconds longer than
building rustc alone, because rustdoc takes +69 seconds and clippy takes +84
seconds, and all three tools build serially. Altogether Buck is **32%** faster
at building this group of tools.

Some less significant factors that also make the Buck build faster:

- x.py builds multiple copies of many crates. For example the `tracing` crate
  and its nontrivial dependency graph are built separately when rustc depends on
  tracing versus when rustdoc depends on tracing. In the Buck build, there is
  just one build of `tracing` that both rustc and rustdoc use.

- In x.py, C++ dependencies (like the `llvm-wrapper` built by rustc\_llvm's
  build.rs) build pretty late in the build process, after a stage1 standard
  library is finished compiling, after rustc\_llvm's build-dependencies and
  build script are finished compiling. In Buck the llvm-wrapper build is one of
  the first things to build because it does not depend on any Rust code or
  anything else other than the unpack of downloaded LLVM headers.

- The previous item is exacerbated by the fact that x.py builds llvm-wrapper
  multiple times, separately for stage1 and stage2, because there is no facility
  for the stage2 compiler build's build scripts to share such artifacts with the
  stage1 build. Buck builds llvm-wrapper once because the sources are all the
  same, the same C++ compiler is used by stage1 and stage2, and the flags to the
  C++ compiler are the same, so we are really talking about one build action.
  Stage1 and stage2 differ only in what Rust compiler is used and whether
  `--cfg=bootstrap` is passed to Rust compilations, neither of which is relevant
  to a C++ compilation.

Incremental builds are faster in Buck too. After already having built it,
rebuilding rustc\_ast with a small change in its lib.rs takes 1.625 seconds with
`buck2 build :rustc_ast[check]` and 2.6 seconds with `x.py check
compiler/rustc_ast`. The actual underlying rustc command to typecheck rustc\_ast
used by both build systems takes 1.575 seconds, so Buck's overhead for this is
50 milliseconds (0.05 seconds) while x.py's and Cargo's is about 1 second, an
order of magnitude larger.

At least 2 factors contribute to x.py's overhead:

- x.py does not have a granular view of the dependency graph. At a high level it
  knows that building the compiler requires building the standard library first,
  but within the standard library or compiler it does not manage what crate
  depends on which others, and which source files go into which crate. Even when
  local changes definitely do not require rebuilding the standard library, x.py
  must still delegate to a sequence of slow serial Cargo invocations whereby
  Cargo could choose to rebuild the standard library if it were necessary (which
  it isn't), adding latency. In contrast, a single Buck process coordinates the
  entire dependency graph from top-level targets to build actions to input files
  which those actions operate on. If is quick to map from a file change to
  exactly which build actions need to be kicked off right away.

- The state of the Buck build graph is preserved in memory across CLI commands.
  Like how IDEs rely on a long-running language server (LSP) that preserves
  facts about the user's program in complex data structures in memory to serve
  IDE features with low latency, Buck does this for build graphs. In contrast,
  Cargo reloads the world each time it runs, including parsing Cargo.toml files
  and lockfiles and Cargo config files. And as mentioned, x.py will do multiple
  of these Cargo invocations serially.

## Remote execution

With remote execution, your build can be distributed across a pool of remote
cores that is larger than what is available on your local machine, and can
leverage a remote cache to skip over build steps that have already previously
succeeded.

Remote execution _does not_ involve naively uploading and downloading the input
and output of every compiler command. The bytes stay in the cloud, and only
small checksums are received by your machine, as well as the end result of the
build (which you can skip with `--materializations=none` or `-M none` when you
only care about the success or compiler diagnostics, not the resulting binary).

To enable remote execution, add the following 4 entries to `.buckconfig.local`
in the repo root, using values given by your remote execution provider. The
format for some specific services is shown below, but anything that supports
Bazel's [remote execution API] is likely to work.

[remote execution API]: https://github.com/bazelbuild/remote-apis

**BuildBuddy** has a generous free tier with 80 cores of parallelism on fast
machines, and is easy to sign up for.

```ini
[buck2_re_client]
engine_address = remote.buildbuddy.io
action_cache_address = remote.buildbuddy.io
cas_address = remote.buildbuddy.io
http_headers = x-buildbuddy-api-key:zzzzzzzzzzzzzzzzzzzz
```

**NativeLink**

```ini
[buck2_re_client]
engine_address = scheduler-whoami-zzzzzz.build-faster.nativelink.net
action_cache_address = cas-whoami-zzzzzz.build-faster.nativelink.net
cas_address = cas-whoami-zzzzzz.build-faster.nativelink.net
http_headers = x-nativelink-api-key:zzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz
```
