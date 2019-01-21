/**
 * \file cmac.h
 *
 * \brief The Cipher-based Message Authentication Code (CMAC) Mode for
 *        Authentication.
 */
/*
 *  Copyright (C) 2015-2018, Arm Limited (or its affiliates), All Rights Reserved
 *  SPDX-License-Identifier: Apache-2.0
 *
 *  Licensed under the Apache License, Version 2.0 (the "License"); you may
 *  not use this file except in compliance with the License.
 *  You may obtain a copy of the License at
 *
 *  http://www.apache.org/licenses/LICENSE-2.0
 *
 *  Unless required by applicable law or agreed to in writing, software
 *  distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
 *  WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 *  See the License for the specific language governing permissions and
 *  limitations under the License.
 *
 *  This file is part of Mbed TLS (https://tls.mbed.org)
 */

#ifndef MBEDTLS_CMAC_H
#define MBEDTLS_CMAC_H

#include "mbedtls/cipher.h"

#ifdef __cplusplus
extern "C" {
#endif

#define MBEDTLS_ERR_CMAC_HW_ACCEL_FAILED -0x007A  /**< CMAC hardware accelerator failed. */

#define MBEDTLS_AES_BLOCK_SIZE          16
#define MBEDTLS_DES3_BLOCK_SIZE         8

#if defined(MBEDTLS_AES_C)
#define MBEDTLS_CIPHER_BLKSIZE_MAX      16  /* The longest block used by CMAC is that of AES. */
#else
#define MBEDTLS_CIPHER_BLKSIZE_MAX      8   /* The longest block used by CMAC is that of 3DES. */
#endif

#if !defined(MBEDTLS_CMAC_ALT)

/**
 * The CMAC context structure.
 */
struct mbedtls_cmac_context_t
{
    /** The internal state of the CMAC algorithm.  */
    unsigned char       state[MBEDTLS_CIPHER_BLKSIZE_MAX];

    /** Unprocessed data - either data that was not block aligned and is still
     *  pending processing, or the final block. */
    unsigned char       unprocessed_block[MBEDTLS_CIPHER_BLKSIZE_MAX];

    /** The length of data pending processing. */
    size_t              unprocessed_len;
};

/**
 * \brief               This function sets the CMAC key, and prepares to authenticate
 *                      the input data.
 *                      Must be called with an initialized cipher context.
 *
 * \param ctx           The cipher context used for the CMAC operation, initialized
 *                      as one of the following types:<ul>
 *                      <li>MBEDTLS_CIPHER_AES_128_ECB</li>
 *                      <li>MBEDTLS_CIPHER_AES_192_ECB</li>
 *                      <li>MBEDTLS_CIPHER_AES_256_ECB</li>
 *                      <li>MBEDTLS_CIPHER_DES_EDE3_ECB</li></ul>
 * \param key           The CMAC key.
 * \param keybits       The length of the CMAC key in bits.
 *                      Must be supported by the cipher.
 *
 * \return              \c 0 on success, or a cipher-specific error code.
 */
int mbedtls_cipher_cmac_starts( mbedtls_cipher_context_t *ctx,
                                const unsigned char *key, size_t keybits );

/**
 * \brief               This function feeds an input buffer into an ongoing CMAC
 *                      computation.
 *
 *                      It is called between mbedtls_cipher_cmac_starts() or
 *                      mbedtls_cipher_cmac_reset(), and mbedtls_cipher_cmac_finish().
 *                      Can be called repeatedly.
 *
 * \param ctx           The cipher context used for the CMAC operation.
 * \param input         The buffer holding the input data.
 * \param ilen          The length of the input data.
 *
 * \returns             \c 0 on success, or #MBEDTLS_ERR_MD_BAD_INPUT_DATA
 *                      if parameter verification fails.
 */
int mbedtls_cipher_cmac_update( mbedtls_cipher_context_t *ctx,
                                const unsigned char *input, size_t ilen );

/**
 * \brief               This function finishes the CMAC operation, and writes
 *                      the result to the output buffer.
 *
 *                      It is called after mbedtls_cipher_cmac_update().
 *                      It can be followed by mbedtls_cipher_cmac_reset() and
 *                      mbedtls_cipher_cmac_update(), or mbedtls_cipher_free().
 *
 * \param ctx           The cipher context used for the CMAC operation.
 * \param output        The output buffer for the CMAC checksum result.
 *
 * \returns             \c 0 on success, or #MBEDTLS_ERR_MD_BAD_INPUT_DATA
 *                      if parameter verification fails.
 */
int mbedtls_cipher_cmac_finish( mbedtls_cipher_context_t *ctx,
                                unsigned char *output );

/**
 * \brief               This function prepares the authentication of another
 *                      message with the same key as the previous CMAC
 *                      operation.
 *
 *                      It is called after mbedtls_cipher_cmac_finish()
 *                      and before mbedtls_cipher_cmac_update().
 *
 * \param ctx           The cipher context used for the CMAC operation.
 *
 * \returns             \c 0 on success, or #MBEDTLS_ERR_MD_BAD_INPUT_DATA
 *                      if parameter verification fails.
 */
int mbedtls_cipher_cmac_reset( mbedtls_cipher_context_t *ctx );

/**
 * \brief               This function calculates the full generic CMAC
 *                      on the input buffer with the provided key.
 *
 *                      The function allocates the context, performs the
 *                      calculation, and frees the context.
 *
 *                      The CMAC result is calculated as
 *                      output = generic CMAC(cmac key, input buffer).
 *
 *
 * \param cipher_info   The cipher information.
 * \param key           The CMAC key.
 * \param keylen        The length of the CMAC key in bits.
 * \param input         The buffer holding the input data.
 * \param ilen          The length of the input data.
 * \param output        The buffer for the generic CMAC result.
 *
 * \returns             \c 0 on success, or #MBEDTLS_ERR_MD_BAD_INPUT_DATA
 *                      if parameter verification fails.
 */
int mbedtls_cipher_cmac( const mbedtls_cipher_info_t *cipher_info,
                         const unsigned char *key, size_t keylen,
                         const unsigned char *input, size_t ilen,
                         unsigned char *output );

#if defined(MBEDTLS_AES_C)
/**
 * \brief           This function implements the AES-CMAC-PRF-128 pseudorandom
 *                  function, as defined in
 *                  <em>RFC-4615: The Advanced Encryption Standard-Cipher-based
 *                  Message Authentication Code-Pseudo-Random Function-128
 *                  (AES-CMAC-PRF-128) Algorithm for the Internet Key
 *                  Exchange Protocol (IKE).</em>
 *
 * \param key       The key to use.
 * \param key_len   The key length in Bytes.
 * \param input     The buffer holding the input data.
 * \param in_len    The length of the input data in Bytes.
 * \param output    The buffer holding the generated 16 Bytes of
 *                  pseudorandom output.
 *
 * \return          \c 0 on success.
 */
int mbedtls_aes_cmac_prf_128( const unsigned char *key, size_t key_len,
                              const unsigned char *input, size_t in_len,
                              unsigned char output[16] );
#endif /* MBEDTLS_AES_C */

#ifdef __cplusplus
}
#endif

#else  /* !MBEDTLS_CMAC_ALT */
#include "cmac_alt.h"
#endif /* !MBEDTLS_CMAC_ALT */

#ifdef __cplusplus
extern "C" {
#endif

#if defined(MBEDTLS_SELF_TEST) && ( defined(MBEDTLS_AES_C) || defined(MBEDTLS_DES_C) )
/**
 * \brief          The CMAC checkup routine.
 *
 * \return         \c 0 on success, or \c 1 on failure.
 */
int mbedtls_cmac_self_test( int verbose );
#endif /* MBEDTLS_SELF_TEST && ( MBEDTLS_AES_C || MBEDTLS_DES_C ) */

#ifdef __cplusplus
}
#endif

#endif /* MBEDTLS_CMAC_H */
