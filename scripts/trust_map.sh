#!/bin/bash
# SARA SRE 代理 v1 - 信任图层 (Trust Map Layer)
# 路径: scripts/trust_map.sh
# 用途: 动态生成系统信任链 SVG 拓扑，支持风险传播可视化。

OUTPUT_SVG="/data/local/tmp/sara_trust_map.svg"
OUTPUT_JSON="/data/local/tmp/sara_trust_map.json"
EVENTS_FILE="/data/local/tmp/sara_events.json"

log_info() {
    # Agent D (UX Designer) Style: [标题] 描述: 状态 (Chinese only as per Agent D instructions)
    printf "[%-18s] %-40s: %s\n" "$1" "$2" "$3"
}

# Agent A (Builder): 代码执行引擎
mkdir -p /data/local/tmp/

# 检查输入，支持 Mock 回退
if [ ! -f "$EVENTS_FILE" ]; then
    echo "[模拟] 输入数据缺失，注入 Mock 安全事件进行故障弱化运行..."
    cat <<EOM > "$EVENTS_FILE"
[
  {"id": "namespace_leak", "title": "Mount Namespace", "status": "异常"},
  {"id": "selinux_denial", "title": "SELinux", "status": "风险"}
]
EOM
fi

log_info "信任图引擎" "启动基于核心算法的 SVG 拓扑渲染器" "运行中"

# 使用 Python3 逻辑进行 SVG 生成 (适配典型 Linux/Android 环境)
# 如果环境中没有 Python，可以使用纯 Shell，但 Python 生成 SVG 更精确。
python3 -c '
import json, os, time

def generate():
    events_file = "/data/local/tmp/sara_events.json"
    output_svg = "/data/local/tmp/sara_trust_map.svg"
    output_json = "/data/local/tmp/sara_trust_map.json"
    
    events = []
    if os.path.exists(events_file):
        with open(events_file, "r") as f: events = json.load(f)
    
    ids = [e.get("id") for e in events]
    nodes = {
        "VFS": {"name": "VFS Layer / SUSFS", "color": "#52C41A", "st": "Healthy", "cn": "正常"},
        "MNS": {"name": "Mount Namespaces", "color": "#52C41A", "st": "Isolated", "cn": "隔离"},
        "SLX": {"name": "SELinux Policies", "color": "#52C41A", "st": "Enforcing", "cn": "强制"},
        "HKF": {"name": "Hook Frameworks", "color": "#52C41A", "st": "Clean", "cn": "纯净"},
        "TEE": {"name": "TEE/Keystore", "color": "#52C41A", "st": "Verified", "cn": "受信"},
        "BND": {"name": "Binder IPC", "color": "#52C41A", "st": "Optimal", "cn": "最优"}
    }
    
    prop = []
    if "namespace_leak" in ids:
        nodes["MNS"].update({"color": "#FF4D4F", "st": "Leak Detected", "cn": "泄漏"})
        nodes["VFS"].update({"color": "#FF9C6E", "st": "Exposed", "cn": "暴露"})
        prop.append(("MNS", "VFS"))
    if "selinux_denial" in ids:
        nodes["SLX"].update({"color": "#FF9C6E", "st": "Permissive", "cn": "宽容"})
        nodes["TEE"].update({"color": "#FF4D4F", "st": "Untrusted", "cn": "不可信"})
        prop.append(("SLX", "TEE"))
    if "hook_detection" in ids:
        nodes["HKF"].update({"color": "#FF4D4F", "st": "Hooked", "cn": "注入"})
    if "binder_stall" in ids:
        nodes["BND"].update({"color": "#FF9C6E", "st": "Stalled", "cn": "拥塞"} )

    pos = {"VFS":(150,100), "MNS":(150,300), "SLX":(400,100), "HKF":(400,300), "TEE":(650,100), "BND":(650,300)}
    
    svg = f"""<svg width="800" height="400" xmlns="http://www.w3.org/2000/svg">
    <rect width="100%" height="100%" fill="#F0F2F5" />
    <style>
        .n {{ font: bold 13px sans-serif; }} .s {{ font: 11px sans-serif; }}
        @keyframes flash {{ from {{ opacity: 1; }} to {{ opacity: 0.4; }} }}
        .flash {{ animation: flash 0.8s infinite alternate; }}
    </style>"""
    
    for start, end in [("VFS", "SLX"), ("SLX", "TEE"), ("MNS", "VFS"), ("HKF", "BND")]:
        x1, y1 = pos[start]; x2, y2 = pos[end]
        svg += f"<line x1=\"{x1}\" y1=\"{y1}\" x2=\"{x2}\" y2=\"{y2}\" stroke=\"#D9D9D9\" stroke-width=\"2\" />"
    
    for start, end in prop:
        x1, y1 = pos[start]; x2, y2 = pos[end]
        svg += f"<line x1=\"{x1}\" y1=\"{y1}\" x2=\"{x2}\" y2=\"{y2}\" stroke=\"#FF4D4F\" stroke-width=\"3\" stroke-dasharray=\"5,5\" />"
    
    for k, p in pos.items():
        n = nodes[k]; f_cl = " class=\"flash\"" if n["color"] == "#FF4D4F" else ""
        svg += f"""<g transform=\"translate({p[0]-75},{p[1]-40})\">
        <rect width=\"150\" height=\"80\" rx=\"8\" fill=\"white\" stroke=\"{n["color"]}\" stroke-width=\"3\"{f_cl} />
        <text x=\"75\" y=\"30\" text-anchor=\"middle\" class=\"n\" fill=\"#262626\">{n["name"]}</text>
        <text x=\"75\" y=\"55\" text-anchor=\"middle\" class=\"s\" fill=\"{n["color"]}\">{n["st"]} ({n["cn"]})</text></g>"""
    
    svg += "</svg>"
    with open(output_svg, "w") as f: f.write(svg)
    meta = {"timestamp": int(time.time()), "ux": {"title_cn": "信任图层分析", "desc_cn": "基于 GKI 与内核安全原语的信任链拓扑结构", "status_cn": "构建成功"}, "nodes": nodes}
    with open(output_json, "w") as f: json.dump(meta, f, indent=2, ensure_ascii=False)
    print("SUCCESS")
generate()' 2>/dev/null || echo "FAILED: Python3 not found or execution error"

if [ -f "$OUTPUT_SVG" ]; then
    log_info "拓扑可视化" "SVG 信任链地图构建 (Trust Chain Map)" "成功 (PASS)"
    log_info "UX 配置" "多语言指标与元数据导出" "成功 (PASS)"
else
    # 紧急回退逻辑 (Pure Bash SVG Generation if Python fails)
    log_info "拓扑可视化" "正在尝试 Shell 原生回退渲染..." "警告"
    echo "<svg width='800' height='400' xmlns='http://www.w3.org/2000/svg'><text x='10' y='20'>Trust Map (Fallback)</text></svg>" > "$OUTPUT_SVG"
    echo '{"ux": {"title_cn": "信任图层", "status_cn": "回退模式"}}' > "$OUTPUT_JSON"
fi

echo "========================================================================"
echo "SARA SRE 信任图层 - 拓扑分析流水线执行完毕"
echo "========================================================================"
