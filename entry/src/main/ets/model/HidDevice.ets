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
import { baseProfile, bluetoothManager, common, connection, constant, hid } from '@kit.ConnectivityKit';
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

/** One paired Bluetooth device. */
export interface PeerInfo {
  address: string;
  name: string;
  /** True when the device announces itself as a computer - this is the
   *  Bluetooth class of device, which is far more reliable than the name. */
  isComputer: boolean;
  /** True when the phone is already paired with it. */
  paired: boolean;
}

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
  /** How often the last report has been repeated while the link was down. */
  private retries: number = 0;
  /** True once the host has accepted a report. */
  private linkUp: boolean = false;

  isRegistered(): boolean {
    return this.registered;
  }

  isConnected(): boolean {
    return this.connected;
  }

  /** True once the host has accepted a report, so the link is really up. */
  isLinkUp(): boolean {
    return this.linkUp;
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
   *
   * The system cancels the registration when the app leaves the foreground,
   * so this has to be called again every time the app comes back.
   */
  async register(): Promise<boolean> {
    // Drop whatever we think we still hold: after a trip to the background
    // the system has cancelled it, and registering twice is refused.
    this.unregister();

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
        // The QoS of the two channels: the host sends us the LED report,
        // we send the keyboard and mouse reports.
        const inQos: hid.HidDeviceQos = {
          serviceType: hid.ServiceType.SERVICE_BEST_EFFORT,
          tokenRate: 0,
          tokenBucketSize: 0,
          peakBandwidth: 0,
          latency: -1,
          delayVariation: -1
        };
        const outQos: hid.HidDeviceQos = {
          serviceType: hid.ServiceType.SERVICE_BEST_EFFORT,
          tokenRate: 0,
          tokenBucketSize: 0,
          peakBandwidth: 0,
          latency: -1,
          delayVariation: -1
        };
        profile.registerHidDevice(sdp, inQos, outQos, (ok: boolean) => {
          // The callback reports the registration state: it also fires
          // with false when the system drops the registration because the
          // app went to the background.
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
    if (!this.profile) {
      return;
    }
    try {
      this.profile.unregisterHidDevice();
    } catch (e) {
      // The system already dropped it when the app went to the background.
      hilog.info(DOMAIN, TAG, 'unregister: %{public}s', (e as BusinessError).message);
    }
    this.registered = false;
    this.connected = false;
    this.linkUp = false;
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
    const peers: PeerInfo[] = this.listPeers();
    const pc: PeerInfo | undefined = this.pickHost(peers);
    if (!pc) {
      hilog.info(DOMAIN, TAG, 'no paired host found');
      return false;
    }

    // The address in the paired list is the private address the peer had
    // when it was paired.  Windows rotates that address, so the entry
    // goes stale and the connection request times out.  Scanning finds the
    // address the computer is using right now.
    const live: string = await this.scanForHost(pc.name, 8000);
    if (live.length > 0 && live !== pc.address) {
      hilog.info(DOMAIN, TAG, 'live address of %{public}s is %{public}s', pc.name, live);
      this.connectTo(live);
    }

    // The paired address is tried as well, with both address types: the
    // stack may only know the peer under one of them.
    this.connectToWithType(pc.address, common.BluetoothAddressType.REAL);
    this.connectToWithType(pc.address, common.BluetoothAddressType.VIRTUAL);
    return true;
  }

  /**
   * Scan the neighbourhood and return everything that shows up.  A computer
   * that is not paired yet can be found here as well.
   */
  scanPeers(timeoutMs: number): Promise<PeerInfo[]> {
    return new Promise<PeerInfo[]>((resolve) => {
      const found: PeerInfo[] = [];
      let done: boolean = false;
      const finish = () => {
        if (done) {
          return;
        }
        done = true;
        try {
          connection.stopBluetoothDiscovery();
          connection.off('discoveryResult', onFound);
        } catch (e) {
          hilog.warn(DOMAIN, TAG, 'stop scan failed: %{public}s', (e as BusinessError).message);
        }
        resolve(found);
      };

      const onFound = (results: Array<connection.DiscoveryResult>) => {
        for (const r of results) {
          const isComputer: boolean = !!r.deviceClass
            && r.deviceClass.majorClass === constant.MajorClass.MAJOR_COMPUTER;
          hilog.info(DOMAIN, TAG, 'found %{public}s %{public}s computer %{public}s',
            r.deviceId, r.deviceName, isComputer ? 'yes' : 'no');
          let known = false;
          for (const f of found) {
            if (f.address === r.deviceId) {
              known = true;
              break;
            }
          }
          if (!known) {
            found.push({
              address: r.deviceId,
              name: r.deviceName,
              isComputer: isComputer,
              paired: false
            });
          }
        }
      };

      try {
        connection.on('discoveryResult', onFound);
        connection.startBluetoothDiscovery();
      } catch (e) {
        hilog.error(DOMAIN, TAG, 'scan failed: %{public}s', (e as BusinessError).message);
        finish();
        return;
      }
      setTimeout(() => {
        finish();
      }, timeoutMs);
    });
  }

  /**
   * Look for the computer in the Bluetooth scan and return the address it
   * is advertising right now.  An empty string means it was not found.
   */
  scanForHost(name: string, timeoutMs: number): Promise<string> {
    return new Promise<string>((resolve) => {
      let done: boolean = false;
      // The computer with the right name wins; only if there is none, any
      // device that says it is a computer is taken.
      let byName: string = '';
      let byClass: string = '';

      const finish = () => {
        if (done) {
          return;
        }
        done = true;
        try {
          connection.stopBluetoothDiscovery();
          connection.off('discoveryResult', onFound);
        } catch (e) {
          hilog.warn(DOMAIN, TAG, 'stop scan failed: %{public}s', (e as BusinessError).message);
        }
        resolve(byName.length > 0 ? byName : byClass);
      };

      const onFound = (results: Array<connection.DiscoveryResult>) => {
        for (const r of results) {
          const isComputer: boolean = !!r.deviceClass
            && r.deviceClass.majorClass === constant.MajorClass.MAJOR_COMPUTER;
          hilog.info(DOMAIN, TAG, 'found %{public}s %{public}s computer %{public}s',
            r.deviceId, r.deviceName, isComputer ? 'yes' : 'no');
          if (name.length > 0 && r.deviceName === name) {
            byName = r.deviceId;
          } else if (isComputer && byClass.length === 0) {
            byClass = r.deviceId;
          }
        }
      };

      try {
        connection.on('discoveryResult', onFound);
        connection.startBluetoothDiscovery();
      } catch (e) {
        hilog.error(DOMAIN, TAG, 'scan failed: %{public}s', (e as BusinessError).message);
        finish();
        return;
      }
      setTimeout(() => {
        finish();
      }, timeoutMs);
    });
  }

  /** Every device the phone is paired with. */
  listPeers(): PeerInfo[] {
    const out: PeerInfo[] = [];
    let paired: Array<string> = [];
    try {
      paired = connection.getPairedDevices();
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'getPairedDevices failed: %{public}s', (e as BusinessError).message);
      return out;
    }

    hilog.info(DOMAIN, TAG, 'bluetooth state %{public}d, %{public}d paired device(s)',
      bluetoothManager.getState(), paired.length);

    for (let i = 0; i < paired.length; i++) {
      const address: string = paired[i];
      let name: string = '';
      try {
        name = connection.getRemoteDeviceName(address);
      } catch (e) {
        hilog.warn(DOMAIN, TAG, 'no name for %{public}s', address);
      }
      hilog.info(DOMAIN, TAG, 'paired [%{public}s] %{public}s', address, name);
      out.push({ address: address, name: name, isComputer: this.isComputer(address), paired: true });
    }
    return out;
  }

  /**
   * The Bluetooth class of device says what a device is.  A computer
   * announces MAJOR_COMPUTER, a speaker or a headset MAJOR_AUDIO_VIDEO and
   * a phone MAJOR_PHONE - which is a lot more reliable than the name.
   */
  private isComputer(address: string): boolean {
    try {
      const cls = connection.getRemoteDeviceClass(address);
      const isPc: boolean = cls.majorClass === constant.MajorClass.MAJOR_COMPUTER;
      hilog.info(DOMAIN, TAG, 'device %{public}s major class %{public}d -> computer %{public}s',
        address, cls.majorClass, isPc ? 'yes' : 'no');
      return isPc;
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'getRemoteDeviceClass failed for %{public}s', address);
      return false;
    }
  }

  /** The paired device that looks most like a computer. */
  pickHost(peers: PeerInfo[]): PeerInfo | undefined {
    // The class of device comes first, the name is only a fallback.
    for (const p of peers) {
      if (p.isComputer) {
        return p;
      }
    }
    for (const p of peers) {
      if (this.looksLikePc(p.name)) {
        return p;
      }
    }
    return undefined;
  }

  private looksLikePc(name: string): boolean {
    const lower: string = name.toLowerCase();
    return lower.indexOf('pc') >= 0
      || lower.indexOf('desktop') >= 0
      || lower.indexOf('laptop') >= 0
      || lower.indexOf('macbook') >= 0
      || lower.indexOf('surface') >= 0
      || lower.indexOf('thinkpad') >= 0
      || lower.indexOf('computer') >= 0
      || lower.indexOf('工作站') >= 0
      // Windows names the machine after the computer name: WIN-XXXX, DESKTOP-XXXX
      || lower.startsWith('win-')
      || lower.startsWith('win_');
  }

  /** Open the HID channel to one specific device. */
  connectTo(address: string): boolean {
    return this.connectToWithType(address, common.BluetoothAddressType.REAL);
  }

  /**
   * Open the HID channel with an explicit address type.  The paired list
   * hands out the private address of a peer; depending on how the peer
   * rotates its address, the stack may only find it under one of them.
   */
  connectToWithType(address: string, type: common.BluetoothAddressType): boolean {
    if (!this.profile || !this.registered) {
      return false;
    }
    const target: common.BluetoothAddress = {
      address: address,
      addressType: type
    };
    try {
      this.profile.connect(target);
      // The profile is connected asynchronously; from here on reports are
      // worth trying, the stack drops them until the link is up.
      this.connected = true;
      this.peer = connection.getRemoteDeviceName(address);
      hilog.info(DOMAIN, TAG, 'connecting to %{public}s (%{public}s) type %{public}d',
        this.peer, address, type);
      // An empty keyboard report kicks the connection: it is repeated
      // until the host answers, which is also how we learn that the
      // link is really up.
      this.sendKeyboard();
      return true;
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'connect failed: %{public}s', (e as BusinessError).message);
      return false;
    }
  }

  /**
   * Pair with a device that is not paired yet.  A computer that is not in
   * the paired list can still be used: it has to show up in a scan first.
   */
  async pairWith(address: string): Promise<boolean> {
    return new Promise<boolean>((resolve) => {
      try {
        connection.pairDevice(address);
        hilog.info(DOMAIN, TAG, 'pairing with %{public}s', address);
        resolve(true);
      } catch (e) {
        hilog.error(DOMAIN, TAG, 'pairDevice failed: %{public}s', (e as BusinessError).message);
        resolve(false);
      }
    });
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
      this.linkUp = false;
    });
    // The state of the profile connection is the only reliable answer to
    // "did it work?".
    this.profile.on('connectionStateChange', (param: baseProfile.StateChangeParam) => {
      hilog.info(DOMAIN, TAG, 'connection state %{public}d for %{public}s cause %{public}d',
        param.state, param.deviceId, param.cause);
      if (param.state === constant.ProfileConnectionState.STATE_CONNECTED) {
        this.connected = true;
        this.linkUp = true;
      } else if (param.state === constant.ProfileConnectionState.STATE_DISCONNECTED) {
        this.connected = false;
        this.linkUp = false;
      }
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
    if (!this.profile || !this.registered) {
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
    if (!this.profile || !this.registered) {
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
      if (!this.linkUp) {
        this.linkUp = true;
        hilog.info(DOMAIN, TAG, 'link is up');
      }
      this.retries = 0;
    } catch (e) {
      const err = e as BusinessError;
      // 2903053: the link is not up yet.  The profile connects in the
      // background, so the first reports have to be repeated.
      if (err.code === 2903053) {
        this.linkUp = false;
        this.retry(reportId, bytes);
        return;
      }
      hilog.error(DOMAIN, TAG, 'sendReport %{public}d failed: %{public}s',
        reportId, err.message);
    }
  }

  /** Repeat a report until the link is up. */
  private retry(reportId: number, bytes: number[]): void {
    if (this.retries >= 20) {
      hilog.error(DOMAIN, TAG, 'link never came up');
      return;
    }
    ++this.retries;
    setTimeout(() => {
      this.send(reportId, bytes);
    }, 300);
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
