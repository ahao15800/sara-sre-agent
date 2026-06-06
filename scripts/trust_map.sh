#!/bin/bash
# SARA SRE Phase 5: Trust Map Engine (Strict Integration)
# Path: scripts/trust_map.sh

log_info() {
    printf "[%-18s] %-40s: %s\n" "$1" "$2" "$3"
}

SNAPSHOT_FILE="/data/local/tmp/system_snapshot.json"
EVENTS_FILE="/data/local/tmp/sara_events.json"
OUTPUT_SVG="/data/local/tmp/sara_trust_map.svg"
OUTPUT_JSON="/data/local/tmp/sara_trust_map.json"

echo "========================================================================"
echo "SARA SRE 信任拓扑引擎 - 正在生成动态信任图谱 (Production Mode)"
echo "========================================================================"

if [ ! -f "$SNAPSHOT_FILE" ] || [ ! -f "$EVENTS_FILE" ]; then
    echo "[错误] 缺失前置快照或事件数据，无法构建信任图。"
    exit 1
fi

# 状态提取 (基于真实上游数据)
VFS_STATUS="healthy"
grep -q "\"active\":true" "$SNAPSHOT_FILE" || VFS_STATUS="risk"

NS_STATUS="healthy"
grep -q "namespace_leak" "$EVENTS_FILE" && NS_STATUS="breached"

SEL_STATUS="healthy"
grep -q "SELinux Policy" "$EVENTS_FILE" && SEL_STATUS="breached"

ZYGOTE_STATUS="healthy"
grep -q "hook_detection" "$EVENTS_FILE" && ZYGOTE_STATUS="breached"

BINDER_STATUS="healthy"
grep -q "binder_stall" "$EVENTS_FILE" && BINDER_STATUS="risk"

# 颜色映射
GET_COLOR() {
    case $1 in
        "healthy") echo "#52C41A" ;;
        "risk") echo "#FF9C6E" ;;
        "breached") echo "#FF4D4F" ;;
        *) echo "#FFFFFF" ;;
    esac
}

VFS_COLOR=$(GET_COLOR $VFS_STATUS)
NS_COLOR=$(GET_COLOR $NS_STATUS)
SEL_COLOR=$(GET_COLOR $SEL_STATUS)
ZYGOTE_COLOR=$(GET_COLOR $ZYGOTE_STATUS)
BINDER_COLOR=$(GET_COLOR $BINDER_STATUS)

# 生成 SVG
cat <<SVG_EOF > "$OUTPUT_SVG"
<svg width="800" height="500" viewBox="0 0 800 500" xmlns="http://www.w3.org/2000/svg">
    <rect width="100%" height="100%" fill="#141414" rx="12"/>
    <text x="30" y="50" fill="#FFFFFF" font-family="monospace" font-size="24" font-weight="bold">SARA TRUST MAP v1.2</text>
    <g transform="translate(100, 200)">
        <rect width="160" height="80" rx="8" fill="$VFS_COLOR" fill-opacity="0.1" stroke="$VFS_COLOR" stroke-width="3"/>
        <text x="80" y="45" fill="white" font-family="sans-serif" font-size="14" font-weight="bold" text-anchor="middle">VFS (SUSFS)</text>
    </g>
    <g transform="translate(400, 150)">
        <rect width="160" height="80" rx="8" fill="$NS_COLOR" fill-opacity="0.1" stroke="$NS_COLOR" stroke-width="3"/>
        <text x="80" y="45" fill="white" font-family="sans-serif" font-size="14" font-weight="bold" text-anchor="middle">Namespace</text>
    </g>
    <g transform="translate(600, 200)">
        <rect width="160" height="80" rx="8" fill="$SEL_COLOR" fill-opacity="0.1" stroke="$SEL_COLOR" stroke-width="3"/>
        <text x="80" y="45" fill="white" font-family="sans-serif" font-size="14" font-weight="bold" text-anchor="middle">SELinux</text>
    </g>
</svg>
SVG_EOF

cat <<JSON_EOF > "$OUTPUT_JSON"
{
  "timestamp": $(date +%s),
  "node_states": {
    "vfs": "$VFS_STATUS",
    "namespace": "$NS_STATUS",
    "selinux": "$SEL_STATUS"
  }
}
JSON_EOF

log_info "拓扑可视化" "SVG 信任链地图构建" "成功 (PASS)"
echo "========================================================================"
