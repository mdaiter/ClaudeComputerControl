# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

MachOSwiftSection is a Swift library for parsing Mach-O binary files to extract Swift runtime metadata (Types/Protocols/Protocol Conformances). It uses a custom demangler to parse symbolic references and restore Swift Runtime logic from compiled binaries.

Built as an extension of [MachOKit](https://github.com/p-x9/MachOKit).

## Build Commands

```bash
# Build the project
swift build

# Build release version
swift build -c release

# Run tests
swift test

# Run tests in silent mode (suppresses verbose output)
MACHO_SWIFT_SECTION_SILENT_TEST=1 swift test

# Run a specific test
swift test --filter DemanglingTests

# Build universal binary (arm64 + x86_64) for distribution
./build-executable-product.sh
```

## Environment Variables

- `MACHO_SWIFT_SECTION_SILENT_TEST=1` - Silent test mode
- `MACHO_SWIFT_SECTION_USE_SPM_PREBUILD_VERSION=1` - Use MachOKit-SPM instead of MachOKit origin
- `MACHO_SWIFT_SECTION_USE_SWIFTTUI=1` - Enable SwiftTUI dependency

## Architecture

### Module Hierarchy (bottom to top)

```
CLI Layer
├── swift-section          CLI tool with dump/interface subcommands

Public Libraries
├── SwiftInterface         Generates .swiftinterface files
├── SwiftDump              Converts metadata to human-readable text
├── TypeIndexing           High-level type analysis with SourceKit
└── MachOSwiftSection      Main library - Swift metadata extraction

Core Processing
├── MachOFoundation        Unified interface for MachO operations
├── MachOSymbols           Symbol table processing and resolution
├── MachOSymbolPointers    Symbol pointer handling
├── MachOPointers          Relative pointer types
├── MachOResolving         Address/offset resolution
├── MachOReading           I/O abstraction (file/memory/cache)
├── MachOCaches            Dyld shared cache support
├── MachOExtensions        MachOKit augmentation
├── Demangling             Custom Swift symbol demangler (AST-based)
├── Semantic               Syntax-aware text formatting
└── Utilities              Common helpers, macros, async extensions
```

### Key Patterns

- **Extension Pattern**: MachOKit types are extended with a `.swift` property that provides Swift metadata access
- **Relative Pointers**: Custom pointer types (`RelativeDirectPointer`, `RelativeIndirectablePointer`) handle position-independent references in binaries
- **AST-Based Demangling**: The demangler produces a `Node` tree from mangled symbols, not just strings
- **Lazy Evaluation**: Data sequences read on-demand from binaries to handle large files

### Important Directories

- `Sources/MachOSwiftSection/Models/` - 200+ model files for Swift descriptor types
- `Sources/Demangling/Main/` - Core demangling algorithm implementation
- `Sources/SwiftInterface/NodePrintables/` - Type-specific printers for interface generation

### Data Flow

1. Binary → `MachOFile.load()` → Parse Mach-O structure
2. `machO.swift.typeContextDescriptors` → Read `__swift5_types` section
3. Relative pointers resolved → `TypeContextDescriptorWrapper`
4. Demangler converts mangled names → `Node` AST
5. `NodePrinter` or dumpers → Human-readable output

## CLI Tool Usage

```bash
# Dump Swift metadata
swift-section dump /path/to/binary

# Dump specific sections
swift-section dump --sections types,protocols /path/to/binary

# Generate Swift interface
swift-section interface /path/to/binary

# Work with dyld shared cache
swift-section dump --uses-system-dyld-shared-cache --cache-image-name SwiftUICore
```

## Testing

Test modules mirror the main modules:
- `DemanglingTests` - Symbol demangling correctness
- `MachOSwiftSectionTests` - Core metadata extraction
- `SwiftDumpTests` - Metadata dumping
- `SwiftInterfaceTests` - Interface generation
- `TypeIndexingTests` - Type index correctness

`MachOTestingSupport` provides test helpers and access to system binaries.
