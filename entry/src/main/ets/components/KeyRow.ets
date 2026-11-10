/*
 * KeyRow - one row of the on-screen keyboard.
 *
 * The keys of a row are laid out with weights, so a key can be wider than
 * the others (Shift, Enter, Space).
 */
import { KeyDef, MOD_ALT, MOD_CTRL, MOD_GUI, MOD_SHIFT } from '../model/Keymap';
import { hidDevice } from '../model/Global';

@Component
export struct KeyRow {
  keys: KeyDef[] = [];
  /** True while Shift is latched, so the keys can show their upper case. */
  @Link shifted: boolean;

  build() {
    Row() {
      ForEach(this.keys, (k: KeyDef) => {
        KeyCap({ def: k, shifted: this.shifted })
      }, (k: KeyDef) => k.label)
    }
    .width('100%')
    .justifyContent(FlexAlign.Center)
  }
}

/**
 * KeyCap - a single key.
 *
 * A plain key is pressed and released right away.  A modifier key latches:
 * it stays down until it is tapped again, the way the right Shift of a
 * BlackBerry keyboard behaves.
 */
@Component
export struct KeyCap {
  def: KeyDef = {
    label: '', usage: 0, shifted: '', wide: 1, latch: false, consumer: false
  };
  @Link shifted: boolean;

  build() {
    Text(this.label())
      .fontSize(15)
      .fontColor('#e8eef4')
      .textAlign(TextAlign.Center)
      .height(44)
      .borderRadius(8)
      .backgroundColor(this.def.latch && this.shifted ? '#0a3d22' : '#171e25')
      .border({ width: 1, color: this.def.latch && this.shifted ? '#00d060' : '#232d36' })
      .layoutWeight(this.def.wide)
      .onClick(() => {
        this.tap();
      })
  }

  private label(): string {
    if (this.def.latch) {
      return this.def.label;
    }
    if (this.shifted && this.def.shifted.length > 0) {
      return this.def.shifted;
    }
    return this.def.label;
  }

  private tap(): void {
    const d: KeyDef = this.def;

    if (d.latch) {
      // Modifier keys toggle: the key goes down and stays down.
      const bits: number = d.usage === 0xE0 ? MOD_CTRL
        : d.usage === 0xE1 ? MOD_SHIFT
        : d.usage === 0xE2 ? MOD_ALT
        : MOD_GUI;
      const on: boolean = (hidDevice.modifierState() & bits) === 0;
      hidDevice.setModifier(bits, on);
      if (bits === MOD_SHIFT) {
        this.shifted = on;
      }
      return;
    }

    if (d.consumer) {
      hidDevice.sendConsumer(d.usage);
      return;
    }

    // A key with an upper case character is sent as Shift + the key.
    const needShift: boolean = this.shifted && d.shifted.length > 0;
    hidDevice.pressKey(d.usage, needShift);
    hidDevice.releaseKey(d.usage);
  }
}
