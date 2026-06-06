#!/bin/bash
# SARA SRE Agent - ReSukiSU 模块构建脚本
# 此脚本生成符合 KernelSU/ReSukiSU 标准的安装包

ZIP_NAME="sara_sre_agent_resukisu_v1.0.0.zip"

echo "--------------------------------------"
echo "开始构建 SARA SRE Agent 模块包..."
echo "--------------------------------------"

# 清理旧包
if [ -f "$ZIP_NAME" ]; then
    echo "清理旧的构建文件: $ZIP_NAME"
    rm -f "$ZIP_NAME"
fi

# 验证核心文件存在
REQUIRED_FILES=("module.prop" "service.sh" "customize.sh")
for file in "${REQUIRED_FILES[@]}"; do
    if [ ! -f "$file" ]; then
        echo "错误: 缺少核心文件 $file，构建停止。"
        exit 1
    fi
done

# 打包
zip -r "$ZIP_NAME" . \
    -x "*.git*" \
    "build_zip.sh" \
    "*.zip" \
    "install_locally.sh" \
    "deployment_design.txt" \
    "README.md" \
    "LICENSE" \
    "README_NEW.md"

if [ $? -eq 0 ]; then
    echo "--------------------------------------"
    echo "构建成功: $ZIP_NAME"
    echo "结构验证: 符合 ReSukiSU 一键安装规范"
    echo "--------------------------------------"
else
    echo "错误: 打包过程出现问题。"
    exit 1
fi
