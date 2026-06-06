#!/system/bin/sh
# SARA SRE Agent - Event Engine (Refactored for KernelSU)
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
INPUT_FILE="${SARA_INPUT_FILE:-/data/local/tmp/system_snapshot.json}"
OUTPUT_FILE="${SARA_OUTPUT_FILE:-/data/local/tmp/sara_events.json}"

log_info() { printf "[%-18s] %-40s: %s\n" "$1" "$2" "$3"; }

if [ ! -f "$INPUT_FILE" ]; then
    echo "[错误] 找不到快照文件: $INPUT_FILE"
    exit 1
fi

get_json_val() {
    local key=$1
    grep -o "\"$key\":[^,}]*" "$INPUT_FILE" | cut -d':' -f2- | tr -d '" ' | head -n1
}

SUSFS_ACTIVE=$(get_json_val "active")
NAMESPACE_LEAK=$(get_json_val "leak_detected")
SELINUX_STATE=$(get_json_val "selinux_state")
LSPOSED_DETECTED=$(get_json_val "lsposed_detected")
BINDER_STATS_AVAILABLE=$(get_json_val "stats_available")
BINDER_TX=$(get_json_val "total_transactions")

EVENTS_JSON="["
FIRST_EVENT=true

add_event() {
    local id=$1 priority=$2 title=$3 desc=$4 status=$5
    [ "$FIRST_EVENT" = false ] && EVENTS_JSON="$EVENTS_JSON,"
    EVENTS_JSON="$EVENTS_JSON
  {
    \"id\": \"$id\",
    \"priority\": \"$priority\",
    \"title\": \"$title\",
    \"description\": \"$desc\",
    \"status\": \"$status\",
    \"timestamp\": $(date +%s)
  }"
    FIRST_EVENT=false
    log_info "$title" "$desc" "$status"
}

echo "========================================================================"
echo "SARA SRE 事件引擎 - 正在处理系统安全事件"
echo "========================================================================"

if [ "$SUSFS_ACTIVE" = "true" ]; then
    add_event "susfs_active" "INFO" "VFS Layer" "内核级 SUSFS 隐藏已激活" "正常 (Active)"
else
    add_event "susfs_active" "WARNING" "VFS Layer" "未检测到 SUSFS 节点，内核加固缺失" "警告 (Inactive)"
fi

if [ "$NAMESPACE_LEAK" = "true" ]; then
    add_event "namespace_leak" "CRITICAL" "Mount Namespace" "检测到命名空间泄漏" "异常 (Leak Detected)"
else
    add_event "namespace_leak" "INFO" "Mount Namespace" "命名空间挂载点隔离完整" "正常 (Isolated)"
fi

if [[ "$SELINUX_STATE" =~ "Permissive" ]]; then
    add_event "selinux_denial" "HIGH" "SELinux Policy" "SELinux 处于 Permissive 模式" "风险 (Permissive)"
else
    add_event "selinux_denial" "INFO" "SELinux Policy" "SELinux 处于 Enforcing 模式" "正常 (Enforcing)"
fi

if [ "$LSPOSED_DETECTED" = "true" ]; then
    add_event "hook_detection" "HIGH" "Runtime Security" "检测到 LSPosed/Zygisk 注入" "异常 (Hook Detected)"
else
    add_event "hook_detection" "INFO" "Runtime Security" "未检测到活跃的 Hook 框架注入" "安全 (Clean)"
fi

if [ "$BINDER_STATS_AVAILABLE" = "true" ]; then
    if [ "${BINDER_TX:-0}" -gt 10000 ]; then
         add_event "binder_stall" "MEDIUM" "Binder IPC" "检测到大规模 Binder 事务并发" "拥塞"
    else
         add_event "binder_stall" "INFO" "Binder IPC" "Binder IPC 通信指标处于健康水平" "流畅"
    fi
fi

EVENTS_JSON="$EVENTS_JSON
]"
echo "$EVENTS_JSON" > "$OUTPUT_FILE"
echo "========================================================================"
