task("x-firmware")
set_category("plugin")
set_menu({
    usage = "xmake x-firmware --config=<JSON> <app|upgrade|diff|inspect|product>",
    description = "按显式配置处理本地固件文件",
    options = {
        {"c", "config", "kv", nil, "文件处理配置 JSON，相对路径以该配置所在目录为基准"},
        {nil, "operation", "v", nil, "app/upgrade/diff/inspect/product"}
    }
})
on_run("main")
