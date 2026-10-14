"""真实安装本地固定提交并验证 API/规则/命令，不修改日常 Xmake 全局目录。"""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import time

root = Path(__file__).resolve().parents[1]
base = root / "build/addon-integration"
base.mkdir(exist_ok=True)
globaldir = Path(tempfile.mkdtemp(prefix="global-", dir=base))
repo = base / "repository"
project = base / "consumer"
project.mkdir(exist_ok=True)
version = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=root, text=True).strip()
recipe = repo / "addons/x/x-firmware/xmake.lua"
recipe.parent.mkdir(parents=True, exist_ok=True)
recipe.write_text(f'''package("x-firmware")
set_kind("addon")
set_license("MIT")
add_urls("file://{root.as_posix()}/.git")
add_versions("0.1.0", "{version}")
on_install(function(package)
    import("prepare-addon", {{rootdir=path.join(os.curdir(), "scripts"), anonymous=true}}).install(package)
end)
on_test(function(package)
    assert(os.isfile(package:installdir("modules/include/x_firmware/firmware.h")))
    assert(os.isfile(package:installdir("modules/licenses/bsdiff.txt")))
end)
package_end()
''')
if os.environ.get("FIRMWARE_ADDON_REPOSITORY"):
    # 验证真实分发配方，不修改外部索引的源码或提交号。
    repo = Path(os.environ["FIRMWARE_ADDON_REPOSITORY"]).resolve()
env = os.environ.copy()
env["XMAKE_GLOBALDIR"] = str(globaldir)
env["XMAKE_COLORTERM"] = "nocolor"
logs = []
def run(*args):
    p = subprocess.run(args, cwd=project, env=env, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    logs.append({"command": list(args), "returncode": p.returncode, "output": p.stdout})
    (base / "commands.json").write_text(json.dumps(logs, ensure_ascii=False, indent=2))
    if p.returncode:
        print(p.stdout[-10000:])
        raise RuntimeError(f"命令失败：{args}")
    return p.stdout

def configure(compression):
    (project / "xmake.lua").write_text(f'''set_project("firmware-addon-consumer")
set_xmakever("3.1.1")
add_repositories("firmware-local {repo.as_posix()}")
add_addons("x-firmware 0.1.0")
target("consumer")
    set_kind("binary")
    add_files("main.c")
    add_rules("@addon/x-firmware/protocol")
    add_rules("@addon/x-firmware/package", {{config={{operation="upgrade",input="app.bin",
        output="upgrade.bin",options={{compression="{compression}"}}}}}})
''')

(project / "main.c").write_text('''#include <x_firmware/firmware.h>
int main(void) { return sizeof(image_head_run_t) != 44; }
''')
shutil.copyfile(root / "build/文件 API 空格/v2.bin", project / "app.bin")
configure("lz4")
run("xmake", "f", "-c", "-y", "-m", "release")
run("xmake", "-y")
packed = project / "upgrade.bin"
first = packed.stat().st_mtime_ns
time.sleep(1.1)
run("xmake", "-y")
assert packed.stat().st_mtime_ns == first, "无变化构建重复打包"
packed.unlink()
run("xmake", "-y")
assert packed.exists(), "缺失产物没有恢复"
compressed_size = packed.stat().st_size
time.sleep(1.1)
configure("none")
run("xmake", "f", "-y", "-m", "release")
run("xmake", "-y")
assert packed.stat().st_size > compressed_size, "参数变化没有重打包"
config = project / "inspect.json"
config.write_text(json.dumps({"input": "upgrade.bin"}))
response = run("xmake", "x-firmware", "--config=inspect.json", "inspect")
assert '"restored_crc_valid":true' in response.replace(" ", ""), response
response = run("xmake", "l", "-c", 'local a=import("@addon.x-firmware.api"); print(a.include_dir()); assert(a.inspect("upgrade.bin").kind=="upgrade")')
assert "include" in response
run("xmake", "run", "consumer")
(base / "result.json").write_text(json.dumps({"status": "PASS", "source_commit": version,
    "repository": str(repo), "globaldir": str(globaldir),
    "checks": ["真实隔离安装", "C 头及许可证分发", "API 导入", "协议规则", "文件打包规则", "正常增量",
               "缺失产物恢复", "参数变化重打包", "命令入口", "消费程序运行"]}, ensure_ascii=False, indent=2))
print("PASS: Addon 真实隔离安装、API/规则/命令及增量行为，提交", version)
