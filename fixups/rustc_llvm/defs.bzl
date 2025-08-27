def _llvm_config_impl(ctx: AnalysisContext) -> list[Provider]:
    llvm = ctx.attrs.llvm[DefaultInfo].default_outputs[0]
    llvm_bin = llvm.project("bin")
    llvm_lib = llvm.project("lib")
    llvm_config = llvm_bin.project("llvm-config").with_associated_artifacts([llvm_lib])
    return [
        DefaultInfo(default_output = llvm_config),
        RunInfo(llvm_config),
    ]

llvm_config = rule(
    impl = _llvm_config_impl,
    attrs = {"llvm": attrs.dep()},
)

def _rustc_cfg_llvm_component_impl(
        actions: AnalysisActions,
        llvm_config_components: ArtifactValue,
        output: OutputArtifact) -> list[Provider]:
    cfg = []
    for component in llvm_config_components.read_string().split():
        cfg.append("--cfg=llvm_component=\"{}\"\n".format(component))

    actions.write(output, "".join(cfg))
    return []

_rustc_cfg_llvm_component = dynamic_actions(
    impl = _rustc_cfg_llvm_component_impl,
    attrs = {
        "llvm_config_components": dynattrs.artifact_value(),
        "output": dynattrs.output(),
    },
)

def _llvm_rustc_flags_impl(ctx: AnalysisContext) -> list[Provider]:
    llvm_config_components = ctx.actions.declare_output("components")
    ctx.actions.run(
        [
            ctx.attrs._redirect_stdout[RunInfo],
            llvm_config_components.as_output(),
            ctx.attrs.host_llvm_config[RunInfo],
            "--components",
        ],
        category = "llvm_config",
    )

    rustc_flags = ctx.actions.declare_output("rustc-flags")
    ctx.actions.dynamic_output_new(
        _rustc_cfg_llvm_component(
            llvm_config_components = llvm_config_components,
            output = rustc_flags.as_output(),
        ),
    )

    return [DefaultInfo(default_output = rustc_flags)]

llvm_rustc_flags = rule(
    impl = _llvm_rustc_flags_impl,
    attrs = {
        "host_llvm_config": attrs.dep(providers = [RunInfo]),
        "_redirect_stdout": attrs.default_only(attrs.exec_dep(providers = [RunInfo], default = "prelude//rust/tools:redirect_stdout")),
    },
)

def _cxx_flags_impl(
        actions: AnalysisActions,
        llvm_config_cxxflags: ArtifactValue,
        output: OutputArtifact) -> list[Provider]:
    flags = []
    for flag in llvm_config_cxxflags.read_string().split():
        if flag.startswith("-std=") or flag.startswith("-stdlib=") or flag.startswith("-f"):
            flags.append(flag + "\n")
        elif not (flag.startswith("-I") or flag.startswith("-D")):
            fail("unrecognized llvm flag:", repr(flag))
    actions.write(output, "".join(flags))
    return []

_cxx_flags = dynamic_actions(
    impl = _cxx_flags_impl,
    attrs = {
        "llvm_config_cxxflags": dynattrs.artifact_value(),
        "output": dynattrs.output(),
    },
)

def _llvm_cxx_flags_impl(ctx: AnalysisContext) -> list[Provider]:
    llvm_config_cxxflags = ctx.actions.declare_output("cxxflags")
    ctx.actions.run(
        [
            ctx.attrs._redirect_stdout[RunInfo],
            llvm_config_cxxflags.as_output(),
            ctx.attrs.host_llvm_config[RunInfo],
            "--cxxflags",
        ],
        category = "llvm_config",
    )

    cxx_flags = ctx.actions.declare_output("cxx-flags")
    ctx.actions.dynamic_output_new(
        _cxx_flags(
            llvm_config_cxxflags = llvm_config_cxxflags,
            output = cxx_flags.as_output(),
        ),
    )

    return [DefaultInfo(default_output = cxx_flags)]

llvm_cxx_flags = rule(
    impl = _llvm_cxx_flags_impl,
    attrs = {
        "host_llvm_config": attrs.dep(providers = [RunInfo]),
        "_redirect_stdout": attrs.default_only(attrs.exec_dep(providers = [RunInfo], default = "prelude//rust/tools:redirect_stdout")),
    },
)

def _preprocessor_flags_impl(
        actions: AnalysisActions,
        llvm_config_cxxflags: ArtifactValue,
        output: OutputArtifact) -> list[Provider]:
    flags = []
    for flag in llvm_config_cxxflags.read_string().split():
        if flag.startswith("-D"):
            flags.append(flag + "\n")
    actions.write(output, "".join(flags))
    return []

_preprocessor_flags = dynamic_actions(
    impl = _preprocessor_flags_impl,
    attrs = {
        "llvm_config_cxxflags": dynattrs.artifact_value(),
        "output": dynattrs.output(),
    },
)

def _llvm_preprocessor_flags_impl(ctx: AnalysisContext) -> list[Provider]:
    llvm_config_cxxflags = ctx.actions.declare_output("cxxflags")
    ctx.actions.run(
        [
            ctx.attrs._redirect_stdout[RunInfo],
            llvm_config_cxxflags.as_output(),
            ctx.attrs.host_llvm_config[RunInfo],
            "--cxxflags",
        ],
        category = "llvm_config",
    )

    preprocessor_flags = ctx.actions.declare_output("preprocessor-flags")
    ctx.actions.dynamic_output_new(
        _preprocessor_flags(
            llvm_config_cxxflags = llvm_config_cxxflags,
            output = preprocessor_flags.as_output(),
        ),
    )

    return [DefaultInfo(default_output = preprocessor_flags)]

llvm_preprocessor_flags = rule(
    impl = _llvm_preprocessor_flags_impl,
    attrs = {
        "host_llvm_config": attrs.dep(providers = [RunInfo]),
        "_redirect_stdout": attrs.default_only(attrs.exec_dep(providers = [RunInfo], default = "prelude//rust/tools:redirect_stdout")),
    },
)

def _run_llvm_config_for_linker_flags_impl(
        actions: AnalysisActions,
        host_llvm_config: RunInfo,
        link_type: ArtifactValue,
        output: OutputArtifact,
        redirect_stdout: RunInfo) -> list[Provider]:
    link_type = link_type.read_string().strip()
    if link_type == "static":
        link_type_flags = ["--link-static", "--ignore-libllvm"]
    elif link_type == "dynamic":
        link_type_flags = ["--link-shared"]
    else:
        fail("unknown LLVM link type:", link_type)

    actions.run(
        [redirect_stdout, output, host_llvm_config, "--libs", link_type_flags],
        category = "llvm_config",
    )
    return []

_run_llvm_config_for_linker_flags = dynamic_actions(
    impl = _run_llvm_config_for_linker_flags_impl,
    attrs = {
        "host_llvm_config": dynattrs.value(RunInfo),
        "link_type": dynattrs.artifact_value(),
        "output": dynattrs.output(),
        "redirect_stdout": dynattrs.value(RunInfo),
    },
)

def _linker_flags_impl(
        actions: AnalysisActions,
        llvm_config_libs: ArtifactValue,
        output: OutputArtifact) -> list[Provider]:
    flags = []
    for flag in llvm_config_libs.read_string().split():
        flags.append(flag + "\n")
    actions.write(output, "".join(flags))
    return []

_linker_flags = dynamic_actions(
    impl = _linker_flags_impl,
    attrs = {
        "llvm_config_libs": dynattrs.artifact_value(),
        "output": dynattrs.output(),
    },
)

def _llvm_linker_flags_impl(ctx: AnalysisContext) -> list[Provider]:
    link_type = ctx.actions.declare_output("link-type.txt")
    ctx.actions.run(
        [
            ctx.attrs._frob[RunInfo],
            cmd_args(ctx.attrs.target_llvm[DefaultInfo].default_outputs[0], format = "source={}"),
            cmd_args(link_type.as_output(), format = "dest={}"),
            ["--cp", "{source}/link-type.txt", "{dest}"],
        ],
        category = "link_type",
    )

    llvm_config_libs = ctx.actions.declare_output("libs")
    ctx.actions.dynamic_output_new(
        _run_llvm_config_for_linker_flags(
            host_llvm_config = ctx.attrs.host_llvm_config[RunInfo],
            link_type = link_type,
            output = llvm_config_libs.as_output(),
            redirect_stdout = ctx.attrs._redirect_stdout[RunInfo],
        ),
    )

    linker_flags = ctx.actions.declare_output("linker-flags")
    ctx.actions.dynamic_output_new(
        _linker_flags(
            llvm_config_libs = llvm_config_libs,
            output = linker_flags.as_output(),
        ),
    )

    return [DefaultInfo(default_output = linker_flags)]

llvm_linker_flags = rule(
    impl = _llvm_linker_flags_impl,
    attrs = {
        "host_llvm_config": attrs.dep(providers = [RunInfo]),
        "target_llvm": attrs.dep(),
        "_frob": attrs.default_only(attrs.exec_dep(providers = [RunInfo], default = "//stage0:frob")),
        "_redirect_stdout": attrs.default_only(attrs.exec_dep(providers = [RunInfo], default = "prelude//rust/tools:redirect_stdout")),
    },
)
