load("@prelude//python_bootstrap:toolchain.bzl", "PythonBootstrapToolchainInfo")

def _python_bootstrap_toolchain_impl(ctx: AnalysisContext) -> list[Provider]:
    return [
        DefaultInfo(),
        PythonBootstrapToolchainInfo(interpreter = cmd_args(ctx.attrs.interpreter)),
    ]

python_bootstrap_toolchain = rule(
    impl = _python_bootstrap_toolchain_impl,
    attrs = {
        "interpreter": attrs.default_only(attrs.list(attrs.arg(), default = select({
            "DEFAULT": ["python3"],
            # Apply a default PATH if absent. This works around Remote Execution
            # providers that run all actions with an empty PATH.
            "config//os:linux": [
                "/bin/sh",
                "-c",
                '/usr/bin/env PATH="${PATH:-/usr/local/bin:/usr/bin:/bin}" python3 "$0" "$@"',
            ],
            "config//os:windows": ["python.exe"],
        }))),
    },
    is_toolchain_rule = True,
)
