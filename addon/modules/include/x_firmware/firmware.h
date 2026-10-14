/**
 * \file firmware.h
 *
 * \brief 固件信息定义.
 *
 * \internal
 * \par Modification history
 * - 1.00 2018年12月26日 MeM : first create the file
 * \endinternal
 */

#ifndef __FIRMWARE_H_
#define __FIRMWARE_H_

#include <stdint.h>

/* 线格式为小端；对齐要求不表示预留容量。 */
#define FIRMWARE_RUN_ALIGNMENT 1024u
#define FIRMWARE_UPGRADE_ALIGNMENT 4096u
#define FIRMWARE_DATA_RAW 0u
#define FIRMWARE_DATA_LZ4 1u
#define FIRMWARE_CRYPTO_LZ4 0u

/** \brief 幻数信息 */
typedef struct firmware_magic {
//Firmware magic
#define FIRMWARE_MAGIC_IMAGE_RUN     0x464D524E  /**< \brief 可直接运行的固件 */
#define FIRMWARE_MAGIC_IMAGE_DIFF    0x464D4446  /**< \brief 差异固件 */
#define FIRMWARE_MAGIC_IMAGE_UPGRADE 0x464D5550  /**< \brief 升级固件 */
#define FIRMWARE_MAGIC_IMAGE_ENCRYPT 0x464D4554  /**< \brief 外层封装，当前只支持 LZ4 */
    uint32_t flag;      /**< \brief 标识 */
    uint32_t crc32;     /**< \brief magic 之后至头部末尾的 CRC32 */
    uint32_t size;      /**< \brief 头部总长度，包含 magic 和变长平台字符串 */
} firmware_magic_t;

//platform      -> "IOB_V01;IOB_v02"
//platform_size -> 包含"\0"的大小

/** \brief 可运行固件头部 */
typedef struct image_head_run {
    firmware_magic_t magic;      /**< \brief 幻数信息 */

    uint32_t  version;           /**< \brief 固件版本 */
    uint32_t  addr;              /**< \brief 固件地址 */
    uint32_t  size;              /**< \brief 固件大小 */
    char      identifier[16];    /**< \brief 固件标识(\0结尾) */
    uint32_t  platform_len;      /**< \brief 平台字符串长度(包含"\0") */
    char      p_platform[];     /**< \brief 硬件平台(\0结尾) */
} image_head_run_t;

/** \brief 升级固件头部 */
typedef struct image_head_upgrade {
    firmware_magic_t magic;     /**< \brief 幻数信息 */

    uint32_t addr;              /**< \brief 原始固件地址 */
    uint32_t size;              /**< \brief 原始固件大小 */
    uint32_t crc;               /**< \brief 原始固件CRC32 */
    uint32_t version;           /**< \brief 原始固件版本 */

    uint32_t dat_size;          /**< \brief 固件数据大小 */
    uint32_t dat_crc;           /**< \brief 固件数据CRC32 */
    uint32_t dat_type;          /**< \brief 固件数据格式，0:原始数据，1：LZ4压缩数据 */

    char     identifier[16];    /**< \brief 固件标识(\0结尾) */

    uint32_t platform_len;      /**< \brief 平台字符串长度(包含"\0") */
    char     p_platform[];     /**< \brief 硬件平台(\0结尾) */
} image_head_upgrade_t;

/** \brief 差异固件头部 */
typedef struct image_head_diff {
    firmware_magic_t magic;     /**< \brief 幻数信息 */

    uint32_t src_addr;          /**< \brief 原固件存放地址 */
    uint32_t src_size;          /**< \brief 原固件大小 */
    uint32_t src_crc;           /**< \brief 原固件CRC32 */
    uint32_t src_version;       /**< \brief 原固件版本号 */

    uint32_t dst_addr;          /**< \brief 目标固件存放地址 */
    uint32_t dst_size;          /**< \brief 目标固件大小 */
    uint32_t dst_crc;           /**< \brief 目标固件CRC32 */
    uint32_t dst_version;       /**< \brief 目标固件版本号 */

    uint32_t dat_size;          /**< \brief 差异数据大小 */
    uint32_t dat_crc;           /**< \brief 差异数据CRC32 */

    char     identifier[16];    /**< \brief 固件标识(\0结尾) */

    uint32_t platform_len;      /**< \brief 平台字符串长度(包含"\0") */
    char     p_platform[];     /**< \brief 硬件平台(\0结尾) */
} image_head_diff_t;

/** \brief 外层封装头部；保留原命名，不表示已实现加密 */
typedef struct image_head_encrypt {
    firmware_magic_t magic;     /**< \brief 幻数信息 */

    uint32_t src_size;          /**< \brief 原始数据大小 */
    uint32_t dat_size;          /**< \brief 数据大小 */
    uint32_t dat_crc;           /**< \brief 数据CRC32 */
    uint32_t dat_crypto;        /**< \brief 数据加密方式，0:LZ4压缩 */
} image_head_encrypt_t;

#endif // __FIRMWARE_H_
