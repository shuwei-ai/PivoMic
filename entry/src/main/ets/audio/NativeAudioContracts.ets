import { Song } from '../domain/MusicModels';

export enum AudioProcessorKind {
  AEC = 'aec',
  NOISE_SUPPRESSION = 'noise_suppression',
  AUTO_GAIN = 'auto_gain',
  REVERB = 'reverb',
  MIXER = 'mixer',
  FEEDBACK_SUPPRESSION = 'feedback_suppression'
}

export interface AudioFrame {
  samples: ArrayBuffer;
  sampleRate: number;
  channels: number;
  timestampUs: number;
}

export interface AudioProcessor {
  kind: AudioProcessorKind;
  process(input: AudioFrame, playbackReference?: AudioFrame): AudioFrame;
}

export interface LowLatencyAudioBackend {
  openInput(): Promise<boolean>;
  openOutput(): Promise<boolean>;
  close(): void;
}

export interface MediaSessionAdapter {
  activate(song: Song): Promise<void>;
  updatePosition(positionMs: number): void;
  deactivate(): void;
}

export const DEFAULT_PROCESSOR_ORDER: AudioProcessorKind[] = [
  AudioProcessorKind.AEC,
  AudioProcessorKind.NOISE_SUPPRESSION,
  AudioProcessorKind.AUTO_GAIN,
  AudioProcessorKind.REVERB,
  AudioProcessorKind.MIXER,
  AudioProcessorKind.FEEDBACK_SUPPRESSION
];

