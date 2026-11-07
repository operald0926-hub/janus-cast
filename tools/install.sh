#!/bin/sh
# 通过 ADB 把模块放进 KernelSU 模块目录（不打包、不重启）。
# 之后在 KernelSU 管理器里能看到该模块，重启后生效；也可以先手动执行 service.sh 验证。

set -eu
ROOT=$(cd "$(dirname "$0")/.." && pwd)
MODSRC=$ROOT/module
MODID=extdisplay
DEST=/data/adb/modules/$MODID

echo "== 上传到 /data/local/tmp/$MODID =="
adb push "$MODSRC" "/data/local/tmp/$MODID" >/dev/null

echo "== 安装到 $DEST =="
adb shell "su -c '
set -e
rm -rf $DEST
mkdir -p $DEST
cp -r /data/local/tmp/$MODID/. $DEST/
chmod 0755 $DEST/bin/extd $DEST/bin/bootstrap $DEST/service.sh $DEST/uninstall.sh $DEST/action.sh
chown -R 0:0 $DEST
mkdir -p /data/adb/extdisplay
if [ ! -f /data/adb/extdisplay/config.conf ]; then
  cp $DEST/config.sample.conf /data/adb/extdisplay/config.conf
fi
rm -rf /data/local/tmp/$MODID
echo INSTALLED
'"

echo "== 安装模块外兜底守卫到 /data/adb/service.d =="
adb push "$ROOT/tools/extdisplay-guard.sh" /data/local/tmp/extdisplay-guard.sh >/dev/null
adb shell "su -c '
mkdir -p /data/adb/service.d
cp /data/local/tmp/extdisplay-guard.sh /data/adb/service.d/extdisplay-guard.sh
chmod 0755 /data/adb/service.d/extdisplay-guard.sh
rm -f /data/local/tmp/extdisplay-guard.sh
echo GUARD_INSTALLED
'"

echo "== 校验 =="
adb shell "su -c '$DEST/bin/extd status'" || true

echo
echo "已完成。模块将在下次重启后自动运行。"
echo "不重启先验证：adb shell \"su -c '$DEST/service.sh'; sleep 8; su -c '$DEST/bin/extd status'\""
