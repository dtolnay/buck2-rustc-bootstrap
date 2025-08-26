def _troubleshoot_impl(ctx: AnalysisContext) -> list[Provider]:
    out = ctx.actions.declare_output("out")
    ctx.actions.run(
        ctx.attrs.script,
        env = {"OUT": out.as_output()},
        category = "script",
    )
    return [DefaultInfo(default_output = out)]

troubleshoot = rule(
    impl = _troubleshoot_impl,
    attrs = {
        "script": attrs.source(),
    },
)
