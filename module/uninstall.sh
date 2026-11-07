#!/system/bin/sh
# 卸载时执行：停守护、还原显示、清理数据。

MODDIR=$(cd "$(dirname "$0")" 2>/dev/null && pwd)
DATA=/data/adb/extdisplay

[ -f "$DATA/extd.pid" ] && kill "$(cat "$DATA/extd.pid" 2>/dev/null)" 2>/dev/null
touch "$DATA/stopped" 2>/dev/null
sleep 1

if [ -x "$MODDIR/bin/extd" ]; then
    "$MODDIR/bin/extd" restore >> "$DATA/uninstall.log" 2>&1
fi

# 兜底：无论 origin 是否存在都把覆盖清干净
wm size reset
wm density reset

# 保留最后一份日志便于事后排查
mkdir -p /data/local/tmp 2>/dev/null
[ -f "$DATA/extd.log" ] && cp "$DATA/extd.log" /data/local/tmp/extdisplay-uninstall.log 2>/dev/null

# 同时移除模块外守卫
rm -f /data/adb/service.d/extdisplay-guard.sh

rm -rf "$DATA"
exit 0
