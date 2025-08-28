load("//platforms:name.bzl", "platform_info_label")

def _rustc_target_platform_impl(ctx: AnalysisContext) -> list[Provider]:
    setting = ctx.attrs.rustc_target_triple_constraint[ConstraintSettingInfo]

    constraints = {
        setting.label: ConstraintValueInfo(
            setting = setting,
            label = ctx.label.raw_target(),
        ),
    }

    configuration = ConfigurationInfo(
        constraints = constraints,
        values = {},
    )

    return [
        DefaultInfo(),
        PlatformInfo(
            label = platform_info_label(constraints),
            configuration = configuration,
        ),
        configuration,
    ]

rustc_target_platform = rule(
    impl = _rustc_target_platform_impl,
    attrs = {
        "cpu_os_constraints": attrs.option(attrs.tuple(attrs.configuration_label(), attrs.configuration_label()), default = None),
        "rustc_target_triple_constraint": attrs.default_only(attrs.dep(default = "//platforms/cross:rustc_target_triple")),
    },
    is_configuration_rule = True,
)
