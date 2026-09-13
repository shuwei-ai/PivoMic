export enum AudioOutputRoute {
  SPEAKER = 'speaker',
  WIRED = 'wired',
  USB = 'usb',
  BLUETOOTH_LOW_LATENCY = 'bluetooth-low-latency',
  BLUETOOTH_UNVERIFIED = 'bluetooth-unverified',
  UNKNOWN = 'unknown'
}

export interface MonitoringSafetyInput {
  aecSupported: boolean;
  safeOutputConnected: boolean;
  outputRoute?: AudioOutputRoute;
}

export interface MonitoringSafetyDecision {
  allowed: boolean;
  reason: string;
}

export function isHeadsetRoute(route: AudioOutputRoute): boolean {
  return route === AudioOutputRoute.WIRED ||
    route === AudioOutputRoute.USB ||
    route === AudioOutputRoute.BLUETOOTH_LOW_LATENCY ||
    route === AudioOutputRoute.BLUETOOTH_UNVERIFIED;
}

export function isVerifiedSafeOutput(route: AudioOutputRoute): boolean {
  return isHeadsetRoute(route);
}

export function classifyPreferredOutput(routes: AudioOutputRoute[]): AudioOutputRoute {
  if (routes.length !== 1) return AudioOutputRoute.UNKNOWN;
  return routes[0];
}

export function canStartMonitoring(input: MonitoringSafetyInput): MonitoringSafetyDecision {
  const route = input.outputRoute ?? AudioOutputRoute.UNKNOWN;
  if (route === AudioOutputRoute.UNKNOWN) {
    return {
      allowed: false,
      reason: '无法确认当前音频输出设备，请检查音频连接后重试'
    };
  }
  return { allowed: true, reason: '' };
}
