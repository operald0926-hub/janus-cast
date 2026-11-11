#!/bin/sh
# 紧急恢复：不依赖模块是否正常，直接用 ADB 把显示状态清干净。
# 场景：黑屏、DPI 异常、方向锁死、模块被停用后残留覆盖。

set -u
MODBIN=/data/adb/modules/extdisplay/bin/extd

echo "== 当前状态 =="
adb shell 'wm size; wm density; wm user-rotation' 2>&1

echo "== 停止守护进程 =="
# shellcheck disable=SC2016  # 变量由设备端 shell 展开
adb shell 'su -c "touch /data/adb/extdisplay/stopped 2>/dev/null; [ -f /data/adb/extdisplay/extd.pid ] && kill \$(cat /data/adb/extdisplay/extd.pid) 2>/dev/null; echo killed"' 2>&1

echo "== 还原 =="
if adb shell "[ -x $MODBIN ]" >/dev/null 2>&1; then
    adb shell "su -c '$MODBIN restore'" 2>&1
else
    echo "模块不在，使用兜底 reset"
    adb shell 'su -c "wm size reset; wm density reset; settings put system accelerometer_rotation 0; settings put system user_rotation 0"' 2>&1
fi

echo "== 结果 =="
adb shell 'wm size; wm density; wm user-rotation' 2>&1
echo
echo "若仍异常，可重启设备（模块启动时会自动做一次 boot-restore）。"
