import Foundation
import Testing
import XCTest
import MachOKit
import Demangling
@testable import MachOSwiftSection
@testable import MachOTestingSupport

final class ExternalSymbolTests: @unchecked Sendable {
    @Test func machOSections() async throws {
        let swiftUIPath = MachOFileName.iOS_18_5_Simulator_SwiftUI.rawValue
        guard FileManager.default.fileExists(atPath: swiftUIPath) else {
            return
        }
        let file = try loadFromFile(named: .iOS_18_5_Simulator_SwiftUI)
        let machO: MachOFile
        switch file {
        case .fat(let fatFile):
            machO = try required(fatFile.machOFiles().first)
        case .machO(let machOFile):
            machO = machOFile
        @unknown default:
            fatalError()
        }
        for symbol in machO.symbols where symbol.nlist.isExternal && symbol.name.isSwiftSymbol {
            let demangledNode = try symbol.demangledNode
            demangledNode.print(using: DemangleOptions.default).print()
            demangledNode.description.print()
            "-----------------------------".print()
        }
    }
}
