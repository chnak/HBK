/*
 * HidDevice - the phone as a Bluetooth HID device.
 *
 * The phone plays the role of the keyboard/mouse and the PC plays the role
 * of the host, exactly like the BB10 build did with bt_hid_connect().
 * Windows enumerates us as an ordinary Bluetooth keyboard and mouse, so no
 * driver is needed on the PC.
 *
 * The whole thing only works while the app is in the foreground: the system
 * cancels the registration as soon as the app goes to the background.
 */
import { common, connection, hid } from '@kit.ConnectivityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

import { HidDescriptor } from './HidDescriptor';

const TAG: string = 'HBK';
const DOMAIN: number = 0x3200;

/** Modifier bits of the keyboard report. */
const MOD_CTRL: number = 0x01;
const MOD_SHIFT: number = 0x02;
const MOD_ALT: number = 0x04;
const MOD_GUI: number = 0x08;

export class HidDevice {
  private profile: hid.HidDeviceProfile | null = null;
  private registered: boolean = false;
  private connected: boolean = false;
  private peer: string = '';

  /** The key codes currently held down, in the order they were pressed. */
  private held: number[] = [];
  /** Modifiers the user latched with the modifier keys. */
  private latched: number = 0;
  /** Modifiers that belong to the key being pressed right now. */
  private temporary: number = 0;

  /** The mouse buttons currently held down. */
  private buttons: number = 0;

  /** LED state reported by the host: bit 0 num lock, bit 1 caps lock. */
  private leds: number = 0;

  isRegistered(): boolean {
    return this.registered;
  }

  isConnected(): boolean {
    return this.connected;
  }

  peerName(): string {
    return this.peer;
  }

  ledState(): number {
    return this.leds;
  }

  /**
   * Register the HID device service.  The app has to be in the foreground,
   * and no other app may have registered a HID device already.
   */
  async register(): Promise<boolean> {
    if (this.registered) {
      return true;
    }

    const profile: hid.HidDeviceProfile = hid.createHidDeviceProfile();
    this.profile = profile;

    const sdp: hid.HidDeviceSdp = {
      name: 'HBK',
      description: 'Harmony Bluetooth Keyboard',
      provider: 'HBK',
      subclass: hid.Subclass.SUBCLASS_COMBO,
      descriptors: HidDescriptor.build()
    };

    return new Promise<boolean>((resolve) => {
      try {
        profile.registerHidDevice(sdp, {}, {}, (ok: boolean) => {
          this.registered = ok;
          hilog.info(DOMAIN, TAG, 'registerHidDevice: %{public}s', ok ? 'ok' : 'refused');
          if (ok) {
            this.watchHost();
          }
          resolve(ok);
        });
      } catch (e) {
        hilog.error(DOMAIN, TAG, 'registerHidDevice threw: %{public}s', (e as BusinessError).message);
        resolve(false);
      }
    });
  }

  /** Give the registration back to the system. */
  unregister(): void {
    if (!this.profile || !this.registered) {
      return;
    }
    try {
      this.profile.unregisterHidDevice();
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'unregister failed: %{public}s', (e as BusinessError).message);
    }
    this.registered = false;
    this.connected = false;
    this.held = [];
    this.latched = 0;
    this.temporary = 0;
    this.buttons = 0;
  }

  /**
   * Look for the PC among the paired devices and connect to it.  The phone
   * has to be the one that opens the connection, otherwise the PC never
   * sees a keyboard.
   */
  async connectToHost(): Promise<boolean> {
    if (!this.profile || !this.registered) {
      return false;
    }

    const peers: string[] = this.findHosts();
    if (peers.length === 0) {
      hilog.info(DOMAIN, TAG, 'no paired host found');
      return false;
    }

    const address: string = peers[0];
    const target: common.BluetoothAddress = {
      address: address,
      addressType: common.BluetoothAddressType.REAL
    };
    try {
      this.profile.connect(target);
      // The profile is connected asynchronously; from here on reports are
      // worth trying, the stack drops them until the link is up.
      this.connected = true;
      this.peer = connection.getRemoteDeviceName(address);
      hilog.info(DOMAIN, TAG, 'connecting to %{public}s (%{public}s)',
        this.peer, address);
      return true;
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'connect failed: %{public}s', (e as BusinessError).message);
      return false;
    }
  }

  /**
   * The paired devices that could be a PC.  A keyboard or a mouse shows up
   * as a HID device of its own, so those are skipped.
   */
  private findHosts(): string[] {
    const out: string[] = [];
    let paired: Array<string> = [];
    try {
      paired = connection.getPairedDevices();
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'getPairedDevices failed: %{public}s', (e as BusinessError).message);
      return out;
    }

    for (let i = 0; i < paired.length; i++) {
      const address: string = paired[i];
      let name: string = '';
      try {
        name = connection.getRemoteDeviceName(address);
      } catch (e) {
        hilog.warn(DOMAIN, TAG, 'no name for %{public}s', address);
      }
      const lower: string = name.toLowerCase();
      // "PC", "Desktop", "Laptop", "Surface", "ThinkPad", "MacBook" ...
      const looksLikePc: boolean = lower.indexOf('pc') >= 0
        || lower.indexOf('desktop') >= 0
        || lower.indexOf('laptop') >= 0
        || lower.indexOf('macbook') >= 0
        || lower.indexOf('surface') >= 0
        || lower.indexOf('thinkpad') >= 0
        || lower.indexOf('computer') >= 0;
      if (looksLikePc) {
        out.push(address);
      }
    }
    return out;
  }

  /** Listen for the host's LED report and for the cable being unplugged. */
  private watchHost(): void {
    if (!this.profile) {
      return;
    }
    this.profile.onSetReport((data: hid.SetReportData) => {
      if (data.type === hid.ReportType.REPORT_TYPE_OUTPUT) {
        const bytes: Uint8Array = data.data;
        this.leds = bytes.length > 0 ? bytes[0] : 0;
        hilog.info(DOMAIN, TAG, 'host LEDs: %{public}d', this.leds);
      }
    });
    this.profile.onVirtualCableUnplug(() => {
      hilog.info(DOMAIN, TAG, 'host unplugged');
      this.connected = false;
    });
  }

  // ------------------------------------------------------------- keyboard

  /**
   * Press a key.  The key stays down until releaseKey() is called with the
   * same usage.
   */
  pressKey(usage: number, needShift: boolean): void {
    if (this.held.indexOf(usage) < 0) {
      this.held.push(usage);
    }
    this.temporary = needShift ? MOD_SHIFT : 0;
    this.sendKeyboard();
  }

  /** Release a key that was pressed before. */
  releaseKey(usage: number): void {
    const at: number = this.held.indexOf(usage);
    if (at >= 0) {
      this.held.splice(at, 1);
    }
    this.temporary = 0;
    this.sendKeyboard();
  }

  /** Release everything - used when the app loses the foreground. */
  releaseAll(): void {
    this.held = [];
    this.latched = 0;
    this.temporary = 0;
    this.buttons = 0;
    this.sendKeyboard();
    this.sendMouse(0, 0, 0, 0, 0);
  }

  /** Set or clear one modifier bit (latched by the modifier keys). */
  setModifier(bit: number, on: boolean): void {
    if (on) {
      this.latched |= bit;
    } else {
      this.latched &= ~bit;
    }
    this.sendKeyboard();
  }

  modifierState(): number {
    return this.latched;
  }

  private sendKeyboard(): void {
    if (!this.profile || !this.connected) {
      return;
    }
    const report: number[] = [this.latched | this.temporary, 0, 0, 0, 0, 0, 0, 0];
    // The report carries six key codes; anything beyond that is dropped.
    for (let i = 0; i < this.held.length && i < 6; i++) {
      report[2 + i] = this.held[i] & 0xFF;
    }
    this.send(HidDescriptor.REPORT_KEYBOARD, report);
  }

  // ---------------------------------------------------------------- mouse

  mouseMove(dx: number, dy: number): void {
    this.sendMouse(this.buttons, dx, dy, 0, 0);
  }

  mouseButton(button: number, pressed: boolean): void {
    if (pressed) {
      this.buttons |= button;
    } else {
      this.buttons &= ~button;
    }
    this.sendMouse(this.buttons, 0, 0, 0, 0);
  }

  mouseWheel(notches: number): void {
    this.sendMouse(this.buttons, 0, 0, notches, 0);
  }

  mousePan(notches: number): void {
    this.sendMouse(this.buttons, 0, 0, 0, notches);
  }

  /**
   * Zoom is Ctrl plus the wheel: the modifier lives in the keyboard report
   * and the wheel in the mouse report, so Ctrl is held for the turn.
   */
  mouseZoom(notches: number): void {
    if (!this.connected) {
      return;
    }
    this.temporary = MOD_CTRL;
    this.sendKeyboard();
    this.sendMouse(this.buttons, 0, 0, notches, 0);
    this.temporary = 0;
    this.sendKeyboard();
  }

  private sendMouse(buttons: number, dx: number, dy: number, wheel: number, pan: number): void {
    if (!this.profile || !this.connected) {
      return;
    }
    const report: number[] = [
      buttons & 0xFF,
      clampSigned(dx),
      clampSigned(dy),
      clampSigned(wheel),
      clampSigned(pan)
    ];
    this.send(HidDescriptor.REPORT_MOUSE, report);
  }

  // ------------------------------------------------------------- consumer

  /** Send one consumer-page key (volume, media, ...). */
  sendConsumer(usage: number): void {
    if (!this.profile || !this.connected) {
      return;
    }
    const report: number[] = [0, 0, 0, 0, 0, 0, 0, 0];
    report[0] = usage & 0xFF;
    report[1] = (usage >> 8) & 0xFF;
    this.send(HidDescriptor.REPORT_CONSUMER, report);
  }

  // --------------------------------------------------------------- plumbing

  private send(reportId: number, bytes: number[]): void {
    if (!this.profile) {
      return;
    }
    try {
      this.profile.sendReport(reportId, new Uint8Array(bytes));
    } catch (e) {
      // The link can be down even though connect() did not complain.
      this.connected = false;
      hilog.error(DOMAIN, TAG, 'sendReport %{public}d failed: %{public}s',
        reportId, (e as BusinessError).message);
    }
  }
}

/** Keep a movement inside the range a signed byte can carry. */
function clampSigned(value: number): number {
  if (value > 127) {
    return 127;
  }
  if (value < -127) {
    return -127;
  }
  return value;
}
