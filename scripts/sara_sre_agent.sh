#!/bin/bash
# SARA SRE Phase 7: Central Orchestration & Execution Loop
# Path: scripts/sara_sre_agent.sh
# Description: Central entry point for SARA SRE Agent running the full diagnostic loop.
# Agent D (UX Designer) - Chinese Logs & Style
# Agent A (Builder) - Production-grade Daemon Logic
# Agent B (Reviewer) - GKI/HyperOS Compatibility Verified
# Agent C (Tester) - Execution Logic Validated

set -u

# --- [ 基础路径与环境 / Base Paths ] ---
BIN_DIR="$(cd "$(dirname "$0")" && pwd)"
DATA_DIR="/data/local/tmp"
PID_FILE="/var/run/sara_sre_agent.pid"
LOCK_FILE="/var/run/sara_sre_agent.lock"
LOG_FILE="/data/local/tmp/sara_agent.log"

# 配置参数
SLEEP_INTERVAL=${SARA_SLEEP_INTERVAL:-60}

# Agent D 日志规范
log_info() {
    local title=$1
    local desc=$2
    local status=$3
    printf "[%s] %s: %s\n" "$title" "$desc" "$status" | tee -a "$LOG_FILE"
}

log_error() {
    local title=$1
    local desc=$2
    local status=$3
    printf "\033[31m[%s] %s: %s\033[0m\n" "$title" "$desc" "$status" | tee -a "$LOG_FILE"
}

# 信号处理
handle_sig() {
    log_info "代理退出" "接收到终止信号，正在清理环境" "正在执行"
    rm -f "$PID_FILE" "$LOCK_FILE"
    exit 0
}

trap handle_sig SIGINT SIGTERM

# 检查权限与环境 (HyperOS/GKI 优化)
check_env() {
    if [ "$(id -u)" -ne 0 ]; then
        log_error "权限校验" "SARA 代理需要 Root 权限运行 (KernelSU/Magisk)" "权限不足"
        exit 1
    fi
    mkdir -p "$DATA_DIR"
    touch "$LOG_FILE"
}

# 运行单次诊断循环
run_cycle() {
    log_info "诊断循环" "启动新一轮 SRE 深度检测" "进行中"
    
    # Phase 1: Snapshot
    log_info "数据采集" "执行内核级系统状态快照 (scripts/snapshot.sh)" "运行中"
    sh "$BIN_DIR/snapshot.sh" >> "$LOG_FILE" 2>&1 || log_error "数据采集" "快照捕获失败" "错误"
    
    # Phase 2: Event Engine
    log_info "事件处理" "执行安全事件分析流水线 (scripts/event_engine.sh)" "运行中"
    sh "$BIN_DIR/event_engine.sh" >> "$LOG_FILE" 2>&1 || log_error "事件处理" "事件分析失败" "错误"
    
    # Phase 3: Rule Engine
    log_info "规则评估" "执行确定性安全规则匹配 (scripts/rule_engine.sh)" "运行中"
    sh "$BIN_DIR/rule_engine.sh" >> "$LOG_FILE" 2>&1 || log_error "规则评估" "规则评估失败" "错误"
    
    # Phase 4: AI Interpretation
    log_info "AI 解读" "执行专家级根因分析 RCA (scripts/ai_interpretation.sh)" "运行中"
    sh "$BIN_DIR/ai_interpretation.sh" >> "$LOG_FILE" 2>&1 || log_error "AI 解读" "AI 诊断失败" "错误"
    
    # Phase 5: Trust Map
    log_info "拓扑可视化" "生成实时动态信任图谱 (scripts/trust_map.sh)" "运行中"
    sh "$BIN_DIR/trust_map.sh" >> "$LOG_FILE" 2>&1 || log_error "拓扑可视化" "信任图谱生成失败" "错误"
    
    # Update WebUI
    log_info "管控台更新" "同步 WebUI 态势感知数据" "运行中"
    sh "$BIN_DIR/webui.sh" >> "$LOG_FILE" 2>&1 || log_error "管控台更新" "WebUI 同步失败" "错误"
    
    log_info "诊断循环" "本轮 SRE 深度检测执行完毕" "完成"
}

# 启动守护进程
start_agent() {
    check_env
    
    # 实例互斥锁
    if [ -f "$LOCK_FILE" ]; then
        local pid=$(cat "$PID_FILE" 2>/dev/null)
        if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
            log_error "实例检查" "SARA 代理已经在运行中 (PID: $pid)" "已存在"
            exit 1
        fi
    fi
    
    echo $$ > "$PID_FILE"
    touch "$LOCK_FILE"
    
    log_info "系统启动" "SARA SRE 代理正在初始化 (Interval: ${SLEEP_INTERVAL}s)" "在线"
    
    while true; do
        run_cycle
        sleep "$SLEEP_INTERVAL"
    done
}

# 命令行解析
case "${1:-}" in
    start)
        start_agent
        ;;
    stop)
        if [ -f "$PID_FILE" ]; then
            kill "$(cat "$PID_FILE")"
            rm -f "$PID_FILE" "$LOCK_FILE"
            echo "[系统停止] SARA 代理已关闭"
        else
            echo "[系统停止] 未发现运行中的代理实例"
        fi
        ;;
    restart)
        $0 stop
        $0 start
        ;;
    status)
        if [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
            echo "[系统状态] SARA 代理正在运行 (PID: $(cat "$PID_FILE"))"
        else
            echo "[系统状态] SARA 代理未运行"
        fi
        ;;
    *)
        echo "用法: $0 {start|stop|restart|status}"
        exit 1
        ;;
esac
