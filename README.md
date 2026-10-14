# x-firmware

xmake Addon，供 Boot、APP 和其他 xmake 脚本共享固件格式，并通过显式文件 API 制作完整及差分升级镜像。

当前已实现共用 C 协议头、全部文件 API、纯 Lua LZ4/bsdiff、协议编解码、流式 CRC32、构建规则和命令入口。独立 C 算法互通、真实隔离 Addon 安装、API/规则/命令消费及增量行为均已通过。源码与 Addon 采用同一版本号 0.1.0，分发配方固定对应源码提交。

## 安装

在消费工程的 xmake.lua 中声明：

```lua
add_repositories("wmem-xmake-addon git@github.com:wmem/xmake-addons.git")
add_addons("x-firmware 0.1.0")
```

随后执行 `xmake f -y`，即可通过公开模块、规则和命令调用。安装不需要算法二进制、Python 或其他插件；本仓库的独立 C 互通测试另需现有主机编译器、系统 liblz4 和 uv/Python。

## 协议和公开入口

C 入口为 [firmware.h](addon/modules/include/x_firmware/firmware.h) 和 [product.h](addon/modules/include/x_firmware/product.h)。固定字段、magic 和 C 布局由这里维护；Lua 序列化见 [format.lua](addon/modules/format.lua)，与 C 独立参考实现互通验证。所有数值字段按小端写入。

固件 magic.size 包含 magic、固定字段及变长平台字符串，magic.crc32 覆盖 magic 后到头部末尾。产品信息头的 size 和 CRC 指后续 `key=value\0` 数据；两种头的长度和 CRC 范围不同。CRC 使用 CRC-32/ISO-HDLC，`123456789` 的校验值为 0xCBF43926。

运行头按 1 KiB 对齐、升级包按 4 KiB 对齐，对齐不代表预留容量。identifier 最多 15 字节并以 NUL 结束，可为空；Boot 不以此标识判断平台支持。平台字符串以分号分隔，platform_len 包含末尾 NUL。底层编解码允许空平台字符串，用于解析或制作拒绝升级的测试数据；Boot 必须拒绝空支持列表。

`image_head_encrypt_t` 及 magic 保留输入定义的命名；当前设计的 dat_crypto=0 代表 LZ4 外层封装，不表示提供加密。算法和有效性策略由后续打包 API 及 Boot 实现，协议编解码不代替安装准入检查。

当前公开 [api.lua](addon/modules/api.lua) 提供 `include_dir()`、`encode_header(kind, info)`、`decode_header(bytes, offset)`、`encode_product(values)` 和 `decode_product(bytes, offset)`。返回头部字节或解析后的 table，错误通过 xmake 的错误机制报告，不读取 target、板描述或修改工作目录。

通过本地源码验证接口时显式指定模块目录：

```lua
local firmware = import("api", {rootdir = "/path/to/x-firmware/addon/modules"})
local header = firmware.encode_header("run", {
    version = 7, addr = 0x08004000, size = 98304,
    identifier = "sample", platform = "KY3133_B00;TEST"
})
```

正式安装后使用 `import("@addon.x-firmware.api")`。文件函数参数为：

| 函数 | 参数 |
| --- | --- |
| fill_run_header | input, output, info, options；必须显式指定 options.header_capacity |
| make_upgrade | input, output, info, options；compression 默认 none，可设 lz4 |
| make_diff | oldfile, newfile, output, info, options；compression 默认 lz4，可设 none |
| add_header | input, output, info, options；info.kind 为 upgrade/diff/encrypt |
| compress_lz4 | input, output, info, options；输出 raw block |
| diff_bsdiff | oldfile, newfile, output, info, options；输出未压缩交错补丁 |
| inspect | input, options；校验头部和载荷，完整包还校验恢复结果 |
| write_product | output, values, options；写入产品键值镜像 |

函数返回产物路径、长度及头部/CRC 元数据，不修改调用方信息。fill_run_header 在 bin 的 1 KiB 对齐处寻找运行头，多个候选时拒绝，或由 options.header_offset 显式选取；只改预留区域，不改变文件长度或向量表。文件处理失败保留既有输出。完整和差分打包输入须为已补全的运行镜像。

升级包头地址的 4 KiB 对齐由 APP 写入 Flash 时保证；打包工具不在文件前插入 4 KiB 填充。压缩完整包使用 upgrade.dat_type=1；压缩差分包使用 encrypt 外层包含完整的 diff 头和未压缩补丁。

构建目标可以添加 `@addon/x-firmware/protocol` 规则取得公共包含目录；`@addon/x-firmware/package` 接收 config table，其中 operation=app/upgrade/diff/product，其他字段与文件 API 一致，相对路径以消费工程根目录为基准。调用方先生成 input bin；该规则在 after_build 调用同一 API，用文件元数据、参数及模块版本实现增量，不使用内容 hash。

命令入口 `xmake x-firmware --config=firmware.json <app|upgrade|diff|inspect|product>`，JSON 中提供 input/output 或 old/new，以及 info/options。相对路径以 JSON 所在目录为基准；规则和命令共用 execute 入口。

## 验证

在仓库根目录执行：

```sh
xmake l tests/protocol.lua
xmake l tests/files.lua
uv run --no-project --offline python tests/addon_integration.py
```

需要现有 xmake、主机 cc、arm-none-eabi-gcc、uv Python 及测试用系统 liblz4，不自动安装工具。也可给测试函数显式传入仓库路径。检查包含 C 字段布局和五种格式互通、流式 CRC、错误输入拒绝、ARM 布局、26 组 Lua/C 双向 LZ4/bsdiff 互通、三类镜像恢复、中文空格路径、原位加头及失败输出保护。依赖来源及许可证见 [THIRD_PARTY](THIRD_PARTY.md)。

2026-10-14 在 WSL、Xmake 3.1.1+HEAD.3ba37a0、ARM GCC 10.3.1 下以上协议及文件检查通过。代表性的 256 KiB 输入 bsdiff 约 8.4 秒，未压缩补丁 262172 字节，LZ4 后 2066 字节，因此采用纯 Lua 后端。原始样例和结果位于本地 build/protocol 和 build/文件 API 空格；这不代表 MCU 升级流程已经验证。

准备独立载荷时，输出目录必须不存在：

```sh
xmake l scripts/prepare-addon.lua /path/to/new-payload /path/to/x-firmware
```

载荷包含 addon.lua、modules、plugins 和 rules，C 包含文件和许可证作为 modules 的资源分发。addon_integration.py 从本地 Git 固定提交真实安装到独立 XMAKE_GLOBALDIR，验证导入、C 头及许可证、协议及打包规则、命令入口、正常增量、参数变更、缺失产物恢复及消费程序运行，不覆盖日常插件安装。
