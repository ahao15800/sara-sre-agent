#!/system/bin/sh
# SARA SRE Agent v1 - Event Engine
# Path: /data/adb/modules/sara_sre_agent/scripts/event_engine.sh or scripts/event_engine.sh in repo
# Purpose: Read system_snapshot.json, ingest live kernel logcat/dmesg anomalies, and produce structured events.
# Input: /data/local/tmp/system_snapshot.json
# Output: /data/local/tmp/sara_events.json

set -u

SNAPSHOT_FILE="/data/local/tmp/system_snapshot.json"
EVENTS_FILE="/data/local/tmp/sara_events.json"
TIMESTAMP=$(date +%s)

if [ ! -f "$SNAPSHOT_FILE" ]; then
    echo "Error: Snapshot file $SNAPSHOT_FILE not found! Run snapshot.sh first."
    exit 1
fi

# Helper function to extract JSON values using grep/sed (no jq dependency)
get_json_bool() {
    grep -o "\"$1\": [^,}]*" "$SNAPSHOT_FILE" | head -n1 | awk '{print $2}' | tr -d ' \r\n'
}

get_json_str() {
    grep -o "\"$1\": \"[^\"]*\"" "$SNAPSHOT_FILE" | head -n1 | cut -d'"' -f4 | tr -d '\r\n'
}

get_json_num() {
    grep -o "\"$1\": [0-9]*" "$SNAPSHOT_FILE" | head -n1 | awk '{print $2}' | tr -d ' \r\n'
}

# Parse variables from Snapshot Layer
SUSFS_ACTIVE=$(get_json_bool "active")
SUSFS_VERSION=$(get_json_str "version")
VFS_HIDING=$(get_json_num "vfs_hiding_enabled")
NAMESPACE_LEAK=$(get_json_bool "leak_detected")
INIT_MOUNTS=$(get_json_num "init_mounts_count")
SELF_MOUNTS=$(get_json_num "self_mounts_count")
MODULE_MOUNTS=$(get_json_num "module_mounts_count")
SELINUX_STATE=$(get_json_str "selinux_state")
LSPOSED_DETECTED=$(get_json_bool "lsposed_detected")

# Initialize event array list
EVENT_INDEX=1
EVENTS_JSON=""

add_event() {
    local source="$1"
    local severity="$2"
    local event_type="$3"
    local message="$4"
    local details="$5"
    
    local EV_ID="EV_${TIMESTAMP}_00${EVENT_INDEX}"
    
    local SINGLE_EVENT=$(cat <<EOF
  {
    "event_id": "$EV_ID",
    "timestamp": $TIMESTAMP,
    "source": "$source",
    "severity": "$severity",
    "event_type": "$event_type",
    "message": "$message",
    "details": $details
  }
EOF
)

    if [ -n "$EVENTS_JSON" ]; then
        EVENTS_JSON="${EVENTS_JSON},
${SINGLE_EVENT}"
    else
        EVENTS_JSON="${SINGLE_EVENT}"
    fi
    
    EVENT_INDEX=$((EVENT_INDEX + 1))
}

# --- Event Rule 1: SUSFS Inactivity / Hiding Disabled ---
if [ "$SUSFS_ACTIVE" = "false" ]; then
    add_event "kernel_susfs" "CRITICAL" "SUSFS_INACTIVE" \
        "Kernel-level SUSFS security is inactive. Root hides will fail." \
        "{\"active\": false, \"version\": \"$SUSFS_VERSION\"}"
elif [ "$VFS_HIDING" -eq 0 ]; then
    add_event "kernel_susfs" "WARNING" "SUSFS_VFS_HIDING_DISABLED" \
        "SUSFS detected but VFS path hiding is disabled." \
        "{\"active\": true, \"vfs_hiding_enabled\": 0}"
fi

# --- Event Rule 2: Mount Namespace Leak ---
if [ "$NAMESPACE_LEAK" = "true" ]; then
    DIFF=$((SELF_MOUNTS - INIT_MOUNTS))
    add_event "mount_namespace" "HIGH" "MOUNT_NS_LEAK_DETECTED" \
        "Mount namespace discrepancy detected. Root hooks leaked into app space." \
        "{\"diff_count\": $DIFF, \"init_mounts\": $INIT_MOUNTS, \"self_mounts\": $SELF_MOUNTS, \"module_mounts\": $MODULE_MOUNTS}"
fi

# --- Event Rule 3: SELinux State Compromise ---
if [ "$SELINUX_STATE" = "Permissive" ]; then
    add_event "middleware" "HIGH" "SELINUX_PERMISSIVE_DETECTED" \
        "SELinux is running in Permissive mode. High exploit vulnerability." \
        "{\"current_state\": \"Permissive\"}"
fi

# --- Event Rule 4: LSPosed/Zygisk Active ---
if [ "$LSPOSED_DETECTED" = "true" ]; then
    add_event "middleware" "INFO" "LSPOSED_FRAMEWORK_ACTIVE" \
        "LSPosed / Zygisk framework was detected inside running address spaces." \
        "{\"detected\": true}"
fi

# --- Event Rule 5: Dynamic Logcat / SELinux AVC Denials scan ---
# Check for any recent SELinux AVC denials in the dmesg buffer or logcat (last 100 lines for efficiency)
AVC_COUNT=0
if logcat -d -t 100 2>/dev/null | grep -q "avc: denied"; then
    AVC_COUNT=$(logcat -d -t 100 2>/dev/null | grep -c "avc: denied")
elif dmesg 2>/dev/null | grep -q "avc: denied"; then
    AVC_COUNT=$(dmesg 2>/dev/null | grep -c "avc: denied")
fi

if [ "$AVC_COUNT" -gt 0 ]; then
    add_event "kernel_selinux" "WARNING" "SELINUX_AVC_DENIED" \
        "System logcat reported active SELinux policy denials." \
        "{\"avc_denial_count\": $AVC_COUNT}"
fi

# --- Event Rule 6: Binder transaction pressure scan ---
# Look for Binder blockings or excessive transaction latency signatures
BINDER_BLOCKED=false
if logcat -d -t 100 2>/dev/null | grep -E -q "binder_alloc|slow transaction|binder thread|blocked"; then
    BINDER_BLOCKED=true
fi

if [ "$BINDER_BLOCKED" = "true" ]; then
    add_event "binder_radar" "WARNING" "BINDER_TRANSACTION_DELAY" \
        "Slow transaction signatures detected in Binder IPC communication." \
        "{\"binder_ipc_pressure\": true}"
fi

# Output full JSON array
cat <<EOF > "$EVENTS_FILE"
[
$EVENTS_JSON
]
EOF

chmod 0644 "$EVENTS_FILE"
echo "Events generation completed. Output written to $EVENTS_FILE"
