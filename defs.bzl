load("@prelude//:rules.bzl", "rust_library")
load("@prelude//rust:cargo_buildscript.bzl", "buildscript_run")
load("@prelude//rust:cargo_package.bzl", "apply_platform_attrs")
load("@prelude//rust:proc_macro_alias.bzl", "rust_proc_macro_alias")
load("@prelude//utils:type_defs.bzl", "is_select")
load("//constraints:defs.bzl", "transition_alias")

def rust_bootstrap_alias(actual, **kwargs):
    if not actual.endswith("-0.0.0"):
        native.alias(
            actual = actual,
            target_compatible_with = _target_constraints(None),
            **kwargs
        )

def rust_bootstrap_binary(
        name,
        crate,
        crate_root,
        platform = {},
        rustc_flags = [],
        **kwargs):
    extra_rustc_flags = []

    if crate_root.startswith("rust/library/"):
        default_target_platform = "//platforms/stage1:library-build-script"
    elif crate_root.startswith("rust/compiler/") or crate_root.startswith("rust/src/"):
        default_target_platform = "//platforms/stage1:compiler"
    else:
        default_target_platform = "//platforms/stage1:compiler"
        extra_rustc_flags.append("--cap-lints=allow")

    native.rust_binary(
        name = name,
        crate = crate,
        crate_root = crate_root,
        default_target_platform = default_target_platform,
        rustc_flags = rustc_flags + extra_rustc_flags,
        target_compatible_with = _target_constraints(crate_root),
        **apply_platform_attrs(platform, kwargs)
    )

def rust_bootstrap_library(
        name,
        crate,
        crate_root,
        deps = [],
        env = {},
        platform = {},
        preferred_linkage = None,
        proc_macro = False,
        rustc_flags = [],
        srcs = [],
        target_compatible_with = None,
        visibility = None,
        **kwargs):
    target_compatible_with = target_compatible_with or _target_constraints(crate_root)

    if name.endswith("-0.0.0"):
        versioned_name = name
        name = name.removesuffix("-0.0.0")
        native.alias(
            name = versioned_name,
            actual = ":{}".format(name),
            target_compatible_with = target_compatible_with,
        )
        visibility = ["PUBLIC"]

    extra_deps = []
    extra_env = {}
    extra_rustc_flags = []
    extra_srcs = []

    if crate_root.startswith("rust/library/"):
        default_target_platform = "//platforms/stage1:library"
    elif crate_root.startswith("rust/compiler/") or crate_root.startswith("rust/src/"):
        default_target_platform = "//platforms/stage1:compiler"
        messages_ftl = glob(["rust/compiler/{}/messages.ftl".format(crate)])
        if messages_ftl:
            extra_env["CARGO_CRATE_NAME"] = crate
            extra_srcs += messages_ftl
        extra_srcs.append("rust/src/version")
        extra_env["CFG_RELEASE"] = "\\$(cat rust/src/version)"
        extra_env["CFG_RELEASE_CHANNEL"] = "dev"
        extra_env["CFG_VERSION"] = "\\$(cat rust/src/version) " + select({
            "//constraints:stage1": "(buckified stage1)",
            "//constraints:stage2": "(buckified stage2)",
        })
        extra_env["CFG_COMPILER_HOST_TRIPLE"] = "$(target_triple)"
        extra_deps.append("toolchains//target:rustc_target_triple")
    else:
        default_target_platform = None
        extra_rustc_flags.append("--cap-lints=allow")

    if proc_macro:
        rust_proc_macro_alias(
            name = name,
            actual_exec = ":_{}".format(name),
            actual_plugin = ":_{}".format(name),
            default_target_platform = default_target_platform,
            target_compatible_with = target_compatible_with,
            visibility = visibility,
        )
        name = "_{}".format(name)
        visibility = []

    rust_library(
        name = name,
        crate = crate,
        crate_root = crate_root,
        default_target_platform = default_target_platform,
        preferred_linkage = preferred_linkage or "static",
        proc_macro = proc_macro,
        srcs = srcs + extra_srcs,
        target_compatible_with = target_compatible_with,
        visibility = visibility,
        **apply_platform_attrs(platform, kwargs | dict(
            deps = deps + extra_deps,
            env = env + extra_env if is_select(env) else env | extra_env,
            rustc_flags = rustc_flags + extra_rustc_flags,
        ))
    )

def rust_bootstrap_buildscript_run(**kwargs):
    constraints = _target_constraints(None)
    buildscript_run(
        target_compatible_with = constraints,
        buildscript_compatible_with = constraints,
        **kwargs
    )

def cxx_bootstrap_library(
        name,
        compatible_with = None,
        deps = [],
        visibility = None,
        **kwargs):
    extra_deps = ["toolchains//cxx:stdlib"]

    native.cxx_library(
        name = "{}-compile".format(name),
        compatible_with = compatible_with,
        deps = deps + extra_deps,
        preferred_linkage = "static",
        **kwargs
    )

    transition_alias(
        name = name,
        actual = ":{}-compile".format(name),
        compatible_with = compatible_with,
        incoming_transition = "toolchains//cxx:prune_cxx_configuration",
        visibility = visibility,
    )

def _target_constraints(crate_root):
    if crate_root and crate_root.startswith("rust/library/"):
        target_compatible_with = ["//constraints:library"]
    elif crate_root and (crate_root.startswith("rust/compiler/") or crate_root.startswith("rust/src/")):
        target_compatible_with = ["//constraints:compiler"]
    else:
        target_compatible_with = select({
            "DEFAULT": ["prelude//:none"],
            "//constraints:compiler": [],
            "//constraints:library": [],
        })

    return target_compatible_with
