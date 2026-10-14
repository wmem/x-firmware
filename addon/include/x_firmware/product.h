/**
 * \file product.h
 *
 * \brief 产品信息定义.
 *
 * \internal
 * \par Modification history
 * - 1.00 2018年12月26日 MeM : first create the file
 * \endinternal
 */

#ifndef __PRODUCT_H_
#define __PRODUCT_H_

#include <stdint.h>

/** \brief 产品信息 */
typedef struct product_head {
#define PRODUCT_MAGIC     0x50524454  /**< \brief 产品信息幻数 */
    uint32_t flag;      /**< \brief 标识 */
    uint32_t crc32;     /**< \brief 后面数据的crc32 */
    uint32_t size;      /**< \brief 后面数据的大小 */
} product_head_t;

//产品信息内容
// "key1=value1\0key2=value2"

#endif // __PRODUCT_H_
