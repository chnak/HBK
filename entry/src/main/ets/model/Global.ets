/*
 * Global - the one HID device the whole app talks to.
 *
 * A module-level instance keeps the state out of the component tree: the
 * keyboard, the touchpad and the status bar all need the same link and the
 * same modifier state.
 */
import { HidDevice } from './HidDevice';

export const hidDevice: HidDevice = new HidDevice();
