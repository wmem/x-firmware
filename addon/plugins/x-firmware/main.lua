import("core.base.option")
import("core.base.json")
function main()
    local filename = path.absolute(assert(option.get("config"), "请提供 --config=<JSON>"))
    local api = import("api", {rootdir = path.absolute("../../modules", os.scriptdir())})
    local config = json.loadfile(filename)
    print(json.encode(api.execute(option.get("operation"), config, path.directory(filename))))
end
