#!/bin/sh
# 离线验证 extd 的解析与决策逻辑（不上真机、不写任何显示参数）
# 用 tests/stub 里的 wm/settings/dumpsys 桩替代 Android 侧命令。

ROOT=$(cd "$(dirname "$0")/.." && pwd)
EXTD="$ROOT/module/bin/extd"
FIX="$ROOT/tests/fixtures"
STUB="$ROOT/tests/stub"

PASS=0
FAIL=0
T=""

ck() {
    desc=$1; got=$2; want=$3
    if [ "$got" = "$want" ]; then
        PASS=$((PASS + 1)); printf '  ok    %s\n' "$desc"
    else
        FAIL=$((FAIL + 1)); printf '  FAIL  %s\n        got=[%s]\n        want=[%s]\n' "$desc" "$got" "$want"
    fi
}

ckin() {
    desc=$1; got=$2; want=$3
    case "$got" in
        *"$want"*) PASS=$((PASS + 1)); printf '  ok    %s\n' "$desc" ;;
        *) FAIL=$((FAIL + 1)); printf '  FAIL  %s\n        got=[%s]\n        want substring=[%s]\n' "$desc" "$got" "$want" ;;
    esac
}

setup() {
    T=$(mktemp -d)
    export STUB_STATE="$T/stub"
    mkdir -p "$STUB_STATE"
    printf '0' > "$STUB_STATE/accelerometer_rotation"
    printf '0' > "$STUB_STATE/user_rotation"
    printf 'lock 0' > "$STUB_STATE/rot"
    export EXTD_DATA="$T/data"
    export STUB_DUMP="$FIX/$1"
    export EXTD_PATH="$STUB:/usr/bin:/bin:/usr/sbin:/sbin"
}

teardown() { rm -rf "$T"; }
run() { sh "$EXTD" "$@" 2>/dev/null; }

echo "=== 1. 无外屏 ==="
setup none.txt
ck "detect 输出 NONE" "$(run detect)" "NONE
-> 无外屏（保持原状）"
ck "detect 退出码 1" "$(run detect >/dev/null 2>&1; echo $?)" "1"
teardown

echo "=== 2. Miracast 镜像 1920x1080 ==="
setup mirror-1080p.txt
ckin "detect 判定为 MIRROR" "$(run detect)" "MIRROR 2|1920|1080|320|WIFI|0|0|ON"
out=$(run on)
ck "on 执行成功" "$out" "applied"
ck "wm size 写为纵向逻辑 1080x1920" "$(cat "$STUB_STATE/size")" "1080x1920"
ck "wm density 写为 320" "$(cat "$STUB_STATE/density")" "320"
ck "方向锁为横屏 lock 1" "$(cat "$STUB_STATE/rot")" "lock 1"
ck "自动旋转被关闭" "$(cat "$STUB_STATE/accelerometer_rotation")" "0"
ck "强制按用户旋转已开启" "$(cat "$STUB_STATE/fixedrot" 2>/dev/null)" "enabled"
ck "state 标记 active" "$(grep -c '^STATUS=active' "$EXTD_DATA/state")" "1"
ck "origin 记录了基线" "$(grep -c '^ORIG_SIZE=""$' "$EXTD_DATA/origin.env")" "1"
echo "=== 3. 断开后还原 ==="
run off >/dev/null
ck "wm size 覆盖被清除" "$([ -f "$STUB_STATE/size" ] && cat "$STUB_STATE/size" || echo none)" "none"
ck "wm density 覆盖被清除" "$([ -f "$STUB_STATE/density" ] && cat "$STUB_STATE/density" || echo none)" "none"
ck "方向恢复 lock 0" "$(cat "$STUB_STATE/rot")" "lock 0"
ck "强制旋转恢复 default" "$(cat "$STUB_STATE/fixedrot" 2>/dev/null)" "default"
ck "state 被清除" "$([ -f "$EXTD_DATA/state" ] && echo yes || echo no)" "no"
ck "origin 被清除" "$([ -f "$EXTD_DATA/origin.env" ] && echo yes || echo no)" "no"
teardown

echo "=== 4. 720p 外屏 ==="
setup mirror-720p.txt
run on >/dev/null
ck "wm size 1080->720x1280" "$(cat "$STUB_STATE/size")" "720x1280"
ck "density 跟随 213" "$(cat "$STUB_STATE/density")" "213"
teardown

echo "=== 5. DP 1440p ==="
setup dp-1440p.txt
run on >/dev/null
ck "wm size 1440x2560" "$(cat "$STUB_STATE/size")" "1440x2560"
teardown

echo "=== 6. 扩展模式（layerStack != 0）不应改动内屏 ==="
setup extended.txt
ckin "detect 判定 EXTENDED" "$(run detect)" "EXTENDED"
ck "on 拒绝执行" "$(run on)" "拒绝：当前没有可跟随的镜像外屏"
ck "未写入任何 size" "$([ -f "$STUB_STATE/size" ] && echo yes || echo no)" "no"
teardown

echo "=== 7. 4K 超上限 ==="
setup dp-4k.txt
ckin "on 拒绝 4K" "$(run on)" "超过像素上限"
ck "未写入 size" "$([ -f "$STUB_STATE/size" ] && echo yes || echo no)" "no"
teardown

echo "=== 8. 外屏 state=OFF 视为不存在 ==="
setup mirror-off.txt
ck "detect 输出 NONE" "$(run detect | head -n1)" "NONE"
teardown

echo "=== 9. 密度裁剪 ==="
setup mirror-1080p.txt
sed 's/density 320/density 700/' "$FIX/mirror-1080p.txt" > "$T/hidpi.txt"
export STUB_DUMP="$T/hidpi.txt"
run on >/dev/null
ck "700dpi 被裁剪到 480" "$(cat "$STUB_STATE/density")" "480"
teardown

echo "=== 10. 已有 override 的基线恢复（不写死默认值）==="
setup none.txt
printf '1200x2600' > "$STUB_STATE/size"
printf '560' > "$STUB_STATE/density"
printf 'lock 3' > "$STUB_STATE/rot"
export STUB_DUMP="$FIX/mirror-1080p.txt"
run on >/dev/null
ck "先记录基线" "$(grep '^ORIG_SIZE=' "$EXTD_DATA/origin.env")" 'ORIG_SIZE="1200x2600"'
run off >/dev/null
ck "还原到 1200x2600 而非 reset" "$(cat "$STUB_STATE/size")" "1200x2600"
ck "还原到 560dpi" "$(cat "$STUB_STATE/density")" "560"
ck "还原到 lock 3" "$(cat "$STUB_STATE/rot")" "lock 3"
teardown

echo "=== 11. 守护进程循环：出现->应用，消失->还原 ==="
setup mirror-1080p.txt
mkdir -p "$EXTD_DATA"; printf 'WATCHDOG_INTERVAL=0\n' > "$EXTD_DATA/config.conf"
EXTD_MAX_TICKS=2 run daemon >/dev/null 2>&1
ck "daemon 检测到外屏后写入 size" "$(cat "$STUB_STATE/size" 2>/dev/null)" "1080x1920"
export STUB_DUMP="$FIX/none.txt"
EXTD_MAX_TICKS=7 run daemon >/dev/null 2>&1
ck "daemon 判定断开后还原 size" "$([ -f "$STUB_STATE/size" ] && cat "$STUB_STATE/size" || echo none)" "none"
ck "daemon 还原后清理 state" "$([ -f "$EXTD_DATA/state" ] && echo yes || echo no)" "no"
teardown

echo "=== 12. dumpsys 解析失败时不误还原 ==="
setup mirror-1080p.txt
mkdir -p "$EXTD_DATA"; printf 'WATCHDOG_INTERVAL=0\n' > "$EXTD_DATA/config.conf"
EXTD_MAX_TICKS=2 run daemon >/dev/null 2>&1
: > "$T/empty.txt"
export STUB_DUMP="$T/empty.txt"
EXTD_MAX_TICKS=7 run daemon >/dev/null 2>&1
ck "空 dump 时保持已应用状态" "$(cat "$STUB_STATE/size" 2>/dev/null)" "1080x1920"
teardown

echo "=== 13. 无线镜像：独立 layerStack（真机 BRAVIA 实测形态）==="
setup mirror-wifi-ls3.txt
ckin "layerStack=3 仍判定为 MIRROR" "$(run detect)" "MIRROR 2|1920|1080|320|WIFI|3|0|ON"
run on >/dev/null
ck "仍然应用 1080x1920" "$(cat "$STUB_STATE/size" 2>/dev/null)" "1080x1920"
teardown

echo "=== 14. EXTERNAL 类型不会被 MIRROR_TYPES 误纳入 ==="
setup extended.txt
ckin "EXTERNAL 仍判为 EXTENDED" "$(run detect)" "EXTENDED"
teardown

echo "=== 15. 用户原本用第三方桌面：断开后必须还原成它 ==="
setup mirror-1080p.txt
printf 'com.example.otherhome/com.example.otherhome.Home\n' > "$STUB_STATE/home"
run on >/dev/null 2>&1
ck "投屏时切到 Lawnchair" "$(cat "$STUB_STATE/home")" "app.lawnchair/app.lawnchair.LawnchairLauncher"
run off >/dev/null 2>&1
ck "断开后还原成用户原本的桌面（不是 OPPO 的）" "$(cat "$STUB_STATE/home")" "com.example.otherhome/com.example.otherhome.Home"
teardown

echo "=== 16. 读不到默认桌面时不切换（避免还原不回去）==="
setup mirror-1080p.txt
printf 'com.android.launcher/com.android.launcher.Launcher\n' > "$STUB_STATE/home"
printf '1' > "$STUB_STATE/home_broken"
run on >/dev/null 2>&1
ck "解析落到 Resolver 时保持原桌面不动" "$(cat "$STUB_STATE/home")" "com.android.launcher/com.android.launcher.Launcher"
teardown

echo
printf '通过 %s / 失败 %s\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
