import { AbilityConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';

import { hidDevice } from '../model/Global';

const DOMAIN: number = 0x3200;
const TAG: string = 'HBK';

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(DOMAIN, TAG, 'onCreate');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, TAG, 'loadContent failed: %{public}s', err.message);
        return;
      }
      hilog.info(DOMAIN, TAG, 'content loaded');
      this.goFullScreen(windowStage);
    });
  }

  /**
   * The app is a keyboard and a mouse: every pixel of the screen belongs
   * to them, so the status bar and the navigation bar are hidden and the
   * layout goes all the way to the edges.
   */
  private goFullScreen(windowStage: window.WindowStage): void {
    windowStage.getMainWindow().then((mainWindow: window.Window) => {
      mainWindow.setWindowLayoutFullScreen(true).then(() => {
        hilog.info(DOMAIN, TAG, 'full screen layout');
      }).catch(() => {
        hilog.error(DOMAIN, TAG, 'setWindowLayoutFullScreen failed');
      });
      mainWindow.setWindowSystemBarEnable([]).then(() => {
        hilog.info(DOMAIN, TAG, 'system bars hidden');
      }).catch(() => {
        hilog.error(DOMAIN, TAG, 'setWindowSystemBarEnable failed');
      });
    }).catch(() => {
      hilog.error(DOMAIN, TAG, 'getMainWindow failed');
    });
  }

  onForeground(): void {
    // The system cancels the HID registration as soon as the app leaves the
    // foreground, so the link has to be opened again every time.
    hilog.info(DOMAIN, TAG, 'onForeground');
  }

  onBackground(): void {
    hilog.info(DOMAIN, TAG, 'onBackground');
    // Let go of every key that is still down, or the PC keeps it latched.
    hidDevice.releaseAll();
  }

  onWindowStageDestroy(): void {
    hidDevice.unregister();
  }
}
