#!/system/bin/sh
MODDIR=${0%/*}
# Wait for boot completion
while [ "$(getprop sys.boot_completed)" != "1" ]; do sleep 5; done
# Start the agent
sh "$MODDIR/scripts/sara_sre_agent.sh" start
