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
import { promptAction } from '@kit.ArkUI';
import { BusinessError } from '@kit.BasicServicesKit';

import { hidDevice } from '../model/Global';
import { KeyDef, extraKeys, leftRows, rightRows } from '../model/Keymap';
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

  private left: KeyDef[][] = leftRows();
  private right: KeyDef[][] = rightRows();
  private extra: KeyDef[] = extraKeys();

  aboutToAppear(): void {
    this.start();
  }

  private async start(): Promise<void> {
    this.status = '正在注册 HID…';
    const ok: boolean = await hidDevice.register();
    if (!ok) {
      this.status = '注册失败：请确认蓝牙已打开，且没有别的应用占用 HID';
      return;
    }

    this.status = '正在查找电脑…';
    const linked: boolean = await hidDevice.connectToHost();
    if (!linked) {
      this.status = '没有找到已配对的电脑：请先在系统蓝牙里配对';
      return;
    }
    this.linked = true;
    this.status = '已连接：' + hidDevice.peerName();
  }

  private reconnect(): void {
    this.start();
  }

  build() {
    Column() {
      // ------------------------------------------------------ status line
      Row() {
        Circle({ width: 10, height: 10 })
          .fill(this.linked ? '#00d060' : '#ff5a5a')
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
              if (k.consumer) {
                hidDevice.sendConsumer(k.usage);
              } else {
                hidDevice.pressKey(k.usage, false);
                hidDevice.releaseKey(k.usage);
              }
            })
        }, (k: KeyDef) => k.label)
      }
      .width('100%')
      .padding({ left: 6, right: 6, bottom: 6 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#0b0e11')
  }
}
