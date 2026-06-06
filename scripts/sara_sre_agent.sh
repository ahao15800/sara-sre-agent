#!/system/bin/sh
# SARA SRE Agent - Central Agent (Refactored for KernelSU)
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DATA_DIR="/data/local/tmp"
PID_FILE="/data/local/tmp/sara_sre_agent.pid"
LOCK_FILE="/data/local/tmp/sara_sre_agent.lock"
LOG_FILE="/data/local/tmp/sara_agent.log"
SLEEP_INTERVAL=${SARA_SLEEP_INTERVAL:-60}

log_info() { printf "[%s] %s: %s\n" "$1" "$2" "$3" | tee -a "$LOG_FILE"; }

handle_sig() { rm -f "$PID_FILE" "$LOCK_FILE"; exit 0; }
trap handle_sig SIGINT SIGTERM

run_cycle() {
    log_info "诊断循环" "启动 SRE 检测" "运行中"
    sh "$SCRIPT_DIR/snapshot.sh" >> "$LOG_FILE" 2>&1
    sh "$SCRIPT_DIR/event_engine.sh" >> "$LOG_FILE" 2>&1
    sh "$SCRIPT_DIR/rule_engine.sh" >> "$LOG_FILE" 2>&1
    sh "$SCRIPT_DIR/ai_interpretation.sh" >> "$LOG_FILE" 2>&1
    sh "$SCRIPT_DIR/trust_map.sh" >> "$LOG_FILE" 2>&1
    sh "$SCRIPT_DIR/webui.sh" >> "$LOG_FILE" 2>&1
}

case "${1:-}" in
    start)
        echo $$ > "$PID_FILE"
        touch "$LOCK_FILE"
        while true; do run_cycle; sleep "$SLEEP_INTERVAL"; done &
        ;;
    stop)
        [ -f "$PID_FILE" ] && kill $(cat "$PID_FILE") && rm -f "$PID_FILE" "$LOCK_FILE"
        ;;
esac
