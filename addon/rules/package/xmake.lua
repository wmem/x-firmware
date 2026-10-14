rule("package")
after_build(function(target)
    import("core.package.addon")
    import("core.project.depend")
    import("core.base.json")
    local api = import("@self.api")
    local owner = "@addon/" .. addon.owner() .. "/package"
    local config = assert(target:extraconf("rules", owner, "config"), "package 规则必须提供 config")
    assert(type(config) == "table" and config.operation and config.output, "config 必须提供 operation/output")
    local root = os.projectdir()
    local files = {}
    for _, key in ipairs({"input", "old", "new"}) do
        if config[key] then files[#files + 1] = path.absolute(config[key], root) end
    end
    local modules = path.directory(api.include_dir())
    for _, filename in ipairs(os.files(path.join(modules, "*.lua"))) do files[#files + 1] = filename end
    table.sort(files)
    local output = path.absolute(config.output, root)
    depend.on_changed(function()
        api.execute(config.operation, config, root)
    end, {dependfile = target:dependfile(output), files = files,
          values = {"x-firmware-0.1.0", json.encode(config)},
          changed = target:is_rebuilt() or not os.isfile(output), lastmtime = os.mtime(output)})
end)
rule_end()
