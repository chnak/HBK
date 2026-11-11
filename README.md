# HBK

把 HarmonyOS 手机变成 PC 的**蓝牙键盘 / 鼠标**。

思路和 [BBK](https://github.com/chnak/BBK)（BlackBerry Q20 版）一样：手机扮演
Bluetooth HID Device，PC 扮演 HID Host，键盘和触控板的输入都转成标准 HID 报告
发过去。Windows 会把它识别成普通的蓝牙键鼠，**不用装驱动**。

## 界面

横屏全屏，三栏：

```
┌───────────────────────────────────────────────────────────────┐
│ ● 已连接：DESKTOP-XXX                              重连          │
├──────────────┬───────────────────────────┬─────────────────────┤
│ Esc ` 1 2 3  │                           │ 7 8 9 0 - = ⌫        │
│ Tab q w e r  │                           │ y u i o p [ ]        │
│ Caps a s d f │      鼠标触摸板           │ h j k l ; ⏎          │
│ Shift z x c  │                           │ n m , . / ↑          │
│ Ctrl Win Alt │                           │ Space Alt ← ↓ →      │
├──────────────┴───────────────────────────┴─────────────────────┤
│ 🔊+ 🔉- 🔇 ⏯ ⏭ ⏮ F5 F12                                     │
├───────────────────────────────────────────────────────────────┤
│ 复制 粘贴 剪切 全选 撤销 切换 任务 锁屏          找鼠标        │
└───────────────────────────────────────────────────────────────┘
```

键盘从标准 QWERTY 的正中间劈开：左手那一半在左，右手那一半在右，中间空出来当
鼠标区。修饰键（Ctrl / Win / Alt / Shift）是**锁定式**的 —— 点一下按下，再点一下
松开，按住 Shift 时字母键会变成大写。

底部两排是常用的：

- 媒体键（音量、播放）和 F5 / F12
- 快捷键：复制 Ctrl+C、粘贴 Ctrl+V、剪切 Ctrl+X、全选 Ctrl+A、撤销 Ctrl+Z、
  切换 Alt+Tab、任务管理器 Ctrl+Shift+Esc、锁屏 Win+L
- 「找鼠标」：让指针抖一圈，大屏上找不到时用

## 手势

| 手势 | 作用 |
|---|---|
| 单指移动 | 移动鼠标指针 |
| 单指轻点 | 左键 |
| 单指按住再移动 | 拖选（左键按住不放） |
| 双指轻点 | 右键 |
| 三指轻点 | 中键 |
| 双指捏合 | 缩放（Ctrl + 滚轮） |
| 双指横滑 | 横向滚动 |

## 硬件要求

- **HarmonyOS 6.x / API 23 及以上**。`@ohos.bluetooth.hid` 的
  `createHidDeviceProfile()`（HID 从机角色）是 API 23 才有的；更老的版本只有
  HID Host 角色，做不了这件事。
- 应用必须**在前台**。系统会在应用退到后台时自动注销 HID 注册，所以不能锁屏、
  不能切到别的应用。

## 编译

需要 DevEco Studio（自带 JDK 和 SDK）。命令行编译：

```powershell
.\build.ps1
```

产物在 `entry\build\default\outputs\default\entry-default-unsigned.hap`。

> ⚠️ 必须用 DevEco 自带的 JDK（`jbr`）。系统里装的 JDK 24 会让
> `app_packing_tool.jar` 直接崩（0xC0000005）。

## 签名与安装

一条命令：编译 → 签名 → 安装 → 启动。

```powershell
.\install.ps1                       # 自动找手机：先看 hdc 已连上的，再扫本机网段
.\install.ps1 -Device 192.168.50.22:37793
```

手机上的无线调试地址在「开发者选项 → 无线调试 → IP 地址和端口」里看。
插 USB 线的话 hdc 会自己认出来。

签名用的是华为云签发的调试证书（`hap_installer` 已经存了一份）：

| 文件 | 说明 |
|---|---|
| `xiaobai.p12` | 私钥，alias `xiaobai`，密码 `xiaobai123`，EC P-256 |
| `auto_debug_<id>.cer.cer` | 应用证书 |
| `dev_hackeris_hish_desktop.p7b` | profile，里面有这台手机的 UDID |

> ⚠️ **profile 和包名是绑死的**：`AppScope\app.json5` 里的 `bundleName`
> 必须和 profile 里的 `bundle-name` 一致，否则安装报 `verify signature failed`。
> 想用自己的包名，就要在 DevEco 里重新配一次自动签名。

也可以走 DevEco 的「自动签名」：用 DevEco Studio 打开本工程 →
`Project Structure → Signing Configs` → 勾 **Automatically generate signature**，
之后 `build.ps1` 出来的就是签好名的 hap。

## 配对

手机和 PC 先在系统蓝牙里配对。应用会从已配对列表里找设备，然后：

1. 用蓝牙 **COD 大类**判断哪些是电脑（`MajorClass.MAJOR_COMPUTER`），
   比认名字可靠 —— 电脑的名字可以是任何东西
2. 扫一次蓝牙，拿到电脑**当前**广播的地址。Windows 会轮换自己的地址，
   配对列表里存的那份会失效，连接请求就会寻呼超时
3. 由手机主动连 PC 的 HID 服务 —— 方向和 BB10 上一样，**必须由手机发起**，
   否则 PC 那边不会出现键盘

扫描到但还没配对的电脑，列表里会标成「电脑·未配对」，点一下先配对再连。

## 已知问题

**手机连不上 PC 时怎么查**：手机侧日志会出现

```
btm_acl_paging: bda:3a:76:...:f9
l2c_link_hci_conn_comp: ... connection fail 4
```

`connection fail 4` 是 HCI 的**寻呼超时**：PC 没有回应连接请求。检查方向：

- PC 的蓝牙地址：`Get-NetAdapter` 里那个 PAN 网卡的 MAC
- 手机配对列表里的地址：`hilog` 里 `HBK: paired [xx:xx:...] <名字>`
- 让 PC 可被发现再试（否则手机扫不到它）：
  `BluetoothEnableDiscovery(NULL, 300, TRUE)`（`bthprops.cpl`）

## 代码结构

```
entry/src/main/ets/
├── entryability/EntryAbility.ets   应用入口，全屏、前后台切换时释放按键
├── pages/Index.ets                 横屏三栏布局
├── components/
│   ├── KeyRow.ets                  一行按键和单个按键（锁定式修饰键、快捷键）
│   └── TouchPad.ets                鼠标区与手势识别
└── model/
    ├── HidDescriptor.ets           HID report descriptor
    ├── HidDevice.ets               HID 从机：注册、连接、发报告
    ├── Keymap.ets                  键位表（HID usage code）
    └── Global.ets                  全局唯一的 HID 实例
tools/bt-host.ps1                   PC 侧：让电脑可被发现、允许手机连进来
```

## 已知限制

- **打不了中文**：HID 只能发键码，中文必须由 PC 的输入法打出来。
- 不能后台运行（见上面的硬件要求）。
- 只能连一个 HID Host，切换电脑要重新配对。
