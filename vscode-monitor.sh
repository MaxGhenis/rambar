#!/bin/bash
# VSCode Crash Monitor - logs system state every 10s, detects crashes

LOG_DIR="$HOME/.vscode-monitor"
LOG_FILE="$LOG_DIR/system-state.log"
CRASH_LOG="$LOG_DIR/crashes.log"
mkdir -p "$LOG_DIR"

VSCODE_PID=""

log_state() {
    local ts=$(date '+%Y-%m-%d %H:%M:%S')
    local mem_pressure=$(memory_pressure 2>/dev/null | grep "System-wide memory free" | awk '{print $5}')
    local vscode_rss=$(ps -o rss= -p $(pgrep -f "Visual Studio Code" | head -1) 2>/dev/null | awk '{print $1/1024}')
    local claude_count=$(pgrep -f "claude" | wc -l | tr -d ' ')
    local chrome_rss=$(ps -o rss= -p $(pgrep -f "Google Chrome$" | head -1) 2>/dev/null | awk '{print $1/1024}')
    local swap_used=$(sysctl vm.swapusage 2>/dev/null | awk '{print $7}')
    local load=$(uptime | awk -F'load averages:' '{print $2}' | awk '{print $1}')

    echo "$ts | mem_free=$mem_pressure | vscode_mb=${vscode_rss:-0} | chrome_mb=${chrome_rss:-0} | claude_procs=$claude_count | swap=$swap_used | load=$load" >> "$LOG_FILE"
}

check_crash() {
    local current_pid=$(pgrep -f "Visual Studio Code.app/Contents/MacOS/Electron" | head -1)

    if [[ -n "$VSCODE_PID" && -z "$current_pid" ]]; then
        # VSCode was running but now isn't - potential crash
        local ts=$(date '+%Y-%m-%d %H:%M:%S')
        echo "=== VSCODE CRASH DETECTED: $ts ===" >> "$CRASH_LOG"
        echo "Previous PID: $VSCODE_PID" >> "$CRASH_LOG"

        # Capture system state at crash
        echo "Memory state:" >> "$CRASH_LOG"
        vm_stat >> "$CRASH_LOG" 2>&1
        echo "---" >> "$CRASH_LOG"

        # Check for crash reports
        local latest_crash=$(ls -t ~/Library/Logs/DiagnosticReports/*Code* 2>/dev/null | head -1)
        if [[ -n "$latest_crash" ]]; then
            echo "Crash report: $latest_crash" >> "$CRASH_LOG"
            head -100 "$latest_crash" >> "$CRASH_LOG" 2>/dev/null
        fi

        # Log recent console errors
        echo "Recent VSCode logs:" >> "$CRASH_LOG"
        log show --predicate 'processImagePath contains "Code"' --last 2m 2>/dev/null | tail -50 >> "$CRASH_LOG"

        echo "========================================" >> "$CRASH_LOG"
        echo ""
        echo "⚠️  VSCode crash detected at $ts - logged to $CRASH_LOG"
    fi

    VSCODE_PID="$current_pid"
}

echo "VSCode Monitor started at $(date)"
echo "Logging to: $LOG_FILE"
echo "Crash log: $CRASH_LOG"
echo "Press Ctrl+C to stop"
echo ""

# Initialize
VSCODE_PID=$(pgrep -f "Visual Studio Code.app/Contents/MacOS/Electron" | head -1)
echo "Initial VSCode PID: ${VSCODE_PID:-not running}"

while true; do
    log_state
    check_crash
    sleep 10
done
