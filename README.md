# HBK

把 HarmonyOS 手机变成 PC 的**蓝牙键盘 / 鼠标**。

思路和 [BBK](https://github.com/chnak/BBK)（BlackBerry Q20 版）一样：手机扮演
Bluetooth HID Device，PC 扮演 HID Host，键盘和触控板的输入都转成标准 HID 报告
发过去。Windows 会把它识别成普通的蓝牙键鼠，**不用装驱动**。

## 界面

横屏，三栏：

```
┌───────────────────────────────────────────────────────────────┐
│ ● 已连接：DESKTOP-XXX            │        电量  重连          │
├──────────────┬───────────────────────────┬─────────────────────┤
│ Esc ` 1 2 3  │                           │ 7 8 9 0 - = ⌫        │
│ Tab q w e r  │                           │ y u i o p [ ]        │
│ Caps a s d f │      鼠标触摸板           │ h j k l ; ⏎          │
│ Shift z x c  │                           │ n m , . / ↑          │
│ Ctrl Win Alt │                           │ Space Alt ← ↓ →      │
├──────────────┴───────────────────────────┴─────────────────────┤
│ 🔊+ 🔉- 🔇 ⏯ ⏭ ⏮   F5 F11 F12                              │
└───────────────────────────────────────────────────────────────┘
```

键盘从标准 QWERTY 的正中间劈开：左手那一半在左，右手那一半在右，中间空出来当
鼠标区。修饰键（Ctrl / Win / Alt / Shift）是**锁定式**的 —— 点一下按下，再点一下
松开，按住 Shift 时字母键会变成大写。

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

自动签名要靠 DevEco 的「自动签名」功能，它需要华为账号：

1. 用 DevEco Studio 打开本工程
2. `File → Project Structure → Signing Configs`，勾选 **Automatically generate signature**
3. 连上手机，`Run` 即可

勾过之后，`build-profile.json5` 里会有 `signingConfigs`，`build.ps1` 产出的就是
签好名的 hap，可以直接用 `hdc install` 装。

命令行安装：

```powershell
hdc install entry\build\default\outputs\default\entry-default-signed.hap
```

## 配对

手机和 PC 先在系统蓝牙里配对。应用会从已配对列表里找名字像电脑的设备
（PC / Desktop / Laptop / MacBook / Surface / ThinkPad），然后由手机主动去连
PC 的 HID 服务 —— 方向和 BB10 上一样，**必须由手机发起连接**，否则 PC 那边不会
出现键盘。

## 代码结构

```
entry/src/main/ets/
├── entryability/EntryAbility.ets   应用入口，前后台切换时释放按键
├── pages/Index.ets                 横屏三栏布局
├── components/
│   ├── KeyRow.ets                  一行按键和单个按键（锁定式修饰键）
│   └── TouchPad.ets                鼠标区与手势识别
└── model/
    ├── HidDescriptor.ets           HID report descriptor
    ├── HidDevice.ets               HID 从机：注册、连接、发报告
    ├── Keymap.ets                  键位表（HID usage code）
    └── Global.ets                  全局唯一的 HID 实例
```

## 已知限制

- **打不了中文**：HID 只能发键码，中文必须由 PC 的输入法打出来。
- 不能后台运行（见上面的硬件要求）。
- 只能连一个 HID Host，切换电脑要重新配对。
