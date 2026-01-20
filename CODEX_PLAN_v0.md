# CODEX_PLAN_v0.md

## Scope
Build a production-ready (developer-grade) unified automation system for macOS apps (initial targets: Safari, Messages) using:
- JSON-RPC over a local socket
- AX accessibility + dynamic backend routing
- Per-app helpers via NSXPCConnection (crash isolated)
- Streaming observe API (client-requested interval)
- No code injection; minimal AppleScript usage
- Dry-run mode that blocks all actions
- Future-proof shim driver interface

---

## Final Requirements (Locked)
- Transport: local socket with pure JSON-RPC
- Selectors: JSON schema, exact/contains only (no regex)
- Backends: AX, NSXPC helpers, minimal AppleScript
- Helpers: per-app NSXPCConnection processes
- Streaming: client-requested interval
- Streaming payload: initial snapshot + diffs
- Dry-run: all actions blocked
- Apps: Safari, Messages

---

## Architecture Overview

### Core Daemon
Responsibilities:
- JSON-RPC server over UNIX socket
- Request validation + dispatch
- Backend routing (AX vs XPC helper)
- Helper lifecycle (auto-start, auto-restart)
- Streaming subscriptions (observe_stream)
- Dry-run enforcement
- Observability (trace logs, routing decisions)

### Per-App Helpers (NSXPC)
Responsibilities:
- App-specific adapter (Safari, Messages)
- Capabilities reporting
- App-specific automation (ScriptingBridge/AppleScript where needed)
- Streaming observe support

### Unified API (JSON-RPC)
Key methods:
- observe(app)
- diff(app)
- query(app, selector)
- perform(app, action)
- open_url(app, url)
- menu(app, path)
- shortcut(app, keys)
- type(app, selector, text)
- observe_stream.start(app, interval_ms)
- observe_stream.stop(token)
- capabilities(app)
- health()
- list_apps()

---

## Data Schemas

### Selector Schema (JSON)
Fields:
- role, title, value, path, attributes, bounds, window
- match: exact | contains (per field)
- limit, visibility, enabled, focused

### Action Schema (JSON)
Fields:
- action: click | set_value | press_key | scroll | invoke | menu | open_url | shortcut
- selector or element_id
- params (key/value)

### Response Schema (JSON)
Fields:
- success, error_code, retry_hint, signals, changed, data

### Stream Events
- snapshot: full UI state
- diff: incremental changes
- signal: derived semantic signals
- error: errors for the stream

---

## Backend Routing Policy
Priority per action:
1) AX (if selector matches reliably)
2) App helper via XPC (app-specific primitives)
3) AppleScript (only if helper indicates AX insufficient)

Routing policy persists per app in a capability profile:
- AX richness score
- Scripting suite support
- URL scheme support
- Mach-O capability hints (OSAKit/ScriptingBridge/WebKit)

---

## AX Reliability Upgrades
- Stable element identity: hash of (role + title + path + bounds + window)
- Re-match across snapshots with a scoring system
- Robust typing strategy: AXValue -> key events -> clipboard
- Focus/window activation before action
- Retry + timeout + re-observe loop

---

## App Helpers

### Safari Helper
- Prefer ScriptingBridge for open_url, tab actions
- AX for page UI and prompts
- Stream events on UI changes

### Messages Helper
- Minimal AppleScript for select_conversation, send_message
- AX for navigation + content
- Dry-run: report planned action without execution

---

## Streaming Observe API
- Client requests interval: observe_stream.start(app, interval_ms)
- Response returns token
- Stream events: initial snapshot, then diff per interval
- observe_stream.stop(token) terminates

---

## Dry-Run Mode
- Global daemon flag (startup parameter)
- All actions blocked
- Responses include planned_actions for visibility

---

## Test Harness (Developer-Grade)
- CLI runner for scripted flows
- Trace recorder: actions + snapshots + diffs + routing decisions
- Baselines:
  - Safari: open URL -> search -> open tab
  - Messages: open conversation -> send message (dry-run)

---

## Implementation Checklist (Phased)

### Phase 1 - Protocol + Schemas
- JSON-RPC envelope
- Selector schema (exact/contains)
- Action schema
- Response + error codes
- Stream event types

### Phase 2 - Daemon
- UNIX socket server
- JSON-RPC router
- Helper manager (auto-start/restart)
- Streaming subscription manager
- Dry-run enforcement

### Phase 3 - AX Driver
- Observe + flatten + stable IDs
- Selector matching + scoring
- Perform + retry loop
- Robust typing + focus handling

### Phase 4 - XPC Helpers
- NSXPC interface
- Shared request/response types
- Per-app helper bootstrapping

### Phase 5 - Safari Helper
- ScriptingBridge for URL and tabs
- AX for UI interactions
- Stream updates

### Phase 6 - Messages Helper
- Minimal AppleScript for send/select
- AX for UI and content
- Dry-run support

### Phase 7 - Routing + Capability Profiles
- Capability cache per app
- Deterministic routing rules
- Fallback order tracking

### Phase 8 - Test Harness
- CLI script runner
- Trace recorder + replay
- Baseline diff comparisons

---

## Open Decisions (Resolved)
- Transport: JSON-RPC over local socket
- Selector matching: exact/contains only
- Helpers: NSXPCConnection
- Streaming: client-requested interval
- Streaming payload: initial snapshot + diffs
- Dry-run: block all actions
