load("//remote_execution:config.bzl", "executor_config")
load(":name.bzl", "platform_info_label")

def _platform_impl(ctx: AnalysisContext) -> list[Provider]:
    platform_label = ctx.label.raw_target()
    constraints = {}

    if ctx.attrs.base:
        for label, value in ctx.attrs.base[PlatformInfo].configuration.constraints.items():
            constraints[label] = value

    for dep in ctx.attrs.constraint_values:
        for label, value in dep[ConfigurationInfo].constraints.items():
            constraints[label] = value

    configuration = ConfigurationInfo(
        constraints = constraints,
        values = {},
    )

    transition = set()
    for dep in ctx.attrs.transition:
        transition.add(dep[ConstraintSettingInfo].label)

    def transition_impl(platform: PlatformInfo) -> PlatformInfo:
        constraints = dict(configuration.constraints)
        for setting, value in platform.configuration.constraints.items():
            if setting not in transition:
                constraints[setting] = value

        return PlatformInfo(
            label = platform_info_label(constraints),
            configuration = ConfigurationInfo(
                constraints = constraints,
                values = platform.configuration.values,
            ),
        )

    return [
        DefaultInfo(),
        PlatformInfo(
            label = platform_info_label(configuration.constraints),
            configuration = configuration,
        ),
        TransitionInfo(impl = transition_impl),
    ] + (
        [ExecutionPlatformInfo(
            label = platform_label,
            configuration = configuration,
            executor_config = executor_config(configuration),
        )] if ctx.attrs.execution_platform else []
    )

_platform_attrs = {
    "base": attrs.option(attrs.dep(providers = [PlatformInfo]), default = None),
    "constraint_values": attrs.list(attrs.configuration_label(), default = []),
    # Configuration settings in this list are overwritten during a
    # transition to this platform, whereas configuration settings not in
    # this list are preserved.
    "transition": attrs.list(attrs.configuration_label(), default = [
        "//constraints:bootstrap-stage",
        "//constraints:build-script",
        "//constraints:opt-level",
        "//constraints:workspace",
    ]),
}

target_platform = rule(
    impl = _platform_impl,
    attrs = _platform_attrs | {
        "execution_platform": attrs.default_only(attrs.bool(default = False)),
    },
    is_configuration_rule = True,
)

execution_platform = rule(
    impl = _platform_impl,
    attrs = _platform_attrs | {
        "execution_platform": attrs.default_only(attrs.bool(default = True)),
    },
    is_configuration_rule = True,
)

def _execution_platforms_impl(ctx: AnalysisContext) -> list[Provider]:
    platforms = [
        platform[ExecutionPlatformInfo]
        for platform in ctx.attrs.platforms
    ]

    return [
        DefaultInfo(),
        ExecutionPlatformRegistrationInfo(platforms = platforms),
    ]

execution_platforms = rule(
    impl = _execution_platforms_impl,
    attrs = {
        "platforms": attrs.list(attrs.dep(providers = [ExecutionPlatformInfo])),
    },
    is_configuration_rule = True,
)
