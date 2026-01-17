# MachOSwiftSection

A Swift library for parsing mach-o files to obtain Swift information.
（Types/Protocol/ProtocolConformance info）

It may be the most powerful swift dump you can find so far, as it uses a custom Demangler to parse symbolic references and restore the original logic of the Swift Runtime as much as possible.

> [!NOTE]
> This library is developed as an extension of [MachOKit](https://github.com/p-x9/MachOKit) for Swift

## MachOSwiftSection Library

### Roadmap

- [x] Protocol Descriptors
- [x] Protocol Conformance Descriptors
- [x] Type Context Descriptors
- [x] Associated Type Descriptors
- [x] Method Symbol For Dyld Caches
- [x] Builtin Type Descriptors
- [x] Swift Interface Support
- [ ] Type Member Layout (WIP, MachOImage only)
- [ ] Swift Section MCP

### Usage

#### Basic

Swift information from MachOImage or MachOFile can be retrieved via the `swift` property.

```swift
import MachOKit
import MachOSwiftSection

let machO //` MachOFile` or `MachOImage`

// Protocol Descriptors
let protocolDescriptors = try machO.swift.protocolDescriptors
for protocolDescriptor in protocolDescriptors {
    let protocolType = try Protocol(descriptor: protocolDescriptor, in: machO)
    // do somethings ...
}

// Protocol Conformance Descriptors
let protocolConformanceDescriptors = try machO.swift.protocolConformanceDescriptors
for protocolConformanceDescriptor in protocolConformanceDescriptors {
    let protocolConformance = try ProtocolConformance(descriptor: protocolConformanceDescriptor, in: machO)
    // do somethings ...
}

// Type/Nominal Descriptors
let typeContextDescriptors = try machO.swift.typesContextDescriptors
for typeContextDescriptor in typeContextDescriptors {
    switch typeContextDescriptor {
    case .type(let typeContextDescriptorWrapper):
        switch typeContextDescriptorWrapper {
        case .enum(let enumDescriptor):
            let enumType = try Enum(descriptor: enumDescriptor, in: machO)
            // do somethings ...
        case .struct(let structDescriptor):
            let structType = try Struct(descriptor: structDescriptor, in: machO)
            // do somethings ...
        case .class(let classDescriptor):
            let classType = try Class(descriptor: classDescriptor, in: machO)
            // do somethings ...
        }
    default:
        break
    }
}
```

#### Generate Complete Swift Interface

For generating complete Swift interface files, you can use the `SwiftInterface` library which provides a more comprehensive interface generation capability.

```swift
import MachOKit
import SwiftInterface

let builder = try SwiftInterfaceBuilder(configuration: .init(), eventHandlers: [], in: machO)
try await builder.prepare()
let result = try await builder.printRoot()
```

## swift-section CLI Tool

### Installation

You can get the swift-section CLI tool in three ways:

- **GitHub Releases**: Download from [GitHub releases](https://github.com/MxIris-Reverse-Engineering/MachOSwiftSection/releases)
- **Homebrew**: Install via `brew install swift-section`
- **Build from Source**: Build with `./build-executable-product.sh` (requires Xcode 26.0 / Swift 6.2+ toolchain)

### Usage

The swift-section CLI tool provides two main subcommands: `dump`, and `interface`.

#### dump - Dump Swift Information

Dump Swift information from a Mach-O file or dyld shared cache.

```bash
swift-section dump [options] [file-path]
```

**Basic usage:**
```bash
# Dump all Swift information from a Mach-O file
swift-section dump /path/to/binary

# Dump only types and protocols
swift-section dump --sections types,protocols /path/to/binary

# Save output to file
swift-section dump --output-path output.txt /path/to/binary

# Use specific architecture
swift-section dump --architecture arm64 /path/to/binary
```

**Working with dyld shared cache:**
```bash
# Dump from system dyld shared cache
swift-section dump --uses-system-dyld-shared-cache --cache-image-name SwiftUICore

# Dump from specific dyld shared cache
swift-section dump --dyld-shared-cache --cache-image-path /path/to/cache /path/to/dyld_shared_cache
```

#### interface - Generate Swift Interface

Generate a complete Swift interface file from a Mach-O file, similar to Swift's generated interfaces.

```bash
swift-section interface [options] [file-path]
```

**Basic usage:**
```bash
# Generate Swift interface from a Mach-O file
swift-section interface /path/to/binary

# Save interface to file
swift-section interface --output-path interface.swiftinterface /path/to/binary

# Use specific architecture
swift-section interface --architecture arm64 /path/to/binary

**Working with dyld shared cache:**
# Dump from system dyld shared cache
swift-section interface --uses-system-dyld-shared-cache --cache-image-name SwiftUICore

# Dump from specific dyld shared cache
swift-section interface --dyld-shared-cache --cache-image-path /path/to/cache /path/to/dyld_shared_cache
```

## Swift Section MCP Server

The repository now includes an experimental [Model Context Protocol](https://modelcontextprotocol.io) server target (`swift-section-mcp`) that exposes the same capabilities as the `interface` subcommand to Claude or any MCP-compatible client.

### Running the server

```bash
# From the repository root
CLANG_MODULE_CACHE_PATH=.build/clang-module-cache \
SWIFTC_MODULECACHE_PATH=.build/module-cache \
swift run swift-section-mcp
```

The server uses JSON-RPC over stdio. Add it to your Claude MCP configuration with `command: ["<path>/swift-section-mcp"]`.

### Available tools

`swiftInterface`
: Generates a Swift interface for a binary or dyld shared cache image. Arguments mirror the CLI flags:

- `binaryPath` – Mach-O path when not using the system cache.
- `dyldSharedCache`, `usesSystemDyldSharedCache`, `cacheImageName`, `cacheImagePath` – select dyld cache images.
- `architecture` – `arm64`, `arm64e`, or `x86_64` for fat binaries.
- `showCImportedTypes`, `parseOpaqueReturnType`, `emitOffsetComments` – match CLI flags.
- `outputPath` – optional file destination; the generated text is still returned to the MCP client.
- `colorScheme` – `none`, `light`, or `dark` ANSI coloring.

`listTypes`
: Quickly enumerate Swift nominal types inside the binary without building the full interface.

- `query` – optional substring filter (case-insensitive by default).
- `kindFilter` – restrict the results to `enum`, `struct`, or `class`.
- `limit` – cap the number of returned rows (defaults to 100).
- All Mach-O selection fields (`binaryPath`, dyld cache flags, `architecture`) match `swiftInterface`.
- Response body is JSON containing `name`, `shortName`, `module`, `kind`, and optional mangled names.

`searchSymbols`
: Search Swift symbols (functions, methods, metadata, etc.) inside the binary and return structured matches.

- `query` – substring applied to demangled and mangled names.
- `kindFilter` – optional category list (`function`, `method`, `accessor`, `variable`, `typeMetadata`, `type`, `other`).
- `limit` – defaults to 50 results.
- Shares the same Mach-O selection fields as the other tools.
- Response body is JSON containing the demangled name, optional mangled name, symbol kind, and Mach-O offset.

Each tool returns a short status message followed by a JSON payload in the final `text` block so Claude can capture either summary or structured results.

### Integration tests

An integration test suite (`SwiftSectionMCPTests`) spawns the MCP server, sends real `tools/call` requests, and compares the `swiftInterface` response with the CLI output. Running these tests requires providing three environment variables:

| Variable | Purpose |
| --- | --- |
| `SWIFT_SECTION_MCP_BINARY` | Absolute path to the built `swift-section-mcp` executable |
| `SWIFT_SECTION_CLI_BINARY` | Path to the `swift-section` CLI executable (used for reference output) |
| `SWIFT_SECTION_FIXTURE` | Path to a Mach-O binary used as the fixture |

Example:

```bash
SWIFT_SECTION_MCP_BINARY=.build/debug/swift-section-mcp \
SWIFT_SECTION_CLI_BINARY=.build/debug/swift-section \
SWIFT_SECTION_FIXTURE=/System/Library/CoreServices/Finder.app/Contents/MacOS/Finder \
swift test --filter MCPIntegrationTests
```

### Roadmap for MCP integration

1. **Even richer query tools** – extend the new focused MCP endpoints with protocol, conformance, and metadata layout filters so Claude can target individual subsystems without full dumps.
2. **Context-aware symbol queries** – accept natural language prompts (e.g. "grab symbols controlling window focus") and translate them into metadata filters that reuse the existing `SwiftInterface` + `TypeIndexing` stack.
3. **Dyld cache helpers** – expose new tools to enumerate cache images and surface their available architectures, simplifying Frida-style attach workflows.
4. **Frida/LLM bridge** – document how to pipe the MCP output into the forthcoming Frida MCP so Claude can immediately hook exported symbols after discovering them here.
5. **Test coverage** – introduce integration tests that spin up the MCP server, issue `tools/call` requests, and diff the output against the CLI command for representative binaries.

## Accessibility-Based App Control Agent

The repository includes experimental tools for controlling macOS applications via Accessibility APIs, enabling LLM-driven automation without SIP bypass or code injection.

### Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                      agent_loop.py                           │
│            Claude API + Tool Use orchestration              │
└─────────────────────────────────────────────────────────────┘
                            │
                   JSON-RPC (stdin/stdout)
                            ▼
┌─────────────────────────────────────────────────────────────┐
│                     AppAgent.swift                           │
│     VoiceOver-style navigation + scratch pad memory         │
└─────────────────────────────────────────────────────────────┘
                            │
                    Accessibility APIs
                            ▼
┌─────────────────────────────────────────────────────────────┐
│                       Target App                             │
└─────────────────────────────────────────────────────────────┘
```

### Tools

| Tool | Description |
|------|-------------|
| `observe_ui` | Capture full UI state with element IDs, roles, titles, values, actions |
| `diff_ui` | Compare to last observation, extract semantic signals |
| `find_content` | Search for elements by text content |
| `navigate` | Move element-by-element (like VoiceOver arrow keys) |
| `jump_to` | Jump to next element of a specific role |
| `list_landmarks` | Find UI regions (toolbar, sidebar, main, etc.) |
| `go_to_landmark` | Jump to a landmark by type or index |
| `where_am_i` | Get navigation context: path, landmarks, hypothesis, recent actions |
| `set_hypothesis` | Record current belief about app state |
| `click/type/press_key` | Perform actions |

### Quick Start

```bash
# Compile the agent
swiftc -O -o /tmp/AppAgent AppAgent.swift

# Interactive REPL
/tmp/AppAgent Safari

# LLM-controlled automation
export ANTHROPIC_API_KEY=sk-ant-...
python3 agent_loop.py WhatsApp "Send a message to Alice saying hello"
```

### Design Philosophy

The agent uses a **VoiceOver-style navigation model** rather than dumping the full UI:

1. **Incremental exploration** – Navigate element-by-element, building understanding
2. **Landmarks for orientation** – Find toolbar, sidebar, main content areas
3. **Scratch pad memory** – Maintain path, landmarks, hypothesis, recent actions
4. **Signal extraction** – Detect what changed semantically, not just structurally

This mirrors how blind users navigate apps with screen readers and works better for LLMs than parsing 200+ elements at once.

### Combining with MachO Analysis

The accessibility agent can be combined with MachOSwiftSection for richer context:

```bash
# Get UI structure
/tmp/AppAgent Safari --json > ui.json

# Get internal types
swift-section interface /Applications/Safari.app/Contents/MacOS/Safari > types.swift

# Feed both to LLM for correlation
cat ui.json types.swift | llm "Correlate UI elements to backing Swift types"
```

## License

[MachOObjCSection](https://github.com/p-x9/MachOObjCSection)

[MachOKit](https://github.com/p-x9/MachOKit)

[CwlDemangle](https://github.com/mattgallagher/CwlDemangle)

MachOSwiftSection is released under the MIT License. See [LICENSE](./LICENSE)
