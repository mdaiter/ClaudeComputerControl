# MachOSwiftSection

Control macOS apps with Claude. Extract Swift metadata from binaries.

## Quick Start: App Control Agent

Control any macOS app using natural language via Accessibility APIs—no code injection required.

```bash
# Build the agent
swiftc -O -o /tmp/AppAgent AppAgent.swift

# Control an app with Claude
export ANTHROPIC_API_KEY=sk-ant-...
python3 agent_loop.py Safari "Open a new tab and go to github.com"
python3 agent_loop.py Notes "Create a new note titled 'Meeting Notes'"
python3 agent_loop.py Finder "Navigate to Downloads folder"
```

### Interactive Mode

```bash
# Start interactive REPL with any app
/tmp/AppAgent Safari

# Available commands in REPL:
> observe_ui          # See all UI elements
> find_content "New"  # Search for text
> click 42            # Click element by ID
> type "hello"        # Type text
> press_key cmd+t     # Keyboard shortcut
```

### How It Works

```
Claude API ──JSON-RPC──▶ AppAgent.swift ──Accessibility APIs──▶ Target App
```

The agent uses VoiceOver-style navigation—exploring incrementally rather than dumping 200+ elements at once.

| Tool | What it does |
|------|--------------|
| `observe_ui` | Capture UI state with element IDs, roles, titles |
| `find_content` | Search elements by text |
| `navigate` | Move element-by-element |
| `click` / `type` / `press_key` | Perform actions |
| `where_am_i` | Get current navigation context |

---

## Swift Binary Analysis

Parse Mach-O files to extract Swift types, protocols, and conformances.

### CLI Tool

```bash
# Install via Homebrew
brew install swift-section

# Dump Swift metadata
swift-section dump /path/to/binary

# Generate Swift interface (like Xcode's "Generated Interface")
swift-section interface /path/to/binary

# Dump from system frameworks
swift-section interface --uses-system-dyld-shared-cache --cache-image-name SwiftUICore
```

### Library Usage

```swift
import MachOKit
import MachOSwiftSection

let machO: MachOFile = try .load(from: path)

// Get all Swift types
for descriptor in try machO.swift.typesContextDescriptors {
    switch descriptor {
    case .type(let wrapper):
        switch wrapper {
        case .class(let classDesc):
            let classType = try Class(descriptor: classDesc, in: machO)
            print(classType.name)
        case .struct(let structDesc):
            let structType = try Struct(descriptor: structDesc, in: machO)
            print(structType.name)
        case .enum(let enumDesc):
            let enumType = try Enum(descriptor: enumDesc, in: machO)
            print(enumType.name)
        }
    default: break
    }
}
```

### Generate Complete Swift Interface

```swift
import SwiftInterface

let builder = try SwiftInterfaceBuilder(configuration: .init(), eventHandlers: [], in: machO)
try await builder.prepare()
let interface = try await builder.printRoot()
```

---

## MCP Server

Expose Swift analysis to Claude via Model Context Protocol.

```bash
swift run swift-section-mcp
```

Add to Claude's MCP config:
```json
{ "command": ["path/to/swift-section-mcp"] }
```

**Available tools:**
- `swiftInterface` – Generate Swift interface from binary
- `listTypes` – Enumerate types with optional filtering
- `searchSymbols` – Search functions, methods, metadata

---

## Combining UI + Binary Analysis

Correlate what you see with what's in the code:

```bash
# Capture UI structure
/tmp/AppAgent Safari --json > ui.json

# Extract Swift types
swift-section interface /Applications/Safari.app/Contents/MacOS/Safari > types.swift

# Ask Claude to correlate
cat ui.json types.swift | llm "Match UI elements to their Swift implementations"
```

---

## Building from Source

```bash
# Build
swift build

# Test
swift test

# Build universal binary for distribution
./build-executable-product.sh
```

## License

MIT License. See [LICENSE](./LICENSE).

Based on [MachOKit](https://github.com/p-x9/MachOKit), [MachOObjCSection](https://github.com/p-x9/MachOObjCSection), and [CwlDemangle](https://github.com/mattgallagher/CwlDemangle).
