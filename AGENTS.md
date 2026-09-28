# AGENTS.md

给 **AI coding agent** 和**协作者**的作业指南。这里记录的全是踩过的坑——
请先读完再动手,尤其是「硬性纪律」和「已知陷阱」两节。

---

## 1. 这是什么

ThinkPad X230(i5-3230M, Ivy Bridge)上跑 **macOS 11 – 15** 的 OpenCore EFI,
外加这套配置的完整来龙去脉。`README.md` 面向使用者,本文件面向「要改它的人」。

技术栈:**OpenCore 1.0.7** + **OpenCore Legacy Patcher(OCLP,12 及以后才用得上)**。
一份 EFI 靠 `Kernel/Add` 里每个 kext 的 `MinKernel` / `MaxKernel` 切档,
同一份 config 覆盖 11 到 15(见 `README.md` 的版本对照表)。

关键分界线:Ivy Bridge 的图形栈 Apple 是在 **macOS 12** 砍掉的。

- **11**:HD 4000 原生加速,不碰 OCLP;
- **12+**:必须跑 OCLP 的 `Post-Install Root Patch` 把驱动打回系统卷。
  OCLP 只 patch **系统卷**(`/S/L/E`、kernel collection),**一个字都不写进 EFI**。

面向使用者的文档在 `docs/`:

| 文档 | 内容 |
|---|---|
| `docs/安装指南.md` | 做 U 盘 → 安装 → 切 config → 验证,全流程 |
| `docs/OCLP.md` | 12+ 的显卡 / 无线补丁:前置检查、怎么跑、怎么验证、怎么抓日志 |
| `docs/踩坑记录.md` | 每条坑的「现象 / 根因 / 修法」 |
| `docs/USB定制.md` | X230 的 USB 端口拓扑 + 端口地图怎么做 |
| `docs/参考/` | 本机硬件转储、经典仓库对比笔记(出处见其 `README.md`) |

## 2. 硬性纪律(违反过一次,代价是半天排查)

### 2.1 EFI 只有一个来源

- 仓库里只有**一份** EFI:`EFI/` —— 它就是拷到 ESP(或安装 U 盘)的那份,ESP 上是它的下游。
- 拷贝方向**永远只有** `仓库 → ESP`,用 `tools/efi-sync.sh push`。
- **绝不允许从 ESP 反向拷回仓库**。曾经发生过一次:把 ESP 上的旧 config 拖回工作区,
  一次性冲掉了 6 条内核补丁和 NVRAM 键。

### 2.2 改 config.plist 的方式

用 Python + `plistlib` 改,**不要**手工编辑 XML,也**不要**用会把 plist 重新格式化的 GUI 工具:

```python
import plistlib
p = plistlib.load(open('EFI/OC/config.plist','rb'))
# ... 改 ...
plistlib.dump(p, open('EFI/OC/config.plist','wb'))
```

改完**必须**验证(两份 config 都要):

```bash
ocvalidate EFI/OC/config.plist            # 期望 "No issues found."
ocvalidate EFI/OC/config-install.plist
```

`ocvalidate` / `macserial` 不随仓库附带,来源见 `tools/README.md`。

### 2.3 ESP 上只放该放的东西

`EFI/` 里只应有 `BOOT/` 和 `OC/` —— 这两个目录之下的**所有东西**都会被拷到 ESP。
**不要**把日志、`.rtf`、`.md`、README、截图、`EFI-Backups/` 塞进 `EFI/`。

> 曾经有个 `EFI/说明.md` 混在里面,内容已经并进 `docs/`。别让它复活。
> 添加文件前先问一句:这个文件需要出现在别人的 ESP 上吗?

**例外(只读、别提交)**:`config-install.plist` 里 `Misc/Debug/Target = 0x43` +
`AppleDebug` 会让 OpenCore 每次开机往 **ESP 根目录**写 `opencore-YYYY-MM-DD-*.txt`。
那是抓问题用的现场日志,**不是仓库内容**——别 `git add`,排查完关掉调试即可
(见 `docs/OCLP.md` 5.2)。日常那份 `config.plist` 里这两项是关着的,不会写盘。

### 2.4 三码

仓库里的 SMBIOS 三码是**占位值**,不是任何真机的序列号:

| 字段 | 值 |
|---|---|
| `SystemSerialNumber` | `W00000000001` |
| `MLB` | `M0000000000000001` |
| `SystemUUID` | `00000000-0000-0000-0000-000000000000` |
| `ROM` | `112233445566` |

这四个值就是 OpenCore 官方 `Docs/Sample.plist` 里那套「一眼假」的占位写法:
系统能正常引导,但 **iCloud / iMessage / FaceTime 会登不上**。

**所有人上机前都必须换成自己生成的**:

```bash
macserial -g MacBookPro9,2     # 取 SystemSerialNumber / MLB / SmUUID
```

`ROM` 填本机有线网卡的 MAC 地址(6 字节),不要留 `112233445566`。

> ⚠️ **`SecureBootModel` 必须是 `Disabled`,直到你换上真三码为止。**
> 它一开(`Default` / `x86legacy`),OpenCore 就要拿 SMBIOS 的 `SystemUUID` 去算
> x86legacy 的 ApECID;占位 UUID 是全零 → 直接
> `OC: Grabbed zero system-id for SB, this is not allowed` + 死循环停机,连引导菜单都过不去。
> 详见 `docs/踩坑记录.md` 第 13 条。只有换完真三码、想开 Apple 安全启动(medium security)时,
> 才把它改回 `Default`。

> 别去抄别人的真码,轻则两边 Apple ID 互相踢,重则被 Apple 拉黑。
> 给本仓库提 PR 时**也不要**把真码提交进来——占位值请原样保留。

### 2.5 别碰这些

- `docs/参考/` 里其他仓库的 config —— 那是**别家机器**的配置,直接套会出问题(见 3.4)。
  出处和「拿了什么」都标在 `docs/参考/README.md` 里。
- 退役件(旧版 EFI、config 副本、日志、别家仓库快照)—— 一律不进仓库,
  也别建 `_archive/` 之类的目录来堆它们。**EFI 只留当前在用的这一份。**

---

## 3. 已知陷阱(每条都真实踩过)

### 3.1 `_LID → XLID` 重命名会让 DSDT 的 `VID._INI` 崩

[RapidEFI](https://github.com/JeoJay127/RapidEFI-Tool) 生成的 config 里有一条 `_LID\x00 → XLID\x00` 的全表重命名。X230 的 DSDT 中:

```asl
Device (VID) {                      // _SB.PCI0.VID,显卡
    Method (_INI, 0) { CLID = \_SB.LID._LID () }    // 引用 LID._LID
}
```

重命名把 `_LID` 的**定义**改成了 `XLID`(Count=0,全表),而这个引用没有跟着改,
于是启动时报:

```
ACPI Error: Method parse/execution failed \_SB.PCI0.VID._INI, AE_NOT_FOUND
```

**修法**:删掉这条重命名,同时删掉依赖它的 `SSDT-LID.aml`。
`_LID` 走原厂实现即可——那个「合盖伪装」本来就是个可选的 hack。

> 教训:OpenCore 的 ACPI Patch 会作用于**所有固件表**。
> 做重命名时务必想清楚「谁在引用这个名字」。

### 3.2 蓝牙 kext 在安装器环境下 kernel panic

引导**安装器**(BaseSystem)时 panic,屏幕最后两行是:

```
dependency: as.acidanthera.BrcmFirmwareStore(2.7.2)
dependency: com.apple.ioKit.IOUSBHostFamily(1.2)
```

![安装器 panic 现场](docs/images/install-panic-brcm.jpg)

`as.acidanthera.BrcmFirmwareStore` = `BrcmFirmwareData.kext`,
这是 `BrcmPatchRAM3.kext` 的依赖表。它在 BaseSystem 下会去匹配 USB 蓝牙设备并灌固件,
而此时 USB 栈尚未成型 → 崩。

**修法**:装系统阶段关掉蓝牙这一组(会崩的是上面那三个 Brcm;
`BlueToolFixup` 是 12+ 才用的,一并关掉只为安装期清单更干净),装完系统后再开:

```
BrcmBluetoothInjector.kext   ← 关
BrcmFirmwareData.kext        ← 关
BrcmPatchRAM3.kext           ← 关
BlueToolFixup.kext           ← 关
```

本仓库用两份 config 区分:`config-install.plist`(装系统)/ `config.plist`(日常)。

> 参考:[`banhbaoxamlan/X230-Hackintosh`](https://github.com/banhbaoxamlan/X230-Hackintosh)
> 也是这么分的,它的 Install USB 版连自定义 ACPI 都不加载。
> **装系统时的第一原则:变数越少越好。**

### 3.3 `EHC1`/`EHC2` 必须改名成 `EH01`/`EH02`

macOS 的 `AppleUSBEHCIPCI` **只认 `EH01` / `EH02`**;X230 原厂 DSDT 里这两个 EHCI
控制器叫 `EHC1` / `EHC2`。不改名 → 两个控制器不会被驱动 → 挂在 EHC2 内置 hub
(`URTH`→`URMH`)后面的**蓝牙 / 摄像头 / 指纹一个都不出现**。
端口地图也救不了:`provider` 不存在,注入无处可去。

本仓库已加(`ACPI/Patch` 两条,**`Count = 0`**):

```
EHC1 → EH01
EHC2 → EH02
```

`Count` 必须是 0。DSDT 里 `\_SB.PCI0.EHC1.RID` 这种引用比 `Device (EHC1)` 的定义
出现得还早,`Count = 1` 会把引用改掉、定义留着 → 3.1 节那种 `AE_NOT_FOUND`。
改完拿自己的 DSDT 做一遍字节替换再反编译,确认定义和所有引用都跟着换了。

**改名之后还得有人声明端口**:改名只是让 `AppleUSBEHCIPCI` 认下这两个控制器,
**内置 hub 上的端口还得声明出来**。本仓库用 `USBInjectAll.kext` 0.7.8,它自带三类
关键 personality:

- `AppleUSB20InternalHub` 的 `HUB1` / `HUB2` —— 按 `locationID` 绑两个内置 hub
  (`0x1D100000` = EHC1、`0x1A100000` = EHC2),声明出 `HP11…HP18` / `HP21…HP28`;
- `AppleUSBEHCIPCI` 的 `EH01` / `EH02` —— 声明根端口 `PR11…PR18` / `PR21…PR26`;
- 按 PCI device-id `8086_1e31` 挑的 XHCI 表 —— `HS01…HS04` + `SS01…SS04`。

> ⚠️ **试过、在本机失效的岔路**(2026-09-27):换成 Hackintool 实测的 `USBPorts.kext`
> (只声明接出来的口、还带端口类型)之后,**EHC2 内置 hub 后面的内建设备全没了**
> (蓝牙 / 摄像头 / 指纹),换回 `USBInjectAll` 立刻恢复。**原因没查出来**,两个嫌疑:
> ① 那份地图没声明 `HP21`(hub 自身,本仓库文档里写着要填 255);
> ② 同一份 kext 里 internal-hub 组用 `portType`、XHCI/EHCI 组用 `UsbConnector`,
> 键名混用,13/15 上到底认哪个没验。
> **别再直接换上去** —— 要试就先记好回退(把 `Enabled` 对调)。
> 那份地图的可读版本留在 `docs/参考/USB定制/`。

### 3.4 别照抄 [`zyq8888/X230-MAC-OpenCore`](https://github.com/zyq8888/X230-MAC-OpenCore) 的 ACPI

那是另一份 X230 EFI(i5-3320M / BCM94360HMB / SMBIOS `MacBookPro16,2`),
和本机不是一套配置。仓库里**不收录它的任何文件**,要看请直接去上游仓库。

它的 `DSDT.aml` 与本机转储**逐字节相同**:

```
sha256 1c713428c3a79fa03f88285c2a30ac2bd9648b11d50f44764e9ad84b62b7def4
```

这说明「同 BIOS 版本的 X230,DSDT 可以互换」——也正因如此,替换 DSDT 没有任何收益。

但它的几个 SSDT 里,`Scope` 指向的设备在 X230 的 DSDT 里**根本不存在**:

| 它的 SSDT | 引用 | X230 实际 | 后果 |
|---|---|---|---|
| `SSDT-PNLF` | `_SB.PCI0.IGPU` | `_SB.PCI0.VID` | Scope 解析不到 → 背光控制失效 |
| `SSDT-IRQ` | `_SB.PCI0.LPCB.*` | `_SB.PCI0.LPC.*` | 同上 → IRQ 修复失效 |
| `SSDT-EC` | `_SB.PCI0.LPC.EC0` | `_SB.PCI0.LPC.EC`(PNP0C09) | 解析不到 `EC0`,还会在 `LPC` 下重复声明 `EC` |
| `SSDT-Thinkpad_Trackpad` | Scope 用的就是 `LPC.KBD` ✅ | — | 这条是好的(只是多留了个没用的 `LPCB.PS2K` External) |

它 config 里其实准备了 `change PCI0.VID to IGPU` 的重命名,但 **`Enabled = false`** ——
也就是说这份 EFI 在作者自己的机器上,`SSDT-PNLF` 同样是不生效的。

**为什么值得单独记一条**:`Scope` 打错设备名,不会让机器开不了机。verbose 下能看到
`ACPI Error ... AE_NOT_FOUND`,但系统照常进桌面、功能就是没生效——**特别容易被忽略**。

抄别人的 ACPI 之前,先对一遍名字:

```bash
rg -n "Device \(VID\)|Device \(IGPU\)|Device \(LPC\)|Device \(LPCB\)|Device \(KBD\)|Device \(PS2K\)|Device \(EC\)|Device \(EC0\)" DSDT.dsl
```

X230(G2ETB7WW)的结果是:`VID` / `LPC` / `KBD` / `EC` 存在,
`IGPU` / `LPCB` / `PS2K` / `EC0` **都不存在**。

### 3.5 为什么 SMBIOS 是 `MacBookPro9,2`

- 它和 X230 的平台最接近(**Ivy Bridge + HD 4000**),图形、电源管理都按它匹配。
- 2012 年的 `9,2` 不在 11 及以后的官方支持机型里,所以启动时会被板号检查拦下。
  本仓库对付它的是 `Booter/Patch` 里那条 **`Skip Board ID Check`**
  (OCLP 的补丁,OC 上的正规做法),boot-args 里的 `-no_compat_check` 是同一件事的老办法,
  两条都在,互为保险。

> 别为了「省掉这一步」把机型换成 2013 年以后的机器:那会让 Ivy Bridge 的
> 电源管理 / 图形匹配落到别的机型上,没有收益,只会多一个变数。

**为什么不用 T530 那份 EFI 的 `MacBookPro10,1`**:两个机型在 OCLP 的机型表里是等价的
(都 `Max OS Supported = Catalina`、都是 Ivy Bridge + HD 4000),但 `10,1` 额外声明了
`Switchable GPUs = True`(出厂带 NVIDIA Kepler),而且在 OCLP 的 `AGDPSupport` 名单里。
X230 只有核显,装成 `10,1` 等于主动让 macOS 走双显卡那几条分支。
**OCLP 的显卡补丁是按 GPU 架构挑的、不看机型**(`intel_ivy_bridge.py` 的
`present()` 只判断有没有 Ivy Bridge 的 GPU),所以 `9,2` 不会导致补丁不加载;
完整对照见 `docs/OCLP.md` 第 7 节。

### 3.6 电源管理:Ivy Bridge 走 AICPUPM

Ivy Bridge 该走 **AICPUPM**(legacy SMC / `ACPI_SMC_PlatformPlugin`),不是 XCPM。
但 Apple 分两步砍:11 / 12 系统**自带**能用的那份,13 起才移除。
所以本仓库用 `MinKernel` 切档,而不是写死:

| | 11 / 12 | 13+ |
|---|---|---|
| `AppleIntelCPUPowerManagement.kext`(+`Client`) | 不加载 | `MinKernel = 22.0.0`,加载 |
| kext 从哪来 | —— | 直接取 OCLP 的产物 |

Quirks 三件套照旧:

- `Kernel/Quirks/AppleCpuPmCfgLock = True`(绕过 MSR 0xE2 锁)
- `AppleXcpmCfgLock = False`、`Emulate/DummyPowerManagement = False`

验证:

```bash
sysctl machdep.xcpm.mode                                        # 期望 0
kextstat | grep -i AppleIntelCPUPowerManagement
```

> ⚠️ 纪律:凡是「只在某个版本成立」的 kext,一律用 `MinKernel` / `MaxKernel` 关住。
> 从别的 EFI 抄东西时,先问一句「这是给哪个内核版本的」——T530 那份是全程常开的,
> 直接照抄到 11 上就是和系统自带的那份打架。

### 3.7 BIOS:CSM 必须关、DVMT 设到 128 MB、Intel ME 必须开

- **CSM 必须关**:开着时 OpenCore 能引导、进度条能走一半,但**进不去安装器**。
  `UEFI Only` + `CSM = No`。
- **DVMT Pre-Allocated 必须设到 128 MB**、`DVMT Total Gfx Mem = Max`。
  这两项在出厂 BIOS 里是隐藏的,`Advanced → System Agent (SA) Configuration →
  Graphics Configuration` 下面,用 [n4ru/1vyrain](https://github.com/n4ru/1vyrain/)
  刷一次就能看到完整菜单(不用编程器)。经典 X230 仓库也是这么要求的,见
  [banhbaoxamlan/X230-Hackintosh](https://github.com/banhbaoxamlan/X230-Hackintosh)
  的 `Other/README_HARDWARE.md`。
- **这一项和 EFI 里的 `framebuffer-stolenmem` 是一对**:BIOS 这边决定「预留了多少」,
  EFI 那边声明「显卡认为自己能拿走多少」。预留量没到,驱动就会去用一段 BIOS 根本没
  留出来的内存 —— 轻则显存数字乱跳,重则**加速器起不来**。
  两边怎么对齐见 `docs/踩坑记录.md` 第 10 节。
- **Intel ME / AMT 必须开着**(12 及以后)。IVB 的 `AppleIntelFramebufferCapri` 里带着
  `AppleIntelMEIDriver` + `AppleIntelPAVP` + `AppleMEClientController`,**PAVP 会话要经
  MEI(PCI 0x16.0)走**。ME 一关,PCI 上就没这个功能 → PAVP 握手失败 →
  `AppleMEClientController::start` 等满整 30000 ms 定时器 → `IntelAccelerator::start()`
  返回 false → `IOAccelerator` 为空 → **Dock 不透明、显存只剩 4 MB**。
  现象、时间线、判定命令见 `docs/踩坑记录.md` 第 16 条。
  > 别用 `me_cleaner` / HAP 去裁 ME:裁掉就等于掐断这条链路,加速直接没。
  > `SSDT-IMEI.aml` 也救不了 —— 它只补 ACPI 的 `device-id`,变不出 PCI 设备,
  > 所以本仓库把它关着(`Enabled = false`)。

### 3.8 蓝牙必须冷启动

`BCM20702` 不带 Flash,固件由 `BrcmPatchRAM3` 在每次 **USB 上电**时灌进芯片 RAM,
窗口很窄(芯片还停在 bootloader 那一段)。菜单里的「重新启动」不走完整断电,
时序对不上 → 固件没灌进去 → 开关灰 / 打不开。**完全关机再开机**即可恢复。

- 排查蓝牙问题前,先确认是冷启动,别一上来就改 config。
- 从 Windows「重启」进 macOS 也是热重启,一样会挂。
- NVRAM 里的 `bluetoothExternalDongleFailed` / `bluetoothInternalControllerInfo`
  治的是「开关灰」,治不了「固件没灌」,别指望它们。

### 3.9 OCLP:只 patch 系统卷,别点 `Build and Install OpenCore`

- 12 及以后的图形 / 无线都靠 OCLP 的 **`Post-Install Root Patch`**,
  它只动系统卷(`/S/L/E`、kernel collection),**不会写 EFI**。
- **绝对不要点 `Build and Install OpenCore`**:那会把本仓库调好的 config 换成 OCLP 自己那版
  (`Min/MaxKernel` 切档、ACPI 组合、NVRAM 键全丢)。
- 11 上**不要**跑 root patch:那里图形栈是原生的,只会把系统自带驱动换成旧版。

跑之前 EFI 必须满足的几个条件(OCLP 会在开跑前逐条检查):

| 检查 | 本仓库的值 |
|---|---|
| SIP 降到足够低 | `csr-active-config = 03080000`(0x803) |
| `SecureBootModel` | `Disabled` |
| AMFI | `AMFIPass.kext` + boot-args `-amfipassbeta`(加载了 OCLP 才不拦) |
| FileVault | 关 |
| 网络 | **必须通**(15 要下 `MetallibSupportPkg`,13+ 可能要下 KDK) |

改这五项之前先看 `docs/OCLP.md`,那里写了每一条为什么。

### 3.10 传感器 / 无用 SSDT 可以摘

小优化,但能让启动干净一点:

- `SSDT-ALS0.aml`(假环境光传感器):笔记本没有 ALS,本仓库把它**关着**
  (`Enabled = false`),要省启动时间可以直接删。
- `SMCLightSensor`(假光传感器):同上,笔记本用不到。
- `SSDT-EC.aml`:X230 的 EC 已经叫 `EC`(PNP0C09),不需要再补一个;
  本仓库用的是 `SSDT-EC-LAPTOP.aml`(USB 供电属性),两者用途不同,别搞混。

> 摘 SSDT 的原则:先确认没有别的补丁/SSDT 引用它,再删。

### 3.11 12+ 的 IVB 驱动:EFI 预链接注入是哑的,真正在跑的是 OCLP 那份

13+ 上 IVB 显卡补丁走的是 **AuxKC**(OCLP 把两个 kext 挪到 `/Library/Extensions`,
`kmutil create --new aux`),真机上撞到过「帧缓冲进了内核、加速器没进」:

```
kextstat | grep -iE "HD4000|Capri"
#   → 只有 com.apple.driver.AppleIntelFramebufferCapri
#     AppleIntelHD4000Graphics 不在名单里  →  ioreg -lw0 -r -c IOAccelerator 是空的
```

**试过、已在现场否掉的岔路**:把这两个 kext 放进 EFI、让 OpenCore 注入 BootKC。
2026-09-27 的引导日志(`ESP 根目录的 `opencore-*.txt`)把结论写死了:

```text
OC: Prelinked injection AppleIntelFramebufferCapri.kext (V11.7.10 | ...) - Invalid Parameter
OC: Prelinked injection AppleIntelHD4000Graphics.kext (V11.7.10 | ...) - Invalid Parameter
```

**预链接注入被 OpenCore 拒了,一个都没进内核。** 于是 `kextstat` 里那两条
只能来自 OCLP 放在 `/Library/Extensions` 的那两份(内核日志:
`exists in Optional(file:///Library/Extensions/...)` → `marked as loadable`)。
所以:

- **`/Library/Extensions` 里 OCLP 放的那两份必须留着** —— 挪走等于把唯一能用的
  驱动拿走(老版本这里写过「挪走」,那条建议是错的,已作废);
- EFI 里那两条 `Kernel -> Add` **留着但当作哑的**:期望值是 0,别拿
  「`kextstat` 里有」当成「EFI 注入生效了」;
- 现场见过的那句 `kernelmanagerd: Collision: replacing Kext ...` 也**不是**
  BootKC/AuxKC 打架 —— 那是人工跑 `kextutil -t` 时的产物,别据此下结论。

出处 [PatcherSupportPkg](https://github.com/dortania/PatcherSupportPkg)
`Universal-Binaries/11.7.10/System/Library/Extensions/` 与 OCLP 在 13 上取的是
同一份(都是 `16.0.5`),所以「换来源」不改驱动版本 —— 两个来源哪一头在跑,结果是等价的。
对照:[5T33Z0/Lenovo-T530-Hackintosh-OpenCore](https://github.com/5T33Z0/Lenovo-T530-Hackintosh-OpenCore)
(同代 QM77 + HD 4000,12+ 加速可用)只在 OCLP 那一头,`EFI/OC/Kexts/` 里没有这两个 kext。

**边界**:就算注入也只管 `.kext`。OCLP 那套里还有 5 个用户态 bundle
(`...GLDriver.bundle` / `...MTLDriver.bundle` / `...VADriver.bundle` / `AppleIntelIVBVA.bundle` /
`AppleIntelGraphicsShared.bundle`)和 `Metal 3802` 的框架降级,那些只能靠 OCLP 写系统卷。
另外 `AppleIntelHD4000Graphics` 的 `start()` 失败时**不打任何日志**,
所以「内核日志里什么都没有」不等于「没匹配上」—— 别拿它当判据,
用 `ioreg -lw0 -r -c IOAccelerator` 和 `tools/ivb-check.sh` 判定。

**加速起不来的真正形态**(2026-09-27):两处 30 s 超时 ——
`AppleIntelCapriController::start took 30173 ms`、`IntelAccelerator::start took 30001 ms`
→ 紧接着 `IntelAccelerator::start(IGPU) <1> failed`,同时
`AppleMEClientController`(ME/PAVP)也卡满 30 s 并打出
`DRMStatus: iTunes/Apple Store Content Access Problem ... ErrorCode: 8877652`。
不加速时 `IOAccelerator = 0`、WindowServer 刷
`Failed to create MetalDevice for accelerator 0 0` + `Software compositor activated.`。
**看到这一幕先别改 EFI —— 回去看 BIOS 里的 Intel ME 是不是关着**(3.7),
2026-09-27 这台就是这么确诊的。判读和下一步见 `docs/踩坑记录.md` 第 16 条、
`tools/ivb-check.sh` 的 ⓔ 节。

完整的来龙去脉、判定命令和回退方式见 `docs/OCLP.md` 第 8 节,
现象与错误判定见 `docs/踩坑记录.md` 第 15 条。

---

## 4. 常用命令

```bash
./tools/efi-sync.sh status                 # 看 EFI 指纹/补丁数/kext数/三码/boot-args
./tools/efi-sync.sh check /Volumes/EFI     # 对比仓库与 ESP(只读)
./tools/efi-sync.sh push  /Volumes/EFI     # 备份 + 预览 + 覆盖 + 回读校验

ocvalidate EFI/OC/config.plist             # 改完 config 必跑(工具见 tools/README.md)
ocvalidate EFI/OC/config-install.plist

# 反编译 ACPI 看某个 SSDT 干了什么
iasl -d EFI/OC/ACPI/SSDT-PNLF.aml          # 生成同名 .dsl
```

`tools/efi-sync.sh` 会保护 ESP 上的 `Microsoft/ APPLE/ ubuntu/ fedora/ debian/ systemd/`
目录,不拷也不删——多系统机器上不会被误伤。

---

## 5. 适配另一台 X230 的步骤

0. **先过一遍 BIOS 前提**(3.7):`UEFI Only` + `CSM = No`、`SATA = AHCI`、
   `DVMT Pre-Allocated = 128 MB`、`DVMT Total = Max`、**`Intel ME` 开着**。
   这几项都是「不设就起不来 / 起了也没加速」的硬前提。
1. **确认 DSDT 一致**(同 BIOS 版本 `TP-G2`)。不一致的话,那套 SSDT 需要重新核对路径:
   ```bash
   iasl -d docs/参考/硬件报告/ACPI/DSDT.aml
   rg -n "Device \(EC\)|Device \(VID\)|Device \(LPC\)|Device \(KBD\)" DSDT.dsl
   ```
   重点确认这几个名字:`EC`(不是 `EC0`)、`VID`(不是 `IGPU`)、`LPC`(不是 `LPCB`)、`KBD`(不是 `PS2K`)。
2. **重新生成三码**(见 2.4),ROM 换成你自己的网卡 MAC。
3. **换无线网卡驱动**:本仓库是 Intel 7260,按系统版本用
   `AirportItlwm_BigSur`(11)/ `AirportItlwm_Ventura`(13)/ `itlwm` + HeliPort(14、15);
   如果是博通卡,改用 `AirportBrcmFixup` 那一套,并参考 `docs/参考/经典仓库笔记.md`。
4. **重新做 USB 端口地图**:别人的地图不能抄,端口编号和硬件配置强相关。见 `docs/USB定制.md`。
5. **音频 layout-id**:ALC269 在本机是 `18`(`alcid=18`);
   换机器可能要试 `3 / 11 / 13 / 18 / 29 / 55`。
6. **先装系统,再开蓝牙**:安装阶段把 `config-install.plist` 改名顶上(见 `README.md`
   的「两份 config」),装完在系统盘 ESP 上换回日常版 `config.plist`(顺序反了会 panic,见 3.2)。
7. **12+ 记得跑 OCLP**(见 3.9 与 `docs/OCLP.md`);11 不用。
   跑完显卡还是没加速、`ioreg -lw0 -r -c IOAccelerator` 是空的话,
   按 `docs/OCLP.md` 第 6 节往下查(先别动 `/Library/Extensions` 里那两个 kext,见 3.11);
   两处 30 s 超时那种形态见 `docs/踩坑记录.md` 第 16 条 + `tools/ivb-check.sh` 的 ⓔ 节。

## 6. 验证清单

装完之后逐条确认:

```bash
# 显卡:11 应为原生 1536 MB + Metal Supported;12+ 跑完 OCLP 再来看这里
system_profiler SPDisplaysDataType | grep -iE "Chipset|VRAM|Metal"

# 图形 kext 是否加载(12+ 两条都要在;它们来自 /Library/Extensions 那份,见 3.11)
kmutil showloaded | grep -iE "Capri|HD4000"
ioreg -lw0 -r -c IOAccelerator | wc -l      # 12+ 跑完 OCLP 应 >0(有加速器)

# 电源管理:Ivy Bridge 走 AICPUPM,这里应为 0
sysctl machdep.xcpm.mode
pmset -g

# 音频
system_profiler SPAudioDataType | head -20

# 无线
system_profiler SPAirPortDataType | head -30
```

显卡一栏应该是 `VRAM (Total): 1536 MB` + `Metal: Supported`,Dock 是透明的。
**12+ 上如果只有 4 MB / Metal 不支持**,别改 EFI——那是系统卷还没打补丁,
按 `docs/OCLP.md` 第 6 节排查;抓日志见第 5 节。

## 7. 出处与灵感来源

这份 EFI 不是从零写的,三个仓库给了大部分思路。**引用它们时请带上链接**,
不要写成「某个 X230 仓库」——读者查不到就等于没有。

| 仓库 | 拿走了什么 | 本地副本 |
|---|---|---|
| [banhbaoxamlan/X230-Hackintosh](https://github.com/banhbaoxamlan/X230-Hackintosh) | 面向 Catalina / Big Sur / Monterey 的 X230 配置;「装系统阶段尽量少挂东西」的思路 | `docs/参考/经典仓库-*.plist`(两份 config 副本)+ `docs/参考/经典仓库笔记.md` |
| [5T33Z0/Lenovo-T530-Hackintosh-OpenCore](https://github.com/5T33Z0/Lenovo-T530-Hackintosh-OpenCore) | 同代 QM77 + HD 4000,一份 EFI 覆盖 10.13 – 26。`Min/MaxKernel` 切档写法、OCLP 那套前置条件(`csr-active-config = 03080000`、OCLP-Settings / `revblock` / `revpatch`)、`-amfipassbeta`、13+ 注入 AICPUPM | 不收录,直接去上游看 |
| [zyq8888/X230-MAC-OpenCore](https://github.com/zyq8888/X230-MAC-OpenCore) | ACPI / kext 取舍;**反面教材**(3.4 节的 `Scope` 坑) | 不收录,直接去上游看 |

其余上游项目(OpenCorePkg / Lilu / WhateverGreen / VirtualSMC / AppleALC /
BrcmPatchRAM / OpenIntelWireless / Hackintool)见 `README.md` 的致谢。

**写文档的纪律**:凡是要提到别的仓库,一律给可点开的 URL + 一句「拿了什么」。
只在本地、没进仓库的东西,**不要在正文里写成「仓库里有」**——读者按图索骥只会扑空。
