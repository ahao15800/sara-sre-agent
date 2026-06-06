#!/bin/bash
# SARA SRE 代理 v1 - AI 解读层 (AI Interpretation Layer)
# 路径: scripts/ai_interpretation.sh

RULES_FILE="${SARA_RULES_FILE:-/data/local/tmp/sara_rules_assessment.json}"
EVENTS_FILE="${SARA_EVENTS_FILE:-/data/local/tmp/sara_events.json}"
OUTPUT_FILE="${SARA_AI_OUTPUT:-/data/local/tmp/sara_ai_interpretation.json}"

log_info() {
    printf "[%-18s] %-40s: %s\n" "$1" "$2" "$3"
}

if [ ! -f "$RULES_FILE" ] || [ ! -f "$EVENTS_FILE" ]; then
    echo "[错误] 缺失前置数据，AI 引擎无法运行。"
    exit 1
fi

get_json_val() {
    grep -o "\"$1\":[^,}]*" "$2" | cut -d':' -f2- | tr -d '" ' | head -n1
}

has_event() {
    grep -q "\"id\": \"$1\"" "$EVENTS_FILE"
}

RCA_RESULTS=""
REMEDIATION_ADVICE=""

if has_event "namespace_leak" && has_event "hook_detection"; then
    log_info "根因分析 (RCA)" "系统性环境破坏：隔离失效与 Hook 并存" "高危"
    RCA_RESULTS="检测到命名空间泄漏与运行时 Hook 注入的联合攻击向量。"
    REMEDIATION_ADVICE="建议启用内核级 SUSFS 并配置严格的 Mount Isolation。"
fi

if [ -z "$RCA_RESULTS" ]; then
    RCA_RESULTS="未发现显著的系统性风险根源。"
    REMEDIATION_ADVICE="继续保持当前的加固策略。"
fi

cat <<JSON_EOF > "$OUTPUT_FILE"
{
  "timestamp": $(date +%s),
  "diagnostic_report": {
    "root_cause_analysis": "$RCA_RESULTS",
    "remediation_advice": "$REMEDIATION_ADVICE"
  }
}
JSON_EOF

log_info "诊断结论" "根因分析报告" "已生成"
