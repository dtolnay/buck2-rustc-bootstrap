load(
    "@prelude//cxx:cxx_toolchain_types.bzl",
    "BinaryUtilitiesInfo",
    "CCompilerInfo",
    "CxxCompilerInfo",
    "CxxInternalTools",
    "CxxPlatformInfo",
    "CxxToolchainInfo",
    "LinkerInfo",
    "LinkerType",
    "PicBehavior",
    "ShlibInterfacesMode",
)
load("@prelude//cxx:headers.bzl", "HeaderMode")
load("@prelude//linking:link_info.bzl", "LinkStyle")
load("@prelude//linking:lto.bzl", "LtoMode")
load("@prelude//os_lookup:defs.bzl", "Os", "OsLookup")
load("@prelude//toolchains:cxx.bzl", "CxxToolsInfo")
load("//target:target_triple.bzl", "TargetTriple")

def _cxx_toolchain_impl(ctx: AnalysisContext):
    target = ctx.attrs._target_os_type[OsLookup]
    target_triple = ctx.attrs.target_triple[TargetTriple].value
    tools = ctx.attrs._cxx_tools_info[CxxToolsInfo]

    linker_flags = []
    if target.os == Os("linux") and tools.linker != "g++" and tools.cxx_compiler != "g++":
        linker_flags.append("-fuse-ld=lld")

    if target.os == Os("windows"):
        binary_extension = "exe"
        object_file_extension = "obj"
        static_library_extension = "lib"
        shared_library_name_default_prefix = ""
        shared_library_name_format = "{}.dll"
        shared_library_versioned_name_format = "{}.dll"
        linker_type = LinkerType("windows")
        pic_behavior = PicBehavior("not_supported")
    else:
        binary_extension = ""
        object_file_extension = "o"
        static_library_extension = "a"
        shared_library_name_default_prefix = "lib"
        shared_library_name_format = "{}.so"
        shared_library_versioned_name_format = "{}.so.{}"
        if target.os == Os("macos"):
            linker_type = LinkerType("darwin")
            pic_behavior = PicBehavior("always_enabled")
        else:
            linker_type = LinkerType("gnu")
            pic_behavior = PicBehavior("supported")

    return [
        DefaultInfo(),
        CxxPlatformInfo(
            name = "{}-{}".format(target.os, target.cpu),
        ),
        CxxToolchainInfo(
            internal_tools = ctx.attrs._internal_tools[CxxInternalTools],
            linker_info = LinkerInfo(
                type = linker_type,
                linker = RunInfo(tools.linker),
                linker_flags = linker_flags,
                archiver = RunInfo(tools.archiver),
                archiver_type = tools.archiver_type,
                lto_mode = LtoMode("none"),
                link_binaries_locally = False,
                link_libraries_locally = False,
                archive_objects_locally = False,
                use_archiver_flags = True,
                shlib_interfaces = ShlibInterfacesMode("disabled"),
                link_style = LinkStyle("shared"),
                binary_extension = binary_extension,
                object_file_extension = object_file_extension,
                static_library_extension = static_library_extension,
                shared_library_name_default_prefix = shared_library_name_default_prefix,
                shared_library_name_format = shared_library_name_format,
                shared_library_versioned_name_format = shared_library_versioned_name_format,
            ),
            binary_utilities_info = BinaryUtilitiesInfo(
                strip = RunInfo("strip"),
            ),
            cxx_compiler_info = CxxCompilerInfo(
                compiler = RunInfo(tools.cxx_compiler),
                compiler_flags = ["--target={}".format(target_triple)] + ctx.attrs.cxx_flags,
                compiler_type = tools.compiler_type,
            ),
            c_compiler_info = CCompilerInfo(
                compiler = RunInfo(tools.compiler),
                compiler_flags = ["--target={}".format(target_triple)] + ctx.attrs.c_flags,
                compiler_type = tools.compiler_type,
            ),
            as_compiler_info = CCompilerInfo(
                compiler = RunInfo(tools.compiler),
                compiler_flags = ["--target={}".format(target_triple)],
                compiler_type = tools.compiler_type,
            ),
            asm_compiler_info = CCompilerInfo(
                compiler = RunInfo(tools.asm_compiler),
                compiler_flags = ["--target={}".format(target_triple)],
                compiler_type = tools.asm_compiler_type,
            ),
            header_mode = HeaderMode("symlink_tree_only"),
            pic_behavior = pic_behavior,
        ),
    ]

cxx_toolchain = rule(
    impl = _cxx_toolchain_impl,
    attrs = {
        "c_flags": attrs.list(attrs.arg(), default = []),
        "cxx_flags": attrs.list(attrs.arg(), default = []),
        "target_triple": attrs.default_only(attrs.dep(providers = [TargetTriple], default = "//target:clang_target_triple")),
        "_cxx_tools_info": attrs.exec_dep(providers = [CxxToolsInfo], default = "prelude//toolchains/msvc:msvc_tools" if host_info().os.is_windows else "prelude//toolchains/cxx/clang:path_clang_tools"),
        "_internal_tools": attrs.default_only(attrs.exec_dep(providers = [CxxInternalTools], default = "prelude//cxx/tools:internal_tools")),
        "_target_os_type": attrs.default_only(attrs.dep(providers = [OsLookup], default = "prelude//os_lookup/targets:os_lookup")),
    },
    is_toolchain_rule = True,
)
