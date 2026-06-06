#!/bin/bash
# SARA SRE Phase 3: Rule Engine
# Path: scripts/rule_engine.sh

INPUT_FILE="${SARA_EVENTS_FILE:-/data/local/tmp/sara_events.json}"
OUTPUT_FILE="${SARA_RULES_OUTPUT:-/data/local/tmp/sara_rules_assessment.json}"

log_info() {
    printf "[%-18s] %-40s: %s\n" "$1" "$2" "$3"
}

if [ ! -f "$INPUT_FILE" ]; then
    echo "[错误] 找不到事件文件: $INPUT_FILE"
    exit 1
fi

has_event() {
    grep -q "\"id\": \"$1\"" "$INPUT_FILE"
}

RISK_SCORE=100
CRITICAL_THREATS=""
ASSESSMENT_SUMMARY=""

# 1. 组合攻击面
if has_event "namespace_leak" && has_event "hook_detection"; then
    log_info "关联风险" "检测到 Critical Security Threat (复合攻击)" "极高危 (风险分数: 95)"
    RISK_SCORE=$((RISK_SCORE - 95))
    CRITICAL_THREATS="${CRITICAL_THREATS}Critical Security Threat (Namespace Leak + Hook Injection); "
else
    if has_event "namespace_leak"; then
        log_info "独立风险" "检测到 Mount Namespace 隔离失效" "扣除 40 分"
        RISK_SCORE=$((RISK_SCORE - 40))
    fi
    if has_event "hook_detection"; then
        log_info "独立风险" "检测到运行时 Hook 框架 (LSPosed/Zygisk)" "扣除 30 分"
        RISK_SCORE=$((RISK_SCORE - 30))
    fi
fi

# 2. SELinux
if has_event "selinux_denial"; then
    log_info "TEE Validity" "SELinux Permissive 导致 TEE 验证风险" "高概率验证失败"
    RISK_SCORE=$((RISK_SCORE - 20))
    ASSESSMENT_SUMMARY="${ASSESSMENT_SUMMARY}TEE Attestation risk due to SELinux Permissive; "
fi

# 3. 内核加固
if ! has_event "susfs_active"; then
    log_info "GKI Security" "内核缺少 SUSFS (VFS Layer) 加固节点" "建议部署"
    RISK_SCORE=$((RISK_SCORE - 10))
fi

# 4. 稳定性
if has_event "binder_stall"; then
    log_info "Stability" "检测到 Binder IPC 锁竞争风险" "性能受限"
    RISK_SCORE=$((RISK_SCORE - 5))
fi

[ "$RISK_SCORE" -lt 0 ] && RISK_SCORE=0

LEVEL="LOW"
[ "$RISK_SCORE" -lt 70 ] && LEVEL="MEDIUM"
[ "$RISK_SCORE" -lt 40 ] && LEVEL="HIGH"
[ "$RISK_SCORE" -lt 15 ] && LEVEL="CRITICAL"

cat <<EOF > "$OUTPUT_FILE"
{
  "timestamp": $(date +%s),
  "risk_assessment": {
    "score": $RISK_SCORE,
    "level": "$LEVEL",
    "critical_threats": "${CRITICAL_THREATS%; }",
    "summary": "${ASSESSMENT_SUMMARY%; }"
  }
}
EOF
