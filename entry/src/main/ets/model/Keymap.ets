/*
 * Keymap - the keys the on-screen keyboard offers.
 *
 * Every key names the HID usage it sends.  A key that has a different
 * character when Shift is held carries that character in `shifted`; the
 * Shift modifier is then added to the report automatically.
 */

// Modifier bits of the keyboard report.
export const MOD_CTRL: number = 0x01;
export const MOD_SHIFT: number = 0x02;
export const MOD_ALT: number = 0x04;
export const MOD_GUI: number = 0x08;

// HID usage codes of the keyboard page.
export const KEY_ESC: number = 0x29;
export const KEY_ENTER: number = 0x28;
export const KEY_BACKSPACE: number = 0x2A;
export const KEY_TAB: number = 0x2B;
export const KEY_SPACE: number = 0x2C;
export const KEY_CAPS: number = 0x39;
export const KEY_SHIFT: number = 0xE1;
export const KEY_CTRL: number = 0xE0;
export const KEY_ALT: number = 0xE2;
export const KEY_GUI: number = 0xE3;
export const KEY_LEFT: number = 0x50;
export const KEY_RIGHT: number = 0x4F;
export const KEY_DOWN: number = 0x51;
export const KEY_UP: number = 0x52;

// Consumer page usages (report 3).
export const CONS_VOLUME_UP: number = 0xE9;
export const CONS_VOLUME_DOWN: number = 0xEA;
export const CONS_MUTE: number = 0xE2;
export const CONS_PLAY_PAUSE: number = 0xCD;
export const CONS_STOP: number = 0xB7;
export const CONS_NEXT: number = 0xB5;
export const CONS_PREV: number = 0xB8;

/** HID usage codes used by the shortcuts. */
export const KEY_C: number = 0x06;
export const KEY_V: number = 0x19;
export const KEY_X: number = 0x1B;
export const KEY_A: number = 0x04;
export const KEY_Z: number = 0x1A;
export const KEY_L: number = 0x0E;

export interface KeyDef {
  /** What is printed on the key. */
  label: string;
  /** HID usage code, or 0 for a key that only changes the modifier state. */
  usage: number;
  /** The character the key produces with Shift held. */
  shifted: string;
  /** How many key widths the key takes. */
  wide: number;
  /** True when the key latches a modifier instead of sending a key. */
  latch: boolean;
  /** True when the usage belongs to the consumer page instead of the
   *  keyboard page - those go into report 3, not report 1. */
  consumer: boolean;
  /** Modifier bits that are held while the key is pressed (a shortcut). */
  mods: number;
}

function key(label: string, usage: number, shifted: string = '', wide: number = 1): KeyDef {
  return {
    label: label, usage: usage, shifted: shifted,
    wide: wide, latch: false, consumer: false, mods: 0
  };
}

function mod(label: string, usage: number, wide: number = 1): KeyDef {
  return {
    label: label, usage: usage, shifted: '',
    wide: wide, latch: true, consumer: false, mods: 0
  };
}

function cons(label: string, usage: number): KeyDef {
  return {
    label: label, usage: usage, shifted: '',
    wide: 1, latch: false, consumer: true, mods: 0
  };
}

/** A shortcut: a modifier held while one key is pressed. */
function chord(label: string, mods: number, usage: number): KeyDef {
  return {
    label: label, usage: usage, shifted: '',
    wide: 1, latch: false, consumer: false, mods: mods
  };
}

/**
 * The left half of the keyboard.  The split runs down the middle of a
 * normal QWERTY board, so the left hand keeps the letters it knows.
 */
export function leftRows(): KeyDef[][] {
  return [
    [
      key('Esc', KEY_ESC), key('`', 0x35, '~'), key('1', 0x1E, '!'), key('2', 0x1F, '@'),
      key('3', 0x20, '#'), key('4', 0x21, '$'), key('5', 0x22, '%'), key('6', 0x23, '^')
    ],
    [
      key('Tab', KEY_TAB, '', 1.5), key('q', 0x14, 'Q'), key('w', 0x1A, 'W'),
      key('e', 0x08, 'E'), key('r', 0x15, 'R'), key('t', 0x17, 'T')
    ],
    [
      key('Caps', KEY_CAPS, '', 1.5), key('a', 0x04, 'A'), key('s', 0x16, 'S'),
      key('d', 0x07, 'D'), key('f', 0x09, 'F'), key('g', 0x0A, 'G')
    ],
    [
      key('Shift', KEY_SHIFT, '', 1.5), key('z', 0x1D, 'Z'), key('x', 0x1B, 'X'),
      key('c', 0x06, 'C'), key('v', 0x19, 'V'), key('b', 0x05, 'B')
    ],
    [
      mod('Ctrl', KEY_CTRL), mod('Win', KEY_GUI), mod('Alt', KEY_ALT)
    ]
  ];
}

/** The right half, mirrored. */
export function rightRows(): KeyDef[][] {
  return [
    [
      key('7', 0x24, '&'), key('8', 0x25, '*'), key('9', 0x26, '('),
      key('0', 0x27, ')'), key('-', 0x2D, '_'), key('=', 0x2E, '+'),
      key('⌫', KEY_BACKSPACE, '', 1.5)
    ],
    [
      key('y', 0x1C, 'Y'), key('u', 0x18, 'U'), key('i', 0x0C, 'I'),
      key('o', 0x12, 'O'), key('p', 0x13, 'P'), key('[', 0x2F, '{'),
      key(']', 0x30, '}')
    ],
    [
      key('h', 0x0B, 'H'), key('j', 0x0D, 'J'), key('k', 0x0E, 'K'),
      key('l', 0x0F, 'L'), key(';', 0x33, ':'), key("'", 0x34, '"'),
      key('⏎', KEY_ENTER, '', 1.5)
    ],
    [
      key('n', 0x11, 'N'), key('m', 0x10, 'M'), key(',', 0x36, '<'),
      key('.', 0x37, '>'), key('/', 0x38, '?'), key('\\', 0x31, '|'),
      key('↑', KEY_UP, '', 1)
    ],
    [
      key('Space', KEY_SPACE, '', 2.5), mod('Alt', KEY_ALT),
      key('←', KEY_LEFT), key('↓', KEY_DOWN), key('→', KEY_RIGHT)
    ]
  ];
}

/** The extra keys below the keyboard: sound, presentation and the like. */
export function extraKeys(): KeyDef[] {
  return [
    cons('🔊+', CONS_VOLUME_UP),
    cons('🔉-', CONS_VOLUME_DOWN),
    cons('🔇', CONS_MUTE),
    cons('⏯', CONS_PLAY_PAUSE),
    cons('⏭', CONS_NEXT),
    cons('⏮', CONS_PREV),
    key('F5', 0x3F),
    key('F12', 0x45)
  ];
}

/**
 * The shortcuts that are needed all the time: the editing keys, switching
 * windows and locking the screen.
 */
export function shortcutKeys(): KeyDef[] {
  return [
    chord('复制', MOD_CTRL, KEY_C),
    chord('粘贴', MOD_CTRL, KEY_V),
    chord('剪切', MOD_CTRL, KEY_X),
    chord('全选', MOD_CTRL, KEY_A),
    chord('撤销', MOD_CTRL | MOD_SHIFT, KEY_Z),
    chord('切换', MOD_ALT, KEY_TAB),
    chord('任务', MOD_CTRL | MOD_SHIFT, KEY_ESC),
    chord('锁屏', MOD_GUI, KEY_L)
  ];
}
