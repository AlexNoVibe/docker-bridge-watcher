# /// script
# requires-python = ">=3.10"
# dependencies = ["mcp<2"]
# ///

import os
import sys
import time
import argparse
import asyncio
from datetime import datetime
from pathlib import Path
from mcp.server import Server
from mcp.server.stdio import stdio_server
from mcp.types import TextContent, Tool

# --- CONFIGURATION & PATH RESOLUTION ---
parser = argparse.ArgumentParser(description="Docker Bridge MCP Server")
parser.add_argument("--bridge-dir", type=str, default=None, help="Path to docker_switch directory")
args, _ = parser.parse_known_args()

DEFAULT_BRIDGE_DIR = str(Path(__file__).resolve().parent.parent)
BRIDGE_DIR = args.bridge_dir or os.environ.get("BRIDGE_DIR", DEFAULT_BRIDGE_DIR)

COMMANDS_DIR = os.path.join(BRIDGE_DIR, "commands")
STATUS_DIR = os.path.join(BRIDGE_DIR, "status")
LOGS_DIR = os.path.join(BRIDGE_DIR, "logs")

EXECUTE_FILE = os.path.join(COMMANDS_DIR, "execute.txt")
ACTIONS_LOG = os.path.join(STATUS_DIR, "actions.log")
LAST_OUTPUT_LOG = os.path.join(STATUS_DIR, "last-output.log")
CONTINUOUS_LOG = os.path.join(LOGS_DIR, "continuous.log")
HEARTBEAT_FILE = os.path.join(STATUS_DIR, "heartbeat.txt")

server = Server("docker-bridge-mcp")

def get_watcher_liveness() -> dict:
    if not os.path.exists(HEARTBEAT_FILE):
        return {"alive": False, "reason": "heartbeat.txt not found (watcher not started)"}
    try:
        with open(HEARTBEAT_FILE, "r", encoding="utf-8", errors="ignore") as f:
            ts_str = f.read().strip()
        last_ts = datetime.strptime(ts_str, "%Y-%m-%d %H:%M:%S")
        diff_sec = (datetime.now() - last_ts).total_seconds()
        is_alive = diff_sec < 45
        return {
            "alive": is_alive,
            "last_heartbeat": ts_str,
            "seconds_ago": round(diff_sec, 1),
            "reason": "OK" if is_alive else f"Heartbeat is stale ({round(diff_sec, 1)}s old)"
        }
    except Exception as e:
        return {"alive": False, "reason": f"Error reading heartbeat: {e}"}

@server.list_tools()
async def handle_list_tools() -> list[Tool]:
    return [
        Tool(
            name="docker_compose_execute",
            description="Executes any Docker Compose command on the host (e.g. 'up -d', '--profile dev up -d', 'restart web', 'exec web bash -c \"ls -la\"', 'ps'). Waits for execution and returns the status and output.",
            inputSchema={
                "type": "object",
                "properties": {
                    "command": {
                        "type": "string",
                        "description": "Docker Compose arguments to run (e.g. 'up -d', 'restart', 'ps', 'logs --tail 50')"
                    },
                    "timeout_seconds": {
                        "type": "integer",
                        "description": "Timeout to wait for completion (default: 180 seconds)",
                        "default": 180
                    }
                },
                "required": ["command"]
            }
        ),
        Tool(
            name="docker_compose_read_continuous_logs",
            description="Reads the latest N lines from continuous background logs for all containers.",
            inputSchema={
                "type": "object",
                "properties": {
                    "lines": {
                        "type": "integer",
                        "description": "Number of lines to read from the end of continuous.log (default: 100)",
                        "default": 100
                    }
                }
            }
        ),
        Tool(
            name="docker_compose_status",
            description="Checks host watcher liveness, heartbeat timestamp, and recent action logs.",
            inputSchema={
                "type": "object",
                "properties": {}
            }
        ),
        Tool(
            name="docker_compose_ps",
            description="Shortcut to check running containers via 'docker compose ps'.",
            inputSchema={
                "type": "object",
                "properties": {}
            }
        )
    ]

@server.call_tool()
async def handle_call_tool(name: str, arguments: dict | None) -> list[TextContent]:
    arguments = arguments or {}

    if name == "docker_compose_status":
        liveness = get_watcher_liveness()
        recent_actions = "<no actions log>"
        if os.path.exists(ACTIONS_LOG):
            with open(ACTIONS_LOG, "r", encoding="utf-8", errors="ignore") as f:
                recent_actions = "".join(f.readlines()[-15:])
        
        cfg_file = os.path.join(BRIDGE_DIR, "config.ini")
        cfg_project = "auto"
        cfg_safemode = "enabled (default)"
        if os.path.exists(cfg_file):
            try:
                with open(cfg_file, "r", encoding="utf-8", errors="ignore") as cf:
                    for line in cf:
                        line = line.strip()
                        if line and not line.startswith(("#", ";")):
                            parts = line.split("=", 1)
                            if len(parts) == 2:
                                k, v = parts[0].strip().upper(), parts[1].strip()
                                if k == "PROJECT_DIR":
                                    cfg_project = v
                                elif k == "SAFE_MODE":
                                    cfg_safemode = "enabled" if v.lower() in ("true", "1", "yes") else "disabled"
            except Exception:
                pass

        status_text = (
            f"Watcher Alive : {liveness['alive']} ({liveness['reason']})\n"
            f"Last Heartbeat: {liveness.get('last_heartbeat', 'N/A')}\n"
            f"Bridge Dir    : {BRIDGE_DIR}\n"
            f"Target Project: {cfg_project}\n"
            f"Safe Mode     : {cfg_safemode}\n\n"
            f"--- Recent Actions ---\n{recent_actions}"
        )
        return [TextContent(type="text", text=status_text)]

    elif name == "docker_compose_ps":
        # Delegate to docker_compose_execute with command 'ps'
        return await handle_call_tool("docker_compose_execute", {"command": "ps"})

    elif name == "docker_compose_execute":
        command = arguments.get("command", "").strip()
        timeout = arguments.get("timeout_seconds", 180)
        if not command:
            return [TextContent(type="text", text="Error: command cannot be empty.")]

        os.makedirs(COMMANDS_DIR, exist_ok=True)
        os.makedirs(STATUS_DIR, exist_ok=True)
        os.makedirs(LOGS_DIR, exist_ok=True)

        start_size = 0
        if os.path.exists(ACTIONS_LOG):
            start_size = os.path.getsize(ACTIONS_LOG)

        # Write command to execute.txt
        with open(EXECUTE_FILE, "w", encoding="utf-8") as f:
            f.write(command)

        start_time = time.time()
        status_result = f"Timeout waiting for execution to finish after {timeout}s."
        
        completion_markers = [
            "Finished OK",
            "ERROR:",
            "EXCEPTION:",
            "is blocked",
            "not allowed",
            "Multiple commands detected",
            "Failed to parse command",
            "TIMEOUT:",
            "CRITICAL ERROR"
        ]

        while time.time() - start_time < timeout:
            await asyncio.sleep(0.5)
            if os.path.exists(ACTIONS_LOG):
                with open(ACTIONS_LOG, "r", encoding="utf-8", errors="ignore") as f:
                    f.seek(start_size)
                    new_logs = f.read()

                    if any(marker in new_logs for marker in completion_markers):
                        await asyncio.sleep(0.2)
                        status_result = new_logs.strip()
                        break

        last_output = ""
        if os.path.exists(LAST_OUTPUT_LOG):
            with open(LAST_OUTPUT_LOG, "r", encoding="utf-8", errors="ignore") as f:
                last_output = f.read().strip()

        return [
            TextContent(
                type="text",
                text=f"--- Watcher Status ---\n{status_result}\n\n--- Command Output ---\n{last_output if last_output else '<no output>'}"
            )
        ]

    elif name == "docker_compose_read_continuous_logs":
        lines_to_read = arguments.get("lines", 100)
        if not os.path.exists(CONTINUOUS_LOG):
            return [TextContent(type="text", text="Continuous log file does not exist yet.")]

        try:
            with open(CONTINUOUS_LOG, "r", encoding="utf-8", errors="ignore") as f:
                lines = f.readlines()
                return [TextContent(type="text", text="".join(lines[-lines_to_read:]))]
        except Exception as e:
            return [TextContent(type="text", text=f"Error reading logs: {e}")]

    raise ValueError(f"Unknown tool: {name}")

async def main():
    async with stdio_server() as (read_stream, write_stream):
        await server.run(
            read_stream,
            write_stream,
            server.create_initialization_options()
        )

if __name__ == "__main__":
    asyncio.run(main())
