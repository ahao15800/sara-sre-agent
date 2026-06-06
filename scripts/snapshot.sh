#!/bin/bash
# SARA SRE Phase 1: System Snapshot Engine
# Path: scripts/snapshot.sh

set -u

TIMESTAMP=$(date +%s)
OUTPUT_FILE="${SARA_SNAPSHOT_FILE:-/data/local/tmp/system_snapshot.json}"

mkdir -p "$(dirname "$OUTPUT_FILE")"

SUSFS_EXISTS=false
SUSFS_VERSION="null"
VFS_HIDING=0
SUSFS_SUS_PATH_COUNT=0
NAMESPACE_LEAK=false
INIT_MOUNTS_COUNT=0
SELF_MOUNTS_COUNT=0
MODULE_MOUNTS_COUNT=0
SELINUX_STATE="未知"
LSPOSED_DETECTED=false
BINDER_STATS_AVAILABLE=false
BINDER_TRANSACTION_COUNT=0

# 2. 探测 SUSFS
if [ -d "/sys/kernel/susfs" ]; then
    SUSFS_EXISTS=true
    SUSFS_VERSION=$(cat /sys/kernel/susfs/susfs_version 2>/dev/null | tr -d '\r\n' || echo "unknown")
    VFS_HIDING=$(cat /sys/kernel/susfs/vfs_hiding_enabled 2>/dev/null | tr -d '\r\n' || echo "0")
    SUSFS_SUS_PATH_COUNT=$(cat /sys/kernel/susfs/sus_path_count 2>/dev/null | tr -d '\r\n' || echo "0")
fi

# 3. 命名空间
if [ -f "/proc/1/mounts" ] && [ -f "/proc/self/mounts" ]; then
    INIT_MOUNTS_COUNT=$(wc -l < /proc/1/mounts)
    SELF_MOUNTS_COUNT=$(wc -l < /proc/self/mounts)
    MODULE_MOUNTS_COUNT=$(grep -c -E "sara|magisk|ksu" /proc/self/mounts || true)
    DIFF=$((SELF_MOUNTS_COUNT - INIT_MOUNTS_COUNT))
    if [ "$DIFF" -gt 15 ] || [ "$MODULE_MOUNTS_COUNT" -gt 0 ]; then
        NAMESPACE_LEAK=true
    fi
fi

# 4. SELinux
if [ -f "/sys/fs/selinux/enforce" ]; then
    SELINUX_VAL=$(cat /sys/fs/selinux/enforce)
    [ "$SELINUX_VAL" -eq 1 ] && SELINUX_STATE="Enforcing" || SELINUX_STATE="Permissive"
fi

# 5. LSPosed
if [ -f "/proc/self/maps" ]; then
    grep -q -E "lsposed|zygisk|zygote" /proc/self/maps && LSPOSED_DETECTED=true
fi

# 6. Binder
if [ -d "/sys/kernel/debug/binder" ]; then
    BINDER_STATS_AVAILABLE=true
    BINDER_TRANSACTION_COUNT=$(grep -oE "BC_TRANSACTION:[0-9]+" /sys/kernel/debug/binder/stats 2>/dev/null | cut -d':' -f2 | awk '{s+=$1} END {print s}' || echo "0")
fi

# 7. 评分
TRUST_SCORE=100
[ "$SUSFS_EXISTS" = false ] && TRUST_SCORE=$((TRUST_SCORE - 30))
[ "$NAMESPACE_LEAK" = true ] && TRUST_SCORE=$((TRUST_SCORE - 40))
[ "$SELINUX_STATE" = "Permissive" ] && TRUST_SCORE=$((TRUST_SCORE - 15))
[ "$TRUST_SCORE" -lt 0 ] && TRUST_SCORE=0

# 8. JSON
cat <<EOF > "$OUTPUT_FILE"
{
  "timestamp": $TIMESTAMP,
  "kernel_susfs": {
    "active": $SUSFS_EXISTS,
    "version": "$SUSFS_VERSION",
    "vfs_hiding_enabled": $VFS_HIDING,
    "sus_path_count": $SUSFS_SUS_PATH_COUNT
  },
  "mount_namespace": {
    "leak_detected": $NAMESPACE_LEAK,
    "init_mounts_count": $INIT_MOUNTS_COUNT,
    "self_mounts_count": $SELF_MOUNTS_COUNT,
    "module_mounts_count": $MODULE_MOUNTS_COUNT
  },
  "middleware": {
    "selinux_state": "$SELINUX_STATE",
    "lsposed_detected": $LSPOSED_DETECTED
  },
  "binder": {
    "stats_available": $BINDER_STATS_AVAILABLE,
    "total_transactions": ${BINDER_TRANSACTION_COUNT:-0}
  },
  "overall_trust_score": $TRUST_SCORE
}
EOF
