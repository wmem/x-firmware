# x-firmware

xmake Addon，供 Boot、APP 和其他 xmake 脚本共享固件格式，并通过显式文件 API 制作完整及差分升级镜像。

当前已实现共用 C 协议头、Lua 固件头与产品信息编解码、流式 CRC32、Addon 载荷准备和独立 C 互通检查。文件打包、LZ4、bsdiff、构建规则及命令尚未实现；尚未发布版本。

## 协议和公开入口

C 入口为 [addon/include/x_firmware/firmware.h](addon/include/x_firmware/firmware.h) 和 [product.h](addon/include/x_firmware/product.h)。固定字段、magic 和 C 布局由这里维护；Lua 序列化见 [format.lua](addon/modules/format.lua)，与 C 独立参考实现互通验证。所有数值字段按小端写入。

固件 magic.size 包含 magic、固定字段及变长平台字符串，magic.crc32 覆盖 magic 后到头部末尾。产品信息头的 size 和 CRC 指后续 `key=value\0` 数据；两种头的长度和 CRC 范围不同。CRC 使用 CRC-32/ISO-HDLC，`123456789` 的校验值为 0xCBF43926。

运行头按 1 KiB 对齐、升级包按 4 KiB 对齐，对齐不代表预留容量。identifier 最多 15 字节并以 NUL 结束。平台字符串以分号分隔，platform_len 包含末尾 NUL。底层编解码允许空平台字符串，用于解析或制作拒绝升级的测试数据；Boot 必须拒绝空支持列表。

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

正式安装后拟使用 `import("@addon.x-firmware.api")`，安装和消费工程集成在下一阶段验证。完整文件 API 计划提供 fill_run_header、make_upgrade、make_diff、add_header、compress_lz4、diff_bsdiff 和 inspect；传入文件路径、info、options，保持后端选择与接口分离。

## 验证

在仓库根目录执行：

```sh
xmake l tests/protocol.lua
```

需要现有 xmake、主机 `cc` 和 `arm-none-eabi-gcc`，不自动安装工具。也可给测试函数显式传入仓库路径。检查包含 C 字段大小与偏移、C/Lua 五种格式的逐字节互通、CRC 基准与流式处理、错误输入拒绝，以及同一协议头在 Cortex-M4 编译器下的布局检查。

2026-10-14 在 WSL、Xmake 3.1.1+HEAD.3ba37a0、ARM GCC 10.3.1 下通过：五种格式互通、流式 CRC、16 个错误输入和 ARM 布局编译。原始生成样例及结果位于本地 `build/protocol`；这不代表 LZ4、bsdiff 或升级流程已经验证。

准备独立载荷时，输出目录必须不存在：

```sh
xmake l scripts/prepare-addon.lua /path/to/new-payload /path/to/x-firmware
```

载荷包含 addon.lua、modules 和 include；不覆盖日常插件安装。隔离安装与固定提交分发验证仍待后续阶段完成。
