#!/bin/bash
# SARA SRE 代理 v1 - 事件处理引擎
# 用途: 解析 system_snapshot.json 并生成结构化安全事件。

# 允许通过环境变量覆盖路径以便在测试环境中运行
INPUT_FILE="${SARA_INPUT_FILE:-/data/local/tmp/system_snapshot.json}"
OUTPUT_FILE="${SARA_OUTPUT_FILE:-/data/local/tmp/sara_events.json}"

log_info() {
    # Agent D (UX Designer) Style: [标题] 描述: 状态
    # 保持中文输出与硬核术语 (VFS Layer, SUSFS, GKI, SELinux avc, TEE, Binder lock contention)
    printf "[%-18s] %-40s: %s\n" "$1" "$2" "$3"
}

if [ ! -f "$INPUT_FILE" ]; then
    echo "[错误] 找不到快照文件: $INPUT_FILE"
    exit 1
fi

# 简单解析 JSON (使用 grep/sed，确保在 Android minimal shell 环境下的兼容性)
get_json_val() {
    local key=$1
    grep -o "\"$key\":[^,}]*" "$INPUT_FILE" | cut -d':' -f2- | tr -d '" ' | head -n1
}

# 提取关键指标
SUSFS_ACTIVE=$(get_json_val "active")
NAMESPACE_LEAK=$(get_json_val "leak_detected")
SELINUX_STATE=$(get_json_val "selinux_state")
LSPOSED_DETECTED=$(get_json_val "lsposed_detected")
BINDER_STATS_AVAILABLE=$(get_json_val "stats_available")
BINDER_TX=$(get_json_val "total_transactions")

EVENTS_JSON="["
FIRST_EVENT=true

add_event() {
    local id=$1
    local priority=$2
    local title=$3
    local desc=$4
    local status=$5
    
    if [ "$FIRST_EVENT" = false ]; then
        EVENTS_JSON="$EVENTS_JSON,"
    fi
    
    # 构建 JSON，包含中英描述 (_description 字段由 Agent D 定义)
    EVENTS_JSON="$EVENTS_JSON
  {
    \"id\": \"$id\",
    \"priority\": \"$priority\",
    \"title\": \"$title\",
    \"description\": \"$desc\",
    \"status\": \"$status\",
    \"_description\": \"$title ($id) / Structural Security Event\",
    \"timestamp\": $(date +%s)
  }"
    FIRST_EVENT=false
    
    # Terminal Output (UX Constraint: Agent D - "system-settings style")
    log_info "$title" "$desc" "$status"
}

echo "========================================================================"
echo "SARA SRE 事件引擎 - 正在处理系统安全事件 (Industrial-grade Mode)"
echo "========================================================================"

# 1. SUSFS 检查 (VFS Layer / GKI)
if [ "$SUSFS_ACTIVE" = "true" ]; then
    add_event "susfs_active" "INFO" "VFS Layer" "内核级 SUSFS 隐藏已激活" "正常 (Active)"
else
    add_event "susfs_active" "WARNING" "VFS Layer" "未检测到 SUSFS 节点，内核加固缺失" "警告 (Inactive)"
fi

# 2. 命名空间泄漏 (Mount Isolation)
if [ "$NAMESPACE_LEAK" = "true" ]; then
    add_event "namespace_leak" "CRITICAL" "Mount Namespace" "检测到命名空间泄漏，存在跨隔离访问风险" "异常 (Leak Detected)"
else
    add_event "namespace_leak" "INFO" "Mount Namespace" "命名空间挂载点隔离完整 (Strict)" "正常 (Isolated)"
fi

# 3. SELinux 状态 (SELinux avc / TEE Attestation)
if [[ "$SELINUX_STATE" =~ "Permissive" ]] || [[ "$SELINUX_STATE" =~ "宽容" ]]; then
    add_event "selinux_denial" "HIGH" "SELinux Policy" "SELinux 处于 Permissive 模式，TEE 验证可能失败" "风险 (Permissive)"
else
    add_event "selinux_denial" "INFO" "SELinux Policy" "SELinux 处于 Enforcing 模式，符合强制访问控制标准" "正常 (Enforcing)"
fi

# 4. Hook 探测 (Runtime Security)
if [ "$LSPOSED_DETECTED" = "true" ]; then
    add_event "hook_detection" "HIGH" "Runtime Security" "检测到 LSPosed/Zygisk 注入，系统完整性已降级" "异常 (Hook Detected)"
else
    add_event "hook_detection" "INFO" "Runtime Security" "未检测到活跃的 Hook 框架注入" "安全 (Clean)"
fi

# 5. Binder 锁竞争 (Binder lock contention)
if [ "$BINDER_STATS_AVAILABLE" = "true" ]; then
    if [ "$BINDER_TX" -gt 10000 ]; then
         add_event "binder_stall" "MEDIUM" "Binder IPC" "检测到大规模 Binder 事务并发，可能触发锁竞争" "拥塞 (High Load)"
    else
         add_event "binder_stall" "INFO" "Binder IPC" "Binder IPC 通信指标处于健康水平" "流畅 (Low Load)"
    fi
fi

EVENTS_JSON="$EVENTS_JSON
]"

echo "$EVENTS_JSON" > "$OUTPUT_FILE"
echo "========================================================================"
echo "事件处理完成。生成事件总数: $(grep -c "\"id\":" "$OUTPUT_FILE" || echo 0)"
echo "输出文件路径: $OUTPUT_FILE"
echo "========================================================================"
