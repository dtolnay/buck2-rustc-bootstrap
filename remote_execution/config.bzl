# It is strongly recommend to set the following in .buckconfig.local for faster
# runner startup time:
#
#     [remote_execution_properties]
#     dockerNetwork = off
#
_buckconfig_remote_execution_properties = {
    prop: read_config("remote_execution_properties", prop)
    for prop in ["dockerNetwork"]
    if read_config("remote_execution_properties", prop)
}

def executor_config(configuration: ConfigurationInfo) -> CommandExecutorConfig:
    use_windows_path_separators = False
    for value in configuration.constraints.values():
        if str(value.label) == "prelude//os/constraints:windows":
            use_windows_path_separators = True

    if read_config("buck2_re_client", "engine_address"):
        return CommandExecutorConfig(
            local_enabled = True,
            remote_enabled = True,
            use_limited_hybrid = True,
            remote_execution_properties = _buckconfig_remote_execution_properties | {
                "OSFamily": "Linux",
                "Arch": "amd64",
                "container-image": "docker://docker.io/dtolnay/buck2-rustc-bootstrap:latest",
            },
            remote_execution_use_case = "buck2-rustc-bootstrap",
            use_windows_path_separators = use_windows_path_separators,
        )
    else:
        return CommandExecutorConfig(
            local_enabled = True,
            remote_enabled = False,
            use_windows_path_separators = use_windows_path_separators,
        )
