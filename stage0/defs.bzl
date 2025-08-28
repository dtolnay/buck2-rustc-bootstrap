load("@prelude//http_archive:exec_deps.bzl", "HttpArchiveExecDeps")
load("@prelude//http_archive:unarchive.bzl", "unarchive")
load("@prelude//os_lookup:defs.bzl", "OsLookup")
load("@prelude//rust:targets.bzl", "targets")
load("@prelude//utils:cmd_script.bzl", "cmd_script")
load("//stage1:defs.bzl", "RustDistInfo")

Stage0Info = provider(
    fields = {
        "artifacts_server": str,
        "compiler_date": str,
        "compiler_version": str,
        "dist_server": str,
        "entries": dict[str, str],
    },
)

CiArtifactInfo = provider(
    fields = {
        "component": str,
    },
)

def _stage0_parse_impl(
        actions: AnalysisActions,
        stage0_artifact: ArtifactValue) -> list[Provider]:
    _ = actions

    artifacts_server = None
    compiler_date = None
    compiler_version = None
    dist_server = None
    entries = {}

    for line in stage0_artifact.read_string().splitlines():
        if line.startswith("#") or "=" not in line:
            continue

        key, value = line.split("=", 1)
        if key == "artifacts_server":
            artifacts_server = value
        elif key == "compiler_date":
            compiler_date = value
        elif key == "compiler_version":
            compiler_version = value
        elif key == "dist_server":
            dist_server = value
        else:
            entries[key] = value

    return [Stage0Info(
        artifacts_server = artifacts_server,
        compiler_date = compiler_date,
        compiler_version = compiler_version,
        dist_server = dist_server,
        entries = entries,
    )]

_stage0_parse = dynamic_actions(
    impl = _stage0_parse_impl,
    attrs = {
        "stage0_artifact": dynattrs.artifact_value(),
    },
)

def _stage0_component_impl(
        actions: AnalysisActions,
        component: str,
        output: OutputArtifact,
        stage0_info: ResolvedDynamicValue,
        target_triple: str) -> list[Provider]:
    stage0_info = stage0_info.providers[Stage0Info]

    path = "dist/{}/{}-{}-{}.tar.xz".format(
        stage0_info.compiler_date,
        component,
        stage0_info.compiler_version,
        target_triple,
    )

    sha256 = stage0_info.entries.get(path)
    if not sha256:
        fail("no checksum found in stage0 for {}".format(path))

    actions.download_file(
        output,
        "{}/{}".format(stage0_info.dist_server, path),
        sha256 = sha256,
    )
    return []

_stage0_component = dynamic_actions(
    impl = _stage0_component_impl,
    attrs = {
        "component": dynattrs.value(str),
        "output": dynattrs.output(),
        "stage0_info": dynattrs.dynamic_value(),
        "target_triple": dynattrs.value(str),
    },
)

def _stage0_download_impl(ctx: AnalysisContext) -> list[Provider]:
    target_triple = targets.exec_triple(ctx)

    stage0_artifact = ctx.attrs.manifest[DefaultInfo].default_outputs[0]
    stage0_info = ctx.actions.dynamic_output_new(
        _stage0_parse(
            stage0_artifact = stage0_artifact,
        ),
    )

    sub_targets = {}
    for component in ctx.attrs.components:
        download = ctx.actions.declare_output("{}.tar.xz".format(component))
        ctx.actions.dynamic_output_new(
            _stage0_component(
                component = component,
                output = download.as_output(),
                stage0_info = stage0_info,
                target_triple = target_triple,
            ),
        )
        sub_targets[component] = [DefaultInfo(default_output = download)]

    return [DefaultInfo(sub_targets = sub_targets)]

stage0_download = rule(
    impl = _stage0_download_impl,
    attrs = {
        "components": attrs.set(attrs.string()),
        "manifest": attrs.dep(),
        "_exec_os_type": attrs.default_only(attrs.dep(providers = [OsLookup], default = "//platforms/exec:os_lookup")),
    },
    supports_incoming_transition = True,
)

def _stage0_extract_impl(ctx: AnalysisContext) -> list[Provider]:
    sub_targets = {}
    for name, dist in ctx.attrs.dist[DefaultInfo].sub_targets.items():
        contents, _ = unarchive(
            ctx = ctx,
            archive = dist[DefaultInfo].default_outputs[0],
            output_name = name,
            ext_type = "tar.xz",
            excludes = [],
            strip_prefix = None,
            exec_deps = ctx.attrs._exec_deps[HttpArchiveExecDeps],
            prefer_local = False,
            sub_targets = {},
        )
        sub_targets[name] = [DefaultInfo(default_output = contents)]

    return [DefaultInfo(sub_targets = sub_targets)]

stage0_extract = rule(
    impl = _stage0_extract_impl,
    attrs = {
        "dist": attrs.dep(),
        "_exec_deps": attrs.default_only(attrs.exec_dep(providers = [HttpArchiveExecDeps], default = "//platforms/exec:http_archive")),
    },
    supports_incoming_transition = True,
)

def _stage0_executable_impl(ctx: AnalysisContext) -> list[Provider]:
    dist = ctx.attrs.dist[DefaultInfo].default_outputs[0]
    overlay = ctx.actions.declare_output("dist", dir = True)

    hidden = []
    frob = [
        ctx.attrs._frob[RunInfo],
        cmd_args(dist, format = "dist={}"),
        cmd_args(overlay.as_output(), format = "overlay={}"),
        "exe={}".format(ctx.label.name),
        ["--basename", "toplevel={dist}/?"],
        ["--read", "component={dist}/{toplevel}/components"],
        ["--mkdir", "{overlay}"],
        ["--mkdir", "{overlay}/bin"],
    ]

    if ctx.attrs.libdir:
        libdir = ctx.attrs.libdir[DefaultInfo].default_outputs[0]
        hidden.append(libdir)
        frob.extend([
            ["--cp", "{dist}/{toplevel}/{component}/bin/{exe}", "{overlay}/bin/{exe}"],
            cmd_args(libdir, format = "libdir={}", relative_to = overlay),
            ["--basename", "toplevel={overlay}/{libdir}/?"],
            ["--read", "component={overlay}/{libdir}/{toplevel}/components"],
            ["--symlink", "{libdir}/{toplevel}/{component}/lib", "{overlay}/lib"],
        ])
    else:
        hidden.append(dist)
        frob.extend([
            cmd_args(dist, format = "relative={}", relative_to = overlay.project("bin")),
            ["--symlink", "{relative}/{toplevel}/{component}/bin/{exe}", "{overlay}/bin/{exe}"],
        ])

    ctx.actions.run(frob, category = "dist")

    command = overlay.project("bin").project(ctx.label.name).with_associated_artifacts(hidden)

    if ctx.attrs.env:
        command = cmd_script(
            ctx = ctx,
            name = ctx.label.name,
            cmd = cmd_args(
                ctx.attrs._exec[RunInfo],
                command,
                ["{}={}".format(k, v) for k, v in ctx.attrs.env.items()],
                "--",
            ),
            language = ctx.attrs._exec_os_type[OsLookup].script,
        )

    return [
        DefaultInfo(),
        RunInfo(command),
    ]

stage0_executable = rule(
    impl = _stage0_executable_impl,
    attrs = {
        "dist": attrs.dep(),
        "env": attrs.dict(key = attrs.string(), value = attrs.string(), default = {}),
        "libdir": attrs.option(attrs.dep(), default = None),
        "_exec": attrs.default_only(attrs.exec_dep(providers = [RunInfo], default = "//stage0:exec")),
        "_frob": attrs.default_only(attrs.exec_dep(providers = [RunInfo], default = "//stage0:frob")),
        "_exec_os_type": attrs.default_only(attrs.dep(providers = [OsLookup], default = "//platforms/exec:os_lookup")),
    },
    supports_incoming_transition = True,
)

def _stage0_sysroot_impl(ctx: AnalysisContext) -> list[Provider]:
    dist = ctx.attrs.dist[DefaultInfo].default_outputs[0]

    contents, _ = unarchive(
        ctx = ctx,
        archive = dist,
        output_name = "dist",
        ext_type = "tar.xz",
        excludes = [],
        strip_prefix = None,
        exec_deps = ctx.attrs._exec_deps[HttpArchiveExecDeps],
        prefer_local = False,
        sub_targets = {},
    )

    sysroot = ctx.actions.declare_output("sysroot")
    ctx.actions.run(
        [
            ctx.attrs._frob[RunInfo],
            cmd_args(contents, format = "dist={}"),
            cmd_args(contents, format = "relative={}").relative_to(sysroot, parent = 1),
            cmd_args(sysroot.as_output(), format = "symlink={}"),
            ["--basename", "toplevel={dist}/?"],
            ["--read", "component={dist}/{toplevel}/components"],
            ["--symlink", "{relative}/{toplevel}/{component}", "{symlink}"],
        ],
        category = "sysroot",
    )

    return [DefaultInfo(default_output = sysroot)]

stage0_sysroot = rule(
    impl = _stage0_sysroot_impl,
    attrs = {
        "dist": attrs.dep(),
        "_exec_deps": attrs.default_only(attrs.exec_dep(providers = [HttpArchiveExecDeps], default = "//platforms/exec:http_archive")),
        "_frob": attrs.default_only(attrs.exec_dep(providers = [RunInfo], default = "//stage0:frob")),
    },
    supports_incoming_transition = True,
)

def _download_ci_artifact_impl(
        actions: AnalysisActions,
        commit: str,
        component: str,
        output: OutputArtifact,
        sha256: str,
        stage0_info: ResolvedDynamicValue,
        target_triple: str) -> list[Provider]:
    artifacts_server = stage0_info.providers[Stage0Info].artifacts_server
    actions.download_file(
        output,
        "{}/{}/{}-{}.tar.xz".format(artifacts_server, commit, component, target_triple),
        sha256 = sha256,
    )
    return []

_download_ci_artifact = dynamic_actions(
    impl = _download_ci_artifact_impl,
    attrs = {
        "commit": dynattrs.value(str),
        "component": dynattrs.value(str),
        "output": dynattrs.output(),
        "sha256": dynattrs.value(str),
        "stage0_info": dynattrs.dynamic_value(),
        "target_triple": dynattrs.value(str),
    },
)

def _ci_artifact_impl(ctx: AnalysisContext) -> list[Provider]:
    target_triple = targets.exec_triple(ctx)

    stage0_artifact = ctx.attrs.manifest[DefaultInfo].default_outputs[0]
    stage0_info = ctx.actions.dynamic_output_new(
        _stage0_parse(
            stage0_artifact = stage0_artifact,
        ),
    )

    download = ctx.actions.declare_output("{}.tar.xz".format(ctx.attrs.component))
    ctx.actions.dynamic_output_new(
        _download_ci_artifact(
            commit = ctx.attrs.commit,
            component = ctx.attrs.component,
            output = download.as_output(),
            sha256 = ctx.attrs.sha256.get(target_triple, "0" * 64),
            stage0_info = stage0_info,
            target_triple = target_triple,
        ),
    )

    return [
        DefaultInfo(default_output = download),
        CiArtifactInfo(component = ctx.attrs.component),
    ]

ci_artifact = rule(
    impl = _ci_artifact_impl,
    attrs = {
        "commit": attrs.string(),
        "component": attrs.string(),
        "manifest": attrs.dep(),
        "sha256": attrs.dict(key = attrs.string(), value = attrs.string()),
        "_exec_os_type": attrs.default_only(attrs.dep(providers = [OsLookup], default = "//platforms/exec:os_lookup")),
    },
    supports_incoming_transition = True,
)

def _ci_llvm_impl(ctx: AnalysisContext) -> list[Provider]:
    rust_dev = ctx.attrs.rust_dev[DefaultInfo].default_outputs[0]
    component = ctx.attrs.rust_dev[CiArtifactInfo].component

    contents, _ = unarchive(
        ctx = ctx,
        archive = rust_dev,
        output_name = "ci-llvm",
        ext_type = "tar.xz",
        excludes = [],
        strip_prefix = "{}-{}/rust-dev".format(component, targets.exec_triple(ctx)),
        exec_deps = ctx.attrs._exec_deps[HttpArchiveExecDeps],
        prefer_local = False,
        sub_targets = {},
    )

    return [
        DefaultInfo(default_output = contents),
        RustDistInfo(artifacts = {"lib": contents.project("lib")}),
    ]

ci_llvm = rule(
    impl = _ci_llvm_impl,
    attrs = {
        "rust_dev": attrs.dep(providers = [DefaultInfo, CiArtifactInfo]),
        "_exec_deps": attrs.default_only(attrs.exec_dep(providers = [HttpArchiveExecDeps], default = "//platforms/exec:http_archive")),
        "_exec_os_type": attrs.default_only(attrs.dep(providers = [OsLookup], default = "//platforms/exec:os_lookup")),
    },
    supports_incoming_transition = True,
)
