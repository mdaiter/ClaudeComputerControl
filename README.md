# MachOSwiftSection

**Automate macOS apps with natural language. Extract Swift metadata from binaries.**

Three powerful capabilities in one toolkit:
1. **LLM Agent** — Control any macOS app using plain English via Claude
2. **App Automation** — Programmatic control via Accessibility APIs
3. **Binary Analysis** — Parse Mach-O files to extract Swift types

---

## LLM Agent (New!)

Control any macOS app with natural language:

```bash
# Build
MACHO_SWIFT_SECTION_USE_SWIFTTUI=1 swift build

# Set your API key
export ANTHROPIC_API_KEY=sk-ant-...

# Control apps with plain English
./.build/debug/app-agent Safari "open a new tab and go to github.com"
./.build/debug/app-agent Finder "go to Downloads folder"
./.build/debug/app-agent Notes "create a new note titled 'Meeting Notes'"
```

### How It Works

```
You: "open a new tab and go to github.com"
                    ↓
┌─────────────────────────────────────────┐
│  app-agent                              │
│  ├─ Observes Safari's UI               │
│  ├─ Sends to Claude with app hints     │
│  ├─ Claude returns: press_key cmd+t    │
│  ├─ Executes, observes new state       │
│  ├─ Claude returns: press_key cmd+l    │
│  ├─ Claude returns: type "github.com"  │
│  ├─ Claude returns: press_key return   │
│  └─ Claude: "Done!"                    │
└─────────────────────────────────────────┘
                    ↓
            Safari navigates to GitHub
```

The agent:
1. **Observes** the app's UI via Accessibility APIs
2. **Filters** to relevant elements (buttons, text fields, etc.)
3. **Asks Claude** what action to take, with app-specific hints
4. **Executes** the action (keyboard shortcuts, clicks, typing)
5. **Loops** until the task is complete or max iterations reached

### Output Format

```json
{
  "success": true,
  "iterations": 5,
  "steps": [
    {"tool": "observe_ui", "success": true, "message": "..."},
    {"tool": "press_key", "success": true, "details": {"key": "t", "modifiers": ["command"]}},
    {"tool": "press_key", "success": true, "details": {"key": "l", "modifiers": ["command"]}},
    {"tool": "type_text", "success": true, "details": {"text": "github.com"}},
    {"tool": "press_key", "success": true, "details": {"key": "return"}}
  ],
  "summary": "Opened a new tab and navigated to github.com"
}
```

### Supported Apps

Works with any macOS app that supports Accessibility. Best with:

| Category | Apps |
|----------|------|
| Browsers | Safari, Chrome, Firefox |
| Communication | Messages, Mail, Slack |
| Productivity | Finder, Notes, TextEdit, Calendar |
| Development | Terminal, Xcode, VS Code |

### Tips

- Grant Accessibility permissions to Terminal in System Preferences → Privacy & Security
- Make sure the target app is running before executing commands
- Be specific: "click the Submit button" works better than "submit the form"
- The agent uses keyboard shortcuts when possible (faster and more reliable)

---

## App Automation (Low-Level)

For programmatic control without LLM, use the structured CLI:

### Example 1: See What's on Screen

```bash
./.build/debug/app-automation observe Safari
```

```json
{
  "appName": "Safari",
  "elements": [
    {"id": "e1", "role": "AXWindow", "title": "GitHub"},
    {"id": "e5", "role": "AXButton", "title": "Back"},
    {"id": "e8", "role": "AXTextField", "value": "https://github.com"}
  ]
}
```

### Example 2: Find and Click

```bash
./.build/debug/app-automation click Safari '{"title": {"value": "Submit", "match": "contains"}}'
```

### Example 3: Run a Script

```bash
./.build/debug/app-automation run-script test-flow.json
```

### CLI Commands

| Command | Description |
|---------|-------------|
| `observe <app>` | Get UI snapshot |
| `query <app> <selector>` | Find elements |
| `click <app> <selector>` | Click element |
| `type <app> <selector> <text>` | Type text |
| `run-script <file>` | Run JSON script |

---

## Swift Binary Analysis

Parse Mach-O files to extract Swift types, protocols, and conformances.

```bash
# Dump Swift metadata
swift-section dump /path/to/binary

# Generate Swift interface
swift-section interface /path/to/binary

# From dyld shared cache
swift-section interface --uses-system-dyld-shared-cache --cache-image-name SwiftUICore
```

### Library Usage

```swift
import MachOKit
import MachOSwiftSection

let machO: MachOFile = try .load(from: path)

for descriptor in try machO.swift.typesContextDescriptors {
    // Access classes, structs, enums...
}
```

### MCP Server

Expose Swift analysis to Claude via Model Context Protocol:

```bash
swift run swift-section-mcp
```

---

## Building

```bash
# Build everything
MACHO_SWIFT_SECTION_USE_SWIFTTUI=1 swift build

# Run tests
MACHO_SWIFT_SECTION_USE_SWIFTTUI=1 swift test
```

### Environment Variables

| Variable | Description |
|----------|-------------|
| `ANTHROPIC_API_KEY` | Required for app-agent |
| `MACHO_SWIFT_SECTION_USE_SWIFTTUI=1` | Required for build |

---

## Roadmap

### v1.0 (Current)
- [x] LLM agent with Claude for natural language automation
- [x] App Automation daemon with JSON-RPC
- [x] Safari and Messages helpers
- [x] AX-based UI observation and actions
- [x] CLI tools for scripting
- [x] Swift binary parsing

### v1.1 (Next)
- [ ] More app helpers (Finder, Notes, Calendar, Mail)
- [ ] Streaming responses from agent
- [ ] Action recording and playback
- [ ] Retry policies with exponential backoff

### v2.0 (Future)
- [ ] Visual element identification (screenshots + vision)
- [ ] Cross-app workflows
- [ ] Headless mode for CI/CD
- [ ] Plugin system for custom adapters

---

## License

MIT License. See [LICENSE](./LICENSE).

Based on [MachOKit](https://github.com/p-x9/MachOKit) and [CwlDemangle](https://github.com/mattgallagher/CwlDemangle).
