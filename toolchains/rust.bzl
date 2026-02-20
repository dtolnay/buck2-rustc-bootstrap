load(
    "@prelude//rust:rust_toolchain.bzl",
    "PanicRuntime",
    "RustExplicitSysrootDeps",
    "RustToolchainInfo",
)
load("//target:target_triple.bzl", "TargetTriple")

RustcFlags = provider(fields = {
    "flags": list[str],
})

def _rust_toolchain_impl(ctx: AnalysisContext) -> list[Provider]:
    sysroot_path = None
    explicit_sysroot_deps = None
    extra_rustc_flags = []
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
        libs = {}
        for name, lib in ctx.attrs.sysroot.items():
            if isinstance(lib, tuple):
                lib, stage = lib
                if name in ctx.attrs.keep[stage][DefaultInfo].sub_targets:
                    lib = ctx.attrs.keep[stage].sub_target(name)
                    extra_rustc_flags = ctx.attrs.keep[stage][RustcFlags].flags
            libs[name] = lib
        explicit_sysroot_deps = RustExplicitSysrootDeps(
            core = libs.pop("core", None),
            proc_macro = libs.pop("proc_macro", None),
            std = libs.pop("std", None),
            panic_unwind = libs.pop("panic_unwind", None),
            panic_abort = libs.pop("panic_abort", None),
            others = libs.values(),
        )
    elif isinstance(ctx.attrs.sysroot, Dependency):
        sysroot_path = ctx.attrs.sysroot[DefaultInfo].default_outputs[0]

    if isinstance(ctx.attrs.compiler, tuple):
        default_compiler, stage = ctx.attrs.compiler
        keep_compiler = ctx.attrs.keep[stage].get(RunInfo)
        compiler = keep_compiler or default_compiler[RunInfo]
    else:
        compiler = ctx.attrs.compiler[RunInfo]

    return [
        DefaultInfo(),
        RustToolchainInfo(
            advanced_unstable_linking = explicit_sysroot_deps != None,
            clippy_driver = ctx.attrs.clippy_driver[RunInfo],
            compiler = compiler,
            explicit_sysroot_deps = explicit_sysroot_deps,
            panic_runtime = PanicRuntime("unwind"),
            rustc_flags = ctx.attrs.rustc_flags + extra_rustc_flags,
            rustc_target_triple = ctx.attrs.target_triple[TargetTriple].value,
            rustdoc = ctx.attrs.rustdoc[RunInfo],
            rustdoc_flags = ctx.attrs.rustdoc_flags,
            sysroot_path = sysroot_path,
        ),
    ]

def _can_keep(attr: Attr) -> Attr:
    return attrs.one_of(attr, attrs.tuple(attr, attrs.string()))

rust_toolchain = rule(
    impl = _rust_toolchain_impl,
    attrs = {
        "clippy_driver": attrs.exec_dep(providers = [RunInfo]),
        "compiler": _can_keep(attrs.exec_dep(providers = [RunInfo])),
        "keep": attrs.dict(key = attrs.string(), value = attrs.dep()),
        "rustc_flags": attrs.list(attrs.arg(), default = []),
        "rustdoc": attrs.exec_dep(providers = [RunInfo]),
        "rustdoc_flags": attrs.list(attrs.arg(), default = []),
        "sysroot": attrs.one_of(
            # None = no sysroot deps
            # Artifact = path to implicit sysroot deps
            # Dict = explicit sysroot deps
            attrs.option(attrs.dep()),
            attrs.dict(key = attrs.string(), value = _can_keep(attrs.dep())),
        ),
        "target_triple": attrs.default_only(attrs.dep(providers = [TargetTriple], default = "//target:rustc_target_triple")),
    },
    is_toolchain_rule = True,
)
