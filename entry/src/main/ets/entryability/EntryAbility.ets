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
