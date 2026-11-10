/*
 * HidDescriptor - the HID report descriptor of the device.
 *
 * QNX gave the BB10 build a fixed descriptor baked into the Bluetooth stack.
 * Here the descriptor is ours, so the report layout is exactly what the
 * reports in HidDevice.ets assume:
 *
 *   Report 1  keyboard   8 bytes: modifiers, reserved, six key codes
 *   Report 2  mouse      5 bytes: buttons, dx, dy, wheel, horizontal pan
 *   Report 3  consumer   8 bytes: four 16-bit consumer-page usages
 *
 * The keyboard report also carries the LED output report (caps lock, num
 * lock and friends) so that the host can tell us about its lock state.
 */
export class HidDescriptor {
  static readonly REPORT_KEYBOARD: number = 1;
  static readonly REPORT_MOUSE: number = 2;
  static readonly REPORT_CONSUMER: number = 3;

  static build(): Uint8Array {
    const d: number[] = [
      // ---------------------------------------------------------- keyboard
      0x05, 0x01,        // Usage Page (Generic Desktop)
      0x09, 0x06,        // Usage (Keyboard)
      0xA1, 0x01,        // Collection (Application)
      0x85, 0x01,        //   Report ID (1)
      0x05, 0x07,        //   Usage Page (Key Codes)
      0x19, 0xE0,        //   Usage Minimum (224)
      0x29, 0xE7,        //   Usage Maximum (231)
      0x15, 0x00,        //   Logical Minimum (0)
      0x25, 0x01,        //   Logical Maximum (1)
      0x75, 0x01,        //   Report Size (1)
      0x95, 0x08,        //   Report Count (8)
      0x81, 0x02,        //   Input (Data, Variable, Absolute)   modifiers
      0x95, 0x01,        //   Report Count (1)
      0x75, 0x08,        //   Report Size (8)
      0x81, 0x03,        //   Input (Constant)                   reserved
      0x95, 0x05,        //   Report Count (5)
      0x75, 0x01,        //   Report Size (1)
      0x05, 0x08,        //   Usage Page (LEDs)
      0x19, 0x01,        //   Usage Minimum (1)
      0x29, 0x05,        //   Usage Maximum (5)
      0x91, 0x02,        //   Output (Data, Variable, Absolute)  LEDs
      0x95, 0x01,        //   Report Count (1)
      0x75, 0x03,        //   Report Size (3)
      0x91, 0x03,        //   Output (Constant)                  padding
      0x95, 0x06,        //   Report Count (6)
      0x75, 0x08,        //   Report Size (8)
      0x15, 0x00,        //   Logical Minimum (0)
      0x25, 0xFF,        //   Logical Maximum (255)
      0x05, 0x07,        //   Usage Page (Key Codes)
      0x19, 0x00,        //   Usage Minimum (0)
      0x29, 0xFF,        //   Usage Maximum (255)
      0x81, 0x00,        //   Input (Data, Array)                key codes
      0xC0,              // End Collection

      // ------------------------------------------------------------- mouse
      0x05, 0x01,        // Usage Page (Generic Desktop)
      0x09, 0x02,        // Usage (Mouse)
      0xA1, 0x01,        // Collection (Application)
      0x85, 0x02,        //   Report ID (2)
      0x09, 0x01,        //   Usage (Pointer)
      0xA1, 0x00,        //   Collection (Physical)
      0x05, 0x09,        //     Usage Page (Button)
      0x19, 0x01,        //     Usage Minimum (1)
      0x29, 0x05,        //     Usage Maximum (5)
      0x15, 0x00,        //     Logical Minimum (0)
      0x25, 0x01,        //     Logical Maximum (1)
      0x95, 0x05,        //     Report Count (5)
      0x75, 0x01,        //     Report Size (1)
      0x81, 0x02,        //     Input (Data, Variable, Absolute)  buttons
      0x95, 0x01,        //     Report Count (1)
      0x75, 0x03,        //     Report Size (3)
      0x81, 0x01,        //     Input (Constant)                   padding
      0x05, 0x01,        //     Usage Page (Generic Desktop)
      0x09, 0x30,        //     Usage (X)
      0x09, 0x31,        //     Usage (Y)
      0x09, 0x38,        //     Usage (Wheel)
      0x15, 0x81,        //     Logical Minimum (-127)
      0x25, 0x7F,        //     Logical Maximum (127)
      0x75, 0x08,        //     Report Size (8)
      0x95, 0x03,        //     Report Count (3)
      0x81, 0x06,        //     Input (Data, Variable, Relative)  x, y, wheel
      0x05, 0x0C,        //     Usage Page (Consumer Devices)
      0x0A, 0x38, 0x02,  //     Usage (AC Pan)
      0x15, 0x81,        //     Logical Minimum (-127)
      0x25, 0x7F,        //     Logical Maximum (127)
      0x75, 0x08,        //     Report Size (8)
      0x95, 0x01,        //     Report Count (1)
      0x81, 0x06,        //     Input (Data, Variable, Relative)  horizontal
      0xC0,              //   End Collection
      0xC0,              // End Collection

      // ---------------------------------------------------------- consumer
      0x05, 0x0C,        // Usage Page (Consumer)
      0x09, 0x01,        // Usage (Consumer Control)
      0xA1, 0x01,        // Collection (Application)
      0x85, 0x03,        //   Report ID (3)
      0x15, 0x00,        //   Logical Minimum (0)
      0x26, 0xFF, 0x03,  //   Logical Maximum (1023)
      0x19, 0x00,        //   Usage Minimum (0)
      0x2A, 0xFF, 0x03,  //   Usage Maximum (1023)
      0x75, 0x10,        //   Report Size (16)
      0x95, 0x04,        //   Report Count (4)
      0x81, 0x00,        //   Input (Data, Array)
      0xC0               // End Collection
    ];
    return new Uint8Array(d);
  }
}
