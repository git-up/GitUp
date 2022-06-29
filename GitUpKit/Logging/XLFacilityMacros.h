//
//  XLFacilityMacros.h
//  GitUpKit
//
//  Created by Lucas Derraugh on 6/28/22.
//

// This file is a conversion of XLFacilityMacros in https://github.com/swisspol/XLFacility
// In an attempt to use "modern" logging with OSLog, we're reusing the macro names but using os_log under the hood

#import <OSLog/OSLog.h>
#import <Foundation/Foundation.h>

#define XLOG_DEBUG(...)                                                                                \
  do {                                                                                                 \
    os_log_debug(OS_LOG_DEFAULT, "%{public}s", [[NSString stringWithFormat: __VA_ARGS__] UTF8String]); \
  } while (0)
#define XLOG_VERBOSE(...)                                                                              \
  do {                                                                                                 \
    os_log_debug(OS_LOG_DEFAULT, "%{public}s", [[NSString stringWithFormat: __VA_ARGS__] UTF8String]); \
  } while (0)
#define XLOG_INFO(...)                                                                                 \
  do {                                                                                                 \
    os_log_info(OS_LOG_DEFAULT, "%{public}s", [[NSString stringWithFormat: __VA_ARGS__] UTF8String]);  \
  } while (0)
#define XLOG_WARNING(...)                                                                              \
  do {                                                                                                 \
    os_log_error(OS_LOG_DEFAULT, "%{public}s", [[NSString stringWithFormat: __VA_ARGS__] UTF8String]); \
  } while (0)
#define XLOG_ERROR(...)                                                                                \
  do {                                                                                                 \
    os_log_error(OS_LOG_DEFAULT, "%{public}s", [[NSString stringWithFormat: __VA_ARGS__] UTF8String]); \
  } while (0)
#define XLOG_EXCEPTION(__EXCEPTION__)                                              \
  do {                                                                             \
    os_log_fault(OS_LOG_DEFAULT, "%{public}s", [[__EXCEPTION__ name] UTF8String]); \
  } while (0)
#define XLOG_ABORT(...)                                                                                \
  do {                                                                                                 \
    os_log_fault(OS_LOG_DEFAULT, "%{public}s", [[NSString stringWithFormat: __VA_ARGS__] UTF8String]); \
  } while (0)

/**
 *  These other macros let you easily check conditions inside your code and
 *  log messages with XLFacility on failure.
 *
 *  You can use them instead of assert() or NSAssert().
 */

#define XLOG_CHECK(__CONDITION__)                                          \
  do {                                                                     \
    NSCAssert(__CONDITION__, @"Condition failed: \"%s\"", #__CONDITION__); \
  } while (0)

#define XLOG_UNREACHABLE()                                                                              \
  do {                                                                                                  \
    NSCAssert(NO, @"Unreachable code executed in '%s': %s:%i", __FUNCTION__, __FILE__, (int)__LINE__);  \
  } while (0)

#if DEBUG
#define XLOG_DEBUG_CHECK(__CONDITION__) XLOG_CHECK(__CONDITION__)
#define XLOG_DEBUG_UNREACHABLE() XLOG_UNREACHABLE()
#else
#define XLOG_DEBUG_CHECK(__CONDITION__)
#define XLOG_DEBUG_UNREACHABLE()
#endif
