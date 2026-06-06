#!/system/bin/sh
# SARA SRE Agent v1 - Snapshot Layer
# Path: /data/adb/modules/sara_sre_agent/scripts/snapshot.sh (Inside module) or scripts/snapshot.sh in repo
# Purpose: Deep system-level security, mount namespace, and kernel state capture on rooted Android.
# Output: /data/local/tmp/system_snapshot.json

set -u

OUTPUT_FILE="/data/local/tmp/system_snapshot.json"
TIMESTAMP=$(date +%s)

# 1. Initialize JSON fields
SUSFS_EXISTS=false
SUSFS_VERSION="null"
VFS_HIDING=0
SUSFS_SUS_PATH_COUNT=0

NAMESPACE_LEAK=false
INIT_MOUNTS_COUNT=0
SELF_MOUNTS_COUNT=0
MODULE_MOUNTS_COUNT=0

SELINUX_STATE="unknown"
LSPOSED_DETECTED=false
BINDER_STATS_AVAILABLE=false
BINDER_TRANSACTION_COUNT=0

# 2. Probe SUSFS (Kernel VFS Hiding)
if [ -d "/sys/kernel/susfs" ]; then
    SUSFS_EXISTS=true
    if [ -f "/sys/kernel/susfs/susfs_version" ]; then
        SUSFS_VERSION=$(cat /sys/kernel/susfs/susfs_version | tr -d '\r\n')
    fi
    if [ -f "/sys/kernel/susfs/vfs_hiding_enabled" ]; then
        VFS_HIDING=$(cat /sys/kernel/susfs/vfs_hiding_enabled | tr -d '\r\n')
    fi
    if [ -f "/sys/kernel/susfs/sus_path_count" ]; then
        SUSFS_SUS_PATH_COUNT=$(cat /sys/kernel/susfs/sus_path_count | tr -d '\r\n')
    fi
fi

# 3. Analyze Mount Namespace Leakage
# Compare init process (PID 1) mounts with the current shell namespace mounts
if [ -f "/proc/1/mounts" ]; then
    INIT_MOUNTS_COUNT=$(wc -l < /proc/1/mounts)
fi
if [ -f "/proc/self/mounts" ]; then
    SELF_MOUNTS_COUNT=$(wc -l < /proc/self/mounts)
    # Count Magisk/KernelSU modules leaked into current mount namespace
    MODULE_MOUNTS_COUNT=$(grep -c "sara" /proc/self/mounts || true)
fi

# Determine namespace leak based on raw mount count discrepancies and unisolated module paths
DIFF=$((SELF_MOUNTS_COUNT - INIT_MOUNTS_COUNT))
if [ "$DIFF" -gt 15 ] || [ "$MODULE_MOUNTS_COUNT" -gt 0 ]; then
    NAMESPACE_LEAK=true
fi

# 4. Read SELinux Enforce State
if [ -f "/sys/fs/selinux/enforce" ]; then
    SELINUX_VAL=$(cat /sys/fs/selinux/enforce)
    if [ "$SELINUX_VAL" -eq 1 ]; then
        SELINUX_STATE="Enforcing"
    else
        SELINUX_STATE="Permissive"
    fi
else
    SELINUX_STATE=$(getenforce 2>/dev/null || echo "unknown")
fi

# 5. Detect LSPosed/Zygisk Framework Presence
if grep -q -E "lsposed|zygisk|zygote" /proc/self/maps 2>/dev/null; then
    LSPOSED_DETECTED=true
fi

# 6. Check Binder Transaction Count
if [ -f "/sys/kernel/debug/binder/stats" ]; then
    BINDER_STATS_AVAILABLE=true
    # Extract total transaction counts from binder debug stats
    BINDER_TRANSACTION_COUNT=$(grep -oE "BC_TRANSACTION:[0-9]+" /sys/kernel/debug/binder/stats | cut -d':' -f2 | awk '{s+=$1} END {print s}' || echo "0")
fi

# 7. Calculate Trust Score (Deductively)
TRUST_SCORE=100
if [ "$SUSFS_EXISTS" = "false" ]; then
    TRUST_SCORE=$((TRUST_SCORE - 30))
fi
if [ "$NAMESPACE_LEAK" = "true" ]; then
    TRUST_SCORE=$((TRUST_SCORE - 40))
fi
if [ "$SELINUX_STATE" = "Permissive" ]; then
    TRUST_SCORE=$((TRUST_SCORE - 15))
fi
if [ "$TRUST_SCORE" -lt 0 ]; then
    TRUST_SCORE=0
fi

# 8. Output Structured JSON
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
  "binder_radar": {
    "stats_available": $BINDER_STATS_AVAILABLE,
    "total_transactions": ${BINDER_TRANSACTION_COUNT:-0}
  },
  "overall_trust_score": $TRUST_SCORE
}
EOF

chmod 0644 "$OUTPUT_FILE"
echo "Snapshot saved to $OUTPUT_FILE"
