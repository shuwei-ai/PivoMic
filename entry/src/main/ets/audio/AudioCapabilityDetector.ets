import { AudioCapability } from '../domain/MusicModels';

export class AudioCapabilityDetector {
  detectForAVPlayer(): AudioCapability {
    return {
      simulated: false,
      microphoneAvailable: false,
      lowLatencyAvailable: false,
      aecAvailable: false,
      message: 'AVPlayer 真实伴奏播放已启用；麦克风混音、升降调和 AEC 仍需 OHAudio 原生引擎。'
    };
  }

  detectForMockEngine(): AudioCapability {
    return {
      simulated: true,
      microphoneAvailable: false,
      lowLatencyAvailable: false,
      aecAvailable: false,
      message: '当前使用模拟音频引擎：可预览伴奏与歌词，麦克风混音和 AEC 尚未启用。'
    };
  }
}
