load("@prelude//:artifact_tset.bzl", "make_artifact_tset")
load("@prelude//linking:link_info.bzl", "LinkStrategy")
load("@prelude//linking:shared_libraries.bzl", "SharedLibraryInfo")
load("@prelude//rust:build_params.bzl", "MetadataKind")
load("@prelude//rust:context.bzl", "CrateName")
load("@prelude//rust:link_info.bzl", "RustLinkInfo", "RustLinkStrategyInfo")
load("@toolchains//:rust.bzl", "RustcFlags")

def keep(default: str) -> (str, str):
    stage, subtarget = default.removeprefix("rust//").split(":")
    if stage not in ["stage1", "stage2"]:
        fail("unexpected keep target:", default)
    return (default, stage)

def name_of_keep(stage: str, *, default: str) -> str:
    keep = read_config("keep", stage)

    if keep == None:
        keep = default
    elif len(glob([keep + "/**"])) == 0:
        fail("no keep toolchain found in ./keep/{}".format(keep))

    if len(glob([keep + "/**"])) != 0:
        banner = "=" * 64
        warning("\n{}\nWARNING: using {} toolchain from ./keep/{}\n{}".format(banner, stage, keep, banner))

    return keep

def _prebuilt_rust_library(
        actions: AnalysisActions,
        crate: str,
        rlib: Artifact) -> list[Provider]:
    return [
        DefaultInfo(default_output = rlib),
        RustLinkInfo(
            crate = CrateName(
                simple = crate,
                dynamic = None,
            ),
            strategies = {
                strategy: RustLinkStrategyInfo(
                    outputs = {m: rlib for m in MetadataKind},
                    transitive_deps = {m: {} for m in MetadataKind},
                    transitive_proc_macro_deps = set(),
                    pdb = None,
                    external_debug_info = make_artifact_tset(actions = actions),
                )
                for strategy in LinkStrategy
            },
            merged_link_infos = {},
            linkable_graphs = [],
            shared_libs = SharedLibraryInfo(),
            exported_link_deps = [],
        ),
    ]

def _keep_stage_impl(ctx: AnalysisContext) -> list[Provider]:
    libraries = {}
    rustc_flags = set()

    for rlib in ctx.attrs.libs:
        crate = rlib.basename.removeprefix("lib").split("-", 1)[0]
        libraries[crate] = _prebuilt_rust_library(
            actions = ctx.actions,
            crate = crate,
            rlib = rlib.with_associated_artifacts(ctx.attrs.libs),
        )
        parent = rlib.short_path.rsplit("/", 1)[0]
        rustc_flags.add("-Ldependency=keep/{}".format(parent))

    return [
        RunInfo(cmd_args(exe, hidden = ctx.attrs.libs + ctx.attrs.llvm))
        for exe in ctx.attrs.rustc
    ] + [
        DefaultInfo(sub_targets = libraries),
        RustcFlags(flags = list(rustc_flags)),
    ]

keep_stage = rule(
    impl = _keep_stage_impl,
    attrs = {
        "libs": attrs.set(attrs.source()),
        "llvm": attrs.set(attrs.source()),
        "rustc": attrs.set(attrs.source()),
    },
)
