load("@prelude//http_archive:exec_deps.bzl", "HttpArchiveExecDeps")
load("@prelude//http_archive:unarchive.bzl", "unarchive")

def _crate_download_impl(ctx: AnalysisContext) -> list[Provider]:
    filename = ctx.label.name.removesuffix(".crate") + ".tar.gz"
    archive = ctx.actions.declare_output(filename)
    ctx.actions.download_file(
        archive.as_output(),
        ctx.attrs.urls[0],
        sha256 = ctx.attrs.sha256,
    )

    output, sub_targets = unarchive(
        ctx = ctx,
        archive = archive,
        output_name = ctx.label.name,
        ext_type = "tar.gz",
        excludes = [],
        strip_prefix = ctx.attrs.strip_prefix,
        exec_deps = ctx.attrs._exec_deps[HttpArchiveExecDeps],
        prefer_local = False,
        sub_targets = ctx.attrs.sub_targets,
    )

    return [DefaultInfo(
        default_output = output,
        sub_targets = sub_targets,
    )]

crate_download = rule(
    impl = _crate_download_impl,
    attrs = {
        "_exec_deps": attrs.default_only(attrs.exec_dep(providers = [HttpArchiveExecDeps], default = "//platforms/exec:http_archive")),
        "sha256": attrs.string(),
        "strip_prefix": attrs.string(),
        "sub_targets": attrs.set(attrs.string(), default = []),
        "urls": attrs.list(attrs.string()),
    },
    supports_incoming_transition = True,
)
