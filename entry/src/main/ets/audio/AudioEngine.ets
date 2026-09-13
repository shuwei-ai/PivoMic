import { PlaybackSnapshot, Song } from '../domain/MusicModels';

export interface AudioEngine {
  load(song: Song): void;
  unload(): void;
  play(): void;
  pause(): void;
  seek(positionMs: number): void;
  setVolume(volume: number): void;
  setPitch(semitones: number): void;
  tick(elapsedMs: number): void;
  getSnapshot(): PlaybackSnapshot;
}

