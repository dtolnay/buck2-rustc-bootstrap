load("//platforms:name.bzl", "platform_info_label")

def _unified_constraint_impl(ctx: AnalysisContext) -> list[Provider]:
    label = ctx.label.raw_target()
    setting = ConstraintSettingInfo(label = label)
    value = ConstraintValueInfo(setting = setting, label = label)

    return [
        DefaultInfo(),
        setting,
        value,
        ConfigurationInfo(
            constraints = {label: value},
            values = {},
        ),
    ]

unified_constraint = rule(
    impl = _unified_constraint_impl,
    attrs = {},
    is_configuration_rule = True,
)

def constraint(setting, values = []):
    if values:
        native.constraint_setting(
            name = setting,
            visibility = ["PUBLIC"],
        )
        for value in values:
            native.constraint_value(
                name = value,
                constraint_setting = ":{}".format(setting),
                visibility = ["PUBLIC"],
            )
    else:
        unified_constraint(
            name = setting,
            visibility = ["PUBLIC"],
        )

def _configuration_transition_impl(ctx: AnalysisContext) -> list[Provider]:
    if ctx.attrs.add_fallback_settings:
        fallback_constraints = ctx.attrs.add_fallback_settings[PlatformInfo].configuration.constraints
    else:
        fallback_constraints = {}

    keep = set()
    for setting in ctx.attrs.keep_settings or []:
        keep.add(setting[ConstraintSettingInfo].label)

    discard = set()
    for setting in ctx.attrs.discard_settings or []:
        discard.add(setting[ConstraintSettingInfo].label)

    def transition_impl(platform: PlatformInfo) -> PlatformInfo:
        constraints = dict(fallback_constraints)
        for setting, value in platform.configuration.constraints.items():
            if setting in keep or (discard and setting not in discard):
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
        TransitionInfo(impl = transition_impl),
    ]

configuration_transition = rule(
    impl = _configuration_transition_impl,
    attrs = {
        "add_fallback_settings": attrs.option(attrs.dep(providers = [PlatformInfo]), default = None),
        "discard_settings": attrs.option(attrs.list(attrs.dep(providers = [ConstraintSettingInfo])), default = None),
        "keep_settings": attrs.option(attrs.list(attrs.dep(providers = [ConstraintSettingInfo])), default = None),
    },
    is_configuration_rule = True,
)

transition_alias = rule(
    impl = lambda ctx: ctx.attrs.actual.providers,
    attrs = {"actual": attrs.dep()},
    supports_incoming_transition = True,
)
