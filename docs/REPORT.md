# JANUS Cast — 技术报告

> 目标设备：realme GT 8（RMX6699）/ ColorOS 16.0.10.500(CN01) / Android 16 (SDK 36) / KernelSU
> **适配范围：本模块专为 ColorOS 16 / realme UI 7 设计，仅在一台 realme GT 8 上完成适配与验证。其他机型、其他 ROM 未做适配，行为未知。**
> 报告生成时间：2026-11-01
> 证据纪律：每条结论都标注来源等级，**未实测的一律标明未实测，不写成"应该可以"**。

---

## 一、可行性结论

| 项目 | 结论 | 依据等级 |
|---|---|---|
| 无线 Miracast 触发自动切换 | **可行（已实测）** | BRAVIA KDL-60W850B 实机连接，守护进程 2 秒内识别并完成切换 |
| 有线视频输出（DP Alt Mode） | **部分可行** | 内核 DRM 连接器 `card0-DP-1` 实测存在；物理出画面**未实测**（无显示器/线缆） |
| 内屏与外屏同步横屏 | **可行（已实测）** | 四项原语生效，`screencap` 输出 1920×1080，内屏等比 letterbox |
| 按外屏逻辑尺寸渲染（1:1 无损镜像） | **可行（已实测）** | 外屏 `layerStackSpace 1920×1080 → framebufferSpace 1920×1080`，`needsFiltering=false` |

一句话：**无线链路端到端已跑通并达到设计目标——电视拿到的是零缩放、零黑边的 1920×1080 原生画面。剩余唯一未验证项是有线 DP 的物理出画面。**

---

## 二、设备实测证据

### 2.1 基础事实（只读）

```
ro.product.model        RMX6699
ro.build.version.release 16
ro.build.version.sdk     36
ro.build.display.id      RMX6699_16.0.10.500(CN01)
su -c id                 uid=0(root) context=u:r:ksu:s0
```

Display 设备清单：**只有 1 个**

```
Display 0  "Built-in Screen"
  uniqueId  local:4630946650635782803
  real      1440 x 3136
  density   640 (515.15 x 507.35 dpi)
  type      INTERNAL
  layerStack 0
  rotation  0
  supportedModes  1440x3136 (60/90/120/144Hz) 与 1080x2352 (60/90/120/144Hz)
```

`wm` 命令能力（`wm help` 实测）：

- `size [reset|WxH] [-d DISPLAY_ID]`
- `density [reset|D] [-d DISPLAY_ID] [-u UNIQUE_ID]`
- `user-rotation [-d DISPLAY_ID] [free|lock] [rotation]`
- `fixed-to-user-rotation [-d DISPLAY_ID] [enabled|disabled|default]`
- `set-ignore-orientation-request [-d DISPLAY_ID]`

### 2.2 有线通路（只读）

```
/sys/class/drm/card0-DP-1/status   disconnected
/sys/class/drm/card0-DP-1/enabled  disabled
/sys/class/drm/card0-DP-1/edid     0 bytes
/sys/class/drm/                    card0-DP-1, card0-DSI-1, card0-Virtual-1/2 ...
```

结论：**内核 DRM 层确实暴露了一个 DisplayPort 连接器**，不是"根本没有 DP 硬件"的情况。是否物理可用只需插线看 `status` 是否变 `connected`、`edid` 是否非空。这个判断比"假定不支持"要乐观，但**不等于已支持**。

### 2.3 无线通路（只读）

`dumpsys display` 中 `WifiDisplayAdapter / WifiDisplayStatus / WifiDisplays / WifiDisplaySessionInfo` 等符号齐全，说明 Miracast 栈在 DisplayManager 内部是活跃的。

### 2.4 真机可逆测试（写操作，已全部还原）

施加 3 秒后立即撤销，全程在一条命令内完成：

| 阶段 | wm size | wm density | user-rotation | fixed-to-user-rotation | 截图 |
|---|---|---|---|---|---|
| 前 | 1440x3136 | 640 | lock 0 | default | 1440×3136 |
| 中 | **Override 1080x1920** | **Override 320** | **lock 1** | **enabled** | **1920×1080** |
| 后 | 1440x3136 | 640 | lock 0 | default | 1440×3136 |

**这是本项目最核心的一条证据**：四项原语在 ColorOS 16 上真实生效，且完全可逆。

### 2.5 持久化行为（三次重启实测）

这是最容易踩坑、也最容易被想当然的地方。

| 参数 | 跨重启是否存活 | 证据 |
|---|---|---|
| `wm size` 覆盖 | **存活** | 模块停用状态下重启后仍是 `Override size: 1080x1920` |
| `wm density` 覆盖 | **不存活** | 同一次重启后 `Physical density: 640`，无 Override |
| `fixedToUserRotation` | **存活** | 重启后仍为 `enabled` |

持久化文件不是 AOSP 的 `/data/system/display-manager.xml`（该文件在本机**不存在**），而是 ColorOS 自己的：

```
/data/system/display_settings.xml     (ABX 二进制格式，按显示 uniqueId 分组)
  实测内容仅包含 fixedToUserRotation，不含 size / density
```

（`wm size` 具体落在哪尚未定位，但这不影响工程结论——**只要它存活，就必须有开机还原**。）

### 2.6 崩溃恢复实测

场景：把设备置于"投屏中"状态（`state=active` + 覆盖生效），直接重启。

```
13:08:24  boot: 检测到上次异常遗留的激活状态，先还原
13:08:25  restore ok size=[]
13:08:25  daemon start pid=11106
```

重启后：`1440x3136 / 640 / lock 0 / default`，`state` 与 `origin.env` 均已清除。**通过。**

### 2.7 模块停用场景实测

场景：模块被置 `disable` 标记（KernelSU 不再执行模块内任何脚本），且设备卡在 1080×1920 覆盖上重启。

结果：由模块外的 `/data/adb/service.d/extdisplay-guard.sh` 自动还原为 `1440x3136 / 640 / default`。**通过。**

这条很关键：`service.d` 目录在本机确认会被执行，因此即使模块被停用，也不会把用户永久锁在错误分辨率。

### 2.8 无线 Miracast 实机验证（BRAVIA KDL-60W850B）

**连接对象**：Sony BRAVIA KDL-60W850B，经 WiFi P2P / Miracast 连接。

`WifiDisplayAdapter` 状态：

```
mCurrentStatus = WifiDisplayStatus{activeDisplayState=2, ...}
mActiveDisplay = BRAVIA KDL-60W850B (b2:xx:xx:xx:xx:xx)
mRemoteDisplayConnected = true
mAdvertisedDisplayWidth  = 1920
mAdvertisedDisplayHeight = 1080
```

新增显示（真实数据）：

```
displayId   3
name        BRAVIA KDL-60W850B
type        WIFI
real        1920 x 1080
density     320
layerStack  3          ← 关键，见 4.4
flags       FLAG_PRESENTATION | FLAG_TRUSTED
```

**镜像性质确认**（不是靠推断，是 SF 图层级证据）：

```
Layer [93 mirrored from 216,] Wallpaper BBQ wrapper#93
Layer [178 mirrored from 216,] com.android.launcher/com.android.launcher.Launcher#178
Layer [102 mirrored from 216,] StatusBar#102
...（共 116 个 "mirrored from" 图层）
```

外屏显示窗口数 = 0，内屏 = 19 → 外屏没有承载任何独立内容，内容全部来自镜像。

**切换后的合成测量**：

| | 改前 | 改后 |
|---|---|---|
| 外屏 layerStackSpace | 1920×1080 | 1920×1080 |
| 外屏 framebufferSpace | 1920×1080 | 1920×1080 |
| 外屏 `needsFiltering` | false | **false（恒为 1:1）** |
| 内屏 transform | ROT_0 | **ROT_90 + SCALE** |
| 内屏 content 区 | Rect(0,0,1440,3136) | **Rect(0, 288, 1440, 2848)** |

内屏结果：1920×1080 内容旋转 90° 后等比缩放到 1440 宽 = 2560 高，面板 3136 高 → **上下各 288px 黑边，无拉伸**。

这一条同时回答了一个此前未验证的问题：**ColorOS 的内屏对非常规逻辑尺寸是等比 letterbox，不是非等比拉伸。** 原先担心的"横向压扁 22%"没有发生。

### 2.9 运行时开销

`/proc/<pid>/stat` 20 秒采样：utime 0→0，stime 3→6，即 **30ms / 20s ≈ 0.15% 单核**。轮询间隔默认 2s。

---

## 三、踩到的三个真坑（值得单独记）

### 3.1 stdout 重定向到 /data 会让 Binder 调用失败

```
su -c "wm size 1080x1920"                        → rc=0，生效
su -c "wm size 1080x1920 > /data/adb/x.log 2>&1" → rc=2，Failed transaction (2147483646)
su -c "wm size 1080x1920 > /dev/null 2>&1"       → rc=0，生效
su -c "wm size 1080x1920 2>&1 | cat"             → rc=0，生效
```

把 `wm` / `settings` 的 stdout 重定向到 `/data/adb` 下的普通文件时，Binder 事务直接失败，**命令返回非 0 但外部无感知**。

规避方式：`extd` 里所有系统命令统一走命令替换（管道）捕获输出，再写日志。源码里有注释说明，不要改回 `>>` 重定向。

### 3.2 PID 复用让守护进程"假活"

重启后 `extd.pid` 里的旧 PID 可能被完全无关的进程占用（实测被 `vendor.oplus.hardware.riskdetect` 占了）。原来的 `kill -0 <pid>` 判定返回成功 → bootstrap 认为守护进程还活着 → 直接退出，模块永远不启动。

规避方式：`pid_alive()` 除了 `kill -0`，还要核对 `/proc/<pid>/cmdline` 里确实含 `extd`。

### 3.3 layerStack 不是可靠的镜像判据

见 4.4。ColorOS 给无线镜像虚拟显示分配独立 layerStack（实测 3），与 AOSP 文档语义不符。若只按 layerStack 判断，无线投屏场景下模块会**完全不动**，且日志里没有任何异常——属于"静默失效"，最难发现。已改为按显示类型兜底。

---

## 四、底层原理

### 4.1 两条完全不同的显示管线

```
有线 DP
  USB-C → PD 协商 → DP Alt Mode → DRM connector card0-DP-1
  → HWC 作为物理显示设备 hotplug 上报
  → DisplayManagerService 新建 LogicalDisplay（type=EXTERNAL）
  → 是否镜像由 DMS 决定（看 layerStack）

无线 Miracast
  WiFi P2P → RTSP 协商 → WifiDisplaySource 得到 sink 分辨率
  → WifiDisplayAdapter 创建 VirtualDisplay（type=WIFI）
  → SurfaceFlinger 把 Display 0 的图层栈按虚拟显示尺寸缩放合成
  → 编码器 → RTP → 电视
```

**两者事件源不同**这一点你原先的直觉是对的：有色有内核 sysfs 可看，无线没有。

### 4.2 为什么"改成和外屏一样大"能解决问题

镜像时 SurfaceFlinger 会把 Display 0 的合成结果缩放到虚拟显示尺寸。

```
缩放系数 = 外屏尺寸 / Display 0 逻辑尺寸
```

当两者相等时，系数 = 1.0：零重采样、零黑边、零压扁。这就是"手机竖屏画面被压缩/裁切/拉伸"的根因消除方式——不是"调整比例更接近"，而是让比例差**根本不存在**。

### 4.3 `wm size` 的朝向语义（容易搞反）

`wm size` 设置的是**自然朝向（纵向）**下的逻辑尺寸。

外屏 1920×1080（横向）→ 正确写法是 `wm size 1080x1920` + `wm user-rotation lock 1`，此时 app 区才是 1920×1080。直接写 `wm size 1920x1080` 会得到纵向 1920×1080 的畸形布局。

### 4.4 镜像 vs 扩展的判据（最初判断错了，已修正）

按 AOSP 语义，被设置为镜像的 `LogicalDisplay`，`getLayerStack()` 应返回**源显示**的 layerStack。据此最初写成：

```
layerStack == 内屏  → 镜像
layerStack != 内屏  → 扩展，不动内屏
```

**这条在 ColorOS 上是错的。** 实测 BRAVIA 连接后：

```
外屏 layerStack = 3       内屏 layerStack = 0
```

按原判据会被判成"扩展"，模块全程不动作。但 SurfaceFlinger 里 116 个图层都标着 `mirrored from`，且外屏窗口数为 0——**这是标准的镜像**。ColorOS 只是给虚拟显示分配了一个独立的 layerStack 编号，实际镜像由 SF 在合成层完成。

修正后的判据（`extd` 里的 `is_mirror()`）：

```
1. ACCEPT_ANY_EXTERNAL=1            → 一律跟随（调试用）
2. layerStack == 内屏 layerStack     → 镜像
3. type 命中 MIRROR_TYPES（默认 WIFI）→ 镜像
```

第 3 条是修正的核心：手机上不存在桌面模式，`type=WIFI` 的虚拟显示必然是镜像，用类型判断比用 layerStack 稳。`EXTERNAL` 类型仍只认同 layerStack，避免把真正的扩展桌面误改。

对应回归用例：`tests/fixtures/mirror-wifi-ls3.txt`（完全复刻 BRAVIA 实测形态），断言 `layerStack=3` 仍判定为 MIRROR。

### 4.5 厂商桌面会拒绝横屏

MoniTune 的 README 明确写了 HyperOS 桌面是竖屏锁定，光改 `user_rotation` 压不住。ColorOS 大概率同病，因此模块额外调用：

```
wm fixed-to-user-rotation enabled
```

这是 AOSP 提供的「忽略应用自身方向请求、强制按用户旋转」的开关，比叠一层悬浮窗干净得多，也不需要任何额外权限。

---

## 五、方案评估（对照你列的 A/B/C/D）

| 方案 | 评估 | 结论 |
|---|---|---|
| **A. 原生命令** `wm size` / `wm density` / `user-rotation` / `fixed-to-user-rotation` | 本机全部实测可用，`-d DISPLAY_ID` 也支持 | **采用**。是唯一"零注入、零改分区、完全可逆"的路径 |
| **B. DisplayManager / SurfaceFlinger 直连** | 需要 binder 直调或注入 SF 进程；AOSP 没有对外开放"改某显示逻辑尺寸"的稳定接口，`LogicalDisplay` 的 override 入口就是 `wm size` 背后那条 | **不必**。收益为零，风险巨大 |
| **C. ColorOS 专有服务** | 确认存在：`OplusDisplayState`、`OplusFeatureDMR`、`OplusFeatureMEMCGame` 等私有图层；持久化文件也换成了自家 ABX 格式 | **只读观测，不修改**。无公开接口，改私有文件违反你的约束 |
| **D. 自动检测** | 有线：`/sys/class/drm/card*-DP-*/status`（常驻读，成本≈0）；统一：`dumpsys SurfaceFlinger --display-id` 行数变化做触发，变化时才跑一次完整 `dumpsys display` 解析 | **采用**。稳态 0.15% 单核 |

关于**不采用 Frida / 注入**：OPlusAutoHR 的 README 自己写了它的 Canary 版用 Frida 注入 `surfaceflinger`，并明确警告可能导致 SF 不稳定、热插拔异常，以及被反作弊判定异常环境。这条路你原本就禁掉了，实测数据也支持这个决定——我们需要的原语 `wm` 全都给得到，没有任何理由去注入。

---

## 六、开源项目评估（api.github.com 实时查询）

| 项目 | 许可 | 最近提交 | 语言 | 与本项目的关系 |
|---|---|---|---|---|
| **MoniTune** `goodeesh/monitune` | **MIT** | 2026-10-27 | Dart | **思路最接近**：Shizuku/root + 改分辨率/DPI/强制横屏 + 接入时自动应用。MIT 许可**可以借鉴代码**。但它面向小米/HyperOS，且是 App 形态（要常驻前台服务） |
| **SecondScreen** `farmerbb/SecondScreen` | Apache-2.0 | 2024-09-14 | Java | 经典方案，profile 化改分辨率/DPI。README 自己声明"**仅适用于 AOSP / Google 原生 ROM，在厂商定制 ROM 上不保证正常**"。可作为接口用法参考，**不能当作 ColorOS 兼容性的证据** |
| **OPlusAutoHR** `Kimuinaii/OPlusAutoHR` | NOASSERTION（Source Available，**非开源**） | 2026-08-28 | JS | 明确支持 ColorOS，但走的是 **Frida 注入 surfaceflinger** 的路线，且自称实验性、有稳定性与反作弊风险。**代码不可复制**，只可作为"ColorOS 上深水区在哪"的行为参考 |

结论：**MoniTune 是唯一可以直接借鉴代码的项目（MIT）**，但它验证的是 HyperOS 路径；SecondScreen 的方法论可用但兼容性声明对我们不利；OPlusAutoHR 证明确实存在 ColorOS 专有层，但它选择的手段本方案明确不采用。

本项目没有复制以上任何代码，是独立实现；MoniTune 的 README 只用来确认"厂商桌面竖屏锁定"这个已知坑。

---

## 七、风险与恢复

| 风险 | 实际评估 | 缓解 |
|---|---|---|
| **黑屏 / 无法操作** | 低。`wm size` 只改逻辑尺寸，不碰 HWC 模式；最坏是画面畸形，系统仍在跑 | `tools/recover.sh` 一条命令还原；ADB 在畸形状态下依然可用 |
| **卡在错误分辨率** | **中→已缓解**。实测 `wm size` 覆盖跨重启存活 | 开机 `boot-restore`（实测通过）+ 模块外 `service.d` 守卫（实测通过）+ `uninstall.sh` 自动还原 |
| **DPI 异常导致 UI 巨大/极小** | 中。外屏 density 若不合理会直接毁掉可读性 | 裁剪到 [160, 480]，可配置；`density` 覆盖不跨重启，风险自愈 |
| **分辨率不兼容** | 低。超过 1440p 直接拒绝（`MAX_PIXELS`），畸小尺寸拒绝 | 阈值可配置 |
| **投屏延迟 / 性能** | 未测。改逻辑尺寸会改变合成缓冲大小，1080p 下影响应可忽略，4K 未放开 | 默认上限 1440p |
| **扩展模式下误改内屏** | 低。`MIRROR_TYPES=WIFI` + layerStack 双判据，`EXTERNAL` 类型仍只认 layerStack | `ACCEPT_ANY_EXTERNAL` 默认 0 |
| **`dumpsys` 解析失败被误判为"外屏消失"** | 已有防护：解析结果为空时**只跳过，不还原** | 离线测试第 12 项覆盖 |
| **厂商桌面不跟随横屏** | **已实测通过**。BRAVIA 连接后内屏 content 区为 Rect(0,288,1440,2848)，1920×1080 完整横屏呈现 | `fixed-to-user-rotation enabled` |
| **模块被停用后残留** | **已实测并已修复** | `/data/adb/service.d/extdisplay-guard.sh` |
| **SF 显示列表瞬时抖动** | 实测 `--display-id` 在合成刷新瞬间会短暂只报 1 个显示 | 判定用完整 `dumpsys display`，且需连续 `MISS_DEBOUNCE` 次才还原；即便误还原也会自动重新应用 |

紧急恢复（任何情况下都能用）：

```bash
adb shell 'su -c "wm size reset; wm density reset; wm fixed-to-user-rotation default; wm user-rotation lock 0"'
```

---

## 八、证据分级汇总

### 官方资料 / AOSP 语义已确认
- `wm size` 走 `WindowManagerService` → `DisplayManagerService`，设置的是自然朝向逻辑尺寸
- `fixed-to-user-rotation` 语义：忽略应用方向请求、强制用户旋转
- ⚠️ "镜像显示共享源显示 layerStack" 这一条**在本机被实测推翻**，见 4.4

### 设备只读检测已确认
- 设备型号 / Android 16 / ColorOS 16 / KernelSU root
- 单一 Display 0，1440×3136@640，单层栈
- `wm` 全部子命令与 `-d` 参数存在
- WifiDisplayAdapter 存在于 DisplayManager
- DRM `card0-DP-1` 连接器存在（当前 disconnected）
- 持久化文件为 ColorOS 私有 `display_settings.xml`

### 设备实际测试已确认
- 四项原语写入生效、`screencap` 输出 1920×1080、完全可逆
- `wm size` 覆盖跨重启存活；density 不存活；fixedToUserRotation 存活
- 崩溃重启 → 开机自动还原
- 模块停用 → 模块外守卫自动还原
- 守护进程 0.15% 单核
- **Miracast 连接 BRAVIA：识别 1920×1080@320、type=WIFI、layerStack=3，2 秒内完成切换**
- **镜像后外屏 `needsFiltering=false`，layerStackSpace == framebufferSpace == 1920×1080，零缩放**
- **内屏等比 letterbox，上下各 288px 黑边，非拉伸**
- **外屏确为镜像：116 个图层 `mirrored from`，外屏窗口数 0**

### 理论上可行但尚未验证
- 有线 DP 实际出画面（连接器在，未插线）
- 有线 DP 场景下 ColorOS 是镜像还是扩展

### 当前设备不支持
- 暂无。**没有发现任何一项被硬件断死的需求。**

---

## 九、下一步

无线链路已经端到端闭环。只剩有线 DP 一项：

1. 插上 USB-C 显示器 / 转接器，看 `/sys/class/drm/card0-DP-1/status` 是否变 `connected`、`edid` 是否非 0
2. 跑 `./tools/probe.sh dp`，看新增显示的 `type` 与 `layerStack`
3. `su -c '/data/adb/modules/extdisplay/bin/extd detect'` 看模块是否识别

若 DP 场景下 ColorOS 把它标成 `EXTERNAL` 且 layerStack ≠ 0（真扩展桌面），模块会按设计不动内屏——那时需要你决定"扩展时是否也要把内屏对齐外屏"，加一条 `MIRROR_TYPES=WIFI,EXTERNAL` 即可，是策略开关，不是技术障碍。

---

## 十、桌面横屏问题：根因与解决办法

**现象**：投屏切到 1920×1080 横屏后，ColorOS 桌面被压成屏幕正中一条竖条，图标挤在一起；设置、浏览器等普通应用则完整全屏横屏。

### 根因（实测）

```
显示 overrideConfig : sw720dp w1280dp h720dp 320dpi land    ← 显示是横屏
桌面 mBounds         : Rect(656, 0 - 1264, 1080)            ← 只有 608×1080
桌面 mFullConfiguration : sw304dp w304dp h720dp port         ← 桌面自认是 304dp 宽竖屏
```

608 = 1080 × (1080/1920)——按手机原始竖屏宽高比在横屏里居中 letterbox。桌面拿到 304dp 宽画布仍按 4 列排布，于是图标重叠。

### 已尝试、全部无效（每种都做过 force-stop + 重启桌面）

| 手段 | 结果 |
|---|---|
| `wm density` 640 / 320 / 240 / 160 | 窗口恒 608×1080 |
| `wm fixed-to-user-rotation enabled/default` | 只影响显示旋转 |
| `wm set-ignore-orientation-request true` | 无变化 |
| `settings put global force_resizable_activities 1` | 无变化 |
| `wm set-letterbox-style --aspectRatio 1.7778` | 无变化 |
| `wm set-letterbox-style --minAspectRatioForUnresizable 1.7778` | 无变化 |
| `settings put secure landscape_launcher 1/true/force` | 无变化 |

结论：桌面窗口尺寸由 ColorOS 自己的 WindowManager/Launcher 逻辑决定，不受任何标准 AOSP 旋钮控制。改显示参数这条路走不通。

### 解决办法：投屏期间切换默认桌面（已实测通过）

改用支持横屏的第三方桌面（本机已装 Lawnchair），通过 `cmd package set-home-activity` 在投屏时切换：

```
cmd package set-home-activity app.lawnchair/app.lawnchair.LawnchairLauncher
```

**实测结果**：

| 项 | ColorOS 桌面 | Lawnchair |
|---|---|---|
| 窗口 bounds | Rect(656, 0 - 1264, 1080) | **Rect(0, 0 - 1920, 1080)** |
| 配置 | sw304dp w304dp port | **sw540dp w960dp h540dp land** |
| 观感 | 中间一条竖条，图标重叠 | **铺满全屏，网格正常** |

注意点（都已验证）：

- `cmd package set-home-activity` 在 **root（u:r:ksu:s0）下同样可用**（返回 Success），不像 `wm` 那类命令有 Binder 限制
- 切换默认桌面**不会强杀正在运行的桌面**——当前焦点仍是旧桌面，要等下次按 HOME 才生效，因此不打断用户
- 原桌面组件记入基线（`ORIG_HOME`），断开时逐字还原，不写死 `com.android.launcher`
- 只切默认桌面**不会把画面换掉**：实测切换后焦点仍是旧桌面。因此两个方向都会主动拉起（先 `KEYCODE_HOME`，不生效再 `am start -n <component>` 兜底），且仅在用户当前停留在桌面时才动作
- 桌面切换失败不影响显示切换（`apply` 会记日志但返回成功）

**还原路径**：`extd off` / 断开投屏 / 开机 `boot-restore` / 模块停用时的 `service.d` 守卫 / `uninstall.sh`，四条路径都会把默认桌面换回原值。

### 桌面切换踩到的两个坑（复现条件都是"外屏真的接上"）

1. **`dumpsys window` 里有多条 `mCurrentFocus`**。接上外屏后，外接虚拟显示那条是 `mCurrentFocus=null`，排在最前面；手机那条才是真焦点。原来用 `grep mCurrentFocus | head -1` 会拿到 null，逻辑误判成"用户不在桌面"直接退出，桌面切换静默失效。改为只取 `mCurrentFocus=Window` 的行。
2. **比对前台窗口不能只比包名**。Lawnchair 的设置页 `app.lawnchair.ui.preferences.PreferenceActivity` 与桌面 `app.lawnchair.LawnchairLauncher` 同包，按包名比对会把"停在设置页"误判为"已经在桌面上"。必须比对完整组件名。

另外 `extd off` 改为**在本次投屏周期内粘住**（写 `suppressed` 标记），否则守护进程下一轮（约 6 秒后）会把它重新应用回去；外屏断开时抑制标记自动清除。

### 断开响应延迟优化

原实现断线后要 4–5 秒才还原，拆解后发现三个叠加因素：

| 环节 | 原耗时 | 原因 | 处理 |
|---|---|---|---|
| 断线判定 | 2–10s | 需连续 2 次解析确认，但第 2 次解析被"每 5 拍才刷新"卡住 | `miss>0` 时每拍都解析；投屏中改用 `ACTIVE_INTERVAL=1` |
| 会话确认 | 1 拍 | 无条件等第二次采样 | 复用同一次 dumpsys 里的 `mRemoteDisplayConnected`，会话已断则直接判定 |
| 还原执行 | ~4s | `sleep 1` + `sleep 2` 写死等待 | 改为 0.2s 轮询到目标状态即返回，实测 **1.5s** |

实测：`extd off` 1510ms，`extd on` 2032ms。端到端断线还原从 4–5s 降到约 2.5s。

### 空闲功耗优化：轮询改事件驱动

原来空闲时每 2 秒 fork 一次 `dumpsys`，每天 43,200 次唤醒，实测 0.21% 单核。

改为：

- **无线**：`ip monitor link` 监听 `p2p0` 的链路状态（netlink，阻塞等待，零唤醒）
- **有线**：`inotifyd` 监听 `/sys/class/drm`
- 命中后 `kill -USR1` 打断守护进程的 `sleep & wait`，立刻做一次完整判定
- **兜底心跳 60 秒**：不跑 dumpsys，只 `read` 几个 sysfs 字节（`p2p0/operstate`、`card*-DP-*/status`）做断言，确认空闲就直接跳过

实测空闲 CPU：

| | 120 秒 CPU | 单核占比 | 每天唤醒 |
|---|---|---|---|
| 轮询（v1.1.0） | 25 jiffies | 0.208% | 43,200 |
| 事件驱动（v1.2.0） | 1 jiffy | **0.008%** | ~1,440 + 事件 |

投屏期间仍保持 1 秒轮询，保证断开判定速度不变。
