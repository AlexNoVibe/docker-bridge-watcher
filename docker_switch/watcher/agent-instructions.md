# LLM Agent Instructions (Docker Bridge Watcher Universal v2)

Hello, agent! You are working in an isolated environment, but you have access to control Docker Compose on the host machine via the **Docker Bridge Watcher**.

This is the modernized universal bridge (v2) supporting **full native Docker Compose commands, profiles, and continuous log streaming**.

## How to Send Commands

### Option A: Via MCP Tools (Recommended)
If your environment has MCP enabled, call the tools directly:
- `docker_compose_execute(command="up -d")`
- `docker_compose_execute(command="--profile dev up -d")`
- `docker_compose_execute(command="restart web")`
- `docker_compose_ps()`
- `docker_compose_status()`
- `docker_compose_read_continuous_logs(lines=100)`

### Option B: Via File Bridge (`commands/execute.txt`)
Write the command arguments into `commands/execute.txt`:
```bash
echo "up -d" > commands/execute.txt
```
The host watcher automatically prepends `docker compose -f <compose_file>`.

## Allowed Commands & Options

- **Allowed verbs**: `up`, `down`, `restart`, `build`, `logs`, `exec`, `ps`, `pull`, `stop`, `start`, `rm`, `run`, `config`.
- **Profiles supported**: You can use profiles natively, e.g.:
  - `--profile dev up -d`
  - `--profile all up -d`
- **Targeting**:
  - `up -d`: Starts all services defined in compose (or active profiles).
  - `up -d <service_name>`: Starts only the specified service.
  - `restart`: Restarts all services.
  - `restart <service_name>`: Restarts a specific service.
  - `exec <service_name> bash -c "<cmd>"`: Executes a command in a container.
  *(Note: Legacy `full` keyword is no longer required and is ignored if supplied).*

## Continuous Log Stream

Container output from all services is streamed continuously to:
`logs/continuous.log`

Read it at any time:
```bash
tail -n 100 logs/continuous.log
```

## Status & Liveness

- `status/actions.log`: Detailed log of watcher actions with timestamps and exit codes.
- `status/last-output.log`: Exact stdout/stderr of the last executed command.
- `status/heartbeat.txt`: Updated every second. If timestamp is > 45s old, watcher is not running.
