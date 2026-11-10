/*
 * Index - the whole app in one page.
 *
 * Landscape, three columns:
 *
 *   left keys      touchpad      right keys
 *
 * The keyboard is split down the middle of a normal QWERTY board, so the
 * left hand keeps the keys it knows and the right hand the other half.
 */
import { bluetooth } from '@kit.ConnectivityKit';
import { abilityAccessCtrl } from '@kit.AbilityKit';
import { promptAction } from '@kit.ArkUI';
import { BusinessError } from '@kit.BasicServicesKit';

import { hidDevice } from '../model/Global';
import { PeerInfo } from '../model/HidDevice';
import { KeyDef, extraKeys, leftRows, rightRows, shortcutKeys } from '../model/Keymap';
import { KeyRow } from '../components/KeyRow';
import { TouchPad } from '../components/TouchPad';

@Entry
@Component
struct Index {
  /** True while Shift is latched. */
  @State shifted: boolean = false;
  /** What the status line says. */
  @State status: string = '正在启动…';
  /** True when the HID link is up. */
  @State linked: boolean = false;
  /** True once the host has accepted a report - the real link state. */
  @State linkUp: boolean = false;
  /** The paired devices the user can pick from. */
  @State peers: PeerInfo[] = [];
  /** True while the device picker is showing. */
  @State picking: boolean = false;

  private left: KeyDef[][] = leftRows();
  private right: KeyDef[][] = rightRows();
  private extra: KeyDef[] = extraKeys();
  private shortcuts: KeyDef[] = shortcutKeys();
  /** Tries the connection again every few seconds until it works. */
  private retryTimer: number = -1;
  /** Keeps the status line in step with the real link state. */
  private heartbeat: number = -1;

  aboutToAppear(): void {
    this.start();
    this.heartbeat = setInterval(() => {
      const up: boolean = hidDevice.isLinkUp();
      if (up !== this.linkUp) {
        this.linkUp = up;
        if (up) {
          this.status = '已连接：' + hidDevice.peerName();
        }
      }
    }, 1500);
  }

  /**
   * The system cancels the HID registration when the app leaves the
   * foreground, so everything has to be set up again when it comes back.
   */
  onPageShow(): void {
    if (!hidDevice.isRegistered()) {
      this.start();
    }
  }

  onPageHide(): void {
    this.stopRetry();
    if (this.heartbeat >= 0) {
      clearInterval(this.heartbeat);
      this.heartbeat = -1;
    }
  }

  private startRetry(): void {
    this.stopRetry();
    this.retryTimer = setInterval(() => {
      if (!this.linked) {
        this.connectOnly();
      } else if (hidDevice.isLinkUp()) {
        // The host is really there; show it.
        this.status = '已连接：' + hidDevice.peerName();
      }
    }, 8000);
  }

  private stopRetry(): void {
    if (this.retryTimer >= 0) {
      clearInterval(this.retryTimer);
      this.retryTimer = -1;
    }
  }

  private async start(): Promise<void> {
    this.status = '正在申请蓝牙权限…';
    const granted: boolean = await this.askBluetooth();
    if (!granted) {
      this.status = '没有蓝牙权限，无法工作';
      return;
    }

    this.status = '正在注册 HID…';
    const ok: boolean = await hidDevice.register();
    if (!ok) {
      this.status = '注册失败：请确认蓝牙已打开，且没有别的应用占用 HID';
      return;
    }

    this.status = '正在查找电脑…';
    await this.refreshPeers();
    if (this.peers.length === 0) {
      this.status = '没有已配对的设备：请先在系统蓝牙里和电脑配对';
      this.picking = true;
      this.startRetry();
      return;
    }

    await this.connectOnly();
  }

  /**
   * The list the user picks from: the paired devices plus the computers
   * that show up in a scan but are not paired yet.
   */
  private async refreshPeers(): Promise<void> {
    const paired: PeerInfo[] = hidDevice.listPeers();
    const scanned: PeerInfo[] = await hidDevice.scanPeers(6000);
    const merged: PeerInfo[] = [];
    for (const p of paired) {
      merged.push(p);
    }
    for (const s of scanned) {
      if (!s.isComputer) {
        continue;
      }
      let known = false;
      for (const p of paired) {
        if (p.name === s.name) {
          known = true;
          break;
        }
      }
      if (!known) {
        merged.push(s);
      }
    }
    this.peers = merged;
  }

  /** Try to reach the computer; give up to the user if that does not work. */
  private async connectOnly(): Promise<void> {
    const linked: boolean = await hidDevice.connectToHost();
    if (!linked) {
      // The name of a computer is not something we can rely on, so the
      // user picks it from the list of paired devices.
      this.status = '请选择要控制的电脑（若列表里没有，请在电脑端重新配对）';
      this.picking = true;
      this.startRetry();
      return;
    }
    this.linked = true;
    this.picking = false;
    this.status = '已连接：' + hidDevice.peerName();
    this.stopRetry();
  }

  /** A key from the strips below the keyboard. */
  private tapExtra(k: KeyDef): void {
    if (k.consumer) {
      hidDevice.sendConsumer(k.usage);
    } else if (k.mods !== 0) {
      hidDevice.sendChord(k.mods, k.usage);
    } else {
      hidDevice.pressKey(k.usage, false);
      hidDevice.releaseKey(k.usage);
    }
  }

  /** Connect to one of the devices the user picked. */
  private choosePeer(peer: PeerInfo): void {
    this.status = '正在连接…';
    if (!peer.paired) {
      // A computer that shows up in a scan but was never paired: pair
      // with it first, then open the HID channel.
      hidDevice.pairWith(peer.address);
    }
    if (hidDevice.connectTo(peer.address)) {
      this.linked = true;
      this.picking = false;
      this.status = '已连接：' + hidDevice.peerName();
      this.stopRetry();
    } else {
      this.status = '连接失败';
    }
  }

  /**
   * ACCESS_BLUETOOTH is a user_grant permission: without the user saying
   * yes, the Bluetooth stack refuses every call - registering the HID
   * device fails with "Permission denied".
   */
  private async askBluetooth(): Promise<boolean> {
    const context = this.getUIContext().getHostContext();
    if (!context) {
      return false;
    }
    try {
      const atManager = abilityAccessCtrl.createAtManager();
      const result = await atManager.requestPermissionsFromUser(
        context, ['ohos.permission.ACCESS_BLUETOOTH']);
      return result.authResults.length > 0 && result.authResults[0] === 0;
    } catch (e) {
      console.error('HBK: 申请蓝牙权限失败 ' + (e as BusinessError).message);
      return false;
    }
  }

  private reconnect(): void {
    this.start();
  }

  build() {
    Column() {
      // ------------------------------------------------------ status line
      Row() {
        Circle({ width: 10, height: 10 })
          .fill(this.linkUp ? '#00d060' : '#ff5a5a')
        Text(this.status)
          .fontSize(12)
          .fontColor('#9fb0c0')
          .layoutWeight(1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Button('重连')
          .fontSize(12)
          .height(26)
          .padding({ left: 10, right: 10 })
          .backgroundColor('#1b242e')
          .fontColor('#c8d6e2')
          .onClick(() => {
            this.reconnect();
          })
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 4, bottom: 4 })

      // ------------------------------------------------------------ keys
      if (this.picking) {
        // The device of the PC is not recognised by name alone, so the
        // user picks it from the paired devices.
        Column() {
          Text('选择要控制的电脑')
            .fontSize(16)
            .fontColor('#c8d6e2')
            .margin({ top: 12, bottom: 10 })
          ForEach(this.peers, (p: PeerInfo) => {
            Row() {
              Text(p.name.length > 0 ? p.name : p.address)
                .fontSize(15)
                .fontColor('#e8eef4')
                .layoutWeight(1)
              if (p.isComputer) {
                Text(p.paired ? '电脑' : '电脑·未配对')
                  .fontSize(11)
                  .fontColor('#0b0e11')
                  .backgroundColor(p.paired ? '#00d060' : '#3a4a58')
                  .padding({ left: 6, right: 6 })
                  .borderRadius(4)
                  .margin({ right: 8 })
              }
            }
            .width('100%')
            .height(46)
            .padding({ left: 12, right: 12 })
            .margin({ bottom: 6 })
            .borderRadius(8)
            .backgroundColor('#171e25')
            .border({ width: 1, color: '#232d36' })
            .onClick(() => {
              this.choosePeer(p);
            })
          }, (p: PeerInfo) => p.address)
        }
        .width('100%')
        .layoutWeight(1)
        .padding({ left: 20, right: 20 })
      } else {
        Row() {
          // left hand
          Column() {
            ForEach(this.left, (row: KeyDef[]) => {
              KeyRow({ keys: row, shifted: this.shifted })
            }, (row: KeyDef[]) => row[0].label)
          }
          .width('32%')
          .justifyContent(FlexAlign.Center)

          // the mouse
          TouchPad()
            .layoutWeight(1)
            .height('100%')
            .margin({ left: 6, right: 6 })

          // right hand
          Column() {
            ForEach(this.right, (row: KeyDef[]) => {
              KeyRow({ keys: row, shifted: this.shifted })
            }, (row: KeyDef[]) => row[0].label)
          }
          .width('32%')
          .justifyContent(FlexAlign.Center)
        }
        .width('100%')
        .layoutWeight(1)
        .padding({ left: 6, right: 6, bottom: 4 })
      }

      // ------------------------------------------------------ extra keys
      Row() {
        ForEach(this.extra, (k: KeyDef) => {
          Text(k.label)
            .fontSize(13)
            .fontColor('#c8d6e2')
            .textAlign(TextAlign.Center)
            .layoutWeight(1)
            .height(34)
            .borderRadius(8)
            .backgroundColor('#171e25')
            .border({ width: 1, color: '#232d36' })
            .onClick(() => {
              this.tapExtra(k);
            })
        }, (k: KeyDef) => k.label)
      }
      .width('100%')
      .padding({ left: 6, right: 6, bottom: 4 })

      // ----------------------------------------------------- shortcut keys
      Row() {
        ForEach(this.shortcuts, (k: KeyDef) => {
          Text(k.label)
            .fontSize(13)
            .fontColor('#c8d6e2')
            .textAlign(TextAlign.Center)
            .layoutWeight(1)
            .height(34)
            .borderRadius(8)
            .backgroundColor('#171e25')
            .border({ width: 1, color: '#232d36' })
            .onClick(() => {
              this.tapExtra(k);
            })
        }, (k: KeyDef) => k.label)
        Text('找鼠标')
          .fontSize(13)
          .fontColor('#c8d6e2')
          .textAlign(TextAlign.Center)
          .layoutWeight(1)
          .height(34)
          .borderRadius(8)
          .backgroundColor('#171e25')
          .border({ width: 1, color: '#232d36' })
          .onClick(() => {
            hidDevice.findCursor();
          })
      }
      .width('100%')
      .padding({ left: 6, right: 6, bottom: 6 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#0b0e11')
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
