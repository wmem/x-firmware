# 算法来源与许可证

LZ4 Lua 编解码按 [LZ4 Block Format](https://github.com/lz4/lz4/blob/dev/doc/lz4_Block_format.md) 独立实现，使用 raw block，由既有固件头提供输入输出长度。互通测试使用本机已有 liblz4 1.9.4，不将它加入打包插件的运行依赖。

bsdiff 的匹配评分、前后向匹配及重叠处理移植自 [mendsley/bsdiff](https://github.com/mendsley/bsdiff/tree/b817e9491cf7b8699c8462ef9e2657ca4ccd7667)，原作者 Colin Percival、Matthew Endsley，BSD-2-Clause。纯 Lua 后缀数组独立使用倍增和计数排序；输出为未压缩交错 control/diff/extra，控制整数为 8 字节小端符号幅度。完整许可证随 Addon 分发于 [bsdiff.txt](addon/modules/licenses/bsdiff.txt)。

[tests/reference](tests/reference) 中的 bsdiff.c/h、bspatch.c/h 固定取自以上提交，仅用于独立 C 参考互通测试，保留各文件版权与许可证。插件运行不构建或调用这些 C 程序，也不依赖 bzip2。
