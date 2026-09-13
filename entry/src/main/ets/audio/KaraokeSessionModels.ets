export type NativeEngineState = 'Idle' | 'Preparing' | 'Ready' | 'Singing' | 'Paused' | 'Interrupted' | 'Error';
export type KaraokeSessionState = 'idle' | 'preparing' | 'ready' | 'singing' | 'paused' | 'interrupted' | 'error';

export enum AudioRouteMode {
  Speaker = 0,
  SpeakerWithEarReturn = 1,
  Bluetooth = 2,
  Wired = 3
}

export enum PitchScaleType {
  Chromatic = 0,
  Major = 1,
  Minor = 2,
  Pentatonic = 3
}

export interface NativeEngineSnapshot {
  state: NativeEngineState;
  positionMs: number;
  durationMs: number;
  microphonePeak: number;
  latencyMs: number;
  underrunCount: number;
  fastMode: boolean;
  aecSupported: boolean;
  audioRoute: number;
  accompanimentPitchShift: number;
  pitchCorrectionEnabled: boolean;
  pitchCorrectionStrength: number;
  isRecording: boolean;
  recordedDurationMs: number;
  resumeRequested?: boolean;
  isDucked?: boolean;
  errorCode: number;
  errorMessage: string;
}

export interface KaraokeSessionSnapshot {
  state: KaraokeSessionState;
  positionMs: number;
  durationMs: number;
  microphonePeak: number;
  latencyMs: number;
  underrunCount: number;
  fastMode: boolean;
  aecSupported: boolean;
  audioRoute: number;
  accompanimentPitchShift: number;
  pitchCorrectionEnabled: boolean;
  pitchCorrectionStrength: number;
  isRecording: boolean;
  recordedDurationMs: number;
  resumeRequested?: boolean;
  isDucked?: boolean;
  errorCode: number;
  errorMessage: string;
}
