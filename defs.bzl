load("@prelude//:rules.bzl", "rust_library")
load("@prelude//rust:cargo_buildscript.bzl", "buildscript_run")
load("@prelude//rust:cargo_package.bzl", "apply_platform_attrs")
load("@prelude//rust:proc_macro_alias.bzl", "rust_proc_macro_alias")
load("@prelude//utils:type_defs.bzl", "is_select")
load("//constraints:defs.bzl", "transition_alias")

PLATFORM_TEMPLATES = select({
    "prelude//os:linux": select({
        "prelude//cpu:arm64": select({
            "//constraints:library": "linux-arm64-library",
            "//constraints:compiler": "linux-arm64-compiler",
        }),
        "prelude//cpu:x86_64": select({
            "//constraints:library": "linux-x86_64-library",
            "//constraints:compiler": "linux-x86_64-compiler",
        }),
    }),
    "prelude//os:macos": select({
        "prelude//cpu:arm64": select({
            "//constraints:library": "macos-arm64-library",
            "//constraints:compiler": "macos-arm64-compiler",
        }),
        "prelude//cpu:x86_64": select({
            "//constraints:library": "macos-x86_64-library",
            "//constraints:compiler": "macos-x86_64-compiler",
        }),
    }),
    "prelude//os:windows": select({
        "DEFAULT": select({
            "//constraints:library": "windows-msvc-library",
            "//constraints:compiler": "windows-msvc-compiler",
        }),
        "prelude//abi:gnu": select({
            "//constraints:library": "windows-gnu-library",
            "//constraints:compiler": "windows-gnu-compiler",
        }),
        "prelude//abi:msvc": select({
            "//constraints:library": "windows-msvc-library",
            "//constraints:compiler": "windows-msvc-compiler",
        }),
    }),
})

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
        **apply_platform_attrs(
            platform,
            kwargs,
            templates = PLATFORM_TEMPLATES,
        )
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
        visibility = None,
        **kwargs):
    target_compatible_with = _target_constraints(crate_root)

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
            extra_env["CARGO_PKG_NAME"] = crate
            extra_srcs += messages_ftl
        extra_srcs.append("rust/src/version")
        extra_env["CFG_RELEASE"] = "\\$(cat rust/src/version)"
        extra_env["CFG_RELEASE_CHANNEL"] = "dev"
        extra_env["CFG_VERSION"] = "\\$(cat rust/src/version) " + select({
            "//constraints:stage1": "(buckified stage1)",
            "//constraints:stage2": "(buckified stage2)",
        })
        extra_env["CFG_COMPILER_HOST_TRIPLE"] = "$(target_triple)"
        extra_deps.append("toolchains//target:target_triple")
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
        **apply_platform_attrs(
            platform,
            kwargs | dict(
                deps = deps + extra_deps,
                env = env + extra_env if is_select(env) else env | extra_env,
                rustc_flags = rustc_flags + extra_rustc_flags,
            ),
            templates = PLATFORM_TEMPLATES,
        )
    )

def rust_bootstrap_buildscript_run(**kwargs):
    buildscript_run(
        target_compatible_with = _target_constraints(None),
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
        target_compatible_with = [
            "//constraints:library",
            "//constraints:sysroot-deps=explicit",
        ]
    elif crate_root and (crate_root.startswith("rust/compiler/") or crate_root.startswith("rust/src/")):
        target_compatible_with = [
            "//constraints:compiler",
            "//constraints:sysroot-deps=implicit",
        ]
    else:
        target_compatible_with = select({
            "DEFAULT": ["//constraints:false"],
            "//constraints:compiler": [],
            "//constraints:library": [],
        })

    return target_compatible_with
