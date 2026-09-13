import { PlaybackSnapshot, PlaybackState, Song } from '../domain/MusicModels';
import { AudioEngine } from './AudioEngine';

function clamp(value: number, minimum: number, maximum: number): number {
  return Math.min(maximum, Math.max(minimum, value));
}

export class MockAudioEngine implements AudioEngine {
  private snapshot: PlaybackSnapshot = {
    state: PlaybackState.IDLE, positionMs: 0, durationMs: 0,
    bufferedPositionMs: 0, volume: 0.8, pitchSemitones: 0, errorMessage: ''
  };

  load(song: Song): void {
    this.snapshot = {
      state: PlaybackState.READY, positionMs: 0, durationMs: song.durationMs,
      bufferedPositionMs: song.durationMs, volume: this.snapshot.volume, pitchSemitones: 0, errorMessage: ''
    };
  }

  unload(): void {
    this.snapshot = {
      state: PlaybackState.IDLE, positionMs: 0, durationMs: 0,
      bufferedPositionMs: 0, volume: this.snapshot.volume, pitchSemitones: 0, errorMessage: ''
    };
  }

  play(): void {
    if (this.snapshot.state === PlaybackState.READY || this.snapshot.state === PlaybackState.PAUSED) {
      this.snapshot.state = PlaybackState.PLAYING;
    } else if (this.snapshot.state === PlaybackState.COMPLETED) {
      this.snapshot.positionMs = 0;
      this.snapshot.state = PlaybackState.PLAYING;
    }
  }

  pause(): void {
    if (this.snapshot.state === PlaybackState.PLAYING) this.snapshot.state = PlaybackState.PAUSED;
  }

  seek(positionMs: number): void {
    this.snapshot.positionMs = clamp(positionMs, 0, this.snapshot.durationMs);
    if (this.snapshot.positionMs < this.snapshot.durationMs && this.snapshot.state === PlaybackState.COMPLETED) {
      this.snapshot.state = PlaybackState.PAUSED;
    }
  }

  setVolume(volume: number): void {
    this.snapshot.volume = clamp(volume, 0, 1);
  }

  setPitch(semitones: number): void {
    this.snapshot.pitchSemitones = Math.round(clamp(semitones, -6, 6));
  }

  tick(elapsedMs: number): void {
    if (this.snapshot.state !== PlaybackState.PLAYING || elapsedMs <= 0) return;
    this.snapshot.positionMs = clamp(this.snapshot.positionMs + elapsedMs, 0, this.snapshot.durationMs);
    if (this.snapshot.positionMs >= this.snapshot.durationMs) this.snapshot.state = PlaybackState.COMPLETED;
  }

  getSnapshot(): PlaybackSnapshot {
    return {
      state: this.snapshot.state, positionMs: this.snapshot.positionMs, durationMs: this.snapshot.durationMs,
      bufferedPositionMs: this.snapshot.bufferedPositionMs,
      volume: this.snapshot.volume, pitchSemitones: this.snapshot.pitchSemitones,
      errorMessage: this.snapshot.errorMessage
    };
  }
}

