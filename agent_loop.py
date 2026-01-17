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


TOOLS = [
    {
        "name": "observe_ui",
        "description": "Capture the current UI state of the app. Returns all visible elements with their IDs, roles, titles, values, and available actions. Call this first to see what's on screen.",
        "input_schema": {"type": "object", "properties": {}, "required": []}
    },
    {
        "name": "diff_ui",
        "description": "Compare current UI to the last observation. Shows what elements were added, removed, or modified. Returns signals describing what changed semantically.",
        "input_schema": {"type": "object", "properties": {}, "required": []}
    },
    {
        "name": "where_am_i",
        "description": "Get your current navigation context: location in UI hierarchy, known landmarks, recent actions, and current hypothesis. Like VoiceOver's describe command.",
        "input_schema": {"type": "object", "properties": {}, "required": []}
    },
    {
        "name": "navigate",
        "description": "Move to adjacent element in the UI. Like pressing arrow keys in VoiceOver. Builds up mental model incrementally.",
        "input_schema": {
            "type": "object",
            "properties": {
                "direction": {"type": "string", "enum": ["next", "prev", "first", "last"], "description": "Direction to navigate"}
            },
            "required": ["direction"]
        }
    },
    {
        "name": "jump_to",
        "description": "Jump to next element of a specific type. Like VoiceOver rotor - jump between headings, buttons, text fields, etc.",
        "input_schema": {
            "type": "object",
            "properties": {
                "role": {"type": "string", "description": "Element role to find: Button, TextField, StaticText, Image, Cell, etc."},
                "direction": {"type": "string", "enum": ["next", "prev"], "default": "next"}
            },
            "required": ["role"]
        }
    },
    {
        "name": "list_landmarks",
        "description": "Find and list all landmarks/regions in the UI: toolbar, sidebar, main content, navigation, search, forms.",
        "input_schema": {"type": "object", "properties": {}, "required": []}
    },
    {
        "name": "go_to_landmark",
        "description": "Jump directly to a landmark by type or index number.",
        "input_schema": {
            "type": "object",
            "properties": {
                "identifier": {"type": "string", "description": "Landmark type (toolbar, sidebar, main) or index from list_landmarks"}
            },
            "required": ["identifier"]
        }
    },
    {
        "name": "describe_current",
        "description": "Get detailed description of the currently focused element.",
        "input_schema": {"type": "object", "properties": {}, "required": []}
    },
    {
        "name": "list_nearby",
        "description": "List actionable elements near current position. Helps understand available actions without seeing everything.",
        "input_schema": {
            "type": "object",
            "properties": {
                "count": {"type": "integer", "default": 10, "description": "How many nearby elements to list"}
            },
            "required": []
        }
    },
    {
        "name": "set_hypothesis",
        "description": "Record your current belief about the app state. Helps maintain context. Example: 'I am on the login screen'",
        "input_schema": {
            "type": "object",
            "properties": {
                "hypothesis": {"type": "string", "description": "Your understanding of where you are and app state"}
            },
            "required": ["hypothesis"]
        }
    },
    {
        "name": "find_content",
        "description": "Find UI elements that have actual text content (titles, labels, values). Can search for specific text. Great for finding chat items, messages, buttons with labels, etc.",
        "input_schema": {
            "type": "object",
            "properties": {
                "query": {"type": "string", "description": "Optional search term to filter elements"},
                "count": {"type": "integer", "default": 20, "description": "Max results to return"}
            },
            "required": []
        }
    },
    {
        "name": "click",
        "description": "Click/press a UI element by its ID. Use for buttons, checkboxes, menu items, etc.",
        "input_schema": {
            "type": "object",
            "properties": {
                "element_id": {"type": "string", "description": "The element ID (e.g., 'e5')"}
            },
            "required": ["element_id"]
        }
    },
    {
        "name": "type",
        "description": "Type text into a text field or text area by element ID.",
        "input_schema": {
            "type": "object",
            "properties": {
                "element_id": {"type": "string", "description": "The text field element ID"},
                "text": {"type": "string", "description": "The text to type"}
            },
            "required": ["element_id", "text"]
        }
    },
    {
        "name": "focus",
        "description": "Set focus to a specific element.",
        "input_schema": {
            "type": "object",
            "properties": {
                "element_id": {"type": "string", "description": "The element ID to focus"}
            },
            "required": ["element_id"]
        }
    },
    {
        "name": "press_key",
        "description": "Press a keyboard key, optionally with modifiers. For Enter, Tab, Escape, shortcuts, etc.",
        "input_schema": {
            "type": "object",
            "properties": {
                "key": {"type": "string", "description": "Key name: return, tab, escape, space, delete, up, down, left, right, a-z"},
                "modifiers": {"type": "array", "items": {"type": "string"}, "description": "Modifiers: cmd, shift, alt, ctrl"}
            },
            "required": ["key"]
        }
    },
    {
        "name": "wait",
        "description": "Wait for a specified time. Use after actions that trigger animations or loading.",
        "input_schema": {
            "type": "object",
            "properties": {
                "seconds": {"type": "number", "description": "Seconds to wait (e.g., 0.5, 1, 2)"}
            },
            "required": ["seconds"]
        }
    },
    {
        "name": "task_complete",
        "description": "Signal that the task has been completed successfully.",
        "input_schema": {
            "type": "object",
            "properties": {
                "summary": {"type": "string", "description": "Brief summary of what was accomplished"}
            },
            "required": ["summary"]
        }
    },
    {
        "name": "task_failed",
        "description": "Signal that the task cannot be completed.",
        "input_schema": {
            "type": "object",
            "properties": {
                "reason": {"type": "string", "description": "Why the task failed"}
            },
            "required": ["reason"]
        }
    }
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


def run_agent(app_name: str, task: str, max_turns: int = 30, verbose: bool = True):
    """Run the agent loop until task completion or max turns."""

    client = anthropic.Anthropic()
    bridge = AppAgentBridge(app_name)

    if verbose:
        print(f"[Agent] Starting agent for '{app_name}'")
        print(f"[Agent] Task: {task}")
        print("-" * 60)

    bridge.start()

    system_prompt = f"""You are an AI agent controlling a macOS application called "{app_name}" through its accessibility API.

Your task: {task}

Instructions:
1. First, call observe_ui to see the current state of the app
2. Analyze what you see and decide what action to take
3. Execute actions (click, type, press_key, etc.)
4. After each action, either observe_ui or diff_ui to see what changed
5. Continue until the task is complete, then call task_complete
6. If you get stuck or the task is impossible, call task_failed

Tips:
- Element IDs (e.g., "e5") are assigned by observe_ui and may change between observations
- Use diff_ui to efficiently see what changed after an action
- Some actions need a short wait() afterward for animations
- If an element isn't found, call observe_ui to refresh the element cache
- Look for text fields (AXTextField, AXTextArea) to type into
- Look for buttons (AXButton) to click
- Use press_key for keyboard shortcuts (e.g., cmd+t for new tab)

Be methodical: observe, plan, act, verify."""

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

                if verbose:
                    # Truncate large outputs
                    result_str = json.dumps(result)
                    if len(result_str) > 500:
                        result_str = result_str[:500] + "..."
                    print(f"[Result] {result_str}")

                assistant_content.append(block)
                tool_results.append({
                    "type": "tool_result",
                    "tool_use_id": block.id,
                    "content": json.dumps(result)
                })

        # Update messages
        messages.append({"role": "assistant", "content": assistant_content})
        if tool_results:
            messages.append({"role": "user", "content": tool_results})

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
