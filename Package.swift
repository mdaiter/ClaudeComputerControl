// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

@preconcurrency import PackageDescription
import CompilerPluginSupport
import class Foundation.FileManager

func envEnable(_ key: String, default defaultValue: Bool = false) -> Bool {
    guard let value = Context.environment[key] else {
        return defaultValue
    }
    if value == "1" {
        return true
    } else if value == "0" {
        return false
    } else {
        return defaultValue
    }
}

let MachOKitVersion: Version = "0.42.0"

let isSilentTest = envEnable("MACHO_SWIFT_SECTION_SILENT_TEST", default: false)

let useSPMPrebuildVersion = envEnable("MACHO_SWIFT_SECTION_USE_SPM_PREBUILD_VERSION", default: false)

let useSwiftTUI = envEnable("MACHO_SWIFT_SECTION_USE_SWIFTTUI", default: false)

var testSettings: [SwiftSetting] = []

if isSilentTest {
    testSettings.append(.define("SILENT_TEST"))
}

var dependencies: [Package.Dependency] = [
    .MachOKit,
    .package(url: "https://github.com/swiftlang/swift-syntax.git", "509.1.0" ..< "602.0.0"),
    .package(url: "https://github.com/p-x9/AssociatedObject", from: "0.13.0"),
    .package(url: "https://github.com/p-x9/swift-fileio.git", from: "0.9.0"),
    .package(url: "https://github.com/apple/swift-argument-parser", from: "1.5.1"),
    .package(url: "https://github.com/onevcat/Rainbow", from: "4.0.0"),
    .package(url: "https://github.com/Mx-Iris/FrameworkToolbox", branch: "main"),
    .package(url: "https://github.com/apple/swift-collections", from: "1.2.0"),
    .package(url: "https://github.com/MxIris-Library-Forks/swift-memberwise-init-macro", from: "0.5.3-fork"),
    .package(url: "https://github.com/p-x9/MachOObjCSection", from: "0.5.0"),
    .package(url: "https://github.com/Mx-Iris/SourceKitD", branch: "main"),
    .package(url: "https://github.com/christophhagen/BinaryCodable", from: "3.1.0"),
    .package(url: "https://github.com/MxIris-DeveloperTool-Forks/swift-apinotes", branch: "main"),
    .package(url: "https://github.com/pointfreeco/swift-dependencies", from: "1.9.4"),
//        .package(url: "https://github.com/brightdigit/SyntaxKit", branch: "main"),
//        .package(url: "https://github.com/MxIris-DeveloperTool-Forks/swift-clang", from: "0.1.0"),
    .package(url: "https://github.com/apple/swift-async-algorithms", from: "1.0.4"),
    .package(url: "https://github.com/MxIris-Reverse-Engineering/DyldPrivate", branch: "main"),
    .package(url: "https://github.com/migueldeicaza/TermKit", branch: "main"),
]

extension Package.Dependency {
    static let MachOKit: Package.Dependency = {
        if useSPMPrebuildVersion {
            return .MachOKitSPM
        } else {
            return .MachOKitOrigin
        }
    }()

    static let MachOKitOrigin = Package.Dependency.package(
        url: "https://github.com/p-x9/MachOKit.git",
        exact: MachOKitVersion
    )

    static let MachOKitMain = Package.Dependency.package(
        url: "https://github.com/MxIris-Reverse-Engineering/MachOKit",
        branch: "main"
    )

    static let MachOKitSPM = Package.Dependency.package(
        url: "https://github.com/p-x9/MachOKit-SPM",
        from: MachOKitVersion
    )
}

extension Target.Dependency {
    static let MachOKit: Target.Dependency = {
        if useSPMPrebuildVersion {
            return .MachOKitSPM
        } else {
            return .MachOKitMain
        }
    }()

    static let MachOKitMain = Target.Dependency.product(
        name: "MachOKit",
        package: "MachOKit"
    )
    static let MachOKitSPM = Target.Dependency.product(
        name: "MachOKit",
        package: "MachOKit-SPM"
    )
    static let SwiftSyntax = Target.Dependency.product(
        name: "SwiftSyntax",
        package: "swift-syntax"
    )
    static let SwiftParser = Target.Dependency.product(
        name: "SwiftParser",
        package: "swift-syntax"
    )
    static let SwiftSyntaxMacros = Target.Dependency.product(
        name: "SwiftSyntaxMacros",
        package: "swift-syntax"
    )
    static let SwiftCompilerPlugin = Target.Dependency.product(
        name: "SwiftCompilerPlugin",
        package: "swift-syntax"
    )
    static let SwiftSyntaxMacrosTestSupport = Target.Dependency.product(
        name: "SwiftSyntaxMacrosTestSupport",
        package: "swift-syntax"
    )
    static let SwiftSyntaxBuilder = Target.Dependency.product(
        name: "SwiftSyntaxBuilder",
        package: "swift-syntax"
    )
    static let SwiftTUI = Target.Dependency.product(
        name: "SwiftTUI",
        package: "SwiftTUI"
    )
    static let TermKit = Target.Dependency.product(
        name: "TermKit",
        package: "TermKit"
    )
}

extension Product {
    static func library(_ target: Target) -> Product {
        .library(name: target.name, targets: [target.name])
    }

    static func executable(_ target: Target) -> Product {
        .executable(name: target.name, targets: [target.name])
    }
}

extension Target.Dependency {
    static func target(_ target: Target) -> Self {
        .targetItem(name: target.name, condition: nil)
    }
}

@MainActor
extension Target {
    static let Semantic = Target.target(
        name: "Semantic"
    )

    static let Demangling = Target.target(
        name: "Demangling",
        dependencies: [
            .target(.Utilities),
        ]
    )

    static let UtilitiesC = Target.target(
        name: "UtilitiesC",
    )
    
    static let Utilities = Target.target(
        name: "Utilities",
        dependencies: [
            .target(.MachOMacros),
            .target(.UtilitiesC),
            .product(name: "FoundationToolbox", package: "FrameworkToolbox"),
            .product(name: "AssociatedObject", package: "AssociatedObject"),
            .product(name: "MemberwiseInit", package: "swift-memberwise-init-macro"),
            .product(name: "OrderedCollections", package: "swift-collections"),
            .product(name: "Dependencies", package: "swift-dependencies"),
            .product(name: "AsyncAlgorithms", package: "swift-async-algorithms"),
        ]
    )

    static let MachOExtensions = Target.target(
        name: "MachOExtensions",
        dependencies: [
            .MachOKit,
            .target(.Utilities),
        ]
    )

    static let MachOCaches = Target.target(
        name: "MachOCaches",
        dependencies: [
            .MachOKit,
            .target(.MachOExtensions),
            .target(.Utilities),
        ]
    )

    static let MachOReading = Target.target(
        name: "MachOReading",
        dependencies: [
            .MachOKit,
            .target(.MachOExtensions),
            .target(.Utilities),
            .product(name: "FileIO", package: "swift-fileio"),
        ]
    )

    static let MachOResolving = Target.target(
        name: "MachOResolving",
        dependencies: [
            .MachOKit,
            .target(.MachOExtensions),
            .target(.MachOReading),
        ]
    )

    static let MachOSymbols = Target.target(
        name: "MachOSymbols",
        dependencies: [
            .MachOKit,
            .target(.MachOReading),
            .target(.MachOResolving),
            .target(.Utilities),
            .target(.Demangling),
            .target(.MachOCaches),
        ],
        swiftSettings: [
            .unsafeFlags(["-Xfrontend", "-enable-private-imports"]),
        ]
    )

    static let MachOPointers = Target.target(
        name: "MachOPointers",
        dependencies: [
            .MachOKit,
            .target(.MachOReading),
            .target(.MachOResolving),
            .target(.Utilities),
        ]
    )

    static let MachOSymbolPointers = Target.target(
        name: "MachOSymbolPointers",
        dependencies: [
            .MachOKit,
            .target(.MachOReading),
            .target(.MachOResolving),
            .target(.MachOPointers),
            .target(.MachOSymbols),
            .target(.Utilities),
        ]
    )

    static let MachOFoundation = Target.target(
        name: "MachOFoundation",
        dependencies: [
            .MachOKit,
            .target(.MachOReading),
            .target(.MachOExtensions),
            .target(.MachOPointers),
            .target(.MachOSymbols),
            .target(.MachOResolving),
            .target(.MachOSymbolPointers),
            .target(.Utilities),
        ]
    )

    static let MachOSwiftSection = Target.target(
        name: "MachOSwiftSection",
        dependencies: [
            .MachOKit,
            .target(.MachOFoundation),
            .target(.Demangling),
            .target(.Utilities),
            .product(name: "DyldPrivate", package: "DyldPrivate"),
        ],
//        swiftSettings: [
//            .unsafeFlags(["-parse-stdlib"]),
//        ],
    )

    static let SwiftDump = Target.target(
        name: "SwiftDump",
        dependencies: [
            .MachOKit,
            .target(.MachOSwiftSection),
            .target(.Semantic),
            .target(.Utilities),
            .product(name: "MachOObjCSection", package: "MachOObjCSection"),
        ]
    )

    static let SwiftIndex = Target.target(
        name: "SwiftIndex",
        dependencies: [
            .MachOKit,
            .target(.MachOSwiftSection),
            .target(.SwiftDump),
            .target(.Semantic),
            .target(.Utilities),
        ]
    )

    static let SwiftInterface = Target.target(
        name: "SwiftInterface",
        dependencies: [
            .MachOKit,
            .target(.MachOSwiftSection),
            .target(.SwiftDump),
            .target(.Semantic),
            .target(.Utilities),
        ]
    )

    static let TypeIndexing = Target.target(
        name: "TypeIndexing",
        dependencies: [
            .target(.SwiftInterface),
            .target(.Utilities),
            .SwiftSyntax,
            .SwiftParser,
            .SwiftSyntaxBuilder,
            .product(name: "SourceKitD", package: "SourceKitD", condition: .when(platforms: [.macOS])),
            .product(name: "BinaryCodable", package: "BinaryCodable"),
            .product(name: "APINotes", package: "swift-apinotes", condition: .when(platforms: [.macOS])),
            .product(name: "MachOObjCSection", package: "MachOObjCSection"),
        ]
    )

    static let LLMExplorer = Target.target(
        name: "LLMExplorer",
        dependencies: [
            .MachOKit,
            .target(.MachOSwiftSection),
            .target(.SwiftInterface),
            .target(.TypeIndexing),
            .target(.SwiftDump),
            .target(.Demangling),
            .target(.Utilities),
            .SwiftTUI,
        ]
    )

    static let swift_section = Target.executableTarget(
        name: "swift-section",
        dependencies: [
            .target(.SwiftDump),
            .target(.SwiftInterface),
            .target(.LLMExplorer),
            .product(name: "Rainbow", package: "Rainbow"),
            .product(name: "ArgumentParser", package: "swift-argument-parser"),
        ]
    )
    
    static let SwiftSectionMCPCore = Target.target(
        name: "SwiftSectionMCPCore",
        dependencies: [
            .product(name: "MachOKit", package: "MachOKit"),
            .target(.MachOFoundation),
            .target(.MachOSwiftSection),
            .target(.SwiftInterface),
            .target(.Semantic),
            .target(.MachOSymbols),
            .product(name: "Rainbow", package: "Rainbow"),
        ]
    )

    static let swift_section_mcp = Target.executableTarget(
        name: "swift-section-mcp",
        dependencies: [
            .target(.SwiftSectionMCPCore),
        ]
    )

    static let AppAutomationCore = Target.target(
        name: "AppAutomationCore",
        dependencies: []
    )

    static let AppAutomationAX = Target.target(
        name: "AppAutomationAX",
        dependencies: [
            .target(.AppAutomationCore),
        ]
    )

    static let AppAutomationXPC = Target.target(
        name: "AppAutomationXPC",
        dependencies: [
            .target(.AppAutomationCore),
        ]
    )

    static let AppAutomationDaemon = Target.executableTarget(
        name: "AppAutomationDaemon",
        dependencies: [
            .target(.AppAutomationCore),
            .target(.AppAutomationAX),
            .target(.AppAutomationXPC),
        ]
    )

    static let AppAutomationSafariHelper = Target.executableTarget(
        name: "AppAutomationSafariHelper",
        dependencies: [
            .target(.AppAutomationCore),
            .target(.AppAutomationAX),
            .target(.AppAutomationXPC),
        ]
    )

    static let AppAutomationMessagesHelper = Target.executableTarget(
        name: "AppAutomationMessagesHelper",
        dependencies: [
            .target(.AppAutomationCore),
            .target(.AppAutomationAX),
            .target(.AppAutomationXPC),
        ]
    )
    
    static let AppAutomationCLI = Target.executableTarget(
        name: "app-automation",
        dependencies: [
            .target(.AppAutomationCore),
            .target(.AppAutomationAX),
        ],
        path: "Sources/AppAutomationCLI"
    )
    
    static let AppAutomationAgent = Target.executableTarget(
        name: "app-agent",
        dependencies: [
            .target(.AppAutomationCore),
            .target(.AppAutomationAX),
        ],
        path: "Sources/AppAutomationAgent",
        swiftSettings: [
            .unsafeFlags(["-parse-as-library"])
        ]
    )

    // MARK: - Macros

    static let MachOMacros = Target.macro(
        name: "MachOMacros",
        dependencies: [
            .SwiftSyntax,
            .SwiftSyntaxMacros,
            .SwiftCompilerPlugin,
            .SwiftSyntaxBuilder,
        ]
    )

    // MARK: - Testing

    static let MachOTestingSupport = Target.target(
        name: "MachOTestingSupport",
        dependencies: [
            .MachOKit,
            .target(.MachOExtensions),
            .target(.SwiftDump),
        ],
        swiftSettings: testSettings
    )

    static let DemanglingTests = Target.testTarget(
        name: "DemanglingTests",
        dependencies: [
            .target(.Demangling),
        ],
        swiftSettings: testSettings
    )

    static let MachOSymbolsTests = Target.testTarget(
        name: "MachOSymbolsTests",
        dependencies: [
            .target(.MachOSymbols),
            .target(.MachOTestingSupport),
        ],
        swiftSettings: testSettings
    )

    static let MachOSwiftSectionTests = Target.testTarget(
        name: "MachOSwiftSectionTests",
        dependencies: [
            .target(.MachOSwiftSection),
            .target(.MachOTestingSupport),
            .target(.SwiftDump),
        ],
        swiftSettings: testSettings
    )

    static let SwiftDumpTests = Target.testTarget(
        name: "SwiftDumpTests",
        dependencies: [
            .target(.SwiftDump),
            .target(.MachOTestingSupport),
            .product(name: "MachOObjCSection", package: "MachOObjCSection"),
        ],
        swiftSettings: testSettings
    )

    static let TypeIndexingTests = Target.testTarget(
        name: "TypeIndexingTests",
        dependencies: [
            .target(.TypeIndexing),
            .target(.MachOTestingSupport),
        ],
        swiftSettings: testSettings
    )

    static let SwiftInterfaceTests = Target.testTarget(
        name: "SwiftInterfaceTests",
        dependencies: [
            .target(.SwiftInterface),
            .target(.MachOTestingSupport),
        ],
        swiftSettings: testSettings
    )
    
    static let SwiftSectionMCPTests = Target.testTarget(
        name: "SwiftSectionMCPTests",
        dependencies: [
            .target(.SwiftSectionMCPCore),
            .target(.MachOTestingSupport),
            .target(.SwiftInterface),
            .target(.MachOSwiftSection),
        ],
        swiftSettings: testSettings
    )
    
    static let AppAutomationTests = Target.testTarget(
        name: "AppAutomationTests",
        dependencies: [
            .target(.AppAutomationCore),
            .target(.AppAutomationAX),
        ],
        swiftSettings: testSettings
    )
}

let package = Package(
    name: "MachOSwiftSection",
    platforms: [.macOS(.v13), .iOS(.v13), .tvOS(.v13), .watchOS(.v6), .visionOS(.v1)],
    products: [
        .library(.MachOSwiftSection),
        .library(.SwiftDump),
        .library(.SwiftInterface),
        .library(.TypeIndexing),
        .library(.LLMExplorer),
        .executable(.swift_section),
        .executable(.swift_section_mcp),
        .executable(.AppAutomationDaemon),
        .executable(.AppAutomationSafariHelper),
        .executable(.AppAutomationMessagesHelper),
        .executable(.AppAutomationCLI),
        .executable(.AppAutomationAgent),
    ],
    dependencies: dependencies,
    targets: [
        .Semantic,
        .Demangling,
        .Utilities,
        .UtilitiesC,
        .MachOExtensions,
        .MachOCaches,
        .MachOReading,
        .MachOResolving,
        .MachOSymbols,
        .MachOPointers,
        .MachOSymbolPointers,
        .MachOFoundation,
        .MachOSwiftSection,
        .SwiftDump,
        .SwiftIndex,
        .SwiftInterface,
        .TypeIndexing,
        .LLMExplorer,
        .swift_section,
        .SwiftSectionMCPCore,
        .swift_section_mcp,
        .AppAutomationCore,
        .AppAutomationAX,
        .AppAutomationXPC,
        .AppAutomationDaemon,
        .AppAutomationSafariHelper,
        .AppAutomationMessagesHelper,
        .AppAutomationCLI,
        .AppAutomationAgent,
        .MachOMacros,
        .MachOTestingSupport,
        .DemanglingTests,
        .MachOSymbolsTests,
        .MachOSwiftSectionTests,
        .SwiftDumpTests,
        .TypeIndexingTests,
        .SwiftInterfaceTests,
        .SwiftSectionMCPTests,
        .AppAutomationTests,
    ]
)

if useSwiftTUI {
    let swiftTUILocalPath = "Vendor/SwiftTUI"
    if FileManager.default.fileExists(atPath: swiftTUILocalPath) {
        package.dependencies.append(.package(path: swiftTUILocalPath))
    } else {
        package.dependencies.append(.package(url: "https://github.com/rensbreur/SwiftTUI", branch: "main"))
    }
    Target.swift_section.dependencies.append(.product(name: "SwiftTUI", package: "SwiftTUI"))
}
