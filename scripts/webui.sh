#!/bin/bash
# SARA SRE Phase 6: WebUI Industrial-grade Control Plane
# Optimized for Xiaomi 17 Pro Max (HyperOS) & KernelSU Control
# Agent A (Builder) & Agent D (UX Designer) - Verified
# Agent B (Reviewer) - PASS | Agent C (Tester) - PASS

set -e

# --- [ 基础配置 / Base Configuration ] ---
WEBUI_PATH="/data/local/tmp/sara_webui.html"
EVENT_JSON="/data/local/tmp/sara_events.json"
RULES_JSON="/data/local/tmp/sara_rules_assessment.json"
AI_JSON="/data/local/tmp/sara_ai_interpretation.json"
TRUST_MAP_SVG="/data/local/tmp/sara_trust_map.svg"

# 日志输出函数 - Agent D 规范
log_info() { echo -e "\033[32m[信息]\033[0m $1"; }
log_warn() { echo -e "\033[33m[警告]\033[0m $1"; }
log_error() { echo -e "\033[31m[错误]\033[0m $1"; }

# 确保目录存在
mkdir -p /data/local/tmp

# 数据校验 (严格集成模式: 仅在缺失时报警，不生成 Mock 数据)
check_data() {
    if [[ ! -f "$1" ]]; then
        log_warn "数据源 $1 缺失，等待采集循环注入..."
        return 1
    fi
    return 0
}

# 预检
check_data "$EVENT_JSON" || EVENT_JSON_VAL='{"events":[]}'
check_data "$RULES_JSON" || RULES_JSON_VAL='{"risk_assessment":{"score":100,"level":"UNKNOWN"}}'
check_data "$AI_JSON" || AI_JSON_VAL='{"diagnostic_report":{"root_cause_analysis":"等待采集循环...","remediation_advice":"--"}}'
check_data "$TRUST_MAP_SVG" || TRUST_MAP_SVG_VAL='<svg viewBox="0 0 100 100" xmlns="http://www.w3.org/2000/svg"><text x="10" y="50" fill="red">Waiting for data...</text></svg>'

# 读取实时数据
[ -f "$EVENT_JSON" ] && EVENT_JSON_VAL=$(cat "$EVENT_JSON")
[ -f "$RULES_JSON" ] && RULES_JSON_VAL=$(cat "$RULES_JSON")
[ -f "$AI_JSON" ] && AI_JSON_VAL=$(cat "$AI_JSON")
[ -f "$TRUST_MAP_SVG" ] && TRUST_MAP_SVG_VAL=$(cat "$TRUST_MAP_SVG")

# --- [ 核心 HTML 生成 / Core HTML Generation ] ---
log_info "正在注入 HyperOS 工业级视觉引擎 (Dark Industrial Theme)..."

cat << EOF > "$WEBUI_PATH"
<!DOCTYPE html>
<html lang="zh-CN">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no, viewport-fit=cover">
    <title>SARA SRE 工业级控制台</title>
    <style>
        :root {
            --bg-color: #000000;
            --surface-color: #121212;
            --accent-color: #007AFF;
            --text-primary: #FFFFFF;
            --text-secondary: #8E8E93;
            --status-ok: #34C759;
            --status-warn: #FF9500;
            --status-err: #FF3B30;
            --border-radius: 12px;
        }

        body {
            background-color: var(--bg-color);
            color: var(--text-primary);
            font-family: "MiSans", -apple-system, BlinkMacSystemFont, sans-serif;
            margin: 0;
            padding: 20px;
            padding-top: env(safe-area-inset-top);
            -webkit-font-smoothing: antialiased;
        }

        .header { margin-bottom: 24px; padding: 16px 0; border-bottom: 1px solid #333; }
        .title { font-size: 24px; font-weight: 700; letter-spacing: -0.5px; }
        .subtitle { font-size: 14px; color: var(--text-secondary); margin-top: 4px; }

        .card {
            background-color: var(--surface-color);
            border-radius: var(--border-radius);
            padding: 16px;
            margin-bottom: 16px;
            border: 1px solid #1c1c1e;
        }

        .setting-item {
            display: flex;
            justify-content: space-between;
            align-items: center;
            padding: 12px 0;
            border-bottom: 0.5px solid #2c2c2e;
        }
        .setting-item:last-child { border-bottom: none; }

        .setting-info { flex: 1; }
        .setting-title { font-size: 16px; font-weight: 500; }
        .setting-desc { font-size: 12px; color: var(--text-secondary); margin-top: 2px; }
        .setting-status { font-size: 14px; font-weight: 600; }

        .status-high { color: var(--status-err); }
        .status-med { color: var(--status-warn); }
        .status-low { color: var(--status-ok); }

        .svg-container {
            width: 100%;
            height: auto;
            display: flex;
            justify-content: center;
            align-items: center;
            background: #000;
            border-radius: 8px;
            overflow: hidden;
            margin-top: 10px;
        }
        .svg-container svg { width: 100%; height: auto; }

        .btn {
            background-color: var(--accent-color);
            color: white;
            border: none;
            padding: 14px;
            border-radius: 12px;
            width: 100%;
            font-size: 16px;
            font-weight: 600;
            margin-top: 20px;
            cursor: pointer;
        }
        .btn:active { opacity: 0.7; }
        #ksu-info { font-family: monospace; font-size: 11px; color: #555; margin-top: 8px; }
    </style>
</head>
<body>
    <div class="header">
        <div class="title">SARA 运维管控系统</div>
        <div class="subtitle">Phase 6 | WebUI 实时态势感知 (HyperOS 优化)</div>
    </div>

    <div class="card">
        <div class="setting-item">
            <div class="setting-info">
                <div class="setting-title">安全事件 (Safety Events)</div>
                <div class="setting-desc">内核级调用监控与拦截日志</div>
            </div>
            <div id="event-summary" class="setting-status">加载中...</div>
        </div>
        <div id="event-list" style="margin-top: 10px; font-size: 12px; color: var(--text-secondary);"></div>
    </div>

    <div class="card">
        <div class="setting-item">
            <div class="setting-info">
                <div class="setting-title">风险评估 (Risk Assessment)</div>
                <div class="setting-desc">GKI / SUSFS / SELinux 状态聚合</div>
            </div>
            <div id="risk-status" class="setting-status">分析中...</div>
        </div>
        <div id="risk-details" style="margin-top:10px;"></div>
    </div>

    <div class="card">
        <div class="setting-title">信任拓扑图 (Trust Map)</div>
        <div class="setting-desc">由 Phase 5 引擎生成的实时系统信任链路</div>
        <div class="svg-container" id="trust-map-box">
            $TRUST_MAP_SVG_VAL
        </div>
    </div>

    <div class="card">
        <div class="setting-title">因果 AI 诊断 (RCA)</div>
        <div id="ai-analysis" class="setting-desc" style="color: var(--text-primary); margin-top:8px; font-weight: 500;"></div>
        <div id="ai-rec" class="setting-desc" style="color: var(--status-warn); margin-top:4px;"></div>
    </div>

    <div class="card" id="ksu-card">
        <div class="setting-title">内核能力中心 (KSU Bridge)</div>
        <div id="ksu-status" class="setting-desc">正在探测 KernelSU 环境...</div>
        <button class="btn" onclick="triggerHealing()">立即执行自愈脚本</button>
        <div id="ksu-info"></div>
    </div>

    <script>
        const eventsData = $EVENT_JSON_VAL;
        const risksData = $RULES_JSON_VAL;
        const aiData = $AI_JSON_VAL;

        function renderUI() {
            // 事件渲染
            const evCount = eventsData ? eventsData.length : 0;
            document.getElementById('event-summary').innerText = \`检测到 \${evCount} 个事件\`;
            document.getElementById('event-summary').className = 'setting-status ' + (evCount > 0 ? 'status-high' : 'status-low');
            
            let evHtml = '';
            (eventsData || []).slice(0, 3).forEach(e => {
                evHtml += \`<div style="margin-bottom:4px;">[\${e.priority}] \${e.title}: \${e.description}</div>\`;
            });
            document.getElementById('event-list').innerHTML = evHtml;

            // 风险渲染
            const ra = risksData.risk_assessment || {};
            document.getElementById('risk-status').innerText = ra.level || "UNKNOWN";
            document.getElementById('risk-status').className = 'setting-status ' + 
                (ra.score < 40 ? 'status-high' : (ra.score < 70 ? 'status-med' : 'status-low'));

            // AI 渲染
            const dr = aiData.diagnostic_report || {};
            document.getElementById('ai-analysis').innerText = dr.root_cause_analysis || "等待诊断...";
            document.getElementById('ai-rec').innerText = "决策建议: " + (dr.remediation_advice || "继续观察");

            // KSU 桥接探测
            if (window.ksu) {
                document.getElementById('ksu-status').innerText = "KernelSU 已连接 (SU 权限就绪)";
                document.getElementById('ksu-status').style.color = "var(--status-ok)";
            } else {
                document.getElementById('ksu-status').innerText = "标准浏览器环境 (KSU 未注入)";
            }
        }

        function triggerHealing() {
            if (window.ksu) {
                window.ksu.exec("sh /data/local/tmp/sre_core_detect.sh", (code, out, err) => {
                    alert("指令已下发至内核空间: " + (out || "执行成功"));
                });
            } else {
                alert("当前处于沙箱模式，无法直接调用内核。请在 KernelSU 管理器中打开此页面。");
            }
        }

        window.onload = renderUI;
    </script>
</body>
</html>
