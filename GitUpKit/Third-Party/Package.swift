// swift-tools-version:5.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription
import Foundation

let libgit2OriginPath = "./libgit2"
let httpClientPath = "\(libgit2OriginPath)/deps/http-parser"
let ntlmClientPath = "\(libgit2OriginPath)/deps/ntlmclient"

let librariesPath = "."
let libssh2Path = "\(librariesPath)/libssh2.xcframework"
let libsslPath = "\(librariesPath)/libssl.xcframework"
let libcryptoPath = "\(librariesPath)/libcrypto.xcframework"

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
    products: [
        // Products define the executables and libraries a package produces, and make them visible to other packages.
        .library(name: "Libgit2Origin",
                 targets: ["Libgit2Origin"]
        ),
        .library(name: "http-client",
                 targets: ["http-client"]
        ),
        .library(name: "ntlmclient",
                 targets: ["ntlmclient"]
        ),
    ],
    dependencies: [
        // Dependencies declare other packages that this package depends on.
        // .package(url: /* package url */, from: "1.0.0"),
    ],
    targets: [
        // Targets are the basic building blocks of a package. A target can define a module or a test suite.
        // Targets can depend on other targets in this package, and on products in packages this package depends on.
        .target(name: "Libgit2Origin",
                dependencies: [
                    "libssh2", "libssl", "libcrypto", "http-client", "ntlmclient"
                ],
                path: libgit2OriginPath,
                exclude: [
                    // ./
                    "xcode",
                    "binaries",
                    "ci",
                    "cmake",
                    "deps",
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
                    // ./src/
                    "src/CMakeLists.txt",
                    "src/features.h.in",
                    // ./src/hash/sha1
                    "src/hash/sha1/common_crypto.h",
                    "src/hash/sha1/common_crypto.c",
                    "src/hash/sha1/generic.h",
                    "src/hash/sha1/generic.c",
                    "src/hash/sha1/mbedtls.h",
                    "src/hash/sha1/mbedtls.c",
                    "src/hash/sha1/openssl.h",
                    "src/hash/sha1/openssl.c",
                    "src/hash/sha1/win32.h",
                    "src/hash/sha1/win32.c",
                    // ./src/hash/
                    "src/hash/sha1.h",
                    
                    // ./src/win32
                    "src/win32",
                    
                    // ./include/git2/
                    "include/git2/stdint.h",
                    
                ],
                sources: ["src"],
                resources: nil,
                publicHeadersPath: "include",
                cSettings: [
                    .headerSearchPath("src"),
                    .headerSearchPath("deps/http-parser"),
                    .headerSearchPath("deps/ntlmclient"),
                    .define("HAVE_QSORT_R_BSD"),
                    .define("_FILE_OFFSET_BITS", to: "64"),
                    .define("SHA1DC_NO_STANDARD_INCLUDES", to: "1"),
                    .define("SHA1DC_CUSTOM_INCLUDE_SHA1_C", to: "\"common.h\""),
                    .define("SHA1DC_CUSTOM_INCLUDE_UBC_CHECK_C", to: "\"common.h\""),
                ] + FeaturesExtractor.extraLibgit2CSettings(),
                cxxSettings: nil,
                swiftSettings: nil,
                linkerSettings: [
                    .linkedFramework("CoreFoundation"),
                    .linkedFramework("Security"),
                    .linkedLibrary("z"),
                    .linkedLibrary("iconv"),
                ]
        ),
        
        .target(name: "http-client",
                dependencies: [],
                path: httpClientPath,
                exclude: [
                    "CMakeLists.txt",
                    "COPYING"
                ],
                sources: nil,
                resources: nil,
                publicHeadersPath: ".",
                cSettings: [],
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
                    "crypt_commoncrypto.c"
                ],
                resources: nil,
                publicHeadersPath: ".",
                cSettings: [
                    .define("NTLM_STATIC", to: "1"),
                    .define("CRYPT_COMMONCRYPTO")
                ],
                cxxSettings: nil,
                swiftSettings: nil,
                linkerSettings: []
        ),
        
        .binaryTarget(name: "libssh2", path: libssh2Path),
        .binaryTarget(name: "libssl", path: libsslPath),
        .binaryTarget(name: "libcrypto", path: libcryptoPath),
    ]
)
