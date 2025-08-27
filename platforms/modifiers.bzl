load(
    "@prelude//cfg/modifier:cfg_constructor.bzl",
    "PostConstraintAnalysisParams",
    prelude_post_constraint_analysis = "cfg_constructor_post_constraint_analysis",
    prelude_pre_constraint_analysis = "cfg_constructor_pre_constraint_analysis",
)
load("@prelude//cfg/modifier:types.bzl", "Modifier")
load(":name.bzl", "platform_info_label")

RustcBootstrapModifiers = record(
    post_constraint_analysis_params = PostConstraintAnalysisParams,
    target = str | None,
)

def cfg_constructor_pre_constraint_analysis(
        *,
        legacy_platform: PlatformInfo | None,
        package_modifiers: list[dict[str, typing.Any]] | None,
        target_modifiers: list[Modifier] | None,
        cli_modifiers: list[str],
        rule_name: str,
        aliases: struct,
        extra_data: struct) -> (list[str], RustcBootstrapModifiers):
    simple_cli_modifiers = []
    target = None
    for modifier in cli_modifiers:
        if modifier.startswith("target="):
            target = modifier[len("target="):]
        else:
            simple_cli_modifiers.append(modifier)

    refs, params = prelude_pre_constraint_analysis(
        legacy_platform = legacy_platform,
        package_modifiers = package_modifiers,
        target_modifiers = target_modifiers,
        cli_modifiers = simple_cli_modifiers,
        rule_name = rule_name,
        aliases = aliases,
        extra_data = extra_data,
    )

    return refs, RustcBootstrapModifiers(
        post_constraint_analysis_params = params,
        target = target,
    )

def cfg_constructor_post_constraint_analysis(
        *,
        refs: dict[str, ProviderCollection],
        params: RustcBootstrapModifiers) -> PlatformInfo:
    platform = prelude_post_constraint_analysis(
        refs = refs,
        params = params.post_constraint_analysis_params,
    )

    extra_values = {}
    if params.target:
        extra_values["rustc_bootstrap.target_triple"] = params.target

    return PlatformInfo(
        label = platform_info_label(platform.configuration.constraints, params.target),
        configuration = ConfigurationInfo(
            constraints = platform.configuration.constraints,
            values = platform.configuration.values | extra_values,
        ),
    )
