import { KaraokeSessionSnapshot, KaraokeSessionState, NativeEngineSnapshot, NativeEngineState, AudioRouteMode, PitchScaleType } from './KaraokeSessionModels';

export interface NativeKaraokePort {
  prepare(fd: number, offset: number, size: number, durationMs: number): boolean;
  start(): boolean;
  pause(): boolean;
  seek(positionMs: number): boolean;
  stop(): boolean;
  release(): void;
  setSafeOutputConnected(value: boolean): void;
  setAudioRoute?(route: number): void;
  setAccompanimentGain(value: number): void;
  setVocalGain(value: number): void;
  setReverbMix(value: number): void;
  setAntiHowlingEnabled?(enabled: boolean): void;
  setAecEnabled?(enabled: boolean): void;
  setSpatialReverbEnabled?(enabled: boolean): void;
  setReverbPreset?(preset: number): void;
  setParametricEqEnabled?(enabled: boolean): void;
  setDeEsserEnabled?(enabled: boolean): void;
  setVocalDynamicsEnabled?(enabled: boolean): void;
  setAccompanimentPitchShift?(semitones: number): void;
  setPitchCorrection?(enabled: boolean, strength: number, scaleType: number, rootNote: number): void;
  startRecording?(): void;
  stopRecording?(): void;
  exportRecording?(outputPath: string): boolean;
  getSnapshot(): NativeEngineSnapshot;
}

function clamp(value: number, max: number = 2.0): number {
  if (!Number.isFinite(value)) {
    throw new RangeError('gain must be finite');
  }
  return Math.max(0, Math.min(max, value));
}

function mapState(state: NativeEngineState): KaraokeSessionState {
  if (state === 'Idle') return 'idle';
  if (state === 'Preparing') return 'preparing';
  if (state === 'Ready') return 'ready';
  if (state === 'Singing') return 'singing';
  if (state === 'Paused') return 'paused';
  if (state === 'Interrupted') return 'interrupted';
  return 'error';
}

export class KaraokeAudioEngine {
  private released: boolean = false;
  private port: NativeKaraokePort;
  private onRelease: (() => void) | null;

  constructor(port: NativeKaraokePort, onRelease: (() => void) | null = null) {
    this.port = port;
    this.onRelease = onRelease;
  }

  prepare(fd: number, offset: number, size: number, durationMs: number): void {
    this.ensureActive();
    if (!this.port.prepare(fd, offset, size, durationMs)) throw new Error(this.failureMessage());
  }

  start(): void {
    this.ensureActive();
    if (!this.port.start()) throw new Error(this.failureMessage());
  }

  pause(): void {
    this.ensureActive();
    if (!this.port.pause()) throw new Error(this.failureMessage());
  }

  seek(positionMs: number): void {
    this.ensureActive();
    if (!this.port.seek(positionMs)) throw new Error(this.failureMessage());
  }

  stop(): void {
    this.ensureActive();
    if (!this.port.stop()) throw new Error(this.failureMessage());
  }

  release(): void {
    if (this.released) return;
    this.released = true;
    this.port.release();
    if (this.onRelease !== null) {
      this.onRelease();
    }
  }

  setSafeOutputConnected(value: boolean): void {
    this.ensureActive();
    this.port.setSafeOutputConnected(value);
  }

  setAudioRoute(route: AudioRouteMode): void {
    this.ensureActive();
    if (this.port.setAudioRoute) {
      this.port.setAudioRoute(route);
    }
  }

  setAccompanimentGain(value: number): void {
    this.ensureActive();
    this.port.setAccompanimentGain(clamp(value, 2.0));
  }

  setVocalGain(value: number): void {
    this.ensureActive();
    this.port.setVocalGain(clamp(value, 2.0));
  }

  setReverbMix(value: number): void {
    this.ensureActive();
    this.port.setReverbMix(clamp(value, 1.0));
  }

  setAntiHowlingEnabled(enabled: boolean): void {
    this.ensureActive();
    if (this.port.setAntiHowlingEnabled) {
      this.port.setAntiHowlingEnabled(enabled);
    }
  }

  setAecEnabled(enabled: boolean): void {
    this.ensureActive();
    if (this.port.setAecEnabled) {
      this.port.setAecEnabled(enabled);
    }
  }

  setSpatialReverbEnabled(enabled: boolean): void {
    this.ensureActive();
    if (this.port.setSpatialReverbEnabled) {
      this.port.setSpatialReverbEnabled(enabled);
    }
  }

  setReverbPreset(preset: number): void {
    this.ensureActive();
    if (this.port.setReverbPreset) {
      this.port.setReverbPreset(preset);
    }
  }

  setParametricEqEnabled(enabled: boolean): void {
    this.ensureActive();
    if (this.port.setParametricEqEnabled) {
      this.port.setParametricEqEnabled(enabled);
    }
  }

  setDeEsserEnabled(enabled: boolean): void {
    this.ensureActive();
    if (this.port.setDeEsserEnabled) {
      this.port.setDeEsserEnabled(enabled);
    }
  }

  setVocalDynamicsEnabled(enabled: boolean): void {
    this.ensureActive();
    if (this.port.setVocalDynamicsEnabled) {
      this.port.setVocalDynamicsEnabled(enabled);
    }
  }

  setAccompanimentPitchShift(semitones: number): void {
    this.ensureActive();
    if (this.port.setAccompanimentPitchShift) {
      this.port.setAccompanimentPitchShift(semitones);
    }
  }

  setPitchCorrection(enabled: boolean, strength: number, scaleType: PitchScaleType = PitchScaleType.Chromatic, rootNote: number = 0): void {
    this.ensureActive();
    if (this.port.setPitchCorrection) {
      this.port.setPitchCorrection(enabled, strength, scaleType, rootNote);
    }
  }

  startRecording(): void {
    this.ensureActive();
    if (this.port.startRecording) {
      this.port.startRecording();
    }
  }

  stopRecording(): void {
    this.ensureActive();
    if (this.port.stopRecording) {
      this.port.stopRecording();
    }
  }

  exportRecording(outputPath: string): boolean {
    this.ensureActive();
    if (this.port.exportRecording) {
      return this.port.exportRecording(outputPath);
    }
    return false;
  }

  getSnapshot(): KaraokeSessionSnapshot {
    this.ensureActive();
    const v = this.port.getSnapshot();
    return {
      state: mapState(v.state),
      positionMs: v.positionMs,
      durationMs: v.durationMs,
      microphonePeak: v.microphonePeak,
      latencyMs: v.latencyMs,
      underrunCount: v.underrunCount,
      fastMode: v.fastMode,
      aecSupported: v.aecSupported,
      audioRoute: v.audioRoute ?? 0,
      accompanimentPitchShift: v.accompanimentPitchShift ?? 0,
      pitchCorrectionEnabled: v.pitchCorrectionEnabled ?? false,
      pitchCorrectionStrength: v.pitchCorrectionStrength ?? 0,
      isRecording: v.isRecording ?? false,
      recordedDurationMs: v.recordedDurationMs ?? 0,
      resumeRequested: v.resumeRequested ?? false,
      isDucked: v.isDucked ?? false,
      errorCode: v.errorCode,
      errorMessage: v.errorMessage
    };
  }

  private ensureActive(): void {
    if (this.released) {
      throw new Error('Karaoke audio engine lease has been released');
    }
  }

  private failureMessage(): string {
    const v = this.port.getSnapshot();
    return v.errorMessage.length > 0 ? v.errorMessage : 'Native karaoke operation failed';
  }
}
