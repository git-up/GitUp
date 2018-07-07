/**
 * \file havege.h
 *
 * \brief HAVEGE: HArdware Volatile Entropy Gathering and Expansion
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
#ifndef MBEDTLS_HAVEGE_H
#define MBEDTLS_HAVEGE_H

#include <stddef.h>

#define MBEDTLS_HAVEGE_COLLECT_SIZE 1024

#ifdef __cplusplus
extern "C" {
#endif

/**
 * \brief          HAVEGE state structure
 */
typedef struct
{
    int PT1, PT2, offset[2];
    int pool[MBEDTLS_HAVEGE_COLLECT_SIZE];
    int WALK[8192];
}
mbedtls_havege_state;

/**
 * \brief          HAVEGE initialization
 *
 * \param hs       HAVEGE state to be initialized
 */
void mbedtls_havege_init( mbedtls_havege_state *hs );

/**
 * \brief          Clear HAVEGE state
 *
 * \param hs       HAVEGE state to be cleared
 */
void mbedtls_havege_free( mbedtls_havege_state *hs );

/**
 * \brief          HAVEGE rand function
 *
 * \param p_rng    A HAVEGE state
 * \param output   Buffer to fill
 * \param len      Length of buffer
 *
 * \return         0
 */
int mbedtls_havege_random( void *p_rng, unsigned char *output, size_t len );

#ifdef __cplusplus
}
#endif

#endif /* havege.h */
