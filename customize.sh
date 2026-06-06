#!/system/bin/sh
SKIPUNZIP=0
MODPATH="/data/adb/modules/sara_sre_agent"

ui_print "- 正在初始化 SARA SRE Agent..."
ui_print "- 环境: HyperOS / GKI 安全增强版"

# Set permissions
set_perm_recursive "$MODPATH" 0 0 0755 0755
set_perm_recursive "$MODPATH/scripts" 0 0 0755 0755

ui_print "- 安装完成，SARA 代理将在下次重启后自动启动。"
