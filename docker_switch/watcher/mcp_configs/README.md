# MCP Configuration for AI Coding Agents

By default, the MCP server is **OFF**. The host watcher operates autonomously via `docker_switch/commands/execute.txt`.
Enable MCP only in projects where your agent needs direct tool calling.

---

## 1. Quick Activation (Batch Script)

Run from `docker_switch\watcher\mcp_configs\`:
- `enable_mcp.bat zcode` — creates `.zcode.json` and `.claude.json` in project root.
- `enable_mcp.bat opencode` — creates `opencode.json` and `.mcp.json` in project root.
- `enable_mcp.bat deepseek` — creates `.mcp.json` in project root.
- `enable_mcp.bat universal` — creates `.mcp.json` (for Cursor, Windsurf, Claude Code, etc.).
- `enable_mcp.bat all` — enables configs for all agents.
- `disable_mcp.bat` — removes all MCP configs from project root.

---

## 2. Configuration by Agent

### A. ZCode / Claude Code
Copy `zcode.json` to project root as `.zcode.json` or `.claude.json`:
```cmd
copy docker_switch\watcher\mcp_configs\zcode.json .zcode.json
```
Or add via CLI:
```bash
zcode mcp add docker-bridge uv -- run --python 3.12 docker_switch/watcher/docker_bridge_mcp.py
```

### B. OpenCode
Copy `opencode.json` to project root:
```cmd
copy docker_switch\watcher\mcp_configs\opencode.json opencode.json
```

### C. DeepSeek Harness
Copy `deepseek_harness.json` to project root as `.mcp.json`:
```cmd
copy docker_switch\watcher\mcp_configs\deepseek_harness.json .mcp.json
```

### D. Google Antigravity
Configured globally in `~/.gemini/config/mcp_config.json`:
```json
{
  "mcpServers": {
    "docker-bridge": {
      "command": "uv",
      "args": [
        "run",
        "--python",
        "3.12",
        "C:/Users/User/.gemini/config/tools/docker_bridge_mcp.py"
      ]
    }
  }
}
```
Antigravity automatically binds to the active project workspace.

---

## 3. Agent System Prompt / Rules Integration

Add the following note to your project's `AGENTS.md` or `CLAUDE.md`:

```markdown
## Docker Bridge Integration
When executing Docker commands:
- Do NOT run `docker` or `docker compose` directly in container sandboxes.
- Use `docker-bridge` MCP tools (`docker_compose_execute`, `docker_compose_ps`, etc.).
- If MCP is inactive, write the command to `docker_switch/commands/execute.txt` (e.g. `up -d`).
- Monitor logs in `docker_switch/logs/continuous.log`.
```
