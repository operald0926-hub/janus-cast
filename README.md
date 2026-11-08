# JANUS Cast

A KernelSU module that makes an Android phone behave like a proper external display source.

When you mirror your phone to a TV, Android scales a tall portrait framebuffer into a 16:9 panel — pillarboxed, cropped, or squashed. JANUS Cast flips the phone's logical display to the sink's real resolution before that scaling happens, so the mirror becomes **1:1 with zero resampling**. Then it puts everything back the way it was.

Two faces: one for the sink, one for your phone.

> [!IMPORTANT]
> **Requires [Lawnchair Launcher](https://github.com/LawnchairLauncher/lawnchair).** The stock ColorOS launcher is portrait-locked and gets letterboxed into a narrow strip on a landscape display. JANUS Cast switches the default home app to Lawnchair while casting to avoid that — install it **before** installing this module.
>
> **Built for ColorOS 16 / realme UI 7.** Adapted and verified on a single device, **realme GT 8 (RMX6699)**. Other ROMs and devices are untested. See [Compatibility](#compatibility).

---

## The two problems it fixes

**1. Wrong aspect, soft picture**

A 1440×3136 phone mirrored to a 1080p TV is squeezed through a non-uniform scale. Everything looks stretched and soft.

JANUS sets `Display 0` to `1080×1920` logical plus a landscape lock, giving an app area of exactly `1920×1080` — identical to the sink. SurfaceFlinger's mirror transform becomes an identity. Measured on a real device: `needsFiltering=false`, `layerStackSpace == framebufferSpace`.

**2. The home screen can't go landscape**

OEM launchers (ColorOS, HyperOS) are portrait-locked and non-resizable. On a landscape external display Android letterboxes them into a narrow portrait strip (measured: a 608×1080 window inside 1920×1080), so icons look crammed together. No `wm` knob changes this — verified against seven standard AOSP controls, all no-ops.

JANUS switches the default launcher to [Lawnchair](https://github.com/LawnchairLauncher/lawnchair) while casting (which fills the screen: `Rect(0,0-1920,1080)`), and switches back on disconnect.

---

## Features

- **Event-driven** — blocks on `p2p0` link state and `/sys/class/drm` uevents instead of polling, so idle cost is ~0.01 % of one core. Applies within ~1 s, restores in ~1.5 s
- **1:1 mirroring** — no scaling, no pillarboxing, no resampling
- **Launcher-aware** — swaps to a landscape-capable launcher during casting
- **Baseline restore** — captures `wm size` / `wm density` / rotation / `fixed-to-user-rotation` / default home *before* touching anything, and writes back the exact values (never guessed defaults)
- **Verify-then-rollback** — every write is read back; a mismatch triggers one retry and then a rollback
- **No injection, no patching** — only public `wm`, `settings` and `pm` interfaces. No Frida, no SurfaceFlinger hooks, no partition modification
- **Conservative** — if the display dump can't be parsed, it does *nothing*
- **Failsafe** — boot-time restore, crash-loop guard, and an out-of-module watchdog that survives the module being disabled

---

## Compatibility

| | |
|---|---|
| **Designed for** | ColorOS 16 / realme UI 7 |
| **Validated on** | realme GT 8 (RMX6699) only |
| **Tested against** | Miracast → Sony BRAVIA KDL-60W850B, 1920×1080 @ 30 fps |
| **Other ROMs / devices** | **Untested.** Not adapted, not verified |

The module depends on behaviour that turned out to be vendor-specific:

- ColorOS assigns the Wi-Fi virtual display its **own `layerStack`** (`3`), contradicting the AOSP mirror rule — hence the `MIRROR_TYPES` fallback
- ColorOS's launcher is **portrait-locked and non-resizable**, which is why a launcher swap exists at all
- `wm size` overrides **survive reboot** on ColorOS while `wm density` overrides do not

On a different skin these may not hold. If you want to try it elsewhere, run `extd detect` first (read-only, writes nothing) and confirm the decision looks sane before letting the daemon act.

---

## Requirements

| | |
|---|---|
| Root | KernelSU (tested) or Magisk |
| Android | **ColorOS 16 / realme UI 7** (Android 16). Other builds untested |
| Sink | Any Miracast sink or DP-Alt-Mode display |
| Launcher | **[Lawnchair Launcher](https://github.com/LawnchairLauncher/lawnchair) — required** |

---

## Install

**1. Install the launcher first**

Get [Lawnchair Launcher](https://github.com/LawnchairLauncher/lawnchair) from its [releases page](https://github.com/LawnchairLauncher/lawnchair/releases) and launch it once so Android registers it as a home app. JANUS Cast does not bundle or install it, and will silently skip the launcher swap if it is missing.

**2. Install the module**

Download `janus-cast-v1.1.0.zip` from Releases and install it in KernelSU, then reboot.

Or via ADB:

```bash
sh tools/install.sh
```

This copies the module to `/data/adb/modules/extdisplay` and installs the watchdog to `/data/adb/service.d/extdisplay-guard.sh`. Reboot, or start it immediately:

```bash
adb shell 'su -c "/data/adb/modules/extdisplay/service.sh"'
```

---

## Usage

```bash
su -c '/data/adb/modules/extdisplay/bin/extd status'    # state + recent log
su -c '/data/adb/modules/extdisplay/bin/extd detect'    # show the decision, write nothing
su -c '/data/adb/modules/extdisplay/bin/extd on'        # apply now
su -c '/data/adb/modules/extdisplay/bin/extd off'       # restore now (sticky until unplug)
su -c '/data/adb/modules/extdisplay/bin/extd stop'      # stop daemon and restore
su -c '/data/adb/modules/extdisplay/bin/extd start'     # restart daemon
```

### Emergency recovery

```bash
adb shell 'su -c "wm size reset; wm density reset; wm fixed-to-user-rotation default; wm user-rotation lock 0"'
```

or `sh tools/recover.sh`.

---

## Configuration

`/data/adb/extdisplay/config.conf` — created on first install from `config.sample.conf`.

| Key | Default | Description |
|---|---|---|
| `LANDSCAPE_ROT` | `1` | Landscape direction: `1` = 90° CCW, `3` = 90° CW |
| `DENSITY_MODE` | `external` | `external` (use the sink's reported DPI), `ratio` (match the phone's dp height), or `fixed` |
| `DENSITY_MIN` / `DENSITY_MAX` | `160` / `480` | Clamp for the sink's DPI |
| `MIRROR_TYPES` | `WIFI` | Display types treated as mirrored regardless of `layerStack` |
| `SWITCH_LAUNCHER` | `1` | Swap the default launcher during casting |
| `LANDSCAPE_LAUNCHER` | `app.lawnchair/app.lawnchair.LawnchairLauncher` | Launcher component used while casting |
| `BURST_TICKS` | `30` | Seconds of 1 Hz probing after a link event, until the virtual display registers |
| `WATCHDOG_INTERVAL` | `60` | Idle safety heartbeat (seconds). While idle the module blocks on link/uevent events instead of polling; this tick only re-reads a few sysfs bytes. `0` disables it |
| `ACTIVE_INTERVAL` | `1` | Poll interval while casting (seconds) |
| `MISS_DEBOUNCE` | `2` | Consecutive "gone" samples before restoring |
| `ACCEPT_ANY_EXTERNAL` | `0` | Ignore all heuristics, follow any non-internal display (debug) |
| `MAX_PIXELS` | `3686400` | Refuse sinks above this (1440p). Raise to `8294400` for 4K |

Apply changes with `extd stop && extd start`.

---

## How it works

**`wm size` takes the natural (portrait) orientation.** For a 1920×1080 sink the correct call is `wm size 1080x1920` plus `wm user-rotation lock 1` — writing `1920x1080` produces a malformed portrait layout.

**`layerStack` is not a reliable mirror test.** AOSP says a mirrored logical display shares the source's layer stack, but ColorOS assigns the Wi-Fi virtual display its own (measured: `3`). Following the standard rule alone makes the module silently do nothing on Miracast. JANUS treats a display as mirrored if `layerStack` matches **or** its type is listed in `MIRROR_TYPES`.

**Changing the default launcher doesn't change what's on screen.** The running launcher task keeps the foreground; the swap only takes effect on the next HOME. JANUS explicitly brings the target launcher forward — but only when you're already on a home screen, so it never yanks you out of an app.

**Everything is baseline-driven.** Six values are captured before the first write and restored one by one. If there was no override to begin with, `reset` is used rather than a guessed value.

---

## Tested configuration

The only configuration this module was adapted and verified against:

- **realme GT 8 (RMX6699)**, ColorOS 16.0.10.500 (CN01), Android 16 (SDK 36), KernelSU
- Miracast → Sony BRAVIA KDL-60W850B, 1920×1080 @ 30 fps

Sink side: `needsFiltering=false`, `layerStackSpace == framebufferSpace == 1920×1080`. Phone side: even letterboxing (`content=Rect(0,288,1440,2848)`), no stretching. Daemon costs ≈ 0.15 % of one core.

Full evidence, including negative results and dead ends, is in [`docs/REPORT.md`](docs/REPORT.md).

---

## Known limitations

- **1080p30 ceiling** — negotiated by the sink. A 2013-era TV offers no more; the phone cannot raise it.
- **Sink bitrate** — Wi-Fi Display rate control is sink-driven. Weak P2P signal (measured −83 dBm at distance vs −31 dBm up close) directly costs picture quality.
- **Colour** — the vendor `WFDV4L2ENC` hardware encoder exposes no userspace colour controls. If the sink shows oversaturation, compensate on the sink.
- **Launcher swap needs a landscape-capable launcher.** Without one, the home screen stays letterboxed.
- **Wired DP untested** — the DRM connector exists (`card0-DP-1`) but no cable was available.

---

## Safety

Every change is reversible and derived from a measured baseline. Restore paths: `extd off`, disconnect, boot-time `boot-restore`, the `service.d` watchdog (works even when the module is disabled), and `uninstall.sh`.

`wm size` overrides survive a reboot on ColorOS while `wm density` does not — which is exactly why boot-time restore exists.

---

## 中文速览

KernelSU 模块。投屏时把手机逻辑分辨率、DPI、方向对齐外屏，实现 1:1 无缩放镜像。

**装之前先装 [Lawnchair Launcher](https://github.com/LawnchairLauncher/lawnchair)。** 系统桌面竖屏锁定，横屏下会被压成屏幕正中一条竖条；模块投屏时把默认桌面切到 Lawnchair 来解决，所以 Lawnchair 是硬依赖。

断开后按实测基线逐项还原（分辨率、DPI、方向、默认桌面）。

```bash
sh tools/install.sh                                   # 安装
su -c '/data/adb/modules/extdisplay/bin/extd status'  # 查看状态
```

不注入、不 Hook、不改分区，只使用 `wm` / `settings` / `pm` 公开接口，全部可逆。

---

## License

MIT — see [LICENSE](LICENSE).
