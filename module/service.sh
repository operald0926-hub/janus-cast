#!/system/bin/sh
# KernelSU / Magisk late_start service 阶段入口。
# 真正的逻辑在 bin/bootstrap：它会等 sys.boot_completed 后再动手，
# 因为 late_start 阶段 WindowManagerService 可能还没起来，wm 命令无效。

MODDIR=$(cd "$(dirname "$0")" 2>/dev/null && pwd)
DATA=/data/adb/extdisplay
mkdir -p "$DATA" 2>/dev/null

chmod 0755 "$MODDIR/bin/extd" "$MODDIR/bin/bootstrap" 2>/dev/null

if command -v setsid >/dev/null 2>&1; then
    setsid "$MODDIR/bin/bootstrap" >/dev/null 2>&1 &
else
    "$MODDIR/bin/bootstrap" >/dev/null 2>&1 &
fi

exit 0
