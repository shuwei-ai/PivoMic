import { AbilityConstant, Configuration, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window, display, KeyboardAvoidMode } from '@kit.ArkUI';
import { deviceInfo } from '@kit.BasicServicesKit';
import {
  clearMicrophonePermissionContext,
  configureMicrophonePermissionContext
} from '../audio/MicrophonePermissionService';
import { BackgroundTaskService } from '../audio/BackgroundTaskService';
import { systemAppLifecycleEvents } from '../store/AppLifecycleEvents';

const DOMAIN = 0x0000;
const TAG = 'EntryAbility';

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    configureMicrophonePermissionContext(this.context);
    AppStorage.setOrCreate('keyboardHeightPx', 0);
    BackgroundTaskService.getInstance().setContext(this.context);
    try {
      this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'Failed to set colorMode. Cause: %{public}s', JSON.stringify(err));
    }
    hilog.info(DOMAIN, TAG, '[PivoDiag] Ability onCreate | want: %{public}s, launchParam: %{public}s',
      JSON.stringify(want), JSON.stringify(launchParam));
  }

  onDestroy(): void {
    systemAppLifecycleEvents.publishDestroy();
    clearMicrophonePermissionContext();
    BackgroundTaskService.getInstance().stopContinuousAudioTask(this.context);
    BackgroundTaskService.getInstance().releaseSession();
    hilog.info(DOMAIN, TAG, '%{public}s', 'Ability onDestroy');
  }

  private windowObj?: window.Window;

  private syncOrientationForDisplay(windowClass?: window.Window): void {
    if (!windowClass) return;
    try {
      const props = windowClass.getWindowProperties();
      hilog.info(DOMAIN, TAG, '[PivoDiag] WindowProps | id: %{public}d, rect: %{public}s, type: %{public}d, isFullScreen: %{public}s, isLayoutFullScreen: %{public}s',
        props.id, JSON.stringify(props.windowRect), props.type, `${props.isFullScreen}`, `${props.isLayoutFullScreen}`);

      // Log all displays
      try {
        const defaultDisplay = display.getDefaultDisplaySync();
        hilog.info(DOMAIN, TAG, '[PivoDiag] DefaultDisplay | id: %{public}d, name: %{public}s, width: %{public}d, height: %{public}d, dpi: %{public}d, orientation: %{public}d, rotation: %{public}d',
          defaultDisplay.id, defaultDisplay.name, defaultDisplay.width, defaultDisplay.height, defaultDisplay.densityDPI, defaultDisplay.orientation, defaultDisplay.rotation);
      } catch (err) {
        hilog.warn(DOMAIN, TAG, '[PivoDiag] getDefaultDisplaySync failed');
      }

      // Log avoid areas
      try {
        const sysAvoid = windowClass.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
        const cutoutAvoid = windowClass.getWindowAvoidArea(window.AvoidAreaType.TYPE_CUTOUT);
        const navAvoid = windowClass.getWindowAvoidArea(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR);
        hilog.info(DOMAIN, TAG, '[PivoDiag] AvoidAreas | system: %{public}s, cutout: %{public}s, nav: %{public}s',
          JSON.stringify(sysAvoid), JSON.stringify(cutoutAvoid), JSON.stringify(navAvoid));
      } catch (_) {}

      // 1. Adaptive Orientation:
      // Priority 1: Phone app cast/distributed to external display (TV, projector)
      //   → displayId != 0 always means external display in HarmonyOS distributed mode
      //   → Force LANDSCAPE so the window rotates to fill the TV screen
      // Priority 2: deviceType-specific defaults for native devices
      // Priority 3: Aspect-ratio fallback for tablets/foldables
      let isPhonePortrait = (deviceInfo.deviceType === 'phone');
      let targetOrientation: window.Orientation = window.Orientation.AUTO_ROTATION_UNSPECIFIED;

      // Check if running on external display (phone cast to TV)
      let isExternalDisplay = false;
      try {
        const currentDisplay = display.getDefaultDisplaySync();
        if (currentDisplay && currentDisplay.id !== 0) {
          isExternalDisplay = true;
          isPhonePortrait = false;
          targetOrientation = window.Orientation.LANDSCAPE;
          hilog.info(DOMAIN, TAG, '[PivoDiag] External display detected (id=%{public}d) → LANDSCAPE', currentDisplay.id);
        }
      } catch (_e) {}

      if (!isExternalDisplay) {
        if (deviceInfo.deviceType === 'phone') {
          isPhonePortrait = true;
          targetOrientation = window.Orientation.PORTRAIT;
        } else if (deviceInfo.deviceType === 'tv' || deviceInfo.deviceType === '2in1') {
          isPhonePortrait = false;
          targetOrientation = window.Orientation.LANDSCAPE;
        } else {
          try {
            const defaultDisplay = display.getDefaultDisplaySync();
            if (defaultDisplay && defaultDisplay.width > 0 && defaultDisplay.height > 0) {
              if (defaultDisplay.width > defaultDisplay.height) {
                isPhonePortrait = false;
                targetOrientation = window.Orientation.AUTO_ROTATION_LANDSCAPE_RESTRICTED;
              } else {
                isPhonePortrait = true;
                targetOrientation = window.Orientation.AUTO_ROTATION_PORTRAIT_RESTRICTED;
              }
            }
          } catch (_) {
            targetOrientation = window.Orientation.AUTO_ROTATION_UNSPECIFIED;
          }
        }
      }

      windowClass.setPreferredOrientation(targetOrientation).then(() => {
        hilog.info(DOMAIN, TAG, '[PivoDiag] setPreferredOrientation(%{public}d) succeeded for deviceType=%{public}s',
          targetOrientation, deviceInfo.deviceType);
      }).catch((err: Error) => {
        hilog.error(DOMAIN, TAG, '[PivoDiag] setPreferredOrientation failed: %{public}s', err.message);
      });

      // 2. Window Layout & System Bars:
      // Edge-to-edge immersion with transparent system bars (prevents letterboxing / white bars)
      windowClass.setWindowLayoutFullScreen(true).then(() => {
        hilog.info(DOMAIN, TAG, '[PivoDiag] setWindowLayoutFullScreen(true) succeeded');
      }).catch((err: Error) => {
        hilog.warn(DOMAIN, TAG, '[PivoDiag] setWindowLayoutFullScreen(true) failed: %{public}s', err.message);
      });

      if (isPhonePortrait) {
        // Phone: Keep status bar and navigation bar enabled and fully transparent
        windowClass.setWindowSystemBarEnable(['status', 'navigation']).then(() => {
          hilog.info(DOMAIN, TAG, '[PivoDiag] setWindowSystemBarEnable([status, navigation]) succeeded');
        }).catch((err: Error) => {
          hilog.warn(DOMAIN, TAG, '[PivoDiag] setWindowSystemBarEnable failed: %{public}s', err.message);
        });
      } else {
        // TV / Landscape / External display: Fullscreen immersion
        windowClass.setWindowSystemBarEnable([]).then(() => {
          hilog.info(DOMAIN, TAG, '[PivoDiag] setWindowSystemBarEnable([]) for widescreen succeeded');
        }).catch((err: Error) => {
          hilog.warn(DOMAIN, TAG, '[PivoDiag] setWindowSystemBarEnable failed: %{public}s', err.message);
        });
      }

      windowClass.setWindowSystemBarProperties({
        statusBarColor: '#00000000',
        navigationBarColor: '#00000000',
        statusBarContentColor: '#FFFFFF',
        navigationBarContentColor: '#FFFFFF'
      }).catch(() => {});
    } catch (e) {
      hilog.error(DOMAIN, TAG, '[PivoDiag] syncOrientationForDisplay exception: %{public}s', JSON.stringify(e));
    }
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    hilog.info(DOMAIN, TAG, '[PivoDiag] onWindowStageCreate | deviceType: %{public}s, marketName: %{public}s, osFullName: %{public}s',
      deviceInfo.deviceType, deviceInfo.marketName, deviceInfo.osFullName);

    windowStage.getMainWindow().then((windowClass) => {
      this.windowObj = windowClass;
      const initialProps = windowClass.getWindowProperties();
      hilog.info(DOMAIN, TAG, '[PivoDiag] MainWindow acquired: id=%{public}d, rect=%{public}s',
        initialProps.id, JSON.stringify(initialProps.windowRect));
      try {
        windowClass.setWindowFocusable(true);
        try {
          windowClass.getUIContext().setKeyboardAvoidMode(KeyboardAvoidMode.RESIZE);
        } catch (_) {}
        try {
          windowClass.on('keyboardHeightChange', (data: number) => {
            AppStorage.setOrCreate('keyboardHeightPx', data);
            hilog.info(DOMAIN, TAG, '[PivoDiag] keyboardHeightChange: %{public}d px', data);
          });
        } catch (_) {}
        // Keep screen always on to prevent sleep/screen-off during singing and music playback
        windowClass.setWindowKeepScreenOn(true).then(() => {
          hilog.info(DOMAIN, TAG, '[PivoDiag] setWindowKeepScreenOn(true) succeeded');
        }).catch((err: Error) => {
          hilog.warn(DOMAIN, TAG, '[PivoDiag] setWindowKeepScreenOn failed: %{public}s', err.message);
        });
      } catch (_) {}
      this.syncOrientationForDisplay(windowClass);
    }).catch((err: Error) => {
      hilog.error(DOMAIN, TAG, '[PivoDiag] Failed to get main window. Cause: %{public}s', JSON.stringify(err));
    });

    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, TAG, '[PivoDiag] Failed to load content. Cause: %{public}s', JSON.stringify(err));
        return;
      }
      hilog.info(DOMAIN, TAG, '[PivoDiag] Succeeded in loading content.');
    });
  }

  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(DOMAIN, TAG, '%{public}s', 'Ability onNewWant');
    // Re-sync orientation when moved to a new display (e.g. phone cast to TV)
    this.syncOrientationForDisplay(this.windowObj);
  }

  onConfigurationUpdate(newConfig: Configuration): void {
    hilog.info(DOMAIN, TAG, '%{public}s', 'Ability onConfigurationUpdate');
  }

  onContinue(_wantParam: Record<string, Object>): AbilityConstant.OnContinueResult {
    hilog.info(DOMAIN, TAG, '[PivoDistributed] onContinue triggered for multi-device collaboration');
    return AbilityConstant.OnContinueResult.AGREE;
  }

  onWindowStageDestroy(): void {
    hilog.info(DOMAIN, TAG, '%{public}s', 'Ability onWindowStageDestroy');
  }

  onForeground(): void {
    systemAppLifecycleEvents.publishForeground();
    hilog.info(DOMAIN, TAG, '%{public}s', 'Ability onForeground');
  }

  onBackground(): void {
    systemAppLifecycleEvents.publishBackground();
    hilog.info(DOMAIN, TAG, '%{public}s', 'Ability onBackground');
  }
}
