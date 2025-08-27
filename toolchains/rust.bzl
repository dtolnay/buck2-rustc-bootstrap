load(
    "@prelude//rust:rust_toolchain.bzl",
    "PanicRuntime",
    "RustExplicitSysrootDeps",
    "RustToolchainInfo",
)
load("//target:target_triple.bzl", "TargetTriple")

def _rust_toolchain_impl(ctx: AnalysisContext) -> list[Provider]:
    sysroot_path = None
    explicit_sysroot_deps = None
    if ctx.attrs.sysroot == None:
        explicit_sysroot_deps = RustExplicitSysrootDeps(
            core = None,
            proc_macro = None,
            std = None,
            panic_unwind = None,
            panic_abort = None,
            others = [],
        )
    elif isinstance(ctx.attrs.sysroot, dict):
        explicit_sysroot_deps = RustExplicitSysrootDeps(
            core = ctx.attrs.sysroot.pop("core", None),
            proc_macro = ctx.attrs.sysroot.pop("proc_macro", None),
            std = ctx.attrs.sysroot.pop("std", None),
            panic_unwind = ctx.attrs.sysroot.pop("panic_unwind", None),
            panic_abort = ctx.attrs.sysroot.pop("panic_abort", None),
            others = ctx.attrs.sysroot.values(),
        )
    elif isinstance(ctx.attrs.sysroot, Dependency):
        sysroot_path = ctx.attrs.sysroot[DefaultInfo].default_outputs[0]

    return [
        DefaultInfo(),
        RustToolchainInfo(
            advanced_unstable_linking = True,
            clippy_driver = ctx.attrs.clippy_driver[RunInfo],
            compiler = ctx.attrs.compiler[RunInfo],
            explicit_sysroot_deps = explicit_sysroot_deps,
            panic_runtime = PanicRuntime("unwind"),
            rustc_flags = ctx.attrs.rustc_flags,
            rustc_target_triple = ctx.attrs.target_triple[TargetTriple].value,
            rustdoc = ctx.attrs.rustdoc[RunInfo],
            rustdoc_flags = ctx.attrs.rustdoc_flags,
            sysroot_path = sysroot_path,
        ),
    ]

rust_toolchain = rule(
    impl = _rust_toolchain_impl,
    attrs = {
        "clippy_driver": attrs.exec_dep(providers = [RunInfo]),
        "compiler": attrs.exec_dep(providers = [RunInfo]),
        "rustc_flags": attrs.list(attrs.arg(), default = []),
        "rustdoc": attrs.exec_dep(providers = [RunInfo]),
        "rustdoc_flags": attrs.list(attrs.arg(), default = []),
        "sysroot": attrs.one_of(
            # None = no sysroot deps
            # Artifact = path to implicit sysroot deps
            # Dict = explicit sysroot deps
            attrs.option(attrs.dep()),
            attrs.dict(key = attrs.string(), value = attrs.dep()),
        ),
        "target_triple": attrs.default_only(attrs.dep(providers = [TargetTriple], default = "//target:rustc_target_triple")),
    },
    is_toolchain_rule = True,
)
