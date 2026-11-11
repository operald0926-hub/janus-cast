#!/system/bin/sh
# 模块外兜底守卫。安装位置：/data/adb/service.d/extdisplay-guard.sh
#
# 存在的理由：实测 ColorOS 16 上 `wm size` 的覆盖会跨重启存活，而 KernelSU 的模块
# 一旦被「停用」，模块内所有脚本都不再执行。若此时设备正卡在投屏分辨率上，用户会
# 永久停在错误分辨率。本脚本独立于模块，只要开机脚本目录仍被执行，就能把状态清干净。
#
# 判定原则：开机时不存在"正在投屏"的合法场景，所以只要发现上次留下了未被还原的
# 记录（origin.env），就无条件还原。

DATA=/data/adb/extdisplay
MODBIN=/data/adb/modules/extdisplay/bin/extd

i=0
while [ "$(getprop sys.boot_completed)" != "1" ]; do
    i=$((i + 1))
    [ "$i" -gt 180 ] && break
    sleep 1
done
sleep 5

# 没有遗留记录 = 上次是干净退出，什么都不做
[ -f "$DATA/origin.env" ] || exit 0

# 模块还在（哪怕被停用，二进制仍可执行）就交给它按基线还原
if [ -x "$MODBIN" ]; then
    "$MODBIN" restore >/dev/null 2>&1
else
    # 模块已被移除，但基线还在：至少把默认桌面换回去
    # shellcheck disable=SC1091  # 基线文件可能不存在
    . "$DATA/origin.env" 2>/dev/null
    if [ -n "${ORIG_HOME:-}" ]; then
        cmd package set-home-activity "$ORIG_HOME" >/dev/null 2>&1
    fi
fi

# 兜底：仍然有覆盖就直接清掉
# 注意：不能用 > 重定向到 /data 下的普通文件，会让 Binder 事务失败
left=$(wm size 2>/dev/null | grep 'Override size:')
if [ -n "$left" ]; then
    wm size reset >/dev/null 2>&1
fi
left=$(wm density 2>/dev/null | grep 'Override density:')
if [ -n "$left" ]; then
    wm density reset >/dev/null 2>&1
fi

exit 0
