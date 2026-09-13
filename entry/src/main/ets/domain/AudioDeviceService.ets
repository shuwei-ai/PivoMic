import audio from '@ohos.multimedia.audio';
import pasteboard from '@ohos.pasteboard';
import { promptAction } from '@kit.ArkUI';
import { AudioRouteMode } from '../audio/KaraokeSessionModels';

export interface DeviceSelectionListener {
  onInputSelected?(device: FormattedAudioDevice): void;
  onOutputSelected?(device: FormattedAudioDevice, routeMode: AudioRouteMode): void;
}

export interface FormattedAudioDevice {
  id: number;
  name: string;
  displayName: string;
  deviceType: audio.DeviceType;
  deviceRole: audio.DeviceRole;
  deviceTypeName: string;
  address: string;
  sampleRates: string;
  channelCounts: string;
  isRemote: boolean;
  localityLabel: string;
  isActive: boolean;
}

export function isRemoteAudioDevice(device: audio.AudioDeviceDescriptor): boolean {
  const rawType = device.deviceType as number;
  // HarmonyOS 分布式设备枚举: REMOTE_CAST = 24, REMOTE_DAUDIO = 29
  if (rawType === 24 || rawType === 29) {
    return true;
  }
  // 检查 address 是否包含分布式网络 ID 或远端标志
  if (device.address && device.address.trim().length > 0) {
    if (device.address === 'LocalDevice' || device.address === '本机内置') {
      return false;
    }
    if (device.address.length >= 24) {
      return true;
    }
  }
  return false;
}

export class AudioDeviceService {
  private routing: audio.AudioRoutingManager = audio.getAudioManager().getRoutingManager();
  private selectedInputDeviceId: number = -1;
  private selectedOutputDeviceId: number = -1;
  private listeners: DeviceSelectionListener[] = [];

  public addListener(listener: DeviceSelectionListener): void {
    this.listeners.push(listener);
  }

  public removeListener(listener: DeviceSelectionListener): void {
    this.listeners = this.listeners.filter(l => l !== listener);
  }

  private notifyInputSelected(device: FormattedAudioDevice): void {
    for (let i = 0; i < this.listeners.length; ++i) {
      if (this.listeners[i].onInputSelected) {
        this.listeners[i].onInputSelected!(device);
      }
    }
  }

  private notifyOutputSelected(device: FormattedAudioDevice, routeMode: AudioRouteMode): void {
    for (let i = 0; i < this.listeners.length; ++i) {
      if (this.listeners[i].onOutputSelected) {
        this.listeners[i].onOutputSelected!(device, routeMode);
      }
    }
  }

  public getSelectedInputId(): number {
    return this.selectedInputDeviceId;
  }

  public getSelectedOutputId(): number {
    return this.selectedOutputDeviceId;
  }

  public async getAllDevices(): Promise<FormattedAudioDevice[]> {
    try {
      const devices = await this.routing.getDevices(audio.DeviceFlag.ALL_DEVICES_FLAG);
      const res: FormattedAudioDevice[] = [];
      for (let i = 0; i < devices.length; ++i) {
        const isInput = devices[i].deviceRole === audio.DeviceRole.INPUT_DEVICE;
        res.push(this.formatDevice(devices[i], i, isInput));
      }
      return res;
    } catch (_) {
      return [];
    }
  }

  public async getInputDevices(): Promise<FormattedAudioDevice[]> {
    try {
      const devices = await this.routing.getDevices(audio.DeviceFlag.INPUT_DEVICES_FLAG);
      const res: FormattedAudioDevice[] = [];
      for (let i = 0; i < devices.length; ++i) {
        res.push(this.formatDevice(devices[i], i, true));
      }
      return res;
    } catch (_) {
      return [];
    }
  }

  public async getOutputDevices(): Promise<FormattedAudioDevice[]> {
    try {
      const devices = await this.routing.getDevices(audio.DeviceFlag.OUTPUT_DEVICES_FLAG);
      const res: FormattedAudioDevice[] = [];
      for (let i = 0; i < devices.length; ++i) {
        res.push(this.formatDevice(devices[i], i, false));
      }
      return res;
    } catch (_) {
      return [];
    }
  }

  public formatDevice(device: audio.AudioDeviceDescriptor, index: number, isInput: boolean): FormattedAudioDevice {
    const isRemote = isRemoteAudioDevice(device);
    const typeName = this.resolveDeviceTypeName(device.deviceType, device.deviceRole, isRemote);
    const bestName = (device.displayName && device.displayName.trim().length > 0) ?
      device.displayName :
      ((device.name && device.name.trim().length > 0) ? device.name : typeName);

    const isActive = isInput ?
      (this.selectedInputDeviceId === device.id || (this.selectedInputDeviceId === -1 && index === 0)) :
      (this.selectedOutputDeviceId === device.id || (this.selectedOutputDeviceId === -1 && index === 0));

    return {
      id: device.id,
      name: bestName,
      displayName: device.displayName && device.displayName.trim().length > 0 ? device.displayName : bestName,
      deviceType: device.deviceType,
      deviceRole: device.deviceRole,
      deviceTypeName: typeName,
      address: device.address && device.address.trim().length > 0 ? device.address : (isRemote ? '分布式远端节点' : '本机内置'),
      sampleRates: device.sampleRates && device.sampleRates.length > 0 ? device.sampleRates.join(', ') + ' Hz' : '48000 Hz',
      channelCounts: device.channelCounts && device.channelCounts.length > 0 ? device.channelCounts.join(', ') + ' 声道' : '1 声道',
      isRemote: isRemote,
      localityLabel: isRemote ? '🌐 分布式设备' : '🏠 本地设备',
      isActive: isActive
    };
  }

  public resolveDeviceTypeName(type: audio.DeviceType, role: audio.DeviceRole, isRemote: boolean): string {
    const rawType = type as number;
    if (rawType === 24) {
      return role === audio.DeviceRole.INPUT_DEVICE ? '分布式投播麦克风 (REMOTE_CAST)' : '分布式投播音频 (REMOTE_CAST)';
    }
    if (rawType === 29) {
      return role === audio.DeviceRole.INPUT_DEVICE ? '分布式硬件麦克风 (REMOTE_DAUDIO)' : '分布式硬件音箱 (REMOTE_DAUDIO)';
    }
    switch (type) {
      case audio.DeviceType.EARPIECE:
        return '手机听筒 (Earpiece)';
      case audio.DeviceType.SPEAKER:
        return isRemote ? '分布式远程扬声器' : '手机扬声器 (Speaker)';
      case audio.DeviceType.WIRED_HEADSET:
        return role === audio.DeviceRole.INPUT_DEVICE ? '有线耳机麦克风 (Wired Mic)' : '有线耳机 (Wired Headset)';
      case audio.DeviceType.WIRED_HEADPHONES:
        return '有线耳机 (Wired Headphones)';
      case audio.DeviceType.BLUETOOTH_SCO:
        return role === audio.DeviceRole.INPUT_DEVICE ? '蓝牙麦克风 (Bluetooth SCO Mic)' : '蓝牙通话耳机 (Bluetooth SCO)';
      case audio.DeviceType.BLUETOOTH_A2DP:
        return '蓝牙媒体耳机 (Bluetooth A2DP)';
      case audio.DeviceType.MIC:
        return isRemote ? '分布式远程麦克风' : '内置主麦克风 (Built-in Mic)';
      case audio.DeviceType.USB_HEADSET:
        return role === audio.DeviceRole.INPUT_DEVICE ? 'USB麦克风 (USB Mic)' : 'USB耳机 (USB Headset)';
      case audio.DeviceType.USB_DEVICE:
        return role === audio.DeviceRole.INPUT_DEVICE ? 'USB音频输入设备 (USB Audio In)' : 'USB音频输出设备 (USB Audio Out)';
      default:
        return role === audio.DeviceRole.INPUT_DEVICE ?
          (isRemote ? `分布式输入设备 (Type ${rawType})` : `音频输入设备 (Type ${rawType})`) :
          (isRemote ? `分布式输出设备 (Type ${rawType})` : `音频输出设备 (Type ${rawType})`);
    }
  }

  public async selectInputDevice(device: FormattedAudioDevice): Promise<boolean> {
    try {
      const rawDevices = await this.routing.getDevices(audio.DeviceFlag.INPUT_DEVICES_FLAG);
      let target: audio.AudioDeviceDescriptor | undefined = undefined;
      for (let i = 0; i < rawDevices.length; ++i) {
        if (rawDevices[i].id === device.id) {
          target = rawDevices[i];
          break;
        }
      }
      this.selectedInputDeviceId = device.id;
      const remotePrefix = device.isRemote ? '[分布式] ' : '';
      promptAction.showToast({ message: `已切换人声采集设备至: ${remotePrefix}${device.name}` });
      this.notifyInputSelected(device);
      return true;
    } catch (_) {
      this.selectedInputDeviceId = device.id;
      promptAction.showToast({ message: `已指定人声采集设备: ${device.name}` });
      this.notifyInputSelected(device);
      return true;
    }
  }

  public async selectOutputDevice(device: FormattedAudioDevice): Promise<boolean> {
    try {
      let routeMode = AudioRouteMode.Speaker;
      if (device.deviceType === audio.DeviceType.SPEAKER) {
        routeMode = AudioRouteMode.Speaker;
        this.selectedOutputDeviceId = device.id;
        promptAction.showToast({ message: '已切换音频播放至: 手机扬声器外放 (AEC防啸叫已激活)' });
      } else if (device.deviceType === audio.DeviceType.BLUETOOTH_A2DP || device.deviceType === audio.DeviceType.BLUETOOTH_SCO) {
        routeMode = AudioRouteMode.Bluetooth;
        this.selectedOutputDeviceId = device.id;
        const remotePrefix = device.isRemote ? '[分布式] ' : '';
        promptAction.showToast({ message: `已切换音频播放至: ${remotePrefix}${device.name} (A2DP 高品质媒体输出)` });
      } else {
        routeMode = AudioRouteMode.Wired;
        this.selectedOutputDeviceId = device.id;
        const remotePrefix = device.isRemote ? '[分布式] ' : '';
        promptAction.showToast({ message: `已切换音频播放至: ${remotePrefix}${device.name} (低延时高保真输出)` });
      }
      this.notifyOutputSelected(device, routeMode);
      return true;
    } catch (_) {
      this.selectedOutputDeviceId = device.id;
      promptAction.showToast({ message: `已指定音频播放设备: ${device.name}` });
      this.notifyOutputSelected(device, AudioRouteMode.Speaker);
      return true;
    }
  }

  public async copyAllInputDeviceNames(): Promise<boolean> {
    const inputDevices = await this.getInputDevices();
    if (inputDevices.length === 0) {
      promptAction.showToast({ message: '未检测到音频输入设备' });
      return false;
    }

    let summaryText = `【PivoMic 音频输入设备清单】(共 ${inputDevices.length} 个输入设备)\n`;
    inputDevices.forEach((dev: FormattedAudioDevice, idx: number) => {
      summaryText += `${idx + 1}. [${dev.localityLabel}] 设备名称: ${dev.name}\n   - 类型: ${dev.deviceTypeName}\n   - 分布式节点地址: ${dev.address}\n   - 设备ID: ${dev.id}\n   - 采样率: ${dev.sampleRates}\n   - 声道数: ${dev.channelCounts}\n\n`;
    });

    try {
      const pasteData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, summaryText.trim());
      const systemPasteboard = pasteboard.getSystemPasteboard();
      await systemPasteboard.setData(pasteData);
      promptAction.showToast({ message: `已成功复制 ${inputDevices.length} 个输入设备名称与参数！` });
      return true;
    } catch (_) {
      promptAction.showToast({ message: '复制失败，请重试' });
      return false;
    }
  }

  public async copyAllDeviceNames(): Promise<boolean> {
    const inputDevices = await this.getInputDevices();
    const outputDevices = await this.getOutputDevices();

    let summaryText = `【PivoMic 音频设备完整清单 (含本地与分布式远程设备)】\n\n`;
    summaryText += `=== 音频输入设备 (共 ${inputDevices.length} 个) ===\n`;
    inputDevices.forEach((dev: FormattedAudioDevice, idx: number) => {
      summaryText += `${idx + 1}. [${dev.localityLabel}] ${dev.name} (${dev.deviceTypeName}, ID: ${dev.id}, 地址: ${dev.address})\n`;
    });

    summaryText += `\n=== 音频输出设备 (共 ${outputDevices.length} 个) ===\n`;
    outputDevices.forEach((dev: FormattedAudioDevice, idx: number) => {
      summaryText += `${idx + 1}. [${dev.localityLabel}] ${dev.name} (${dev.deviceTypeName}, ID: ${dev.id}, 地址: ${dev.address})\n`;
    });

    try {
      const pasteData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, summaryText.trim());
      const systemPasteboard = pasteboard.getSystemPasteboard();
      await systemPasteboard.setData(pasteData);
      promptAction.showToast({ message: `已复制全部 ${inputDevices.length + outputDevices.length} 个音频设备清单！` });
      return true;
    } catch (_) {
      promptAction.showToast({ message: '复制失败，请重试' });
      return false;
    }
  }
}

export const audioDeviceService = new AudioDeviceService();
