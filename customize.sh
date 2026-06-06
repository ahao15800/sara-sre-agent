#!/sbin/sh

# 检查环境变量
[ -z "$MODPATH" ] && MODPATH="/data/adb/modules/sara_sre_agent"

# Simplified Chinese output helper
ui_print() {
    echo "$1"
}

ui_print "- 正在安装 SARA SRE Agent (ReSukiSU 优化版)"
ui_print "- 目标设备: Xiaomi 17 Pro Max / Sara"

# 设置基础权限
ui_print "- 正在设置核心脚本权限..."
set_perm_recursive "$MODPATH" 0 0 0755 0644
set_perm "$MODPATH/sre_agent" 0 0 0755

# 检查内核支持
if [ -f "/sys/kernel/tracing/trace" ]; then
    ui_print "- 检测到内核追踪支持: 兼容"
else
    ui_print "- 警告: 内核追踪支持未检测到，部分 SRE 功能可能受限"
fi

ui_print "- 安装完成。真正的硬核玩家，从不看 UI。"