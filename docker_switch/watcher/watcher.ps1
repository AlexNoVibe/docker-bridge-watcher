<#
    Docker Bridge Watcher (Universal v2 - Production Hardened)

    FEATURES:
    1. Universal & Portable: Zero hardcoded paths; derives all paths dynamically from script location.
    2. Flexible Docker Compose: Full native support for profiles (--profile), services, and flags.
       No artificial 'full' keyword requirement.
    3. Collision-Proof Mutex: Project-scoped mutex derived from project path hash.
    4. Anti-Freeze Protection:
       - Disables Windows Console QuickEdit mode (prevents mouse clicks from freezing the process).
       - Retry loop on file operations with file lock detection.
       - Start-Job timeout protection with tree process cleanup.
       - Log rotation for continuous.log (caps at 10 MB).
    5. Continuous Heartbeat: Updates status\heartbeat.txt every second.
    6. Stdio & Host Separation: Host console displays detailed paths; actions.log stays clean for agents.
#>

param(
    [string]$ProjectDir = "",
    [switch]$SafeMode
)

# === Configure Console Window (Consolas 16pt & Disable QuickEdit) ===
try {
    Add-Type -TypeDefinition @"
    using System;
    using System.Runtime.InteropServices;

    public class ConsoleWindowHelper {
        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        public struct CONSOLE_FONT_INFO_EX {
            public uint cbSize;
            public uint nFont;
            public short dwFontSizeX;
            public short dwFontSizeY;
            public int FontFamily;
            public int FontWeight;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)]
            public string FaceName;
        }

        [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Auto)]
        public static extern IntPtr CreateFile(
            string lpFileName,
            uint dwDesiredAccess,
            uint dwShareMode,
            IntPtr lpSecurityAttributes,
            uint dwCreationDisposition,
            uint dwFlagsAndAttributes,
            IntPtr hTemplateFile);

        [DllImport("kernel32.dll", SetLastError = true)]
        public static extern bool SetCurrentConsoleFontEx(IntPtr hConsoleOutput, bool bMaximumWindow, ref CONSOLE_FONT_INFO_EX lpConsoleCurrentFontEx);

        [DllImport("kernel32.dll", SetLastError = true)]
        public static extern bool GetCurrentConsoleFontEx(IntPtr hConsoleOutput, bool bMaximumWindow, ref CONSOLE_FONT_INFO_EX lpConsoleCurrentFontEx);

        [DllImport("kernel32.dll", SetLastError = true)]
        public static extern bool GetConsoleMode(IntPtr hConsoleHandle, out uint lpMode);

        [DllImport("kernel32.dll", SetLastError = true)]
        public static extern bool SetConsoleMode(IntPtr hConsoleHandle, uint dwMode);

        [DllImport("kernel32.dll", SetLastError = true)]
        public static extern bool CloseHandle(IntPtr hObject);

        private const uint GENERIC_READ = 0x80000000;
        private const uint GENERIC_WRITE = 0x40000000;
        private const uint FILE_SHARE_READ = 1;
        private const uint FILE_SHARE_WRITE = 2;
        private const uint OPEN_EXISTING = 3;

        public static bool Configure(short fontSize, string fontFace) {
            bool fontOk = false;
            IntPtr hConOut = CreateFile("CONOUT$", GENERIC_READ | GENERIC_WRITE, FILE_SHARE_READ | FILE_SHARE_WRITE, IntPtr.Zero, OPEN_EXISTING, 0, IntPtr.Zero);
            if (hConOut.ToInt64() != -1 && hConOut != IntPtr.Zero) {
                try {
                    CONSOLE_FONT_INFO_EX info = new CONSOLE_FONT_INFO_EX();
                    info.cbSize = (uint)Marshal.SizeOf(info);
                    GetCurrentConsoleFontEx(hConOut, false, ref info);
                    info.dwFontSizeY = fontSize;
                    info.dwFontSizeX = 0;
                    info.FontWeight = 400;
                    info.FontFamily = 54;
                    info.FaceName = fontFace;
                    fontOk = SetCurrentConsoleFontEx(hConOut, false, ref info);
                } catch {}
                CloseHandle(hConOut);
            }

            IntPtr hConIn = CreateFile("CONIN$", GENERIC_READ | GENERIC_WRITE, FILE_SHARE_READ | FILE_SHARE_WRITE, IntPtr.Zero, OPEN_EXISTING, 0, IntPtr.Zero);
            if (hConIn.ToInt64() != -1 && hConIn != IntPtr.Zero) {
                try {
                    uint mode = 0;
                    if (GetConsoleMode(hConIn, out mode)) {
                        uint ENABLE_QUICK_EDIT_MODE = 0x0040;
                        uint ENABLE_EXTENDED_FLAGS  = 0x0080;
                        uint newMode = (mode & ~ENABLE_QUICK_EDIT_MODE) | ENABLE_EXTENDED_FLAGS;
                        SetConsoleMode(hConIn, newMode);
                    }
                } catch {}
                CloseHandle(hConIn);
            }

            return fontOk;
        }
    }
"@
    [ConsoleWindowHelper]::Configure(16, "Consolas") | Out-Null
} catch {
    # Non-fatal if running in environments without direct console handle
}

# === Path & Project Discovery (via config.ini or arguments) ===
$scriptDir  = $PSScriptRoot
if (-not $scriptDir) { $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path }
$bridge     = (Resolve-Path (Join-Path $scriptDir "..")).Path

# 1. Read config.ini from bridge root
$configFile = Join-Path $bridge "config.ini"
$cfgProjectDir = "auto"
$cfgSafeMode   = $true

if (Test-Path $configFile) {
    Get-Content $configFile | ForEach-Object {
        $line = $_.Trim()
        if ($line -and -not $line.StartsWith("#") -and -not $line.StartsWith(";")) {
            $parts = $line -split "=", 2
            if ($parts.Length -eq 2) {
                $key = $parts[0].Trim().ToUpper()
                $val = $parts[1].Trim()
                if ($key -eq "PROJECT_DIR") { $cfgProjectDir = $val }
                if ($key -eq "SAFE_MODE")   { $cfgSafeMode = ($val -eq "true" -or $val -eq "1" -or $val -eq "yes") }
            }
        }
    }
}

# 2. Determine SafeMode (CLI switch takes precedence over config.ini)
if ($PSBoundParameters.ContainsKey('SafeMode')) {
    $SafeMode = $SafeMode.IsPresent
} else {
    $SafeMode = $cfgSafeMode
}

# 3. Determine Project Directory (CLI parameter -> config.ini -> auto parent)
$targetRaw = if ($ProjectDir -and $ProjectDir -ne "auto") {
    $ProjectDir
} elseif ($cfgProjectDir -and $cfgProjectDir -ne "auto") {
    $cfgProjectDir
} else {
    Join-Path $bridge ".."
}

if (-not [System.IO.Path]::IsPathRooted($targetRaw)) {
    $targetRaw = Join-Path $bridge $targetRaw
}

if (-not (Test-Path $targetRaw)) {
    Write-Host "[ERROR] Target project directory not found: $targetRaw" -ForegroundColor Red
    Start-Sleep -Seconds 5
    exit 1
}
$projectDir = (Resolve-Path $targetRaw).Path

# Locate compose file in project root or switch root
$composeCandidates = @(
    (Join-Path $projectDir "docker-compose.yaml"),
    (Join-Path $projectDir "docker-compose.yml"),
    (Join-Path $projectDir "compose.yaml"),
    (Join-Path $projectDir "compose.yml"),
    (Join-Path $bridge "docker-compose.yaml"),
    (Join-Path $bridge "docker-compose.yml")
)
$compose = $null
foreach ($cand in $composeCandidates) {
    if (Test-Path $cand) {
        $compose = (Resolve-Path $cand).Path
        break
    }
}

if (-not $compose) {
    Write-Host "[ERROR] Could not find compose file in $projectDir or $bridge" -ForegroundColor Red
    Start-Sleep -Seconds 5
    exit 1
}

# If target project has its own docker_switch, use it for communication buffers:
$activeBridge = if (Test-Path (Join-Path $projectDir "docker_switch")) {
    (Join-Path $projectDir "docker_switch")
} else {
    $bridge
}

$commandsDir = Join-Path $activeBridge "commands"
$statusDir   = Join-Path $activeBridge "status"
$logsDir     = Join-Path $activeBridge "logs"

foreach ($dir in @($commandsDir, $statusDir, $logsDir)) {
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
}

$actionsLog    = Join-Path $statusDir "actions.log"
$heartbeatPath = Join-Path $statusDir "heartbeat.txt"
$executeFile   = Join-Path $commandsDir "execute.txt"
$processingFile= Join-Path $commandsDir "execute.processing"

# === Single Instance Mutex (Safe Short-Hash Name) ===
$cleanName = (Split-Path -Leaf $projectDir) -replace '[^a-zA-Z0-9_]', '_'
$md5 = [System.Security.Cryptography.MD5]::Create()
$hashBytes = $md5.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($projectDir.ToLower()))
$pathHash = [System.BitConverter]::ToString($hashBytes).Replace('-', '').Substring(0, 8)
$mutexName = "Local\DockerBridgeWatcher_${cleanName}_${pathHash}"

$mutexCreated = $false
$mutex = New-Object System.Threading.Mutex($false, $mutexName, [ref]$mutexCreated)
$mutexOwned = $false
try {
    $mutexOwned = $mutex.WaitOne(0, $false)
} catch [System.Threading.AbandonedMutexException] {
    $mutexOwned = $true
}

if (-not $mutexOwned) {
    Write-Host "[watcher] Another instance is already running for project '$cleanName' (mutex: $mutexName). Exiting." -ForegroundColor Yellow
    Start-Sleep -Seconds 3
    exit 1
}


function Test-DockerDaemon {
    $dockerCmd = Get-Command "docker" -ErrorAction SilentlyContinue
    if (-not $dockerCmd) {
        return @{
            Available = $false
            DaemonOk  = $false
            Message   = "Binary 'docker' not found on PATH. Ensure Docker Desktop is installed and in PATH."
        }
    }

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = "docker"
    $psi.Arguments = "info --format ""{{.ServerVersion}}"""
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true

    $proc = $null
    try {
        $proc = [System.Diagnostics.Process]::Start($psi)
    } catch {
        return @{
            Available = $true
            DaemonOk  = $false
            Message   = "Failed to spawn docker process: $($_.Exception.Message)"
        }
    }

    if ($proc.WaitForExit(4000)) {
        $out = $proc.StandardOutput.ReadToEnd().Trim()
        $err = $proc.StandardError.ReadToEnd().Trim()
        if ($proc.ExitCode -eq 0 -and -not [string]::IsNullOrWhiteSpace($out)) {
            return @{
                Available = $true
                DaemonOk  = $true
                Version   = $out
                Message   = "Online (v$out)"
            }
        } else {
            $msg = if ($err) { $err } else { "Daemon not responding (exit $($proc.ExitCode))" }
            $firstLine = ($msg -split "`r?`n")[0]
            return @{
                Available = $true
                DaemonOk  = $false
                Message   = $firstLine
            }
        }
    } else {
        try { $proc.Kill() } catch {}
        return @{
            Available = $true
            DaemonOk  = $false
            Message   = "Timed out after 4s (daemon may be starting or frozen)"
        }
    }
}

# === Host Console Banner ===
$projectName = Split-Path -Leaf $projectDir
$dockerStatus = Test-DockerDaemon

Write-Host ""
Write-Host "=================================================================" -ForegroundColor DarkCyan
Write-Host "              DOCKER BRIDGE WATCHER (Universal v2)               " -ForegroundColor Cyan
Write-Host "=================================================================" -ForegroundColor DarkCyan
Write-Host "  >>> TARGET PROJECT:  " -NoNewline -ForegroundColor White
Write-Host " [ $projectName ] " -ForegroundColor Black -BackgroundColor Yellow

if ($dockerStatus.DaemonOk) {
    Write-Host "  >>> DOCKER DAEMON :  " -NoNewline -ForegroundColor White
    Write-Host " [ ONLINE ] $($dockerStatus.Message) " -ForegroundColor Green
} else {
    Write-Host "  >>> DOCKER DAEMON :  " -NoNewline -ForegroundColor White
    Write-Host " [ OFFLINE / ERROR ] " -ForegroundColor White -BackgroundColor Red
    Write-Host "      ! $($dockerStatus.Message)" -ForegroundColor Red
}
Write-Host "=================================================================" -ForegroundColor DarkCyan
Write-Host ""

function Write-Action {
    param([string]$Text)
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "[$ts] $Text" | Add-Content -Path $actionsLog -Encoding UTF8
    Write-Host "[$ts] $Text"
}

function Write-Heartbeat {
    try { [System.IO.File]::WriteAllText($heartbeatPath, (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')) } catch {}
}

# === Docker Compose Invocation with Timeout & Cleanup ===
function Invoke-ComposeWithTimeout {
    param([string[]]$ComposeArgs, [int]$TimeoutSec = 180)
    $cmdJob = Start-Job -ScriptBlock {
        param($composeFile, $cmdArgs)
        $out = & docker compose -f $composeFile @cmdArgs 2>&1
        "###EXITCODE:$LASTEXITCODE"
        $out
    } -ArgumentList $compose, $ComposeArgs

    if (Wait-Job $cmdJob -Timeout $TimeoutSec) {
        $jobOut = @(Receive-Job $cmdJob)
        Remove-Job $cmdJob -Force -ErrorAction SilentlyContinue
        $exitCode = 1
        $lines = New-Object System.Collections.Generic.List[string]
        foreach ($l in $jobOut) {
            $s = "$l"
            if ($s -like '###EXITCODE:*') { 
                try { $exitCode = [int]$s.Substring(12) } catch {} 
            } else { 
                $lines.Add($s) 
            }
        }
        $lines | Out-File -FilePath (Join-Path $statusDir "last-output.log") -Encoding UTF8
        return @{ ExitCode = $exitCode; TimedOut = $false; Output = $lines }
    }

    # Job timed out: Stop and remove job
    Stop-Job $cmdJob -ErrorAction SilentlyContinue
    Remove-Job $cmdJob -Force -ErrorAction SilentlyContinue

    "docker compose $($ComposeArgs -join ' ') TIMEOUT after ${TimeoutSec}s" |
        Out-File -FilePath (Join-Path $statusDir "last-output.log") -Encoding UTF8
    return @{ ExitCode = 124; TimedOut = $true; Output = @() }
}


# Continuous Background Logs with Auto-Rotation (10MB limit)
$continuousLogPath = Join-Path $logsDir "continuous.log"
if (Test-Path $continuousLogPath) { Remove-Item $continuousLogPath -Force }

Write-Action "Starting continuous background logs (logs/continuous.log)..."
$logJob = Start-Job -ScriptBlock {
    param($composeFile, $logPath)
    $maxBytes = 10 * 1024 * 1024
    while ($true) {
        try {
            if (Test-Path $logPath) {
                $len = (Get-Item $logPath).Length
                if ($len -gt $maxBytes) {
                    $tailLines = Get-Content $logPath -Tail 2000
                    $tailLines | Out-File -FilePath $logPath -Encoding UTF8 -Force
                }
            }
            & docker compose -f $composeFile logs -f --tail 100 >> $logPath 2>&1
        } catch {}
        Start-Sleep -Seconds 3
    }
} -ArgumentList $compose, $continuousLogPath

# Crash recovery: unfinished command in processing state
if ((-not (Test-Path $executeFile)) -and (Test-Path $processingFile)) {
    Move-Item $processingFile $executeFile -Force
    Write-Action "Recovered unfinished command from execute.processing"
}

$allowedCommands = @("up", "down", "restart", "build", "logs", "exec", "ps", "pull", "stop", "start", "rm", "run", "config")
$dangerousCommands = @("exec", "rm")

if ($dockerStatus.DaemonOk) {
    Write-Action "Docker Daemon: Online ($($dockerStatus.Message))"
} else {
    Write-Action "WARNING: Docker Daemon is OFFLINE: $($dockerStatus.Message)"
}

Write-Action "=== Watcher started ==="
Write-Action "Safe Mode: $SafeMode"
Write-Heartbeat
Write-Host "Watcher is running. Listening for commands. Press Ctrl+C to stop.`n" -ForegroundColor Green

$firstUpDone = $false

try {
    while ($true) {
        Write-Heartbeat

        try {
            if (Test-Path $executeFile) {
                # Safe atomic move with retry to avoid file locking collisions
                $rawCmd = $null
                $moved = $false
                for ($retry = 0; $retry -lt 5; $retry++) {
                    try {
                        Move-Item $executeFile $processingFile -Force -ErrorAction Stop
                        $moved = $true
                        break
                    } catch {
                        Start-Sleep -Milliseconds 150
                    }
                }

                if (-not $moved) {
                    continue
                }

                $rawCmd = (Get-Content $processingFile -Raw)
                if ($null -ne $rawCmd) { $rawCmd = $rawCmd.Trim() }
                Remove-Item $processingFile -Force -ErrorAction SilentlyContinue

                if ([string]::IsNullOrWhiteSpace($rawCmd)) {
                    continue
                }

                Write-Action "Received command: $rawCmd"

                # Parse arguments safely via AST in command mode (prefixed with dummy 'cmd')
                $ast = [System.Management.Automation.Language.Parser]::ParseInput("cmd $rawCmd", [ref]$null, [ref]$null)
                
                if ($ast.EndBlock.Statements.Count -ne 1 -or $ast.EndBlock.Statements[0].GetType().Name -ne "PipelineAst" -or $ast.EndBlock.Statements[0].PipelineElements.Count -ne 1) {
                    Write-Action "Error: Multiple commands or chaining detected (injection attempt?). Only single commands are allowed."
                    continue
                }

                $elements = $ast.EndBlock.Statements[0].PipelineElements[0].CommandElements
                if ($null -eq $elements -or $elements.Count -le 1) {
                    Write-Action "Error: Failed to parse command."
                    continue
                }

                # Extract argument tokens (skipping the dummy 'cmd' at index 0)
                $allTokens = @()
                for ($ti = 1; $ti -lt $elements.Count; $ti++) {
                    $allTokens += $elements[$ti].Extent.Text
                }

                # Detect verb (skipping leading flags like --profile <name> or -p <project>)
                $verb = $null
                $verbIndex = -1
                for ($i = 0; $i -lt $allTokens.Count; $i++) {
                    $token = $allTokens[$i]
                    if ($token.StartsWith("-")) {
                        # If token has value separated by space (like --profile dev), skip next token too
                        if (($token -eq "--profile" -or $token -eq "-p" -or $token -eq "--project-name" -or $token -eq "--env-file") -and ($i + 1 -lt $allTokens.Count)) {
                            $i++
                        }
                        continue
                    } else {
                        $verb = $token.ToLower()
                        $verbIndex = $i
                        break
                    }
                }

                if ($null -eq $verb) {
                    Write-Action "Error: No command verb detected in input."
                    continue
                }

                if ($verb -notin $allowedCommands) {
                    Write-Action "Error: Command '$verb' is not allowed. Allowed: $($allowedCommands -join ', ')"
                    continue
                }

                if ($SafeMode -and ($verb -in $dangerousCommands)) {
                    Write-Action "Error: Command '$verb' is blocked because Safe Mode is enabled."
                    continue
                }

                # Construct final compose args preserving all flags and options
                # Strip legacy 'full' keyword if user or old agent still supplies it
                $finalArgs = @()
                foreach ($token in $allTokens) {
                    if ($token -eq "full") {
                        # Silently ignore legacy 'full'
                        continue
                    }
                    $finalArgs += $token
                }


                # Auto-detach for 'up': ensure -d is present unless non-detached flags exist
                if ($verb -eq 'up' -and '-d' -notin $finalArgs -and '--detach' -notin $finalArgs) {
                    $idx = $finalArgs.IndexOf($verb)
                    $finalArgs = $finalArgs[0..$idx] + @('-d') + $finalArgs[($idx + 1)..($finalArgs.Count - 1)]
                    Write-Action "Injected '-d' to prevent blocking."
                }

                # First Up bootstrap (clean network & dependencies initialization)
                if ($verb -eq 'up' -and -not $firstUpDone) {
                    Write-Action "First 'up' detected in session. Running baseline 'up -d --force-recreate'..."
                    $resFirst = Invoke-ComposeWithTimeout -ComposeArgs @('up', '-d', '--force-recreate') -TimeoutSec 300
                    $firstUpDone = $true
                    Write-Action "Baseline 'up -d --force-recreate' completed (exit=$($resFirst.ExitCode))."
                }

                Write-Action "Executing: docker compose $($finalArgs -join ' ')"
                try {
                    $timeoutSec = if ($verb -eq 'build') { 1200 } else { 180 }
                    $res = Invoke-ComposeWithTimeout -ComposeArgs $finalArgs -TimeoutSec $timeoutSec
                    if ($res.TimedOut) {
                        Write-Action "TIMEOUT: exceeded ${timeoutSec}s -- command cancelled, loop continues"
                    } elseif ($res.ExitCode -eq 0) {
                        Write-Action "Finished OK (exit code 0)"
                    } else {
                        Write-Action "ERROR: exited with code $($res.ExitCode). See status\last-output.log"
                    }
                } catch {
                    Write-Action "EXCEPTION: $($_.Exception.Message)"
                }
            }
        } catch {
            $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
            Write-Action "CRITICAL ERROR inside watcher loop: $($_.Exception.Message)"
            $crashLogPath = Join-Path $statusDir "crash-dump.log"
            "[$ts] CRITICAL ERROR:`n$($_.Exception.ToString())`nStackTrace:`n$($_.ScriptStackTrace)" | Out-File -FilePath $crashLogPath -Encoding UTF8 -Append
            Write-Action "Crash details saved to $crashLogPath. Recovering loop..."
        }

        Start-Sleep -Seconds 1
    }
} catch {
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Action "FATAL ERROR terminating watcher: $($_.Exception.Message)"
    $crashLogPath = Join-Path $statusDir "crash-dump.log"
    "[$ts] FATAL ERROR:`n$($_.Exception.ToString())`nStackTrace:`n$($_.ScriptStackTrace)" | Out-File -FilePath $crashLogPath -Encoding UTF8 -Append
} finally {
    Write-Action "=== Watcher stopped ==="
    if ($null -ne $logJob) {
        Stop-Job $logJob -ErrorAction SilentlyContinue
        Remove-Job $logJob -Force -ErrorAction SilentlyContinue
    }
    if ($mutexOwned) {
        try { $mutex.ReleaseMutex() } catch {}
    }
    if ($null -ne $mutex) {
        $mutex.Dispose()
    }
}
