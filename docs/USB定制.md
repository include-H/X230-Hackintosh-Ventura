# USB 定制

**先给结论**:X230 每个控制器的端口都不到 15 个,不需要端口限制补丁,
也**不需要自己写 `USBPorts.kext`**。本仓库靠这两样:

1. `ACPI/Patch` 里 `EHC1→EH01` / `EHC2→EH02` 两条改名(macOS 只认 EH01/EH02);
2. `USBInjectAll.kext` 0.7.8 —— 根端口(`PRxx`)、内置 hub 端口(`HPxx`)、XHCI
   端口(`HSxx`/`SSxx`)都替我们声明好了,XHCI 那份按 device-id `8086_1e31` 挑,
   内容和 X230 一致。

前提见 [`踩坑记录.md`](踩坑记录.md) 第 4 条:不改名的话 EHC2 内置 hub 后面的
蓝牙 / 摄像头 / 指纹一个都不会出现,那种情况下**做地图也没用**——provider 根本不存在。

> ⚠️ **自己做的地图试过、在本机失效**(2026-09-27):按下面第 4 节的流程,Hackintool
> 实测导出的 `USBPorts.kext` 换上去之后,EHC2 内置 hub 后面的蓝牙 / 摄像头 / 指纹
> **全消失**,换回 `USBInjectAll` 立刻恢复。原因没查到根上,见第 6 节。
> 那份地图的可读版本留在了 [`参考/USB定制/`](参考/USB定制/)
> (`SSDT-UIAC.dsl`,同一张地图的 ACPI 写法),只当「这台机器真实长什么样」的记录。

那什么时候要做?想让内建设备(蓝牙/摄像头/指纹)稳定、
想给端口标上正确的类型(内建 / USB-A / USB3)、想撑过休眠唤醒的端口复位——
那就做一份。

---

## 1. X230 的 USB 硬件长什么样

三个控制器,全部来自 QM77 芯片组。下表直接从本机 DSDT 转储里读出来
(`docs/参考/硬件报告/ACPI/DSDT.dsl`)。

### XHCI —— 左侧两个 USB3 口

| | 值 |
|---|---|
| ACPI 设备 | `_SB.PCI0.XHCI` |
| PCI 路径 | `PciRoot(0x0)/Pci(0x14,0x0)` (`_ADR 0x00140000`) |
| 端口 | 8 个(`URTH` 下 `HSP0–HSP3` + `SSP0–SSP3`) |

| ACPI 名 | _ADR | macOS 端口名 | 实际接线 |
|---|---|---|---|
| `HSP0` | 1 | `HS01` | 左侧 USB3 口 A 的 USB2 部分 |
| `HSP1` | 2 | `HS02` | 左侧 USB3 口 B 的 USB2 部分 |
| `HSP2` | 3 | `HS03` | 未接出 |
| `HSP3` | 4 | `HS04` | 未接出 |
| `SSP0` | 5 | `SS01` | 左侧 USB3 口 A 的 USB3 部分 |
| `SSP1` | 6 | `SS02` | 左侧 USB3 口 B 的 USB3 部分 |
| `SSP2` | 7 | `SS03` | 未接出 |
| `SSP3` | 8 | `SS04` | 未接出 |

> macOS 会把 XHCI 端口按 `_ADR` 重新命名成 `HS01…HS04` / `SS01…SS04`,
> 所以注入时用 `HSxx` / `SSxx`,不是 DSDT 里的 `HSPx` / `SSPx`。

### EHC2 —— 内置 hub(蓝牙 / 摄像头 / 指纹)+ 右侧 USB2

| | 值 |
|---|---|
| ACPI 设备 | `_SB.PCI0.EH02`(原厂名 `EHC2`,已改名) |
| PCI 路径 | `PciRoot(0x0)/Pci(0x1A,0x0)` (`_ADR 0x001A0000`) |
| 结构 | `URTH`(根集线器)→ `URMH`(内置 hub)→ `PRT8 … PRTD` |

| ACPI 名 | _ADR | macOS 端口名 | 实测设备 |
|---|---|---|---|
| `PRT8` | 1 | `HP21` | hub 自身 |
| `PRT9` | 2 | `HP22` | **右侧 USB2 口**(标准 USB-A) |
| `PRTA` | 3 | `HP23` | 指纹 `147E:2020`(UPEK,无解) |
| `PRTB` | 4 | `HP24` | 蓝牙 `0A5C:21E6`(BCM20702) |
| `PRTC` | 5 | `HP25` | 未接出 |
| `PRTD` | 6 | `HP26` | 摄像头 `5986:02D2`(Bison) |

### EHC1 —— 内置 hub(本机为空)

| | 值 |
|---|---|
| ACPI 设备 | `_SB.PCI0.EH01`(原厂名 `EHC1`,已改名) |
| PCI 路径 | `PciRoot(0x0)/Pci(0x1D,0x0)` (`_ADR 0x001D0000`) |
| 结构 | `URTH` → `URMH` → `PRT0 … PRT7`,对应 macOS 的 `HP11 … HP18` |

本机这个 hub 下面没挂任何设备。**但不要删**——它是控制器本身的一部分。

---

## 2. 关键:`AppleUSB20InternalHub` personality 不能省

内置设备(蓝牙/摄像头/指纹)不在根集线器上,而在 `URMH` 这个**内置 hub** 后面。
macOS 给这类 hub 用的驱动类是 **`AppleUSB20InternalHub`**
(部分老仓库写作 `AppleUSB20InternalIntelHub`,那是前者的子类/旧写法)。

所以一份能用的 `USBPorts.kext` 至少要有这两类 personality:

1. `AppleUSBEHCIPCI`(根控制器) —— 声明根集线器上有哪些端口;
2. `AppleUSB20InternalHub`(内置 hub) —— **声明 `HPxx` 这些端口**。

> 不确定自己的机器上该用哪个类名,直接问系统:
> ```bash
> ioreg -c AppleUSB20InternalHub      -w0 -l | head -3
> ioreg -c AppleUSB20InternalIntelHub -w0 -l | head -3
> ```
> 哪个能列出你的内建 hub,就用哪个。

少写第 2 类,后果就是:**一开地图,蓝牙/摄像头/指纹反而全没了**。
本机实测过这个现象。

一份能用的地图在 `Info.plist` 里长这样(personality 名可以自取,`IONameMatch` 不行):

```
EH01                IOProviderClass = AppleUSBEHCIPCI         IONameMatch = EH01
EH01-internal-hub   IOProviderClass = AppleUSB20InternalHub   ← 关键
EH02                IOProviderClass = AppleUSBEHCIPCI         IONameMatch = EH02
EH02-internal-hub   IOProviderClass = AppleUSB20InternalHub   ← 关键
XHCI                IOProviderClass = AppleUSBXHCIPPT         IONameMatch = XHCI
```

> 匹配名要用改名后的 **`EH01` / `EH02`**。Hackintool 之类工具如果在改名之前导出,
> 写进去的是 `EHC1` / `EHC2`,改名之后就再也匹配不上,得手动换过来。

---

## 3. 端口类型怎么填

`UsbConnector` / `portType` 的取值(节选):

| 值 | 含义 | 用在哪 |
|---|---|---|
| `0xFF` (255) | **内建**(Internal) | 蓝牙、摄像头、指纹、hub 自身 |
| `3` | USB-A 标准口(USB3 口也填 3) | 左侧 USB3、右侧 USB2 |
| `9` | Type-C(带开关) | X230 没有 |
| `255` 以外还常用 `0`、`10` | 历史写法 / 其它类型 | 不确定时优先用 `3` |

几个容易填错的:

- **内建设备必须填 255**。填 3 的话蓝牙会被当成「可插拔的外接设备」,
  休眠唤醒后容易掉。
- **左侧那两个 USB3 口的 HS 部分也要填 3**,不要因为它是「USB2 模式」就填别的。
- **`HP21`(hub 自身)填 255**;`HP25` 之类没接出来的端口可以直接不声明。

---

## 4. 怎么做一份自己的地图

别人的地图**不能抄**:端口编号和具体机型、BIOS 版本、网卡配置强相关。
本机和经典仓库 [`banhbaoxamlan/X230-Hackintosh`](https://github.com/banhbaoxamlan/X230-Hackintosh)
的内建 hub 端口号就不一样(它用 `HP22/HP25/HP26`,本机有效的是
`HP22/HP23/HP24/HP26`——HP22 是那个外露的右侧 USB2 口,HP23/HP24/HP26 才是内建设备)。
本机**实测**的那份地图(Hackintool 导出)留在了
[`参考/USB定制/`](参考/USB定制/),端口号和第 2 节的表逐条对得上。

### 4.1 准备:先让所有端口都能看见

```bash
# 1) 确认 ACPI/Patch 里 EHC1→EH01、EHC2→EH02 两条重命名是开的
#    (不开的话 EHC2 内置 hub 根本不会出现,后面全是白做)
# 2) 确认 Kernel/Add 里没有 USBPorts.kext
# 3) 把 USBInjectAll.kext 关掉(Enabled = false)——两条路会抢着声明同一批端口
# 4) 重启
```

X230 不需要端口限制补丁(XHCI 8 个端口 < 15,EHCI 那侧是 hub,不算端口限制),
所以没有地图时,系统本来就会枚举出全部端口。

### 4.2 用 Hackintool 读端口

1. 打开 [Hackintool](https://github.com/benbaker76/Hackintool) → **USB** 标签页。
2. 逐个插拔设备,记下哪个端口在动:
   - 左侧 USB3 口插 U 盘 → `HS01`/`SS01` 或 `HS02`/`SS02`;
   - 右侧 USB2 口插 U 盘 → `HP22`(或你机器上对应的根端口);
   - 内建设备不动,但会一直挂在 `HP23/HP24/HP26` 那一带。
3. 每个设备插两次,取稳定的那个端口号。

### 4.3 生成 kext

三条路,任选:

- **Hackintool 直接导出**:USB 标签页填好类型后,右下角「导出」会生成
  `USBPorts.kext`。
- **[USBMap](https://github.com/corpnewt/USBMap)**(macOS 上跑 Python):
  交互式选端口,自动写 `USBPorts.kext`。
- **[USBToolBox](https://github.com/USBToolBox/tool)**(Windows / Linux 上跑):
  不用先装 macOS,能把地图存成 `UTBMap.kext` 或兼容格式,适合「装系统前先把地图做好」。

> 用 Hackintool / USBMap 生成后,**记得手动补上 `AppleUSB20InternalHub` personality**
> (第 2 节)。有些工具只写根控制器那一层,内建设备就会消失。
>
> 做地图之前**先把 `USBInjectAll.kext` 关掉**(`Kernel/Add` 里 `Enabled = false`),
> 否则它和地图会抢着声明同一批端口。做完再决定留哪个——两者留一个就够。
> **不过本仓库实测下来的结论是不做**——见第 6 节,别白费功夫。

---

## 5. 验证

```bash
# 端口树(能看到 HS/SS/HP 各个端口的名字和速度)
ioreg -p IOUSB -w0 -l | grep -E '\+-o .*(HS|SS|HP|PRT)' | head -40

# 内建设备在不在
system_profiler SPUSBDataType | grep -iE "Bluetooth|Bison|Camera|Fingerprint"

# 摄像头
system_profiler SPCameraDataType
```

对着列表数一遍:该出现的都出现了,该标内建的标了内建,就算成了。

---

## 6. 常见错误

| 现象 | 原因 |
|---|---|
| 内建设备(蓝牙/摄像头/指纹)全消失 | 先查 `EHC1→EH01` / `EHC2→EH02` 有没有开;开了还不行,才是漏了 `AppleUSB20InternalHub` personality |
| 做了地图反而全查不到 | 地图里的 `IONameMatch` 还是 `EHC1`/`EHC2`(改名后应写 `EH01`/`EH02`) |
| 蓝牙能看见但休眠后掉 | 蓝牙端口不是 `255`(内建) |
| 左侧 USB3 口插 U 盘只认 USB2 | `SSxx` 没声明,或类型/端口号填错 |
| 右侧 USB2 口用不了 | 根端口号填错(本机是 `HP22`) |
| 插 U 盘就 panic / 卡住 | 地图里的 `port-count` 和实际端口数对不上 |
| 一开 `USBPorts` 声卡/无线也没了 | 地图把 XHCI 一半覆盖掉了,检查 `Model` 属性是否写成本机机型 |

> `Model` 属性必须等于你的 SMBIOS 机型(本机 `MacBookPro9,2`)。
> 写错成别的机型,personality 就不会匹配,地图等于没生效。

---

## 7. 想省事?

X230 上**不做地图也能跑**:每个控制器端口 < 15,没有端口限制问题,
蓝牙 / 摄像头 / 指纹在默认枚举下就看得见(本机验证过),代价是「未接出的端口也一起显示着」。

**实测结论(2026-09-27):自己做的地图在本机反而坏。** 把 Hackintool 导出的
`USBPorts.kext` 换上去,内建设备(蓝牙 / 摄像头 / 指纹)全部消失;换回
`USBInjectAll` 立刻恢复。原因没查到根上,留了两个嫌疑:

- 那份地图**没声明 `HP21`**(hub 自身;第 2 节的表里写着这一项要填 255);
- 同一份 kext 里 internal-hub 组用 `portType`、XHCI/EHCI 组用 `UsbConnector`,
  键名混用,13 / 15 上到底认哪个没验。

所以本仓库**最终选择不做地图**。第 4 节的流程留着,是想重做的人有个起点;
真要试,先把 `USBInjectAll` 的开关位置记好,一条 `Enabled` 就能切回来。
