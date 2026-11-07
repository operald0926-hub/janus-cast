#!/bin/sh
# 一次性证据采集（全部只读）。用法：
#   ./tools/probe.sh before        # 插显示器之前
#   ./tools/probe.sh wifi          # 无线投屏已连接后
#   ./tools/probe.sh dp            # 有线显示器已连接后
# 结果写入 probes/<label>-<时间戳>.txt

set -u
LABEL=${1:-snapshot}
ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUTDIR=$ROOT/probes
mkdir -p "$OUTDIR"
OUT=$OUTDIR/${LABEL}-$(date +%Y%m%d-%H%M%S).txt

say() { printf '%s\n' "$*" >> "$OUT"; }
cap() {
    title=$1; shift
    say ""
    say "########## $title ##########"
    "$@" >> "$OUT" 2>&1
}
sh_() { adb shell "$@"; }
root_() { adb shell "su -c '$*'"; }

say "probe label: $LABEL"
say "host time  : $(date '+%Y-%m-%d %H:%M:%S')"

cap "device" sh_ 'getprop ro.product.model; getprop ro.build.version.release; getprop ro.build.version.sdk; getprop ro.build.display.id; getprop ro.boot.verifiedbootstate'
cap "root" sh_ 'su -c id'
cap "wm size" sh_ 'wm size'
cap "wm density" sh_ 'wm density'
cap "wm user-rotation" sh_ 'wm user-rotation'
cap "rotation settings" sh_ 'settings get system accelerometer_rotation; settings get system user_rotation'
cap "drm connectors" root_ 'for c in /sys/class/drm/card*-DP-* /sys/class/drm/card*-HDMI-* /sys/class/drm/card*-Virtual-*; do [ -d "$c" ] || continue; echo "== $c"; echo -n "status: "; cat $c/status 2>/dev/null; echo -n "enabled: "; cat $c/enabled 2>/dev/null; echo "modes:"; cat $c/modes 2>/dev/null; echo -n "edid bytes: "; wc -c < $c/edid 2>/dev/null; done'
cap "edid hex (DP)" root_ 'for c in /sys/class/drm/card*-DP-*; do [ -d "$c" ] || continue; echo "== $c"; od -An -tx1 $c/edid 2>/dev/null | tr -d "\n"; echo; done'
cap "SF display list" sh_ 'dumpsys SurfaceFlinger --display-id'
cap "display DisplayInfo" sh_ 'dumpsys display | grep -E "DisplayInfo\\{|DisplayDeviceInfo\\{|mDisplayId" '
cap "display DeviceInfo full" sh_ 'dumpsys display | grep -A2 "DisplayDeviceInfo{" | head -80'
cap "media_router" sh_ 'dumpsys media_router | head -60'
cap "media_projection" sh_ 'dumpsys media_projection | head -40'
cap "wifi display" sh_ 'dumpsys display | grep -i -A3 wifidisplay | head -60'
cap "oplus display" sh_ 'dumpsys display | grep -iE "OplusDisplayState|OplusFeature" | head -20'
cap "wifi status" sh_ 'cmd wifi status 2>&1 | head -20'

say ""
say "########## 关键判读 ##########"
n=$(adb shell 'dumpsys SurfaceFlinger --display-id' 2>/dev/null | grep -c '^Display ')
say "SurfaceFlinger 显示数量: $n"
say "DP 连接器状态: $(root_ 'cat /sys/class/drm/card0-DP-1/status' 2>/dev/null | tr -d '\r')"
say ""
say "判读规则："
say "  1) 若显示数量 > 1，说明外接显示已被系统接纳，记下其 DisplayInfo 的 real WxH / density / layerStack。"
say "  2) layerStack 与内屏（0）相同 = 镜像；不同 = 扩展，本模块不会改动内屏。"
say "  3) DP status=connected 且 edid 非空 = 有线通路真实可用。"
say "  4) 无线场景 card*-DP 不变化，只有 DisplayInfo 多出一条 type=WIFI 的记录。"

printf 'written: %s\n' "$OUT"
