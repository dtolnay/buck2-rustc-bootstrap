load("@prelude//platforms:defs.bzl", "host_configuration")

def platform_info_label(constraints: dict[TargetLabel, ConstraintValueInfo]) -> str:
    settings = {}
    for constraint in constraints.values():
        settings[str(constraint.setting.label)] = constraint.label.name

    stage = settings.get("rust//constraints:bootstrap-stage")
    workspace = settings.get("rust//constraints:workspace")
    build_script = settings.get("rust//constraints:build-script")
    os = settings.get("prelude//os/constraints:os")
    cpu = settings.get("prelude//cpu/constraints:cpu")

    host_os = host_configuration.os.split(":")[1]
    host_cpu = host_configuration.cpu.split(":")[1]

    if not stage and not workspace and not build_script and os == host_os and cpu == host_cpu:
        return "rust//platforms:host"

    if stage and workspace and build_script:
        label = "rust//platforms/{}:{}".format(stage, workspace)
        if build_script == "build-script=true":
            label += "-build-script"
        return label

    if os and cpu:
        return "{}-{}".format(os, cpu)

    if os or cpu:
        return os or cpu

    if len(settings) == 0:
        return "null"

    return "cfg"
