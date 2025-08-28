load("@prelude//linking:link_info.bzl", "LinkStrategy")
load("@prelude//rust:build_params.bzl", "MetadataKind")
load("@prelude//rust:context.bzl", "DepCollectionContext")
load("@prelude//rust:link_info.bzl", "RustDependency", "RustLinkInfo", "resolve_deps")
load("@prelude//rust:rust_toolchain.bzl", "PanicRuntime", "RustToolchainInfo")

SYSROOT_CRATES = [
    "alloc",
    "compiler_builtins",
    "core",
    "panic_abort",
    "panic_unwind",
    "proc_macro",
    "std",
    "test",
]

RustDistInfo = provider(fields = {
    "artifacts": dict[str, Artifact],
})

def _rust_tool_impl(ctx: AnalysisContext) -> list[Provider]:
    llvm = ctx.attrs.llvm[DefaultInfo].default_outputs[0]
    exe = ctx.attrs.exe[DefaultInfo].default_outputs[0]

    dist = ctx.actions.declare_output("toolchain", dir = True)
    ctx.actions.run(
        [
            ctx.attrs._frob[RunInfo],
            cmd_args(llvm, format = "llvm={}", relative_to = dist),
            cmd_args(exe, format = "exe={}"),
            cmd_args(dist.as_output(), format = "dist={}"),
            ["--mkdir", "{dist}"],
            ["--mkdir", "{dist}/bin"],
            ["--cp", "{exe}", "{dist}/bin/" + ctx.label.name],
            ["--symlink", "{llvm}/lib", "{dist}/lib"],
            ["--elaborate", "{dist}/lib"],
        ],
        category = "dist",
    )

    tool = dist.project("bin").project(ctx.label.name).with_associated_artifacts([dist])

    return [
        DefaultInfo(
            default_output = tool,
            sub_targets = {
                name: [providers[DefaultInfo]]
                for name, providers in ctx.attrs.exe[DefaultInfo].sub_targets.items()
            },
        ),
        RunInfo(tool),
        RustDistInfo(artifacts = {"bin/" + ctx.label.name: exe}),
    ]

rust_tool = rule(
    impl = _rust_tool_impl,
    attrs = {
        "exe": attrs.dep(),
        "llvm": attrs.dep(),
        "_frob": attrs.default_only(attrs.exec_dep(providers = [RunInfo], default = "//stage0:frob")),
    },
    supports_incoming_transition = True,
)

def _sysroot_impl(ctx: AnalysisContext) -> list[Provider]:
    dep_ctx = DepCollectionContext(
        advanced_unstable_linking = True,
        include_doc_deps = False,
        is_proc_macro = False,
        explicit_sysroot_deps = None,
        panic_runtime = PanicRuntime("unwind"),
    )

    all_deps = resolve_deps(ctx = ctx, dep_ctx = dep_ctx)

    rust_deps = []
    for crate in all_deps:
        rust_deps.append(RustDependency(
            info = crate.dep[RustLinkInfo],
            label = crate.dep.label,
            dep = crate.dep,
            name = crate.name,
            flags = crate.flags,
            proc_macro_marker = None,
        ))

    rustc_target_triple = ctx.attrs.rust_toolchain[RustToolchainInfo].rustc_target_triple

    sysroot_content = {}
    for dep in rust_deps:
        strategy = dep.info.strategies[LinkStrategy("static_pic")]
        dep_metadata_kind = MetadataKind("link")
        artifact = strategy.outputs[dep_metadata_kind]
        path = "lib/rustlib/{}/lib/{}".format(rustc_target_triple, artifact.basename)
        sysroot_content[path] = artifact

        for artifact in strategy.transitive_deps[dep_metadata_kind].keys():
            path = "lib/rustlib/{}/lib/{}".format(rustc_target_triple, artifact.basename)
            sysroot_content[path] = artifact

    sysroot = ctx.actions.copied_dir("sysroot", sysroot_content)
    return [
        DefaultInfo(default_output = sysroot),
        RustDistInfo(artifacts = sysroot_content),
    ]

sysroot = rule(
    impl = _sysroot_impl,
    attrs = {
        "deps": attrs.set(attrs.dep()),
        "named_deps": attrs.default_only(attrs.dict(key = attrs.string(), value = attrs.dep(), default = {})),
        "flagged_deps": attrs.default_only(attrs.set(attrs.tuple(attrs.dep(), attrs.list(attrs.string())), default = [])),
        "rust_toolchain": attrs.default_only(attrs.toolchain_dep(providers = [RustToolchainInfo], default = "toolchains//:rust")),
    },
    supports_incoming_transition = True,
)

def _rust_dist_impl(ctx: AnalysisContext) -> list[Provider]:
    dist = ctx.actions.declare_output("dist", dir = True)
    script = [
        ctx.attrs._frob[RunInfo],
        cmd_args(dist.as_output(), format = "dist={}"),
        ["--mkdir", "{dist}"],
    ]

    for dep in ctx.attrs.deps:
        for relative_path, artifact in dep[RustDistInfo].artifacts.items():
            script.extend(["--overlay", artifact, "{dist}/" + relative_path])

    ctx.actions.run(script, category = "dist")
    return [DefaultInfo(default_output = dist)]

rust_dist = rule(
    impl = _rust_dist_impl,
    attrs = {
        "deps": attrs.set(attrs.dep(providers = [RustDistInfo])),
        "_frob": attrs.default_only(attrs.exec_dep(providers = [RunInfo], default = "//stage0:frob")),
    },
)
