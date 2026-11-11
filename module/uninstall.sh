#!/system/bin/sh
# 卸载时执行：停守护、还原显示、清理数据。

MODDIR=$(cd "$(dirname "$0")" 2>/dev/null && pwd)
DATA=/data/adb/extdisplay

[ -f "$DATA/extd.pid" ] && kill "$(cat "$DATA/extd.pid" 2>/dev/null)" 2>/dev/null
touch "$DATA/stopped" 2>/dev/null

# 等守护进程把 TERM trap 里的还原跑完，否则下面的清理会和它抢
i=0
while [ "$i" -lt 30 ]; do
    p=$(cat "$DATA/extd.pid" 2>/dev/null)
    [ -z "$p" ] && break
    kill -0 "$p" 2>/dev/null || break
    sleep 0.2
    i=$((i + 1))
done

# 守护进程若没来得及回收监听器，这里补刀（否则 ip/inotifyd 会变孤儿）
for pf in "$DATA/run/link.pid" "$DATA/run/drm.pid"; do
    [ -f "$pf" ] || continue
    kill "$(cat "$pf" 2>/dev/null)" 2>/dev/null
    rm -f "$pf"
done

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
