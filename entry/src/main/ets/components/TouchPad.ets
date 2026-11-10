/*
 * TouchPad - the mouse area in the middle of the screen.
 *
 * Gestures:
 *   one finger move        move the pointer
 *   one finger tap         left click
 *   one finger hold+move   drag (left button held)
 *   two finger tap         right click
 *   three finger tap       middle click
 *   two finger pinch       zoom (Ctrl + wheel)
 *   two finger sideways    horizontal scroll
 *
 * Only the differences between two positions matter, so the touch points do
 * not have to be converted into the coordinate system of this component.
 */
import { hidDevice } from '../model/Global';

const DOMAIN: number = 0x3200;
const TAG: string = 'HBK';

/** A finger that is currently on the glass. */
interface Finger {
  id: number;
  x: number;
  y: number;
  startX: number;
  startY: number;
  startTime: number;
}

/** Mouse buttons as the HID report counts them. */
const BTN_LEFT: number = 0x01;
const BTN_RIGHT: number = 0x02;
const BTN_MIDDLE: number = 0x04;

/** A tap is short and does not move. */
const TAP_MS: number = 260;
const TAP_SLOP: number = 14;
/** Holding still for this long and then moving is a drag. */
const HOLD_MS: number = 220;
/** Finger travel that makes one wheel notch. */
const ZOOM_STEP: number = 24;
/** How far two fingers have to travel sideways before it is a scroll. */
const PAN_SLOP: number = 12;

@Component
export struct TouchPad {
  /** Screen pixels per mouse count. */
  private speed: number = 0.6;

  private fingers: Finger[] = [];
  /** How many fingers were down at the same time. */
  private peak: number = 0;
  /** When the current gesture started. */
  private gestureStart: number = 0;
  /** The biggest distance any finger travelled during the gesture. */
  private gestureTravel: number = 0;
  /** The button that is held down while dragging. */
  private dragging: boolean = false;
  /** Distance between the two fingers at the last pinch step. */
  private pinchDist: number = 0;
  /** Notches that have not been sent yet. */
  private pinchAcc: number = 0;
  /** The middle of the two fingers at the last scroll step. */
  private panX: number = 0;
  private panning: boolean = false;

  build() {
    Column() {
      Text('鼠标区')
        .fontSize(12)
        .fontColor('#5c6b78')
        .margin({ top: 8 })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Start)
    .backgroundColor('#0e141a')
    .borderRadius(14)
    .border({ width: 1, color: '#1d2831' })
    .onTouch((e: TouchEvent) => {
      this.handleTouch(e);
    })
  }

  private handleTouch(e: TouchEvent): void {
    const now: number = Date.now();

    // Fingers that just went down.
    for (let i = 0; i < e.touches.length; i++) {
      const t = e.touches[i];
      if (this.findFinger(t.id) < 0) {
        this.fingers.push({
          id: t.id,
          x: t.displayX,
          y: t.displayY,
          startX: t.displayX,
          startY: t.displayY,
          startTime: now
        });
        this.peak = Math.max(this.peak, this.fingers.length);
        this.onFingerDown(now);
      }
    }

    if (e.type === TouchType.Move) {
      this.onMove(e, now);
    } else if (e.type === TouchType.Up || e.type === TouchType.Cancel) {
      this.onUp(e, now);
    }
  }

  private findFinger(id: number): number {
    for (let i = 0; i < this.fingers.length; i++) {
      if (this.fingers[i].id === id) {
        return i;
      }
    }
    return -1;
  }

  private onFingerDown(now: number): void {
    if (this.fingers.length === 1) {
      this.gestureStart = now;
      this.gestureTravel = 0;
      this.peak = 1;
      this.dragging = false;
      this.panning = false;
    } else if (this.fingers.length === 2) {
      this.pinchDist = this.twoFingerDistance();
      this.pinchAcc = 0;
      this.panX = this.twoFingerCenterX();
      this.panning = false;
    }
  }

  private onMove(e: TouchEvent, now: number): void {
    if (this.fingers.length === 0) {
      return;
    }

    let dx: number = 0;
    let dy: number = 0;
    for (let i = 0; i < e.touches.length; i++) {
      const t = e.touches[i];
      const at: number = this.findFinger(t.id);
      if (at < 0) {
        continue;
      }
      const f: Finger = this.fingers[at];
      dx += t.displayX - f.x;
      dy += t.displayY - f.y;
      f.x = t.displayX;
      f.y = t.displayY;

      const travel: number = Math.sqrt(
        (f.x - f.startX) * (f.x - f.startX) + (f.y - f.startY) * (f.y - f.startY));
      this.gestureTravel = Math.max(this.gestureTravel, travel);
    }

    if (this.fingers.length === 1) {
      // A finger that has been resting for a while and then starts moving
      // is dragging: the button goes down and stays down until release.
      if (!this.dragging
        && now - this.gestureStart > HOLD_MS
        && this.gestureTravel > TAP_SLOP) {
        this.dragging = true;
        hidDevice.mouseButton(BTN_LEFT, true);
      }
      hidDevice.mouseMove(Math.round(dx * this.speed), Math.round(dy * this.speed));
      return;
    }

    if (this.fingers.length === 2) {
      const dist: number = this.twoFingerDistance();
      const delta: number = dist - this.pinchDist;
      this.pinchDist = dist;

      // A sideways drag of both fingers is a horizontal scroll; a change of
      // distance between them is a pinch.
      const center: number = this.twoFingerCenterX();
      const moved: number = center - this.panX;

      if (this.panning) {
        const notches: number = Math.trunc(moved / PAN_SLOP);
        if (notches !== 0) {
          hidDevice.mousePan(notches);
          this.panX = center;
        }
        return;
      }

      if (Math.abs(delta) > 0 && Math.abs(delta) > Math.abs(moved)) {
        this.pinchAcc += delta;
        const notches: number = Math.trunc(this.pinchAcc / ZOOM_STEP);
        if (notches !== 0) {
          this.pinchAcc -= notches * ZOOM_STEP;
          hidDevice.mouseZoom(notches);
        }
      } else if (Math.abs(moved) > PAN_SLOP) {
        this.panning = true;
        this.panX = center;
      }
    }
  }

  private onUp(e: TouchEvent, now: number): void {
    // The finger that left is in changedTouches.
    const changed = e.changedTouches;
    for (let i = 0; i < changed.length; i++) {
      const at: number = this.findFinger(changed[i].id);
      if (at >= 0) {
        this.fingers.splice(at, 1);
      }
    }

    if (this.fingers.length > 0) {
      // Still other fingers down: the gesture continues.
      if (this.fingers.length === 1) {
        this.pinchDist = 0;
        this.panning = false;
      }
      return;
    }

    // The last finger left: the gesture is over.
    if (this.dragging) {
      hidDevice.mouseButton(BTN_LEFT, false);
      this.dragging = false;
    }

    const quick: boolean = now - this.gestureStart < TAP_MS;
    const still: boolean = this.gestureTravel < TAP_SLOP;

    if (quick && still) {
      if (this.peak === 1) {
        hidDevice.mouseButton(BTN_LEFT, true);
        hidDevice.mouseButton(BTN_LEFT, false);
      } else if (this.peak === 2) {
        hidDevice.mouseButton(BTN_RIGHT, true);
        hidDevice.mouseButton(BTN_RIGHT, false);
      } else if (this.peak >= 3) {
        hidDevice.mouseButton(BTN_MIDDLE, true);
        hidDevice.mouseButton(BTN_MIDDLE, false);
      }
    }

    this.peak = 0;
    this.gestureTravel = 0;
    this.panning = false;
    this.pinchAcc = 0;
  }

  private twoFingerDistance(): number {
    if (this.fingers.length < 2) {
      return 0;
    }
    const dx: number = this.fingers[0].x - this.fingers[1].x;
    const dy: number = this.fingers[0].y - this.fingers[1].y;
    return Math.sqrt(dx * dx + dy * dy);
  }

  private twoFingerCenterX(): number {
    if (this.fingers.length < 2) {
      return 0;
    }
    return (this.fingers[0].x + this.fingers[1].x) / 2;
  }
}
