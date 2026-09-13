export enum MusicSourceKind {
  DEMO = 'demo',
  LOCAL = 'local',
  WEBDAV = 'webdav',
  ONLINE = 'online'
}

export enum MusicSourceMode {
  ONLINE = 'online',
  LOCAL = 'local'
}

export enum PlaybackState {
  IDLE = 'idle',
  READY = 'ready',
  PLAYING = 'playing',
  PAUSED = 'paused',
  COMPLETED = 'completed',
  ERROR = 'error'
}

export interface Song {
  id: string;
  title: string;
  artist: string;
  uri: string;
  durationMs: number;
  format: string;
  source: MusicSourceKind;
  lyricText?: string;
  provider?: string;
  remoteId?: string;
  album?: string;
  coverUrl?: string;
  extra?: string;
  streamUrl?: string;
  lyricUrl?: string;
  /** 本地录音专用：录音开始时原曲的播放位置(ms)。播放录音时需加上此偏移才能正确对齐歌词 */
  lyricOffsetMs?: number;
}

export interface LyricWord {
  timeMs: number;
  text: string;
}

export interface LyricLine {
  timeMs: number;
  text: string;
  words: LyricWord[];
}

export interface LyricDocument {
  title: string;
  artist: string;
  album: string;
  by: string;
  offsetMs: number;
  lines: LyricLine[];
}

export interface PlaybackSnapshot {
  state: PlaybackState;
  positionMs: number;
  durationMs: number;
  bufferedPositionMs: number;
  volume: number;
  pitchSemitones: number;
  errorMessage: string;
}

export interface AudioCapability {
  simulated: boolean;
  microphoneAvailable: boolean;
  lowLatencyAvailable: boolean;
  aecAvailable: boolean;
  message: string;
}

export interface RecommendPlaylist {
  id: string;
  source: string;
  name: string;
  creator: string;
  coverUrl: string;
  trackCount: number;
}
