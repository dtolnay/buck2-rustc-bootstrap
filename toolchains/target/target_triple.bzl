TargetTriple = provider(fields = {
    "value": str,
})

def _target_triple_impl(ctx: AnalysisContext) -> list[Provider]:
    platform_name = ctx.label.configured_target().config().name
    if platform_name.startswith("target="):
        target_triple = platform_name[len("target="):]
    else:
        target_triple = ctx.attrs.value

    return [
        DefaultInfo(),
        TargetTriple(value = target_triple),
        TemplatePlaceholderInfo(
            unkeyed_variables = {
                "target_triple": target_triple,
            },
        ),
    ]

target_triple = rule(
    impl = _target_triple_impl,
    attrs = {"value": attrs.string()},
    supports_incoming_transition = True,
)
