/**
 * \file debug.h
 *
 * \brief Functions for controlling and providing debug output from the library.
 */
/*
 *  Copyright (C) 2006-2015, ARM Limited, All Rights Reserved
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
 *  This file is part of mbed TLS (https://tls.mbed.org)
 */
#ifndef MBEDTLS_DEBUG_H
#define MBEDTLS_DEBUG_H

#if !defined(MBEDTLS_CONFIG_FILE)
#include "config.h"
#else
#include MBEDTLS_CONFIG_FILE
#endif

#include "ssl.h"

#if defined(MBEDTLS_ECP_C)
#include "ecp.h"
#endif

#if defined(MBEDTLS_DEBUG_C)

#define MBEDTLS_DEBUG_STRIP_PARENS( ... )   __VA_ARGS__

#define MBEDTLS_SSL_DEBUG_MSG( level, args )                    \
    mbedtls_debug_print_msg( ssl, level, __FILE__, __LINE__,    \
                             MBEDTLS_DEBUG_STRIP_PARENS args )

#define MBEDTLS_SSL_DEBUG_RET( level, text, ret )                \
    mbedtls_debug_print_ret( ssl, level, __FILE__, __LINE__, text, ret )

#define MBEDTLS_SSL_DEBUG_BUF( level, text, buf, len )           \
    mbedtls_debug_print_buf( ssl, level, __FILE__, __LINE__, text, buf, len )

#if defined(MBEDTLS_BIGNUM_C)
#define MBEDTLS_SSL_DEBUG_MPI( level, text, X )                  \
    mbedtls_debug_print_mpi( ssl, level, __FILE__, __LINE__, text, X )
#endif

#if defined(MBEDTLS_ECP_C)
#define MBEDTLS_SSL_DEBUG_ECP( level, text, X )                  \
    mbedtls_debug_print_ecp( ssl, level, __FILE__, __LINE__, text, X )
#endif

#if defined(MBEDTLS_X509_CRT_PARSE_C)
#define MBEDTLS_SSL_DEBUG_CRT( level, text, crt )                \
    mbedtls_debug_print_crt( ssl, level, __FILE__, __LINE__, text, crt )
#endif

#else /* MBEDTLS_DEBUG_C */

#define MBEDTLS_SSL_DEBUG_MSG( level, args )            do { } while( 0 )
#define MBEDTLS_SSL_DEBUG_RET( level, text, ret )       do { } while( 0 )
#define MBEDTLS_SSL_DEBUG_BUF( level, text, buf, len )  do { } while( 0 )
#define MBEDTLS_SSL_DEBUG_MPI( level, text, X )         do { } while( 0 )
#define MBEDTLS_SSL_DEBUG_ECP( level, text, X )         do { } while( 0 )
#define MBEDTLS_SSL_DEBUG_CRT( level, text, crt )       do { } while( 0 )

#endif /* MBEDTLS_DEBUG_C */

#ifdef __cplusplus
extern "C" {
#endif

/**
 * \brief   Set the threshold error level to handle globally all debug output.
 *          Debug messages that have a level over the threshold value are
 *          discarded.
 *          (Default value: 0 = No debug )
 *
 * \param threshold     theshold level of messages to filter on. Messages at a
 *                      higher level will be discarded.
 *                          - Debug levels
 *                              - 0 No debug
 *                              - 1 Error
 *                              - 2 State change
 *                              - 3 Informational
 *                              - 4 Verbose
 */
void mbedtls_debug_set_threshold( int threshold );

/**
 * \brief    Print a message to the debug output. This function is always used
 *          through the MBEDTLS_SSL_DEBUG_MSG() macro, which supplies the ssl
 *          context, file and line number parameters.
 *
 * \param ssl       SSL context
 * \param level     error level of the debug message
 * \param file      file the message has occurred in
 * \param line      line number the message has occurred at
 * \param format    format specifier, in printf format
 * \param ...       variables used by the format specifier
 *
 * \attention       This function is intended for INTERNAL usage within the
 *                  library only.
 */
void mbedtls_debug_print_msg( const mbedtls_ssl_context *ssl, int level,
                              const char *file, int line,
                              const char *format, ... );

/**
 * \brief   Print the return value of a function to the debug output. This
 *          function is always used through the MBEDTLS_SSL_DEBUG_RET() macro,
 *          which supplies the ssl context, file and line number parameters.
 *
 * \param ssl       SSL context
 * \param level     error level of the debug message
 * \param file      file the error has occurred in
 * \param line      line number the error has occurred in
 * \param text      the name of the function that returned the error
 * \param ret       the return code value
 *
 * \attention       This function is intended for INTERNAL usage within the
 *                  library only.
 */
void mbedtls_debug_print_ret( const mbedtls_ssl_context *ssl, int level,
                      const char *file, int line,
                      const char *text, int ret );

/**
 * \brief   Output a buffer of size len bytes to the debug output. This function
 *          is always used through the MBEDTLS_SSL_DEBUG_BUF() macro,
 *          which supplies the ssl context, file and line number parameters.
 *
 * \param ssl       SSL context
 * \param level     error level of the debug message
 * \param file      file the error has occurred in
 * \param line      line number the error has occurred in
 * \param text      a name or label for the buffer being dumped. Normally the
 *                  variable or buffer name
 * \param buf       the buffer to be outputted
 * \param len       length of the buffer
 *
 * \attention       This function is intended for INTERNAL usage within the
 *                  library only.
 */
void mbedtls_debug_print_buf( const mbedtls_ssl_context *ssl, int level,
                      const char *file, int line, const char *text,
                      const unsigned char *buf, size_t len );

#if defined(MBEDTLS_BIGNUM_C)
/**
 * \brief   Print a MPI variable to the debug output. This function is always
 *          used through the MBEDTLS_SSL_DEBUG_MPI() macro, which supplies the
 *          ssl context, file and line number parameters.
 *
 * \param ssl       SSL context
 * \param level     error level of the debug message
 * \param file      file the error has occurred in
 * \param line      line number the error has occurred in
 * \param text      a name or label for the MPI being output. Normally the
 *                  variable name
 * \param X         the MPI variable
 *
 * \attention       This function is intended for INTERNAL usage within the
 *                  library only.
 */
void mbedtls_debug_print_mpi( const mbedtls_ssl_context *ssl, int level,
                      const char *file, int line,
                      const char *text, const mbedtls_mpi *X );
#endif

#if defined(MBEDTLS_ECP_C)
/**
 * \brief   Print an ECP point to the debug output. This function is always
 *          used through the MBEDTLS_SSL_DEBUG_ECP() macro, which supplies the
 *          ssl context, file and line number parameters.
 *
 * \param ssl       SSL context
 * \param level     error level of the debug message
 * \param file      file the error has occurred in
 * \param line      line number the error has occurred in
 * \param text      a name or label for the ECP point being output. Normally the
 *                  variable name
 * \param X         the ECP point
 *
 * \attention       This function is intended for INTERNAL usage within the
 *                  library only.
 */
void mbedtls_debug_print_ecp( const mbedtls_ssl_context *ssl, int level,
                      const char *file, int line,
                      const char *text, const mbedtls_ecp_point *X );
#endif

#if defined(MBEDTLS_X509_CRT_PARSE_C)
/**
 * \brief   Print a X.509 certificate structure to the debug output. This
 *          function is always used through the MBEDTLS_SSL_DEBUG_CRT() macro,
 *          which supplies the ssl context, file and line number parameters.
 *
 * \param ssl       SSL context
 * \param level     error level of the debug message
 * \param file      file the error has occurred in
 * \param line      line number the error has occurred in
 * \param text      a name or label for the certificate being output
 * \param crt       X.509 certificate structure
 *
 * \attention       This function is intended for INTERNAL usage within the
 *                  library only.
 */
void mbedtls_debug_print_crt( const mbedtls_ssl_context *ssl, int level,
                      const char *file, int line,
                      const char *text, const mbedtls_x509_crt *crt );
#endif

#ifdef __cplusplus
}
#endif

#endif /* debug.h */

