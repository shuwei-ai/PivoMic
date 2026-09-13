import { Song } from '../domain/MusicModels';

export enum MusicSourceStatus {
  READY = 'ready',
  NOT_CONFIGURED = 'not_configured',
  ERROR = 'error'
}

export interface MusicSourceResult {
  status: MusicSourceStatus;
  songs: Song[];
  message: string;
}

export interface ImportResult {
  songs: Song[];
  rejectedCount: number;
  message: string;
}

export interface MusicSource {
  listSongs(): Promise<MusicSourceResult>;
  importUris(uris: string[]): Promise<ImportResult>;
}

