import { Song, MusicSourceKind } from './MusicModels';

export const SEPARATION_MODEL_ID: string = 'UVR-MDX-NET-Inst_Main';
export const SEPARATION_PIPELINE_VERSION: string = 'mdx-inst-main-v1';
export interface AccompanimentAsset {
  id: string;
  song: Song;
  sourceIdentity: string;
  sourceHash: string;
  modelId: string;
  pipelineVersion: string;
  path: string;
  createdAt: number;
  sampleRate: number;
  frameCount: number;
}
export interface SeparationModelSnapshot { phase: string; progress: number; errorMessage: string; }
export interface SeparationJobSnapshot { phase: string; progress: number; errorMessage: string; songId: string; }
export interface SeparationSnapshot {
  assets: AccompanimentAsset[];
  model: SeparationModelSnapshot;
  job: SeparationJobSnapshot;
  busy: boolean;
}
export interface NativeSeparationSnapshot {
  phase: string; progress: number; errorMessage: string; sampleRate: number; frameCount: number;
}
export interface NativeSeparationPort {
  startJob(inputFd: number, offset: number, size: number, modelPath: string, outputTempPath: string): number;
  getJobSnapshot(jobId: number): NativeSeparationSnapshot;
  cancelJob(jobId: number): void;
  releaseJob(jobId: number): void;
}
export function accompanimentSourceIdentity(song: Song): string {
  if (song.source === MusicSourceKind.LOCAL) return `local:${song.uri}`;
  return `${song.source}:${song.provider ?? ''}:${song.remoteId ?? song.id}`;
}
export function accompanimentMatches(asset: AccompanimentAsset, song: Song): boolean {
  return (song.source === MusicSourceKind.LOCAL ? asset.sourceIdentity.startsWith(`${accompanimentSourceIdentity(song)}:`) : asset.sourceIdentity === accompanimentSourceIdentity(song)) &&
    asset.modelId === SEPARATION_MODEL_ID && asset.pipelineVersion === SEPARATION_PIPELINE_VERSION;
}

export function copyAccompanimentSong(song: Song): Song {
  return { id: song.id, title: song.title, artist: song.artist, uri: song.uri, durationMs: song.durationMs,
    format: song.format, source: song.source, lyricText: song.lyricText, provider: song.provider,
    remoteId: song.remoteId, album: song.album, coverUrl: song.coverUrl, extra: song.extra,
    streamUrl: song.streamUrl, lyricUrl: song.lyricUrl };
}
