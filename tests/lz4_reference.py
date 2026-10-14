"""使用系统既有 liblz4 进行独立恢复，不依赖插件的 Lua 解码器。"""
import argparse
import ctypes
import ctypes.util
from pathlib import Path

p = argparse.ArgumentParser()
p.add_argument("source")
p.add_argument("packed")
args = p.parse_args()
library = ctypes.util.find_library("lz4")
assert library, "独立互通检查需要现有 liblz4；不自动安装"
lz4 = ctypes.CDLL(library)
lz4.LZ4_decompress_safe.argtypes = [ctypes.c_void_p, ctypes.c_void_p, ctypes.c_int, ctypes.c_int]
lz4.LZ4_decompress_safe.restype = ctypes.c_int
raw = Path(args.source).read_bytes()
packed = Path(args.packed).read_bytes()
output = ctypes.create_string_buffer(len(raw) + 1)
actual = lz4.LZ4_decompress_safe(packed, output, len(packed), len(raw))
assert actual == len(raw) and output.raw[:actual] == raw, (actual, len(raw))
lz4.LZ4_compressBound.argtypes = [ctypes.c_int]
lz4.LZ4_compressBound.restype = ctypes.c_int
lz4.LZ4_compress_default.argtypes = [ctypes.c_void_p, ctypes.c_void_p, ctypes.c_int, ctypes.c_int]
lz4.LZ4_compress_default.restype = ctypes.c_int
buffer = ctypes.create_string_buffer(lz4.LZ4_compressBound(len(raw)))
count = lz4.LZ4_compress_default(raw, buffer, len(raw), len(buffer))
assert count > 0
Path(args.packed + ".reference").write_bytes(buffer.raw[:count])
