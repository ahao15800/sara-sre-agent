#!/bin/bash

##############################################################################
# SARA SRE Agent - One-Click ADB Module Installer
# 真正的硬核安卓开发者工作流: 自动编译 -> ADB推送 -> KernelSU直接安装
# 
# 使用方式: ./flash_adb.sh
# 需要: ADB已连接设备, KernelSU/ReSukiSU已装载
##############################################################################

set -e

# ============================================================================
# ANSI 颜色输出 (Agent D: Simplified Chinese CLI output)
# ============================================================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# ============================================================================
# 配置变量
# ============================================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_SCRIPT="${SCRIPT_DIR}/build_zip.sh"
MODULE_ZIP=""
DEVICE_SERIAL=""
MODULE_NAME="sara_sre_agent"
MODULE_PATH="/data/local/tmp"
TARGET_DEVICE="Xiaomi 17 Pro Max" # 或 Sara

# ============================================================================
# 日志输出函数
# ============================================================================
log_info() {
    echo -e "${CYAN}[ℹ️ 信息]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[✓ 成功]${NC} $1"
}

log_error() {
    echo -e "${RED}[✗ 错误]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[⚠️ 警告]${NC} $1"
}

log_step() {
    echo -e "${BLUE}[→ 步骤]${NC} $1"
}

# ============================================================================
# 检查 ADB 是否可用 (Agent B: Safety - proper error checks)
# ============================================================================
check_adb() {
    log_step "检查 ADB 连接..."
    
    if ! command -v adb &> /dev/null; then
        log_error "ADB 未找到，请先安装 Android SDK Platform Tools"
        exit 1
    fi
    
    local adb_devices=$(adb devices | tail -n +2 | grep -v "^$" | wc -l)
    if [ "$adb_devices" -eq 0 ]; then
        log_error "未检测到已连接的ADB设备"
        log_info "请确保:"
        log_info "  1. USB连接正常"
        log_info "  2. 设备已启用USB调试"
        log_info "  3. 已在设备上授权此PC"
        exit 1
    fi
    
    # 获取设备序列号
    DEVICE_SERIAL=$(adb devices | tail -n +2 | grep -v "^$" | head -n1 | awk '{print $1}')
    
    log_success "ADB 已连接: $DEVICE_SERIAL"
}

# ============================================================================
# 验证设备型号 (检查是否为目标设备)
# ============================================================================
verify_device_model() {
    log_step "验证设备型号..."
    
    local device_model=$(adb shell getprop ro.product.model 2>/dev/null || echo "未知")
    local device_name=$(adb shell getprop ro.build.product 2>/dev/null || echo "未知")
    
    log_info "检测到设备型号: $device_model (代号: $device_name)"
    
    # 宽松检查 (Sara/Xiaomi 17 Pro Max)
    if [[ "$device_model" == *"Sara"* ]] || [[ "$device_model" == *"Xiaomi 17 Pro Max"* ]] || [[ "$device_name" == *"sara"* ]]; then
        log_success "设备验证成功: 这是目标设备"
    else
        log_warn "检测到的设备可能不是 Sara/Xiaomi 17 Pro Max"
        read -p "是否继续? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_error "用户取消操作"
            exit 1
        fi
    fi
}

# ============================================================================
# 检查 KernelSU/ReSukiSU 是否已安装
# ============================================================================
check_kernelsu() {
    log_step "检查 KernelSU/ReSukiSU 安装状态..."
    
    local has_ksud=$(adb shell "command -v ksud 2>/dev/null || echo no" | grep -v "^$" | head -n1)
    local has_su=$(adb shell "command -v su 2>/dev/null || echo no" | grep -v "^$" | head -n1)
    
    if [[ "$has_ksud" == "no" ]] && [[ "$has_su" == "no" ]]; then
        log_error "设备上未检测到 KernelSU 或 ReSukiSU"
        log_info "请先在设备上安装 KernelSU 或 ReSukiSU 管理器"
        exit 1
    fi
    
    log_success "检测到 Root 权限管理系统"
}

# ============================================================================
# 编译 ZIP 包 (Agent A: Complete implementation)
# ============================================================================
build_module_zip() {
    log_step "执行模块编译..."
    
    if [ ! -f "$BUILD_SCRIPT" ]; then
        log_error "找不到编译脚本: $BUILD_SCRIPT"
        exit 1
    fi
    
    if ! bash "$BUILD_SCRIPT"; then
        log_error "模块编译失败"
        exit 1
    fi
    
    # 查找生成的 ZIP 文件
    MODULE_ZIP=$(find "$SCRIPT_DIR" -maxdepth 1 -name "sara_sre_agent*.zip" -type f -printf '%T@ %p\n' | sort -rn | head -n1 | cut -d' ' -f2-)
    
    if [ -z "$MODULE_ZIP" ] || [ ! -f "$MODULE_ZIP" ]; then
        log_error "未找到编译后的 ZIP 文件"
        exit 1
    fi
    
    log_success "模块编译完成: $(basename "$MODULE_ZIP")"
}

# ============================================================================
# 推送 ZIP 到设备 (Agent C: Test the shell logic)
# ============================================================================
push_zip_to_device() {
    log_step "推送 ZIP 到设备 ($MODULE_PATH/)..."
    
    local zip_filename=$(basename "$MODULE_ZIP")
    local remote_path="$MODULE_PATH/$zip_filename"
    
    # 确保远程目录存在
    adb shell "mkdir -p $MODULE_PATH" || true
    
    if ! adb push "$MODULE_ZIP" "$remote_path"; then
        log_error "推送 ZIP 失败"
        exit 1
    fi
    
    log_success "ZIP 已推送: $remote_path"
}

# ============================================================================
# 检查 Root 权限
# ============================================================================
check_root_access() {
    log_step "检查 Root 权限..."
    
    local root_check=$(adb shell "id -u" 2>/dev/null || echo "999")
    
    if [ "$root_check" = "0" ]; then
        log_success "已获得 Root 权限"
        return 0
    else
        log_warn "当前无 Root 权限，将尝试通过 su 获取"
        return 1
    fi
}

# ============================================================================
# 直接安装模块 - 方案 A: 使用 ksud module install
# ============================================================================
install_via_ksud() {
    log_step "尝试方案 A: 使用 ksud 直接安装..."
    
    local zip_filename=$(basename "$MODULE_ZIP")
    local remote_path="$MODULE_PATH/$zip_filename"
    
    # 尝试直接调用 ksud
    if adb shell "ksud module install '$remote_path'" 2>/dev/null; then
        log_success "模块通过 ksud 安装成功!"
        log_info "安装的模块位置: /data/adb/modules/$MODULE_NAME/"
        return 0
    else
        log_warn "ksud 安装失败或不可用，将尝试方案 B"
        return 1
    fi
}

# ============================================================================
# 直接安装模块 - 方案 B: 手动模拟 ksud 安装流程
# ============================================================================
install_via_manual() {
    log_step "尝试方案 B: 手动模拟 KernelSU 安装流程..."
    
    local zip_filename=$(basename "$MODULE_ZIP")
    local remote_path="$MODULE_PATH/$zip_filename"
    local modules_update_dir="/data/adb/modules_update/$MODULE_NAME"
    local modules_dir="/data/adb/modules/$MODULE_NAME"
    local work_dir="/data/local/tmp/sara_install_work"
    
    # 创建临时工作目录
    log_info "创建临时工作目录..."
    adb shell "mkdir -p $work_dir" || true
    
    # 解压 ZIP
    log_info "解压模块 ZIP..."
    if ! adb shell "cd $work_dir && unzip -q '$remote_path'"; then
        log_error "解压 ZIP 失败"
        return 1
    fi
    
    # 验证 install.sh 存在
    if ! adb shell "test -f $work_dir/install.sh"; then
        log_error "ZIP 中不存在 install.sh"
        return 1
    fi
    
    # 执行 install.sh
    log_info "执行安装脚本..."
    adb shell "cd $work_dir && bash install.sh" || true
    
    # 若无 ksud，尝试推送到 modules_update (待安装目录)
    log_info "推送模块到 modules_update..."
    adb shell "mkdir -p $modules_update_dir" || true
    
    # 复制解压后的内容
    adb shell "cp -r $work_dir/* $modules_update_dir/" || true
    
    # 设置权限
    log_info "设置文件权限..."
    adb shell "chmod -R 0755 $modules_update_dir" || true
    adb shell "chmod 644 $modules_update_dir/module.prop" 2>/dev/null || true
    
    # 标记待安装
    adb shell "touch $modules_update_dir/update" || true
    
    log_success "模块已推送到待安装目录: $modules_update_dir"
    log_warn "重启后 KernelSU 将自动安装此模块"
    
    # 清理临时文件
    log_info "清理临时文件..."
    adb shell "rm -rf $work_dir" || true
    
    return 0
}

# ============================================================================
# 安装模块 (主函数)
# ============================================================================
install_module() {
    log_step "开始模块安装流程..."
    
    # 优先尝试 ksud
    if install_via_ksud; then
        return 0
    fi
    
    # 回退到手动安装
    if install_via_manual; then
        return 0
    fi
    
    log_error "所有安装方案均失败"
    exit 1
}

# ============================================================================
# 验证安装结果
# ============================================================================
verify_installation() {
    log_step "验证模块安装状态..."
    
    sleep 2  # 给系统一点时间更新
    
    # 检查模块目录
    if adb shell "test -d /data/adb/modules/$MODULE_NAME"; then
        log_success "模块已成功安装到 /data/adb/modules/$MODULE_NAME"
        
        # 尝试读取 module.prop
        local module_prop=$(adb shell "cat /data/adb/modules/$MODULE_NAME/module.prop 2>/dev/null" || echo "")
        if [ -n "$module_prop" ]; then
            echo -e "${CYAN}模块信息:${NC}"
            echo "$module_prop" | while read -r line; do
                echo "  $line"
            done
        fi
        return 0
    fi
    
    log_warn "模块安装验证失败，可能需要重启设备"
    return 1
}

# ============================================================================
# 清理远程临时文件
# ============================================================================
cleanup_remote() {
    log_step "清理远程临时文件..."
    
    local zip_filename=$(basename "$MODULE_ZIP")
    local remote_path="$MODULE_PATH/$zip_filename"
    
    adb shell "rm -f '$remote_path'" || true
    
    log_success "临时文件已清理"
}

# ============================================================================
# 主程序流程
# ============================================================================
main() {
    echo -e "${BLUE}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║       SARA SRE Agent - 一键 ADB 模块安装器 v1.0              ║${NC}"
    echo -e "${BLUE}║     真正的硬核安卓开发: 编译 → ADB推送 → KernelSU直接安装    ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    # 执行各个步骤
    check_adb
    verify_device_model
    check_kernelsu
    build_module_zip
    push_zip_to_device
    install_module
    verify_installation
    cleanup_remote
    
    echo ""
    echo -e "${GREEN}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║                   安装流程完成! 🎉                          ║${NC}"
    echo -e "${GREEN}║         模块将在设备重启后生效                              ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════════════════════════════╝${NC}"
    
    log_info "提示: 如需立即启用模块，请在 KernelSU 管理器中启用，或重启设备"
    echo ""
}

# ============================================================================
# 执行
# ============================================================================
main "$@"