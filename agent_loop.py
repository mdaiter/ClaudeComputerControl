#!/usr/bin/env python3
"""
agent_loop.py - LLM-driven app control agent

Connects Claude to AppAgent.swift to autonomously navigate and control macOS apps.
The LLM observes UI state, decides actions, executes them, and observes changes.

Usage:
    export ANTHROPIC_API_KEY=your_key
    python3 agent_loop.py "Safari" "Navigate to google.com and search for 'Claude AI'"
    python3 agent_loop.py "Finder" "Create a new folder called 'Test' on the Desktop"
"""

import subprocess
import json
import sys
import os
from typing import Optional

try:
    import anthropic
except ImportError:
    print("Install anthropic: pip install anthropic")
    sys.exit(1)


# Compact tool definitions - descriptions kept minimal
TOOLS = [
    {"name": "observe_ui", "description": "Get all visible UI elements with IDs, roles, titles, values.", "input_schema": {"type": "object", "properties": {}, "required": []}},
    {"name": "diff_ui", "description": "Show what changed since last observation.", "input_schema": {"type": "object", "properties": {}, "required": []}},
    {"name": "where_am_i", "description": "Get current position and context.", "input_schema": {"type": "object", "properties": {}, "required": []}},
    {"name": "navigate", "description": "Move to adjacent element.", "input_schema": {"type": "object", "properties": {"direction": {"type": "string", "enum": ["next", "prev", "first", "last"]}}, "required": ["direction"]}},
    {"name": "jump_to", "description": "Jump to element by role.", "input_schema": {"type": "object", "properties": {"role": {"type": "string"}, "direction": {"type": "string", "enum": ["next", "prev"], "default": "next"}}, "required": ["role"]}},
    {"name": "go_to_landmark", "description": "Jump to landmark (toolbar/sidebar/main).", "input_schema": {"type": "object", "properties": {"identifier": {"type": "string"}}, "required": ["identifier"]}},
    {"name": "find_content", "description": "Search for elements by text.", "input_schema": {"type": "object", "properties": {"query": {"type": "string"}, "count": {"type": "integer", "default": 20}}, "required": []}},
    {"name": "click", "description": "Click element by ID.", "input_schema": {"type": "object", "properties": {"element_id": {"type": "string"}}, "required": ["element_id"]}},
    {"name": "type", "description": "Type text into element.", "input_schema": {"type": "object", "properties": {"element_id": {"type": "string"}, "text": {"type": "string"}}, "required": ["element_id", "text"]}},
    {"name": "focus", "description": "Focus element.", "input_schema": {"type": "object", "properties": {"element_id": {"type": "string"}}, "required": ["element_id"]}},
    {"name": "press_key", "description": "Press key with optional modifiers (cmd/shift/alt/ctrl).", "input_schema": {"type": "object", "properties": {"key": {"type": "string"}, "modifiers": {"type": "array", "items": {"type": "string"}}}, "required": ["key"]}},
    {"name": "wait", "description": "Wait seconds.", "input_schema": {"type": "object", "properties": {"seconds": {"type": "number"}}, "required": ["seconds"]}},
    {"name": "task_complete", "description": "Task done.", "input_schema": {"type": "object", "properties": {"summary": {"type": "string"}}, "required": ["summary"]}},
    {"name": "task_failed", "description": "Task impossible.", "input_schema": {"type": "object", "properties": {"reason": {"type": "string"}}, "required": ["reason"]}},
]


class AppAgentBridge:
    """Bridges Python to the Swift AppAgent via JSON-RPC over stdin/stdout."""

    def __init__(self, app_name: str):
        self.app_name = app_name
        self.process: Optional[subprocess.Popen] = None

    def start(self):
        script_dir = os.path.dirname(os.path.abspath(__file__))
        agent_path = os.path.join(script_dir, "AppAgent.swift")

        # Pre-compile to avoid timeout on first call
        print("[Bridge] Compiling Swift agent (this may take a moment)...")
        compile_result = subprocess.run(
            ["swiftc", "-o", "/tmp/AppAgent", agent_path],
            capture_output=True,
            text=True
        )
        if compile_result.returncode != 0:
            print(f"[Bridge] Compilation failed:\n{compile_result.stderr}")
            raise RuntimeError("Failed to compile AppAgent.swift")

        print("[Bridge] Starting agent...")
        self.process = subprocess.Popen(
            ["/tmp/AppAgent", self.app_name, "--json-rpc"],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            bufsize=1
        )

        # Check if process started successfully
        import time
        time.sleep(0.1)
        if self.process.poll() is not None:
            stderr = self.process.stderr.read()
            raise RuntimeError(f"Agent failed to start: {stderr}")

    def call(self, tool: str, params: dict = None) -> dict:
        if not self.process:
            raise RuntimeError("Agent not started")

        # Check if process is still alive
        if self.process.poll() is not None:
            stderr = self.process.stderr.read()
            return {"success": False, "message": f"Agent crashed: {stderr}"}

        request = {"tool": tool, "params": params or {}}
        try:
            self.process.stdin.write(json.dumps(request) + "\n")
            self.process.stdin.flush()
        except BrokenPipeError:
            stderr = self.process.stderr.read()
            return {"success": False, "message": f"Agent pipe broken: {stderr}"}

        response_line = self.process.stdout.readline()
        if not response_line:
            stderr = self.process.stderr.read()
            return {"success": False, "message": f"No response from agent. stderr: {stderr}"}

        try:
            return json.loads(response_line)
        except json.JSONDecodeError:
            return {"success": False, "message": f"Invalid JSON: {response_line}"}

    def stop(self):
        if self.process:
            self.process.terminate()
            self.process.wait()


def _estimate_msg_size(msg) -> int:
    """Estimate message size handling Anthropic SDK objects."""
    try:
        return len(json.dumps(msg))
    except TypeError:
        # Handle SDK objects like TextBlock
        return len(str(msg))


def _prune_messages(messages: list, max_chars: int = 20000) -> list:
    """Keep recent messages, drop old ones if total exceeds max_chars."""
    total = sum(_estimate_msg_size(m) for m in messages)
    while total > max_chars and len(messages) > 2:
        # Remove oldest pair (assistant + user tool_result)
        removed = messages.pop(1)
        total -= _estimate_msg_size(removed)
        if messages and len(messages) > 1:
            removed = messages.pop(1)
            total -= _estimate_msg_size(removed)
    return messages


def run_agent(app_name: str, task: str, max_turns: int = 30, verbose: bool = True):
    """Run the agent loop until task completion or max turns."""

    client = anthropic.Anthropic()
    bridge = AppAgentBridge(app_name)

    if verbose:
        print(f"[Agent] Starting agent for '{app_name}'")
        print(f"[Agent] Task: {task}")
        print("-" * 60)

    bridge.start()

    system_prompt = f"""Control "{app_name}" via accessibility API. Task: {task}

Workflow: observe_ui → act → diff_ui → repeat → task_complete/task_failed
Element IDs (e.g. "e5") change between observations. Use press_key for shortcuts (cmd+t=new tab)."""

    messages = [{"role": "user", "content": f"Please complete this task: {task}"}]

    for turn in range(max_turns):
        if verbose:
            print(f"\n[Turn {turn + 1}/{max_turns}]")

        response = client.messages.create(
            model="claude-sonnet-4-20250514",
            max_tokens=4096,
            system=system_prompt,
            tools=TOOLS,
            messages=messages
        )

        # Process response
        assistant_content = []
        tool_results = []

        for block in response.content:
            if block.type == "text":
                if verbose:
                    print(f"[Claude] {block.text}")
                assistant_content.append(block)

            elif block.type == "tool_use":
                tool_name = block.name
                tool_input = block.input

                if verbose:
                    print(f"[Tool] {tool_name}({json.dumps(tool_input)})")

                # Handle terminal tools
                if tool_name == "task_complete":
                    if verbose:
                        print(f"\n[Agent] Task completed: {tool_input.get('summary', 'Done')}")
                    bridge.stop()
                    return {"success": True, "summary": tool_input.get("summary")}

                if tool_name == "task_failed":
                    if verbose:
                        print(f"\n[Agent] Task failed: {tool_input.get('reason', 'Unknown')}")
                    bridge.stop()
                    return {"success": False, "reason": tool_input.get("reason")}

                # Execute tool via bridge
                result = bridge.call(tool_name, tool_input)

                # Truncate result for both display AND message history to save tokens
                result_str = json.dumps(result)
                if len(result_str) > 2000:
                    # Keep structure but truncate data arrays
                    if isinstance(result.get("data"), dict) and "elements" in result.get("data", {}):
                        result["data"]["elements"] = result["data"]["elements"][:15]
                        result["data"]["_truncated"] = True
                    result_str = json.dumps(result)
                    if len(result_str) > 2000:
                        result_str = result_str[:2000] + '..."}'

                if verbose:
                    display_str = result_str[:500] + "..." if len(result_str) > 500 else result_str
                    print(f"[Result] {display_str}")

                assistant_content.append(block)
                tool_results.append({
                    "type": "tool_result",
                    "tool_use_id": block.id,
                    "content": result_str
                })

        # Update messages
        messages.append({"role": "assistant", "content": assistant_content})
        if tool_results:
            messages.append({"role": "user", "content": tool_results})

        # Prune old messages to stay under token limits
        messages = _prune_messages(messages)

        # Check stop reason
        if response.stop_reason == "end_turn" and not tool_results:
            if verbose:
                print("\n[Agent] Claude stopped without completing task")
            break

    bridge.stop()
    return {"success": False, "reason": "Max turns reached"}


def main():
    if len(sys.argv) < 3:
        print(__doc__)
        print("\nExamples:")
        print('  python3 agent_loop.py Safari "Open a new tab and go to github.com"')
        print('  python3 agent_loop.py Notes "Create a new note with the title \'Hello World\'"')
        print('  python3 agent_loop.py "System Preferences" "Open the Displays settings"')
        sys.exit(1)

    app_name = sys.argv[1]
    task = sys.argv[2]
    verbose = "--quiet" not in sys.argv

    if not os.environ.get("ANTHROPIC_API_KEY"):
        print("Error: ANTHROPIC_API_KEY environment variable not set")
        sys.exit(1)

    result = run_agent(app_name, task, verbose=verbose)

    print("\n" + "=" * 60)
    if result.get("success"):
        print(f"SUCCESS: {result.get('summary')}")
    else:
        print(f"FAILED: {result.get('reason')}")


if __name__ == "__main__":
    main()
