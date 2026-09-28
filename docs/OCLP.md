# OCLP:12 及以后的图形 / 无线补丁

面向 **macOS 12 及以后**。Big Sur 11 上 HD 4000 是原生的,**不需要**这篇里的任何一步。

先记住一条界线:

> **OCLP 只 patch 系统卷**(`/System/Library/Extensions`、内核集合 / kernel collection),
> **一个字都不会写进 EFI**。所以「EFI 改了没生效」和「系统卷被补过」是两件独立的事。

本仓库的 EFI 已经按 OCLP 的要求配好(见下「跑之前 EFI 要满足什么」),
你要做的只是**在系统里跑一次 root patch**。

---

## 1. 用哪个版本

| 你的系统 | OCLP |
|---|---|
| 13 Ventura / 14 Sonoma | 2.0.0 以上都行 |
| 15.0 – 15.3 | 2.1.2 以上 |
| 15.4 及以后 | **2.3.2 或更新**(15.4 改过内核集合的构建方式) |
| 写作时的最新 | **2.5.1** |

下载:[OCLP Releases](https://github.com/dortania/OpenCore-Legacy-Patcher/releases)。
装完在「关于本机」里核对一下自己的系统版本,再决定拿哪个 OCLP ——
**15.7.x 配 2.3.x 就会出各种半吊子问题**。

OCLP 自己声明的可打补丁范围是 **11 – 15**(源码 `sys_patch/patchsets/detect.py`:
`_min_os = big_sur`、`_max_os = sequoia`)。26 不在支持范围内。

---

## 2. 跑之前 EFI 要满足什么

OCLP 在开跑之前会做一串前置检查,任何一条不过就会拒绝打补丁
(源码 `sys_patch/patchsets/detect.py` 的 `_detect()`)。逐条对应到本仓库:

| OCLP 检查 | 本仓库的值 | 说明 |
|---|---|---|
| SIP 要降到足够低 | `csr-active-config = 03080000` | 0x803 = `UNTRUSTED_KEXTS`(0x1) + `UNRESTRICTED_FS`(0x2) + `UNAUTHENTICATED_ROOT`(0x800),正是 OCLP 给 Ventura+ 定的那三档。**别改成 `00000000`**,SIP 一开补丁装不进去 |
| `SecureBootModel` 要关 | `Disabled` | 开着 OCLP 会报 "Secure Boot enabled" 罢工;占位三码也开不了(踩坑记录 13) |
| AMFI 要放开 | `AMFIPass.kext` + boot-args `-amfipassbeta` | OCLP 会去看 `com.dhinakg.AMFIPass` 有没有**真的加载**;加载了就把 AMFI 检查降成 `NO_CHECK`。AMFIPass 1.4.x 不带 `-amfipassbeta` 不会加载 → OCLP 报 "AMFI enabled" |
| FileVault 要关 | 未开 | 开着的话根卷是加密的,补不了 |
| 15 还要 Metallib | 联网自动下 | Sequoia 的 Metal 编译器换了格式,OCLP 要下 `MetallibSupportPkg`(几十 MB)。**没这个,Metal 起不来** |
| 13+ 可能要 KDK | 联网自动下 | 补内核集合时用;OCLP 会自己下 |

网络这条不是可选项:上面两项素材都在线拉。**第一次跑补丁前先确认网是通的**
(插网线最稳,Intel 82579LM 走 `IntelMausi`,免驱)。

> **别被 NVRAM 里的 `OCLP-Settings = -allow_fv -allow_amfi` 骗了。**
> 在 OCLP 源码里,`-allow_amfi` 只把 `SKIP_LIBRARY_VALIDATION` 置真
> (对应的是 `LIBRARY_VALIDATION` 那一档检查);而 Ivy Bridge 的显卡补丁集
> 要的是最高一档 `ALLOW_ALL`。真正让这条检查放行的是 **AMFIPass 被加载**
> (加载了它就整体降成 `NO_CHECK`)——所以 `-amfipassbeta` 不能删。
> T530 的作者也在他的 README 里写过这个 `-allow_amfi`「可能已经废弃」。

---

## 3. 跑

1. 打开 `OpenCore-Patcher.app`;
2. `Post-Install Root Patch` → `Start Root Patching`;
3. **看补丁列表**:HD 4000 的机器上应该出现
   `Graphics: Intel Ivy Bridge`;
4. 让它跑完,重启。

> ⚠️ **不要点 `Build and Install OpenCore`**。那个是让 OCLP 重建并覆盖 EFI 的,
> 而这份 EFI 是自己维护的(带 `Min/MaxKernel` 切档、自己的 ACPI 组合)。
> 点了会把 config 换成 OCLP 自己那版。我们只借它的 `Post-Install Root Patch`。

---

## 4. 怎么知道真的成了

```bash
# ① 显存 / Metal —— 这一条最直接
system_profiler SPDisplaysDataType | grep -iE "Chipset|VRAM|Metal|Device ID"
# 期望:Intel HD Graphics 4000 / VRAM 1536 MB / Metal: Supported

# ② 驱动有没有进内核集合
kmutil showloaded | grep -iE "AppleIntelHD4000|FramebufferCapri"

# ③ 驱动文件有没有被写进系统卷(补丁的实体)
ls -l /System/Library/Extensions/AppleIntelHD4000Graphics.kext

# ④ OCLP 自己怎么说(最后一份日志)
ls -t ~/Library/Logs/Dortania/OpenCore-Patcher*.log | head -1
```

① 里如果 `Metal: Supported` 缺了、或者 Dock 不透明、窗口拖动掉帧 —— 就是**没成**。

---

## 5. 抓日志:先看 OCLP 自己怎么说

### 5.1 一条命令,看显卡补丁到底打没打

OCLP 每次 patch 完,都会把「这次给这台机器打了哪些补丁」写进根卷:

```bash
plutil -p /System/Library/CoreServices/OpenCore-Legacy-Patcher.plist
```

输出里有 OCLP 版本、用没用 KDK / Metal Library,以及**补丁清单本身**。判断标准:

- 列表里有 **`Graphics: Intel Ivy Bridge`** → 显卡补丁**确实打过了**;
  还是没加速,往下查第 6 节;
- 只有 `Networking: …`(无线)之类、**没有** `Graphics:` → 补丁根本没进去,
  就是第 6 节第 1、2 条那两个坑。

### 5.2 OpenCore 这边的日志

本仓库的 config **默认开着调试日志**(`Misc/Debug`:`Target = 0x43`、
`AppleDebug = True`、`ApplePanic = True`),每次开机都会在 **EFI 分区根目录**留一份:

```
/Volumes/EFI/opencore-YYYY-MM-DD-HHMMSS.txt
```

里面有 OpenCore 自己的引导过程,还有**内核日志**(`AppleDebug` 的作用)——
`-v` 在屏幕上滚过去的那些,全在里面。

```bash
sudo diskutil mount disk0s1          # 挂系统盘的 EFI
ls -lt /Volumes/EFI/opencore-*.txt | head
```

> 排查完建议关掉(每次写 ESP、开机略慢):把 `Misc/Debug` 的 `Target` 改回 `0`、
> `AppleDebug` / `ApplePanic` 改回 `False`。改法照 `AGENTS.md` 2.2(用 `plistlib`),
> 改完两份 config 都跑一遍 `ocvalidate`。

### 5.3 一次性把系统侧信息收齐

```bash
bash tools/oclp-diag.sh            # 默认输出到 ~/Desktop/oclp-diag-<主机名>-<时间>.txt
```

只读脚本(不改 EFI、不改系统卷、不改 NVRAM),会收:显卡与加速器(IORegistry)、
上面那份补丁记录、补丁实体文件在不在(**含 `/Library/Extensions` 那份 AuxKC 副本**)、
`kextstat` 与 AuxKC 里到底装了哪些 kext、`MTLCompilerService` 有没有在崩、
SIP / NVRAM、电源管理、图形相关的系统日志、根卷挂在哪、以及**真正手动跑的那次补丁日志**。
**要发给别人看,发这一个文件就够。**

---

## 6. 「跑了补丁但还是没加速」的排查顺序

按概率从高到低:

1. **第一次跑只装了无线**。OCLP 在需要在线素材(KDK / Metallib)时会先把能装的装上,
   于是「Wi-Fi 好了、显卡没好」。**联网再跑一次**,确认列表里真有
   `Graphics: Intel Ivy Bridge`,再重启。
2. **Metallib / KDK 没下全**(主要是 15)。断网跑、或者下载中断,
   OCLP 会留下一个「装了一半」的状态。联网重跑一遍即可。
3. **系统上去了、EFI 换了**。`AMFIPass` 没加载(少 `-amfipassbeta`)、
   `csr-active-config` 被改回 `00000000`、`SecureBootModel` 被改成非 `Disabled`,
   都会让已经打进系统卷的驱动不生效 —— 这类问题**回到 EFI 里查**,不是在系统里。
4. **打到了另一个卷**。装过好几个系统 / 快照的机器上,`Post-Install Root Patch`
   认的是**当前启动的那个卷**。`diskutil info / | grep "Mounted"` 对一下。
5. **BCM 蓝牙 / 无线那套是另一回事**。它的补丁和显卡补丁在同一张列表里,
   别把「无线好了」当成「显卡也好了」。

### 6.1 补丁记录里有 `Intel Ivy Bridge`,显存也对,但就是没加速

比上面那几条更深一层。**症状长这样**:

- `system_profiler SPDisplaysDataType` 里 HD 4000、`VRAM 1536 MB` 都在,
  **唯独没有 `Metal: Supported`**;
- `ioreg -lw0 -r -c IOAccelerator` 是**空的**;
- 日志里 `com.apple.MTLCompilerService` 在被反复拉起(`launchd ... draining messages`)。

原因通常是 **Ventura 之后 IVB 显卡补丁走的是 AuxKC,不是内核缓存**:

在 Ventura 上 OCLP 判定 Ivy Bridge **不需要 KDK**(源码 `patchsets/hardware/base.py`:
`requires_kernel_debug_kit()` 默认 `False`),于是它把两个驱动
**从 `/System/Library/Extensions` 挪到 `/Library/Extensions`**,给它们的 `Info.plist`
塞上 `OSBundleRequired = Auxiliary`,再 `kmutil create --allow-missing-kdk --new aux`
重建**辅助内核集合**(`/Library/KernelCollections/AuxiliaryKernelExtensions.kc`),
最后删掉 `KextPolicy` 强制生效(源码 `kernelcache/kernel_collection/auxiliary.py`)。

所以「补丁打了」和「驱动真的进了内核」是两件事,要分开验:

```bash
# ① 加速器到底加载没有(0 = 没加速器)
ioreg -lw0 -r -c IOAccelerator | wc -l
kextstat | grep -iE "HD4000|Capri|IOAccelerator"

# ② AuxKC 里到底有没有这两个 kext
sudo kmutil inspect --collection /Library/KernelCollections/AuxiliaryKernelExtensions.kc \
  | grep -iE "HD4000|Capri"
ls -l /Library/Extensions/AppleIntelHD4000Graphics.kext/Contents/
defaults read /Library/Extensions/AppleIntelHD4000Graphics.kext/Contents/Info OSBundleRequired

# ③ 让驱动自己说为什么不上岗(只体检,不加载)
sudo kextutil -v -t /Library/Extensions/AppleIntelHD4000Graphics.kext 2>&1 | tail -40

# ④ Metal 一侧:编译器服务是不是在崩
ls -lt ~/Library/Logs/DiagnosticReports | head
sudo log show --last boot --info --debug --predicate 'process == "MTLCompilerService"' \
  2>/dev/null | grep -v 'draining messages' | tail -60

# ⑤ 真正手动跑的那次补丁日志(自动补丁会在 hackintosh 上跳过,别看错)
grep -l "Adding AuxKC support" ~/Library/Logs/Dortania/*.log
```

判读:

| 现象 | 含义 | 下一步 |
|---|---|---|
| ② 里找不到这两个 kext | AuxKC 没建成 / 被清理了 | 联网再跑一次 `Post-Install Root Patch`,跑完**别只靠右上角的自动补丁** |
| ② 有,但 ① 是 0 | kext 进去了却没匹配上 | 看 ③ 的输出;同时检查 iGPU 的 `AAPL,ig-platform-id` 与 `framebuffer-*` 注入 |
| **补丁日志里有 `requires authentication in System Preferences`** | 这两个 kext 没进 AuxKC 的构建名单,**只加载了一半也是这么来的**(真机上撞到过:`FramebufferCapri` 进了内核、`HD4000Graphics` 没进) | 手动再跑一次 root patch → 重启 → `kextstat \| grep -iE "HD4000\|Capri"` 复查;不行就去 系统设置 → 隐私与安全性 看放行提示 |
| ④ 的 `DiagnosticReports` 里真有 `MTLCompilerService` 崩溃报告 | Metal 编译器栈不对 | 这一步才轮到 `Metal 3802` 那套补丁 |
| ④ 只有一堆 `draining messages`、没有崩溃报告 | **正常**。`MTLCompilerService` 是按需拉起、用完就退的守护进程,launchd 每退一次就记一条;`MTLCompiler.framework/Versions/Current` 指向 `31001`(13.2.1 降级后的编译器)也**正常**,都不是线索 | 别看这两处,回到 ①②③ |

> 想从头再来:`Post-Install Root Patch` → `Revert Root Patches` → 重启 →
> 再 `Start Root Patching`。**每次都手动点**,别信自动补丁的静默结果。
> 卸载 / 还原的完整流程见上游
> [UNINSTALL.md](https://github.com/dortania/OpenCore-Legacy-Patcher/blob/main/docs/UNINSTALL.md)。


### 6.2 kext 进了内核,`IOAccelerator` 还是 0

比 6.1 再深一层:**两个 kext 在 `kextstat` / `kmutil showloaded` 里都在,
`ioreg -lw0 -r -c IOAccelerator` 却是空的,`ioreg -c IntelAccelerator` 也是空的** ——
也就是加速器服务根本没在 `IGPU` 上 attach 成功。到这一步要问的已经不是「kext 有没有加载」,
而是「匹配器有没有考虑过它」。xnu 的 IOKit 匹配日志默认是关的,打开它:

```
# EFI/OC/config.plist(或 config-install.plist)-> NVRAM -> Add ->
#   7C436110-AB2A-4BBB-A880-FE41995C9F82 -> boot-args 末尾追加:
io=0x1f iokit_print_verbose_match_logs=1
```

`io=0x1f` = `kIOLogAttach|kIOLogProbe|kIOLogStart|kIOLogRegister|kIOLogMatch`
(xnu `iokit/IOKit/IOKitDebug.h`;`io=` 是 TUNABLE,发行版内核一样有效),
配合已有的 `debug=0x100` 就能在 `log show` 里读到判定过程。重启后:

```bash
bash tools/ivb-check.sh /Volumes/EFI      # 看第 ④ 节
```

| ④ 里看到 | 说明 | 往哪查 |
|---|---|---|
| `IntelAccelerator[..]::attach(IGPU[..])` | 个性匹配上了,失败发生在 `start()` | 加速器依赖的内存 / 帧缓冲(它要的 stolen memory 来自帧缓冲) |
| 只有 `Registering:`、没有 attach | 个性压根没匹配上 | kext 的来源、`Info.plist`、AuxKC 构建 |
| `match category ... exists` | 那个匹配类别已被别的服务占了 | 谁先占的 |
| `ioclasscount` 里没有 `IntelAccelerator` | 类都没进内核 | kext 是白加载的,回到 6.1 |

排完把这两个参数从 boot-args 里删掉。

> **先看 BIOS 里的 Intel ME 是不是关着。** 2026-09-27 的现场结论:IVB 帧缓冲驱动里带着
> `AppleIntelMEIDriver` + `AppleIntelPAVP` + `AppleMEClientController`,**PAVP 会话要经
> MEI(PCI 0x16.0)走**。ME 关着时,Iokit 匹配、kext 加载、帧缓冲全都是好的,
> 唯独 `IntelAccelerator::start()` 会和 ME 客户端一起卡满 **整 30000 ms** 然后放弃:
>
> ```text
> AppleMEClientController::start(...) <1>            ← 另一个线程,和加速器同时开始
> IntelAccelerator::start took 30001 ms              ← 整 30 s,定时器到点
> DRMStatus: iTunes/Apple Store Content Access Problem ... ErrorCode: 8877652
> IntelAccelerator::start(IGPU) <1> failed
> ```
>
> 把 BIOS 里的 ME 打开、重启 → 两处 30 s 一起消失、Dock 透明。完整因果链见
> `docs/踩坑记录.md` 第 16 条,`tools/ivb-check.sh` 的 **ⓔ 节**就是抓这一幕的。

---

## 7. 关于机型:为什么是 `MacBookPro9,2` 而不是 T530 的 `MacBookPro10,1`

`5T33Z0/Lenovo-T530-Hackintosh-OpenCore` 用的是 `MacBookPro10,1`。这不代表
`MacBookPro9,2` 会让补丁不加载——**OCLP 的显卡补丁是按 GPU 架构挑的,不看机型**:

```python
# OCLP:sys_patch/patchsets/hardware/graphics/intel_ivy_bridge.py
def present(self) -> bool:
    return self._is_gpu_architecture_present(
        gpu_architectures=[device_probe.Intel.Archs.Ivy_Bridge]
    )
```

两个机型在 OCLP 的机型表里也完全等价(`datasets/smbios_data.py`):

| | `MacBookPro9,2` | `MacBookPro10,1` |
|---|---|---|
| 都在 `SupportedSMBIOS` / `ModernGPU`? | ✅ | ✅ |
| CPU 世代 | Ivy Bridge | Ivy Bridge |
| 出厂 GPU | Ivy Bridge(仅核显) | Ivy Bridge + NVIDIA Kepler |
| `Max OS Supported` | Catalina | Catalina |
| `Switchable GPUs` | — | **True** |
| AGDP 补丁(`AGDPSupport`) | 不在名单 | **在名单** |

X230 只有核显。装成 `10,1` 等于**主动告诉 macOS「我这台是双显卡机」**,
OCLP 那边就会多走 `Switchable GPUs` / `AGDP` 那几条路径,多出来的全是变数。
所以本仓库用 `9,2`,它**更贴近**这台机器,不是更远。

> 触发不了显卡补丁的原因在**显卡识别**上:补丁的 `present()` 要能枚举到
> 架构为 Ivy Bridge 的 GPU。`WhateverGreen` + `AAPL,ig-platform-id` 配错、
> 或者 iGPU 根本没被枚举出来,才会「补丁列表里没有 HD 4000」。

---

## 8. 备选:绕过 AuxKC,让 OpenCore 直接注入这两个 kext

6.1 那种「帧缓冲进了内核、加速器没进」的情况,除了重跑补丁,还有一条更硬的路:
**把两个 kext 放进 EFI,用 `Kernel -> Add` 让 OpenCore 塞进 BootKC**,
让「驱动进内核」这一段彻底不依赖 OCLP 的 AuxKC 构建。

> ⚠️ **现场结论(2026-09-27):这条路在本机 12+ 上没走通 —— 但不是因为「来源冲突」。**
> OpenCore 引导日志(`ESP 根目录的 opencore-*.txt`)里,这两条是这么收场的:
>
> ```text
> OC: Prelinked injection AppleIntelFramebufferCapri.kext (V11.7.10 | ...) - Invalid Parameter
> OC: Prelinked injection AppleIntelHD4000Graphics.kext (V11.7.10 | ...) - Invalid Parameter
> ```
>
> 也就是说 **BootKC 预链接注入被 OpenCore 自己拒了,这两个 kext 一个都没进内核**。
> 那么 `kextstat` 里能看到的那两条,来源只有一个:OCLP 放在
> `/Library/Extensions` 的那两份(内核日志里是
> `... exists in Optional(file:///Library/Extensions/...)` → `marked as loadable`)。
> **所以:别动 `/Library/Extensions` 那两份** —— 挪走等于把唯一能用的驱动拿走。
> 踩坑记录第 15 条里那句「配套动作是把 /Library/Extensions 挪走」,以及
> 「EFI 注入解决了半条」的结论,**都已经作废**(详见
> [`踩坑记录.md`](踩坑记录.md) 第 16 条)。
>
> 8.1 – 8.4 保留的价值:说清「能不能注入 Apple 的 kext」和「注进去也还差什么」。
> 8.5 那份一屏判定照旧可用 —— 它把 OC 日志里的 `Prelinked injection` 行也一并抓出来,
> 免得下次又拿「kextstat 里有」当成「EFI 注入生效了」。

### 8.1 能不能注入 Apple 自己的 kext

能。OpenCore 把注入的 kext 按 `CFBundleIdentifier` 加进内核集合,
与 Apple 原生 kext 同名的会被**替换**(所以改版原生驱动一直是这么玩的)。
OC 自己的文档里就有旁证:

> *Note*: `AppleIntelCPUPowerManagement.kext` is removed as of macOS 13.
> However, a legacy version can be injected and thus get patched using this quirk.

出处:`Docs/Configuration.tex` → `Kernel/Quirks/AppleCpuPmCfgLock`。
本仓库的 `AppleIntelCPUPowerManagement.kext`(见 3.6 节)走的就是同一条路。

### 8.2 素材从哪来

和 OCLP 自己用的是同一份,直取上游,不用解 DMG:

- [dortania/PatcherSupportPkg](https://github.com/dortania/PatcherSupportPkg)
  → `Universal-Binaries/11.7.10/System/Library/Extensions/`
  → `AppleIntelFramebufferCapri.kext`、`AppleIntelHD4000Graphics.kext`

OCLP 在 13 上取的就是 `11.7.10` 这一份(源码 `intel_ivy_bridge.py`
的 `_resolve_ivy_bridge_framebuffers()`;14.4 之前取 `11.7.10-23`、
之后取 `11.7.10-23.4`,三份内容一致,都是 `16.0.5`)。

两个 kext **原样拷、一个字不改**:

- Apple 的代码签名保持有效,不碰 `Info.plist`;
- `AppleIntelFramebufferCapri` 里那个 `OSBundleRequired = Safe Boot` **不用改** ——
  那个键只影响 Apple 自己的 `kcgen` 怎么给 AuxKC 选材,OpenCore 注入时根本不看它。

### 8.3 本仓库怎么放的

```text
EFI/OC/Kexts/AppleIntelFramebufferCapri.kext
EFI/OC/Kexts/AppleIntelHD4000Graphics.kext
```

`Kernel -> Add` 里跟着 `WhateverGreen.kext` 后面两条(两份 config 都有、**都开着**;
但**开着也没用** —— 上面那条现场结论:预链接注入会被拒,日志里明写 `Invalid Parameter`):

| BundlePath | MinKernel | MaxKernel | Arch |
|---|---|---|---|
| `AppleIntelFramebufferCapri.kext` | `21.0.0` | —— | `x86_64` |
| `AppleIntelHD4000Graphics.kext` | `21.0.0` | —— | `x86_64` |

`MinKernel = 21.0.0` 是硬要求,而且**这里的数字是 Darwin 内核版本、不是 macOS 版本号**
(macOS 12 = Darwin 21,和本仓库其它 kext 一致:`22.0.0` = macOS 13、
`20.4.0` = macOS 11.3)。**11 及以前的系统里这两个驱动是原生的**,
注进去等于用 11.7.10 覆盖系统自带的那份,反而容易出问题,所以 11 上这两条不生效。

### 8.4 这条路的边界(很重要)

EFI 注入能解决的**只有 `.kext`**。OCLP 的 IVB 补丁里还有 5 个**用户态 bundle**:

```text
AppleIntelHD4000GraphicsGLDriver.bundle
AppleIntelHD4000GraphicsMTLDriver.bundle    ← Metal 驱动
AppleIntelHD4000GraphicsVADriver.bundle     ← 视频硬解
AppleIntelIVBVA.bundle
AppleIntelGraphicsShared.bundle             ← libIGIL-Metal.dylib
```

外加 `Metal 3802` 对 `Metal.framework` / `MTLCompiler.framework` /
`GPUCompiler.framework` 的降级。这些东西的家在 `/System/Library/Extensions`
和 `/System/Library/Frameworks`,**只能靠 OCLP 写系统卷,EFI 里放不下也管不了**。

所以结论是:**「EFI 注入」不是「不要 OCLP」的替代品**,
它只是把「两个 kext 进内核」这一段从 AuxKC 挪到 BootKC。
`Post-Install Root Patch` 该跑还是要跑。

> 同名的两份 kext 会同时存在(EFI 里一份、OCLP 留在 `/Library/Extensions` 一份)。
> 内核按 `CFBundleIdentifier` 认人,先认到哪份就用哪份,EFI 这边通常在 BootKC 里被先认到。
> 所以**先重启看结果**,不要因为「有两份」就先 `Revert Root Patches`
> —— revert 会把上面那 5 个 bundle 一起带走,Metal 直接没了。

### 8.5 重启之后怎么判定

一条命令搞定(脚本在 [`../tools/ivb-check.sh`](../tools/ivb-check.sh)):

```bash
bash tools/ivb-check.sh
# 退出码 0 = 三条全过;1 = 还有没过的
```

它会逐条打「通过 / 没过」,把上下文(`IntelAccelerator` 节点、帧缓冲属性、
两份同名 kext 的取舍日志)一起收进 `~/Desktop/ivb-check-<主机名>-<时间>.txt`;
**只要有没过,还会自动把 `kextutil -v -t` 和内核日志也塞进同一个文件**,
直接发出来就行,不用另外跑命令。三条指标本身还是这三条:

```bash
# ① 两条都要在(重点看 AppleIntelHD4000Graphics 这一条这次有没有进)
kextstat | grep -iE "AppleIntelHD4000|Capri"

# ② 有加速器了(0 = 还是没加速)
ioreg -lw0 -r -c IOAccelerator | wc -l

# ③ 期望出现 Metal: Supported(中文系统是「Metal 支持: 是」,脚本两种都认)
system_profiler SPDisplaysDataType | grep -iE "Chipset|VRAM|Metal"
```

三条都对上 → 这条路走通了,以后 EFI 就是权威,root patch 里那两个 kext 不再是必需项。

**② 还是 0** 的时候要注意一个新现象:**kext 进内核了,但服务起不来。**
在 ioreg 里的表现是「`kextstat` 有这两条,`ioreg -lw0 -r -c IntelAccelerator` 仍是空」
—— 空不代表没匹配上,而是 `IOService` 被创建过、`start` 返回失败后被内核收走了。
这时候重点查 iGPU 上的注入属性(`PciRoot(0x0)/Pci(0x2,0x0)`),
尤其是**有没有声明一块 BIOS 根本没预留出来的显存** —— 见
[`踩坑记录.md`](踩坑记录.md) 第 10 节的属性表和 `framebuffer-stolenmem` 那一段;
脚本的「附」小节会把实际生效的属性原样打出来,直接对着表看。

### 8.6 怎么退回来

把 `Kernel -> Add` 里这两条的 `Enabled` 改成 `false`(或者连 `EFI/OC/Kexts` 下
那两个 kext 一起删),就回到「完全靠 OCLP」的状态,没有任何副作用。
