import { abilityAccessCtrl, Context, PermissionRequestResult, Permissions } from '@kit.AbilityKit';

const MICROPHONE_PERMISSION: Permissions = 'ohos.permission.MICROPHONE';

export enum MicrophonePermissionStatus {
  GRANTED = 'granted',
  DENIED = 'denied'
}

export interface PermissionRequester {
  requestMicrophone(): Promise<MicrophonePermissionStatus>;
}

export class SystemPermissionRequester implements PermissionRequester {
  private context: Context;

  constructor(context: Context) {
    this.context = context;
  }

  async requestMicrophone(): Promise<MicrophonePermissionStatus> {
    try {
      const manager = abilityAccessCtrl.createAtManager();
      const result: PermissionRequestResult = await manager.requestPermissionsFromUser(
        this.context, [MICROPHONE_PERMISSION]
      );
      if (result.authResults.length === 1 &&
        result.authResults[0] === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED) {
        return MicrophonePermissionStatus.GRANTED;
      }
    } catch (_) {
    }
    return MicrophonePermissionStatus.DENIED;
  }
}

export class MicrophonePermissionService {
  private requester: PermissionRequester;

  constructor(requester: PermissionRequester) {
    this.requester = requester;
  }

  requestForKaraokeStart(): Promise<MicrophonePermissionStatus> {
    return this.requester.requestMicrophone();
  }
}

let systemService: MicrophonePermissionService | undefined = undefined;

export function configureMicrophonePermissionContext(context: Context): void {
  systemService = new MicrophonePermissionService(new SystemPermissionRequester(context));
}

export function clearMicrophonePermissionContext(): void {
  systemService = undefined;
}

export function getMicrophonePermissionService(): MicrophonePermissionService {
  if (systemService === undefined) {
    throw new Error('Microphone permission context has not been configured');
  }
  return systemService;
}
