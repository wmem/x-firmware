local source = path.absolute("..", os.scriptdir())

function main(output, source_root)
    assert(output, "请指定输出目录")
    local root = source_root and path.absolute(source_root) or source
    output = path.absolute(output)
    assert(not os.exists(output), "输出目录已存在：" .. output)
    os.mkdir(output)
    os.cp(path.join(root, "addon.lua"), output)
    os.cp(path.join(root, "addon"), output)
end

function install(package)
    import("core.package.addon")
    local root = source
    local manifest = addon.manifest(root)
    assert(manifest.name == package:name(), "Addon 名称不一致")
    for _, payload in ipairs(addon.payloads_of(addon.payloadroot(root))) do
        os.cp(path.join(addon.payloadroot(root), payload), package:installdir())
    end
    package:data_set("addon.manifest", manifest)
end
