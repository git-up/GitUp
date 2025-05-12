// swift-tools-version:5.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription
import Foundation

let libgit2OriginPath = "./libgit2"
let llhttpPath = "\(libgit2OriginPath)/deps/llhttp"
let ntlmClientPath = "\(libgit2OriginPath)/deps/ntlmclient"

let librariesPath = "."
let libssh2Path = "\(librariesPath)/libssh2.xcframework"
let libsslPath = "\(librariesPath)/libssl.xcframework"
let libcryptoPath = "\(librariesPath)/libcrypto.xcframework"

let silenceWarningsCSettings: [CSetting] = [ // to see libgit2 warnings, set to empty array
    CSetting.unsafeFlags(["-w"])
]

enum FeaturesExtractor {
    private struct Define: CustomStringConvertible {
        let define: String
        let value: String
        var description: String {
            "\(define) \(value)"
        }
    }
    private static var packageSwiftDirectory: URL? {
        var directory = URL.init(fileURLWithPath: "\(#file)")
        if directory.lastPathComponent == "Package.swift" {
            directory.deleteLastPathComponent()
        }
        return directory
    }
    
    private static var libgit2Directory: URL? {
        packageSwiftDirectory?.appendingPathComponent("libgit2")
    }
    
    private static var featuresPath: URL {
        libgit2Directory?.appendingPathComponent("include/git2/sys/features.h") ?? .init(fileURLWithPath: "")
    }
    
    private static func shouldAddExtraDefine(featuresPath: URL, define: Define) -> Bool {
        
        guard let string = try? String.init(contentsOf: featuresPath, encoding: .utf8) else {
            return false
        }
        
        return !string.contains("#define \(define)")
    }
    
    private static func fixedExtraDefine(featuresPath: URL, define: Define) -> [CSetting] {
        shouldAddExtraDefine(featuresPath: featuresPath, define: define) ? [ .define(define.define, to: define.value) ] : []
    }
    
    private static func fixedExtraDefine(define: Define) -> [CSetting] { fixedExtraDefine(featuresPath: featuresPath, define: define) }

    private static func fixedExtraSSHDefines() -> [CSetting] {
        let defines: [Define] = [
            .init(define: "GIT_SSH", value: "1"),
            .init(define: "GIT_SSH_MEMORY_CREDENTIALS", value: "1")
        ]
        return defines.flatMap(fixedExtraDefine(define:))
    }
    
    static func extraLibgit2CSettings() -> [CSetting] {
        let fixedLibgit2CSettings = fixedExtraSSHDefines()
        return fixedLibgit2CSettings
    }
}

let package = Package(
    name: "SwiftPackage",
    platforms: [.macOS(.v10_13)],
    products: [
        .library(name: "Libgit2Origin",
                 targets: ["Libgit2Origin"]
        ),
        .library(name: "llhttp",
                 targets: ["llhttp"]
        ),
        .library(name: "ntlmclient",
                 targets: ["ntlmclient"]
        ),
    ],
    dependencies: [
    ],
    targets: [
        // Since we don't run libgit2's actual CMake build, we need to replicate its effects here: the files it includes, and the options it resolves
        .target(name: "Libgit2Origin",
                dependencies: [
                    "libssl", "libcrypto", "llhttp", "ntlmclient"
                ],
                path: libgit2OriginPath,
                exclude: [
                    // ./
                    "ci",
                    "cmake",
                    "docs",
                    "examples",
                    "fuzzers",
                    "script",
                    "tests",
                    "api.docurium",
                    "AUTHORS",
                    "CMakeLists.txt",
                    "COPYING",
                    "git.git-authors",
                    "package.json",
                    "README.md",
                    "SECURITY.md",
                    "update-xcode.sh",
                    
                    // ./deps/
                    "deps/chromium-zlib",
                    "deps/llhttp",
                    "deps/ntlmclient",
                    "deps/pcre",
                    "deps/winhttp",
                    // xdiff is the only dependency we're building as part of the Libgit2Origin target, because it seems to need access to some libgit2 files
                    "deps/zlib",
                    
                    // ./deps/
                    "deps/xdiff/CMakeLists.txt",
                    
                    // ./src/
                    "src/cli",
                    "src/CMakeLists.txt",
                    "src/README.md",
                    
                    // ./src/libgit2/
                    "src/libgit2/CMakeLists.txt",
                    "src/libgit2/config.cmake.in",
                    "src/libgit2/experimental.h.in",
                    "src/libgit2/git2.rc",
                    
                    // ./src/util/
                    "src/util/CMakeLists.txt",
                    "src/util/git2_features.h.in",
                    "src/util/win32",
                    
                    // ./src/util/hash/
                    "src/util/hash/builtin.h",
                    "src/util/hash/builtin.c",
                    "src/util/hash/mbedtls.h",
                    "src/util/hash/mbedtls.c",
                    "src/util/hash/openssl.h",
                    "src/util/hash/openssl.c",
                    "src/util/hash/sha1dc/sha1.h",
                    "src/util/hash/win32.h",
                    "src/util/hash/win32.c",
                    
                    // ./include/git2/
                    "include/git2/stdint.h",
                    
                ],
                sources: ["deps/xdiff", "src"],
                resources: nil,
                publicHeadersPath: "include",
                cSettings: [
                    .headerSearchPath("src"),
                    .headerSearchPath("src/libgit2"),
                    .headerSearchPath("src/util"),
                    .headerSearchPath("deps/llhttp"),
                    .headerSearchPath("deps/ntlmclient"),
                    .headerSearchPath("deps/xdiff"),
                    
                    .define("HAVE_QSORT_R_BSD"),
                    .define("_FILE_OFFSET_BITS", to: "64"),
                    .define("GIT_IO_POLL", to: "1"),
                    .define("GIT_IO_SELECT", to: "1"),
                    .define("GIT_HTTPPARSER_BUILTIN", to: "1"),
                    
                    // Above we exclude git2_features.h.in, which is a template suppose to set feature flags.
                    // So we need to 1. tell libgit2 the file isn't included and 2. manually set the flags here.
                    .define("LIBGIT2_NO_FEATURES_H", to: "1"),
                    
                    .define("GIT_TRACE", to: "1"),
                    .define("GIT_THREADS", to: "1"),
                    .define("GIT_ARCH_64", to: "1"),
                    .define("GIT_USE_ICONV", to: "1"),
                    .define("GIT_USE_NSEC", to: "1"),
                    .define("GIT_USE_STAT_MTIMESPEC", to: "1"),
                    .define("GIT_USE_FUTIMENS", to: "1"),
                    .define("GIT_REGEX_REGCOMP_L"),
                    .define("GIT_NTLM", to: "1"),
                    .define("GIT_HTTPS", to: "1"),
                    .define("GIT_SECURE_TRANSPORT", to: "1"),
                    .define("GIT_SHA1_COLLISIONDETECT", to: "1"),
                    .define("GIT_SSH_MEMORY_CREDENTIALS", to: "1"),
                    .define("GIT_SSH", to: "1"),
                    
                    // See libgit2/cmake/SelectRegex.cmake
                    .define("GIT_REGEX_REGCOMP_L", to: "1"),
                    
                    // Options set when USE_SSH="exec" (default value is ON. exec uses OpenSSH, which supports SSH config files)
                    // See libgit2/cmake/SelectSSH.cmake
                    .define("USE_SSH", to: "exec"),
                    .define("GIT_SSH", to: "1"),
                    .define("GIT_SSH_EXEC", to: "1"),
                    
                    // Options set when USE_HTTPS="ON" (default value)
                    // See libgit2/cmake/SelectHTTPSBackend.cmake
                    .define("USE_HTTPS", to: "SecureTransport"),
                    
                    // Options set when USE_SHA1="CollisionDetection" (default value)
                    // See libgit2/cmake/SelectHashes.cmake, libgit2/src/util/CMakeLists.txt
                    .define("USE_SHA1", to: "CollisionDetection"),
                    .define("GIT_SHA1_COLLISIONDETECT", to: "1"),
                    .define("SHA1DC_NO_STANDARD_INCLUDES", to: "1"),
                    .define("SHA1DC_CUSTOM_INCLUDE_SHA1_C", to: "\"git2_util.h\""),
                    .define("SHA1DC_CUSTOM_INCLUDE_UBC_CHECK_C", to: "\"git2_util.h\""),
                    
                    // Options set when USE_SHA256="ON" (default value)
                    // See libgit2/cmake/SelectHashes.cmake
                    .define("USE_SHA256", to: "CommonCrypto"),
                    .define("GIT_SHA256_COMMON_CRYPTO", to: "1"),
                    
                    // Options set when USE_THREADS="ON" (default value)
                    // See libgit2/src/CMakeLists.txt
                    .define("GIT_THREADS", to: "1"),
                    
                ]
                + FeaturesExtractor.extraLibgit2CSettings()
                + silenceWarningsCSettings,
                cxxSettings: nil,
                swiftSettings: nil,
                linkerSettings: [
                    .linkedFramework("CoreFoundation"),
                    .linkedFramework("Security"),
                    .linkedLibrary("z"),
                    .linkedLibrary("iconv"),
                ]
        ),
        
        .target(name: "llhttp",
                dependencies: [],
                path: llhttpPath,
                exclude: [
                    "CMakeLists.txt"
                ],
                sources: nil,
                resources: nil,
                publicHeadersPath: ".",
                cSettings: silenceWarningsCSettings,
                cxxSettings: nil,
                swiftSettings: nil,
                linkerSettings: []
        ),
        
        .target(name: "ntlmclient",
                dependencies: ["libssh2"],
                path: ntlmClientPath,
                exclude: [
                    "crypt_openssl.h",
                    "crypt_openssl.c",
                    "crypt_mbedtls.h",
                    "crypt_mbedtls.c",
                    "unicode_builtin.c",
                    "CMakeLists.txt",
                ],
                sources: [
                    "ntlm.c",
                    "unicode_iconv.c",
                    "util.c",
                    "crypt_commoncrypto.c"// maybe include
                ],
                resources: nil,
                publicHeadersPath: ".",
                cSettings: [
                    .define("NTLM_STATIC", to: "1"),
                    .define("CRYPT_COMMONCRYPTO"),
                    .define("UNICODE_ICONV", to: "1")
                ]
                + silenceWarningsCSettings,
                cxxSettings: nil,
                swiftSettings: nil,
                linkerSettings: []
        ),
        
        .binaryTarget(name: "libssh2", path: libssh2Path),
        .binaryTarget(name: "libssl", path: libsslPath),
        .binaryTarget(name: "libcrypto", path: libcryptoPath),
    ]
)
