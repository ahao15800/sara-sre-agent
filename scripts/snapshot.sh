#!/system/bin/sh
# SARA SRE 代理 v1 - 系统快照层
# 路径: /data/adb/modules/sara_sre_agent/scripts/snapshot.sh (模块内) 或仓库中的 scripts/snapshot.sh
# 用途: 在已获取 Root 权限的 Android 设备上进行深层系统安全审计、挂载命名空间及内核状态捕获。
# 输出: /data/local/tmp/system_snapshot.json

set -u

OUTPUT_FILE="/data/local/tmp/system_snapshot.json"
TIMESTAMP=$(date +%s)

echo "[系统安全] 正在初始化系统审计环境..."

# 1. 初始化 JSON 字段
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

# 2. 探测 SUSFS (内核级 VFS 隐藏)
echo "[系统安全] 正在检查内核级 SUSFS 状态..."
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
    echo "[系统安全] 内核支持 SUSFS (版本: $SUSFS_VERSION, VFS 隐藏: $VFS_HIDING)"
else
    echo "[系统安全] 未检测到内核级 SUSFS 支持"
fi

# 3. 分析挂载命名空间泄漏
echo "[挂载命名空间] 正在分析挂载点隔离完整性..."
# 对比 init 进程 (PID 1) 与当前 shell 命名空间的挂载点
if [ -f "/proc/1/mounts" ]; then
    INIT_MOUNTS_COUNT=$(wc -l < /proc/1/mounts)
fi
if [ -f "/proc/self/mounts" ]; then
    SELF_MOUNTS_COUNT=$(wc -l < /proc/self/mounts)
    # 统计泄漏到当前命名空间的 Magisk/KernelSU 模块路径
    MODULE_MOUNTS_COUNT=$(grep -c "sara" /proc/self/mounts || true)
fi

# 基于挂载点数量差异及未隔离的模块路径判定命名空间泄漏
DIFF=$((SELF_MOUNTS_COUNT - INIT_MOUNTS_COUNT))
if [ "$DIFF" -gt 15 ] || [ "$MODULE_MOUNTS_COUNT" -gt 0 ]; then
    NAMESPACE_LEAK=true
    echo "[挂载命名空间] 警报：检测到命名空间泄漏 (差异: $DIFF, 关联模块: $MODULE_MOUNTS_COUNT)"
else
    echo "[挂载命名空间] 命名空间隔离正常"
fi

# 4. 读取 SELinux 强制状态
echo "[系统安全] 正在读取 SELinux 配置状态..."
if [ -f "/sys/fs/selinux/enforce" ]; then
    SELINUX_VAL=$(cat /sys/fs/selinux/enforce)
    if [ "$SELINUX_VAL" -eq 1 ]; then
        SELINUX_STATE="强制 (Enforcing)"
    else
        SELINUX_STATE="宽容 (Permissive)"
    fi
else
    # 回退至 getenforce 命令
    RAW_ENFORCE=$(getenforce 2>/dev/null)
    case "$RAW_ENFORCE" in
        "Enforcing") SELINUX_STATE="强制 (Enforcing)" ;;
        "Permissive") SELINUX_STATE="宽容 (Permissive)" ;;
        *) SELINUX_STATE="未知" ;;
    esac
fi
echo "[系统安全] SELinux 当前状态: $SELINUX_STATE"

# 5. 检测 LSPosed/Zygisk 框架存在性
echo "[系统安全] 正在扫描内存地址空间以检测 Hook 框架..."
if grep -q -E "lsposed|zygisk|zygote" /proc/self/maps 2>/dev/null; then
    LSPOSED_DETECTED=true
    echo "[系统安全] 警报：检测到活跃的 Hook 框架 (LSPosed/Zygisk)"
else
    echo "[系统安全] 未发现已知 Hook 框架注入"
fi

# 6. 检查 Binder 事务统计
echo "[Binder 通信] 正在分析 IPC 事务负载..."
if [ -f "/sys/kernel/debug/binder/stats" ]; then
    BINDER_STATS_AVAILABLE=true
    # 从 binder 调试统计中提取总事务计数
    BINDER_TRANSACTION_COUNT=$(grep -oE "BC_TRANSACTION:[0-9]+" /sys/kernel/debug/binder/stats | cut -d':' -f2 | awk '{s+=$1} END {print s}' || echo "0")
    echo "[Binder 通信] 已捕获实时事务数据 (总计: $BINDER_TRANSACTION_COUNT)"
else
    echo "[Binder 通信] 无法访问调试统计接口 (DebugFS 未挂载)"
fi

# 7. 计算综合信任分数 (演绎法)
echo "[快照状态] 正在计算系统信任度评估结果..."
TRUST_SCORE=100
if [ "$SUSFS_EXISTS" = "false" ]; then
    TRUST_SCORE=$((TRUST_SCORE - 30))
fi
if [ "$NAMESPACE_LEAK" = "true" ]; then
    TRUST_SCORE=$((TRUST_SCORE - 40))
fi
if [ "$SELINUX_STATE" = "宽容 (Permissive)" ]; then
    TRUST_SCORE=$((TRUST_SCORE - 15))
fi
if [ "$TRUST_SCORE" -lt 0 ]; then
    TRUST_SCORE=0
fi
echo "[快照状态] 系统信任评估得分: $TRUST_SCORE/100"

# 8. 输出结构化 JSON
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
echo "[快照状态] 系统快照已成功导出至 $OUTPUT_FILE"
