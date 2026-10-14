#include <assert.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <x_firmware/firmware.h>
#include <x_firmware/product.h>

/* 同时在主机和 ARM 编译；不依赖 Lua 序列化实现。 */
_Static_assert(sizeof(firmware_magic_t) == 12, "magic");
_Static_assert(sizeof(image_head_run_t) == 44, "run");
_Static_assert(offsetof(image_head_run_t, p_platform) == 44, "run platform");
_Static_assert(offsetof(image_head_run_t, identifier) == 24, "run identifier");
_Static_assert(sizeof(image_head_upgrade_t) == 60, "upgrade");
_Static_assert(offsetof(image_head_upgrade_t, dat_size) == 28, "upgrade data");
_Static_assert(offsetof(image_head_upgrade_t, p_platform) == 60, "upgrade platform");
_Static_assert(sizeof(image_head_diff_t) == 72, "diff");
_Static_assert(offsetof(image_head_diff_t, dst_addr) == 28, "diff destination");
_Static_assert(offsetof(image_head_diff_t, dat_size) == 44, "diff data");
_Static_assert(offsetof(image_head_diff_t, p_platform) == 72, "diff platform");
_Static_assert(sizeof(image_head_encrypt_t) == 28, "outer");
_Static_assert(sizeof(product_head_t) == 12, "product");

/* 按位参考实现，独立于 Lua 的查表算法。 */
static uint32_t crc(const uint8_t *data, size_t length)
{
    uint32_t value = 0xffffffff;
    while (length--) {
        value ^= *data++;
        for (unsigned i = 0; i < 8; ++i)
            value = (value >> 1) ^ ((value & 1) ? 0xedb88320 : 0);
    }
    return value ^ 0xffffffff;
}

static void compare_and_write(const char *folder, const char *kind, const uint8_t *data, size_t size)
{
    char filename[2048];
    uint8_t input[1024];
    int n = snprintf(filename, sizeof(filename), "%s/lua-%s.bin", folder, kind);
    assert(n > 0 && (size_t)n < sizeof(filename));
    FILE *f = fopen(filename, "rb");
    assert(f);
    size_t actual = fread(input, 1, sizeof(input), f);
    assert(!ferror(f) && actual == size && memcmp(input, data, size) == 0);
    fclose(f);
    n = snprintf(filename, sizeof(filename), "%s/c-%s.bin", folder, kind);
    assert(n > 0 && (size_t)n < sizeof(filename));
    f = fopen(filename, "wb");
    assert(f && fwrite(data, 1, size, f) == size);
    assert(fclose(f) == 0);
}

static void firmware(const char *folder, const char *kind, const void *header, size_t fixed,
                     const char *platform)
{
    uint8_t bytes[1024];
    memcpy(bytes, header, fixed);
    size_t size = fixed;
    if (platform) {
        size_t count = strlen(platform) + 1;
        uint32_t length = (uint32_t)count;
        memcpy(bytes + fixed - 4, &length, 4);
        memcpy(bytes + fixed, platform, count);
        size += count;
    }
    firmware_magic_t magic;
    memcpy(&magic, bytes, sizeof(magic));
    magic.size = (uint32_t)size;
    magic.crc32 = crc(bytes + sizeof(magic), size - sizeof(magic));
    memcpy(bytes, &magic, sizeof(magic));
    compare_and_write(folder, kind, bytes, size);
}

int main(int argc, char **argv)
{
    assert(argc == 2);
    uint32_t endian = 1;
    assert(*(uint8_t *)&endian == 1);
    assert(crc((const uint8_t *)"123456789", 9) == 0xcbf43926);
    const char *p = "KY3133_B00;TEST";
    image_head_run_t run = {.magic.flag = FIRMWARE_MAGIC_IMAGE_RUN,
        .version = 7, .addr = 0x08004000, .size = 98304, .identifier = "sample"};
    firmware(argv[1], "run", &run, sizeof(run), p);
    image_head_upgrade_t up = {.magic.flag = FIRMWARE_MAGIC_IMAGE_UPGRADE,
        .addr = 0x08004000, .size = 98304, .crc = 0x11223344, .version = 7,
        .dat_size = 65432, .dat_crc = 0xdeadbeef, .dat_type = FIRMWARE_DATA_LZ4,
        .identifier = "sample"};
    firmware(argv[1], "upgrade", &up, sizeof(up), p);
    image_head_diff_t diff = {.magic.flag = FIRMWARE_MAGIC_IMAGE_DIFF,
        .src_addr = 0x08004000, .src_size = 80000, .src_crc = 0x10203040, .src_version = 6,
        .dst_addr = 0x08004000, .dst_size = 98304, .dst_crc = 0x11223344, .dst_version = 7,
        .dat_size = 50123, .dat_crc = 0xdeadbeef, .identifier = "sample"};
    firmware(argv[1], "diff", &diff, sizeof(diff), p);
    image_head_encrypt_t outer = {.magic.flag = FIRMWARE_MAGIC_IMAGE_ENCRYPT,
        .src_size = 50195, .dat_size = 23456, .dat_crc = 0xaabbccdd, .dat_crypto = FIRMWARE_CRYPTO_LZ4};
    firmware(argv[1], "encrypt", &outer, sizeof(outer), NULL);
    const char product[] = "name=test\0platform=KY3133_B00";
    product_head_t h = {.flag = PRODUCT_MAGIC, .size = sizeof(product),
                       .crc32 = crc((const uint8_t *)product, sizeof(product))};
    uint8_t image[sizeof(h) + sizeof(product)];
    memcpy(image, &h, sizeof(h));
    memcpy(image + sizeof(h), product, sizeof(product));
    compare_and_write(argv[1], "product", image, sizeof(image));
    puts("C 布局、CRC 和五种镜像的逐字节互通 PASS");
    return 0;
}
