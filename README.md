# ThinkPad X230 · 黑苹果 OpenCore EFI(macOS 11 – 15)

[![macOS](https://img.shields.io/badge/macOS-11_--_15-000000)](https://www.apple.com/macos/)
[![OpenCore](https://img.shields.io/badge/OpenCore-1.0.7-blue)](https://github.com/acidanthera/OpenCorePkg)
[![ThinkPad](https://img.shields.io/badge/ThinkPad-X230-black)](https://psref.lenovo.com/syspool/Sys/PDF/withdrawnbook/ThinkPad_X230.pdf)

一台 2012 年的 X230,**一份 EFI 用 `Min/MaxKernel` 切档覆盖 Big Sur 11 → Sequoia 15**;
日常建议停在 **macOS Ventura 13**(理由见「[装哪个版本](#装哪个版本推荐-ventura-13)」)。

Ivy Bridge 的图形栈是 Apple 到 Monterey 才砍掉的:所以 **11 上 HD 4000 原生加速**,
**12 及以后要靠 OpenCore Legacy Patcher(OCLP)把驱动打回系统卷**。
这份 EFI 把两套东西都装进去了,开机时按内核版本自己挑。

> 本项目由不知名网友 **Hao** 与 **DeepSeek V4.1-Flash High** 共同完成。
> 感谢上游仓库 [`banhbaoxamlan/X230-Hackintosh`](https://github.com/banhbaoxamlan/X230-Hackintosh)、
> [`zyq8888/X230-MAC-OpenCore`](https://github.com/zyq8888/X230-MAC-OpenCore)
> 与 [RapidEFI](https://github.com/JeoJay127/RapidEFI-Tool);
> 多版本切档与 OCLP 的配法参考了
> [`5T33Z0/Lenovo-T530-Hackintosh-OpenCore`](https://github.com/5T33Z0/Lenovo-T530-Hackintosh-OpenCore)
> (同代 QM77 + HD 4000,一份 EFI 实测 10.13 → 26)。

> 本项目是玩具性质。目标不是让它变成主力机,而是让这套老硬件能优雅地跑起来。

---

## 这台机器

| | 型号 | 状态 |
|---|---|---|
| 机型 | ThinkPad X230(`23068CC`) | — |
| CPU | Intel Core i5-3230M(Ivy Bridge,2C4T,2.6–3.2GHz,**无 AVX2**) | ✅ |
| 内存 | 8GB DDR3L | ✅ |
| 硬盘 | Kingston SA400S37240G(240G,SATA AHCI `8086:1E03`) | ✅ |
| 核显 | Intel HD 4000(`0x01660003`) | ✅ 11 原生 / 12+ 需 OCLP 补丁 |
| 屏幕 | LG LP125WH2-SLB1 12.5" IPS 1366×768 | ✅ |
| 音频 | Realtek ALC269(`layout-id = 18`) | ✅ |
| 有线 | Intel 82579LM | ✅ |
| 无线 | Intel Dual Band Wireless-AC 7260 | ✅ 按版本切驱动,见下 |
| 蓝牙 | Broadcom BCM20702(`0A5C:21E6`) | ⚠️ 需冷启动 |
| 摄像头 | Bison `5986:02D2` | ✅ |
| 触摸板 | Synaptics + TrackPoint | ✅ `VoodooPS2` |
| 指纹 | UPEK/STMicro `147E:2020` | ❌ macOS 无驱动 |

**BIOS 设置**:本机是 `G2ETB7WW (2.77)`,要设的项不少,而且有几项藏在隐藏菜单里
(需要 [n4ru/1vyrain](https://github.com/n4ru/1vyrain/) 解锁)。逐项清单和理由见下面
「[BIOS 设置](#bios-设置必须先过一遍)」——**这项不过关,后面全是白折腾**。

---

## 装哪个版本:推荐 Ventura 13

这台机器的底子摆在这儿(i5-3230M 双核四线程 + 8G 内存,**没有 AVX2**),
选版本本质上是在「有多少驱动是原生的」和「系统有多新」之间取平衡。结论:

| 系统 | 内核 | 显卡 | 无线 | OCLP | 建议 |
|---|---|---|---|---|---|
| **Ventura 13** | 22.x | OCLP 补丁 | **`AirportItlwm_Ventura`(原生 Wi-Fi,不用 HeliPort)** | ✅ | **★ 首选** |
| Big Sur 11 | 20.x | **原生**(免补丁) | `AirportItlwm_BigSur` | ❌ 不要 | ○ 最轻,但系统太旧 |
| Monterey 12 | 21.x | OCLP 补丁(12.0+) | 要自己补一版 `AirportItlwm` | ✅ | ○ 中间档 |
| Sonoma 14 | 23.x | OCLP 补丁 | `itlwm` + HeliPort | ✅ | △ 更吃资源 |
| **Sequoia 15** | 24.x | OCLP 补丁 | `itlwm` + HeliPort | ✅ | **✗ 能跑,但不推荐日常用** |
| Tahoe 26 | 25.x | 不支持 | — | — | ✗ 不试 |

### 为什么是 Ventura

- **12 及以后里,唯一「无线还是原生」的一档**:`AirportItlwm` 是按系统版本编译的,
  Ventura 有官方对应的 `AirportItlwm_Ventura`,Wi-Fi 直接出现在菜单栏 ——
  不需要 **HeliPort** 那个常驻小工具,也不会在系统里多出一张「假以太网卡」。
- **OCLP 生态最成熟的一档**:13 不需要额外下载 Metal 素材
  (`MetallibSupportPkg` 是 15 才要的),补丁素材少、能踩的坑也少。
- **比 15 明显流畅**:15 上 HD 4000 是靠 OCLP 把 11.7.10 的老驱动打回系统卷 +
  对 Metal 做降级的;驱动本身不是为 24.x 写的。双核 + 8G 带 15 的图形栈非常吃力。

一句话:**13 是这台机器「原生程度」和「系统年龄」的最优交点。**

### Sequoia 15:EFI 支持,但不推荐

本仓库的 EFI **确实能装、能启动、能加速** 15(实测 Dock 透明、`Metal: Supported`),
但**不建议当日常系统**:

- 图形全靠 OCLP 把老驱动降级打回系统卷,窗口拖动、动画、滚动都能感觉到掉帧;
- 无线只有 `itlwm` + HeliPort,还要额外下一份 Metal 素材,失败面比 13 大;
- 系统本身对 8G 内存 + 双核就不友好,开几个网页就开始交换。

想尝鲜 15 可以,装完务必跑一次 OCLP(见「[装完之后](#装完之后12-要去跑一次-oclp)」一节)。

### Big Sur 11:最轻,但太旧

11 的图形栈是**原生**的,连 OCLP 都不用跑,kext 也最少 —— 从「省心」角度它其实最好。
但系统本身已经停止安全更新、能跑的新软件越来越少(Homebrew 也只是苟着),
所以把它当备选,而不是首选。

---

## BIOS 设置(必须先过一遍)

本机 BIOS 是 `G2ETB7WW (2.77)`,更老的版本大概率也能用,但下面这些值**一项都不能少**。
其中 `DVMT` 那两项出厂是隐藏菜单,要用 [n4ru/1vyrain](https://github.com/n4ru/1vyrain/)
刷一次才看得见(不用编程器)。

| 设置项 | 值 | 不这样会怎样 |
|---|---|---|
| Boot Mode | **UEFI Only** | Legacy 引导走不通 |
| CSM | **No(关)** | 开着 OpenCore 能引导、进度条走一半,但**进不去安装器**(踩坑记录 1) |
| SATA Controller | **AHCI** | 装 macOS 的硬前提 |
| Secure Boot | **Off** | 会拦下 OpenCore |
| VT-d | **On**(开着) | 本仓库有 `DisableIoMapper`,不用为它关 |
| `DVMT Pre-Allocated` | **128 MB** | 隐藏项;和 EFI 的 `framebuffer-stolenmem` 是一对(踩坑记录 10) |
| `DVMT Total Gfx Mem` | **Max** | 同上 |
| **Intel ME / AMT** | **On(开)** | 关掉的话显存只剩 4 MB、Dock 不透明(踩坑记录 16) |

**DVMT 和 EFI 里的 `framebuffer-stolenmem` 是一对**:BIOS 决定「显卡预留了多少内存」,
EFI 声明「显卡认为自己能拿走多少」。预留量没到 64 MB,驱动就会去用一段 BIOS
根本没留出来的内存 —— 轻则显存数字乱跳,重则**加速器起不来**。本机设的是 128 MB。

**Intel ME 看着像「用不上的带外管理」,12 及以后却必须开着**:
IVB 的 `AppleIntelFramebufferCapri` 里带着 `AppleIntelMEIDriver` + PAVP,
PAVP 会话要经 MEI(PCI `0x16.0`)走。ME 一关,PCI 上就没有这个设备 → PAVP 握手失败
→ `AppleMEClientController::start` 卡满 30 秒 → `IntelAccelerator::start()` 返回 false
→ **显存 4 MB、Dock 不透明**。

> 别用 `me_cleaner` / HAP 去裁 ME —— 裁掉等于掐断这条链路。
> `SSDT-IMEI.aml` 也救不了(它只补 ACPI 的 `device-id`,变不出 PCI 设备),
> 所以仓库里把它关着。

---

## 机型:为什么是 `MacBookPro9,2`

SMBIOS 选的是一台 2012 年的 13" MacBook Pro。理由:

- **平台最接近**:`9,2` 就是 **Ivy Bridge + HD 4000**,和 X230 同一代,
  图形、电源管理都按它匹配;而 X230 没有独显。
- **它不在 11 及以后的官方支持机型里**,所以启动时会被板号检查拦下 ——
  本仓库用 `Booter/Patch` 里的 **`Skip Board ID Check`**(OCLP 那条补丁),
  外加 boot-args 里的 `-no_compat_check`,两条互为保险。
- **为什么不抄 T530 那份 EFI 的 `MacBookPro10,1`**:两个机型在 OCLP 的机型表里
  是等价的(都 `Max OS Supported = Catalina`、都是 Ivy Bridge + HD 4000),但
  `10,1` 额外声明了 `Switchable GPUs = True`(出厂带 NVIDIA Kepler),而且
  **在 OCLP 的 `AGDPSupport` 名单里**。X230 只有核显,装成 `10,1` 等于主动告诉
  macOS「我这台是双显卡机」,凭空多出 `Switchable GPUs` / `AGDP` 几条分支。
  > 顺带澄清一个常见担心:**OCLP 的显卡补丁是按 GPU 架构挑的,不看机型**
  > (`intel_ivy_bridge.py` 的 `present()` 只判断有没有 Ivy Bridge 的 GPU),
  > 所以用 `9,2` **不会**导致 HD 4000 的补丁不加载。

**`SecureBootModel` 必须留在 `Disabled`**:仓库里的三码是官方 Sample 那种占位值
(UUID 全零),一旦开成 `Default` / `x86legacy`,OpenCore 会拿它去算 ApECID →
直接 `OC: Grabbed zero system-id for SB` 停机,连引导菜单都过不去。
换完真三码、想开 Apple 安全启动时再改回去(见 `AGENTS.md` 2.4、踩坑记录 13)。

**所有人上机前都该换成自己生成的三码**:

```bash
macserial -g MacBookPro9,2     # 取 SystemSerialNumber / MLB / SmUUID
```

`ROM` 填本机有线网卡的 MAC(6 字节),别留 `112233445566`。不换成真三码也能正常用,
但 **iCloud / iMessage / FaceTime 登不上**。

---

## 一份 EFI 覆盖哪些版本(怎么做到的)

`Kernel/Add` 里每个 kext 都带 `MinKernel` / `MaxKernel`,按内核版本自动生效,
所以一份 config 能从头管到尾:

| 系统 | 内核 | 挡位 |
|---|---|---|
| Big Sur 11 | 20.x | `AirportItlwm_BigSur`;不加载 IVB 注入、不加载 AICPUPM |
| Monterey 12 | 21.x | IVB 注入 + OCLP,NVRAM 的 `AirportItlwm` 要自己补一版 |
| Ventura 13 | 22.x | `AirportItlwm_Ventura`;AICPUPM 从这一档开始注入(**推荐的档**) |
| Sonoma 14 / Sequoia 15 | 23.x / 24.x | `itlwm` + HeliPort;15 跑完 OCLP 还要 `MetallibSupportPkg` |
| Tahoe 26 | 25.x | 不支持 —— OCLP 补丁集上限就是 15(`_max_os = sequoia`) |

**无线为什么切来切去**:`AirportItlwm` 是**按系统版本编译**的,每个大版本一份;
而它的上游到 Sonoma 14.4 就停更了,**没有 Sequoia 版**。
所以 14/15 换用 `itlwm.kext` —— 它自己实现网络栈,不依赖 Apple 的 Airport,
代价是要配一个叫 **HeliPort** 的小工具(见 [`docs/安装指南.md`](docs/安装指南.md))。

> Monterey(12)那份没打包进来,只为省仓库体积。要用就下
> `AirportItlwm_v2.3.0_stable_Monterey.kext.zip`,填 `MinKernel = 21.0.0` / `MaxKernel = 21.99.99`。

---

## 版本组合(改之前先记住)

| 组件 | 值 |
|---|---|
| OpenCore | **1.0.7** |
| SMBIOS | **`MacBookPro9,2`**(Ivy Bridge + HD 4000,离 X230 最近;见「[机型](#机型为什么是-macbookpro92)」) |
| `SecureBootModel` | **`Disabled`** —— 占位三码(UUID 全零)必须这样,否则开机 `Grabbed zero system-id for SB` 停机 |
| `csr-active-config` | `03080000`(OCLP 官方建议值) |
| boot-args | `keepsyms=1 debug=0x100 -amfipassbeta -btlfxboardid ipc_control_port_options=0 gfxrst=1 alcid=18 -no_compat_check`;装系统那份再多一个 `-v` |
| 板号检查 | `Booter/Patch` 的 `Skip Board ID Check` + `-no_compat_check`(双保险) |
| ACPI 改名 | `EHC1→EH01` / `EHC2→EH02`(内建 hub 上的蓝牙/摄像头/指纹靠它才可见) |
| USB | `USBInjectAll.kext` 0.7.8(配合上面的改名,声明根端口 + 内置 hub 端口) |
| IVB 驱动(12+) | EFI 注入 `AppleIntelHD4000Graphics.kext` / `AppleIntelFramebufferCapri.kext`(11.7.10 原件,`MinKernel = 21.0.0` = macOS 12+);**`/Library/Extensions` 里 OCLP 放的那两份别动**(实测 EFI 预链接注入会被 OC 拒掉,真正在跑的就是那一份)—— 见 [`docs/OCLP.md`](docs/OCLP.md) 第 8 节 |

**OCLP 相关的 NVRAM**(见 [`AGENTS.md`](AGENTS.md) 3.9):

```
4D1FDA02-…  OCLP-Settings = -allow_fv -allow_amfi
            revblock      = media          挡掉 mediaanalysisd(Metal 1 GPU 上会崩)
            revpatch      = f16c,sbvmm     f16c:防 13.3+ 上 CoreGraphics 在 Ivy Bridge 崩
                                           sbvmm:骗一个 VMM 机型,让 11.3+ 能收 OTA
```

---

## 目录

```
EFI/                     ← 拷到安装 U 盘 / ESP 的 EFI 分区
├── BOOT/BOOTx64.efi
└── OC/
    ├── config.plist         日常用(蓝牙四件套开着;不带 -v,不写日志)
    ├── config-install.plist 装系统用(蓝牙四件套关着;带 -v,开 OC 日志)
    ├── ACPI/                14 个 SSDT + 23 条 ACPI/Patch
    ├── Kexts/               27 个 kext(AirportItlwm 两份 + itlwm,按内核版本切档;
    │                        12+ 还含注入用的 IVB 驱动 Capri + HD4000,见 OCLP.md 第 8 节)
    ├── Drivers/
    ├── Resources/
    └── Tools/

docs/
├── 安装指南.md            做 U 盘 → 安装 → 切 config → 验证
├── OCLP.md                12+ 的显卡 / 无线补丁:前置检查、怎么跑、怎么验证、怎么抓日志
├── 踩坑记录.md            每个坑的根因和修法
├── USB定制.md             端口勘探 → 生成地图
├── images/                文档配图(安装器 panic 现场、根卷找不到的现场)
└── 参考/
    ├── README.md          参考资料的出处说明(谁给的、拿了什么)
    ├── 硬件报告/          ★ 这台 X230 的硬件转储,见下
    ├── 经典仓库笔记.md    banhbaoxamlan/X230-Hackintosh 两份 config 的对比
    ├── 经典仓库-*.plist   同上,原文件副本
    └── USB定制/           本机 USB 端口地图的可读存档(**未采用**,见 USB定制.md 第 6 节)

tools/
├── efi-sync.sh            工作区 ↔ ESP 的校验/拷贝(带备份和回读校验)
├── ivb-check.sh           在 macOS 上跑(重启后):一屏判定 IVB 到底有没有加速 + 退出码
├── ivb-now.sh             不重启也能跑:先读 → 现场加载一次 → 再读,做 A/B
├── ivb-snap.sh            最小快照:只抓加速器 / 帧缓冲那几行
├── oclp-diag.sh           在 macOS 上跑:把显卡 / 补丁 / AuxKC / 内核集合状态收成一个文件
└── README.md              工具说明;ocvalidate / macserial 从哪来
```

---

## 硬件报告

`docs/参考/硬件报告/` 是**这台 X230 的原始转储**,不是 EFI 的一部分、也不会被拷到 ESP:

- `sysInfo.txt` — Windows 下导出的设备清单:CPU、内存、屏幕 EDID、BIOS 版本、
  以及**每个 USB 设备挂在哪条 ACPI 路径上**(`USB定制.md` 的端口表就是靠它对出来的)
- `ACPI/` — 固件表转储,含 `DSDT.aml` 和反编译好的 `DSDT.dsl`

`AGENTS.md` 3.4 节「哪些设备名在 X230 上不存在」的结论、
`docs/USB定制.md` 里 `HP2x` / `PRTx` 的对应关系,都是从这份报告里查出来的。
出处与用途汇总见 [`docs/参考/README.md`](docs/参考/README.md)。

---

## 两份 config:装系统 / 日常

OpenCore 只认 `config.plist` 这个名字,所以 `EFI/OC/` 下放**两份**,装系统时
把「装系统那份」改名顶上:

| 文件 | 什么时候用 | 差异 |
|---|---|---|
| `config-install.plist` | **装系统**(拷进 U 盘时改名为 `config.plist`) | 蓝牙四件套**关**;带 `-v`;OC 日志开着 |
| `config.plist` | **日常**(硬盘 ESP 上就是它) | 蓝牙四件套**开**;不带 `-v`;不写日志 |

两份只差上面这几项,那 27 个 kext 一直都在。

**为什么装系统要关蓝牙**:蓝牙固件加载器(`BrcmPatchRAM3`)在**安装器环境**
(BaseSystem)下会去匹配 USB 蓝牙并灌固件,而那时 USB 栈还没成型
→ **直接 kernel panic**(实拍见 [`docs/踩坑记录.md`](docs/踩坑记录.md) 第 3 条)。

实际就是拷的时候改个名:

```bash
# 装 U 盘:用装系统那份
cp EFI/OC/config-install.plist <U盘>/EFI/OC/config.plist

# 装完、硬盘 ESP:用日常那份(仓库 EFI/ 里那份就是,整份覆盖即可)
```

蓝牙固件要**冷启动**才灌得进去。

---

## 装完之后:12+ 要去跑一次 OCLP

11 上什么都不用做。**12 及以后**必须让 OCLP 给系统卷打显卡补丁,否则显存只有 4 MB:

1. 联网,从 [OCLP Releases](https://github.com/dortania/OpenCore-Legacy-Patcher/releases)
   下载对应版本的 `OpenCore-Patcher.app`;
2. `Post-Install Root Patch` → `Start Root Patching`;
3. **确认补丁列表里出现 `Graphics: Intel Ivy Bridge`** —— 第一次跑经常只装 WiFi
   (OCLP 要联网下载素材,拉不到就先只给你 WiFi),所以**跑完再跑一次**;
4. 重启后 `system_profiler SPDisplaysDataType` 里应该是 `VRAM 1536 MB` + `Metal: Supported`。

15 还多一步:**Sequoia 的 Metal 编译器换了格式,OCLP 要下 `MetallibSupportPkg`(几十 MB)**,
没有它 Metal 起不来。所以那台机器上「Wi-Fi 好了、显卡没好」是常见结果,联网重跑即可。

前置检查(SIP、`SecureBootModel`、AMFI、FileVault、网络)、失败排查顺序、
以及「为什么是 `MacBookPro9,2` 而不是 T530 的 `MacBookPro10,1`」都在
[`docs/OCLP.md`](docs/OCLP.md)。

> ⚠️ **不要点 `Build and Install OpenCore`** —— 那个才会动 EFI,而这份 EFI 是自己维护的。
> OCLP 的 `Post-Install Root Patch` 只动系统卷。

---

## 快速开始

```bash
# 1. 看当前 EFI 状态(补丁数、kext 数、三码、boot-args)
./tools/efi-sync.sh status

# 2. 拷到 ESP(自动备份 ESP 上原有文件 + 预览 + 回读校验)
./tools/efi-sync.sh push /Volumes/EFI

# 3. 重启
```

完整流程见 [`docs/安装指南.md`](docs/安装指南.md)。

---

## 已知问题

- **必须冷启动**:蓝牙固件靠冷启动加载,普通重启后蓝牙开关会变灰。
- **不做 USB 端口地图**:靠 `EHC1→EH01` / `EHC2→EH02` 改名 + `USBInjectAll`
  声明端口(蓝牙/摄像头/指纹都在内置 hub 后面)。
  > 试过 Hackintool 实测的 `USBPorts.kext`,在本机**会让内建设备全消失**,已回退 ——
  > 见 [`docs/USB定制.md`](docs/USB定制.md) 第 6 节。
- **14/15 的无线要 HeliPort**:`AirportItlwm` 没有 Sequoia 版,只能用 `itlwm` + HeliPort。
- **亮度上限偏低**:`SSDT-PNLF`(Scope 用的是本机的 `VID`,不是别人 DSDT 里的 `IGPU`)
  + `BrightnessKeys` 已让亮度键和滑块都正常,实测最暗能到全黑;想再抬高上限,
  可以试 boot-args 加 `applbkl=0`(走 AppleBacklight 自己的曲线,而不是 WhateverGreen 那条)。
- **无 AVX2**:Ivy Bridge 没有 AVX2,新版 Chromium / Electron 类应用会拒绝启动,得用老版本。
- **指纹无解**:`147E:2020` 在 macOS 下没有任何驱动。
- **VGA 口无解**:macOS 不支持。
- **Homebrew 已是 Tier 3**:Intel Mac 不再有新 bottle,2027-09 后 Homebrew 将停止在 Intel 上运行。
  详见官方 [Support Tiers](https://docs.brew.sh/Support-Tiers)。

---

## 灵感来源

- [`banhbaoxamlan/X230-Hackintosh`](https://github.com/banhbaoxamlan/X230-Hackintosh)
  —— X230 最经典的仓库,面向 Catalina / Big Sur / Monterey 世代;
  「装系统阶段尽量少挂东西」的思路来自它。
- [`5T33Z0/Lenovo-T530-Hackintosh-OpenCore`](https://github.com/5T33Z0/Lenovo-T530-Hackintosh-OpenCore)
  —— 同代 QM77 + HD 4000 的 T530,一份 EFI 从 10.13 跑到 26。
  本仓库的 `Min/MaxKernel` 切档写法、OCLP 的 NVRAM 三个键、`-amfipassbeta`、
  `revpatch=f16c`、以及「13+ 要注入 `AppleIntelCPUPowerManagement`」都是从它那儿学的。
- [`zyq8888/X230-MAC-OpenCore`](https://github.com/zyq8888/X230-MAC-OpenCore)
  —— ACPI / kext 取舍参考。它的几个 SSDT 因为 `Scope` 指错了设备
  (`IGPU` / `LPCB` / `EC0`)而静默失效,这条坑记在 `AGENTS.md` 3.4。

---

## 致谢

- [Acidanthera](https://github.com/acidanthera) — OpenCorePkg / Lilu / WhateverGreen / VirtualSMC / AppleALC / BrcmPatchRAM / CryptexFixup / RestrictEvents / AMFIPass
- [Dortania](https://dortania.github.io/) — OpenCore Install Guide、Getting Started With ACPI、OpenCore Legacy Patcher
- [5T33Z0](https://github.com/5T33Z0) — T530 的 EFI 与 OC-Little-Translated 笔记
- [OpenIntelWireless](https://github.com/OpenIntelWireless/itlwm) — Intel 无线网卡驱动(itlwm / AirportItlwm / HeliPort)
- [benbaker76/Hackintool](https://github.com/benbaker76/Hackintool) — 端口勘探与 USB 地图生成

---

## 关于许可

`EFI/OC/Kexts/` 里的每个 kext、`EFI/OC/Drivers/` 里的每个驱动、以及
`EFI/OC/ACPI/` 里的 SSDT,都来自上面这些上游项目,**各自保留原有许可**。
本仓库只是把它们按 X230 的组合方式摆在一起。

仓库自身的文档(config 改动、踩坑记录)没有附加许可限制,随意取用;
但如果要再分发,请一并保留上游项目的署名。
