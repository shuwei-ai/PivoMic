import { MusicSourceKind, Song } from '../domain/MusicModels';
import { ImportResult, MusicSource, MusicSourceResult, MusicSourceStatus } from './MusicSource';

function fileNameFromUri(uri: string): string {
  const queryIndex = uri.indexOf('?');
  const cleanUri = queryIndex >= 0 ? uri.substring(0, queryIndex) : uri;
  const slashIndex = cleanUri.lastIndexOf('/');
  const encodedName = slashIndex >= 0 ? cleanUri.substring(slashIndex + 1) : cleanUri;
  try {
    return decodeURIComponent(encodedName);
  } catch (_) {
    return encodedName;
  }
}

function extensionOf(uri: string): string {
  const name = fileNameFromUri(uri);
  const dotIndex = name.lastIndexOf('.');
  return dotIndex >= 0 ? name.substring(dotIndex + 1).toUpperCase() : '';
}

export function isSupportedAudioFile(uri: string): boolean {
  const extension = extensionOf(uri);
  return extension === 'MP3' || extension === 'FLAC' || extension === 'WAV';
}

export function songsFromUris(uris: string[]): ImportResult {
  const songs: Song[] = [];
  let rejectedCount = 0;
  for (let index = 0; index < uris.length; index++) {
    const uri = uris[index];
    if (!isSupportedAudioFile(uri)) {
      rejectedCount++;
      continue;
    }
    const name = fileNameFromUri(uri);
    const dotIndex = name.lastIndexOf('.');
    const title = dotIndex >= 0 ? name.substring(0, dotIndex) : name;
    songs.push({
      id: `local-${index}-${title}`, title: title, artist: '未知艺术家', uri: uri,
      durationMs: 0, format: extensionOf(uri), source: MusicSourceKind.LOCAL
    });
  }
  const message = rejectedCount > 0 ? `已导入 ${songs.length} 首，跳过 ${rejectedCount} 个不支持的文件` : `已导入 ${songs.length} 首歌曲`;
  return { songs: songs, rejectedCount: rejectedCount, message: message };
}

export class LocalMusicSource implements MusicSource {
  private songs: Song[] = [];

  listSongs(): Promise<MusicSourceResult> {
    const result: MusicSourceResult = { status: MusicSourceStatus.READY, songs: this.songs, message: '' };
    return Promise.resolve(result);
  }

  importUris(uris: string[]): Promise<ImportResult> {
    const result = songsFromUris(uris);
    for (let index = 0; index < result.songs.length; index++) this.songs.push(result.songs[index]);
    return Promise.resolve(result);
  }
}
