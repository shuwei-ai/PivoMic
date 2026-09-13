import { buffer } from '@kit.ArkTS';
import { MusicSourceMode, Song, RecommendPlaylist } from '../domain/MusicModels';
import { NativeMusicEngine } from './NativeMusicEngine';
import { FavoritesPersistenceService } from './FavoritesPersistenceService';

export interface SearchSourceOption {
  id: string;
  name: string;
  brandColor: string;
  badge: string;
}

export const SEARCH_SOURCE_OPTIONS: SearchSourceOption[] = [
  { id: 'all', name: '全部', brandColor: '#F59E0B', badge: '全' },
  { id: 'soda', name: '汽水', brandColor: '#10B981', badge: '汽' },
  { id: 'netease', name: '网易云', brandColor: '#E60026', badge: '易' },
  { id: 'qq', name: 'QQ音乐', brandColor: '#1DB954', badge: 'Q' },
  { id: 'kuwo', name: '酷我', brandColor: '#F5A623', badge: '我' },
  { id: 'kugou', name: '酷狗', brandColor: '#00A9F0', badge: '狗' }
];

export const ALL_SEARCH_SOURCES: string[] = ['soda', 'netease', 'qq', 'kuwo', 'kugou'];

export interface OnlineSearchResult {
  songs: Song[];
  message: string;
}

export interface SwitchSourceResult {
  id: string;
  name: string;
  artist: string;
  album?: string;
  album_id?: string;
  duration?: number;
  source: string;
  cover?: string;
  extra?: Object | string;
  score?: number;
  link?: string;
}

export interface MusicServerTestResult {
  success: boolean;
  message: string;
  statusCode?: number;
}

export function responseText(result: string | Object | ArrayBuffer | Uint8Array): string {
  if (typeof result === 'string') return result;
  try {
    if (result instanceof Uint8Array) return buffer.from(result).toString('utf8');
    return buffer.from(result as ArrayBuffer).toString('utf8');
  } catch (_) {
    return '';
  }
}

export function buildStreamUrl(song: Song, _isStream: boolean = true): string {
  return song.streamUrl || song.uri || '';
}

export function buildLyricUrl(song: Song): string {
  return song.lyricUrl || '';
}

export function shuffleArray<T>(array: T[]): T[] {
  const result: T[] = [];
  for (let i = 0; i < array.length; i++) {
    result.push(array[i]);
  }
  for (let i = result.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    const temp = result[i];
    result[i] = result[j];
    result[j] = temp;
  }
  return result;
}

export function parseSearchPayload(_payload: string): Song[] {
  return [];
}

export function parseSearchHtml(_html: string): Song[] {
  return [];
}

export function parseSearchJson(_jsonText: string): Song[] {
  return [];
}

export class OnlineMusicSource {
  private getSourceMode(): MusicSourceMode {
    return FavoritesPersistenceService.getInstance().loadMusicSourceMode();
  }

  /**
   * 测试原生音乐引擎网络连通状态
   */
  async testConnection(_origin?: string): Promise<MusicServerTestResult> {
    const res = await NativeMusicEngine.getInstance().testEngine();
    const testResult: MusicServerTestResult = {
      success: res.success,
      message: res.message,
      statusCode: res.statusCode
    };
    return testResult;
  }

  /**
   * 拉取推荐榜单（官方权威排行榜）
   */
  async fetchRecommendPlaylists(_sources: string[] = ['netease', 'qq']): Promise<RecommendPlaylist[]> {
    const mode = this.getSourceMode();
    if (mode === MusicSourceMode.LOCAL) {
      return [];
    }
    return NativeMusicEngine.getInstance().fetchToplists();
  }

  /**
   * 获取榜单内的歌曲列表
   */
  async fetchPlaylistSongs(playlist: RecommendPlaylist): Promise<Song[]> {
    const mode = this.getSourceMode();
    if (mode === MusicSourceMode.LOCAL) {
      return [];
    }
    return NativeMusicEngine.getInstance().fetchToplistSongs(playlist);
  }

  /**
   * 全网搜索与分源搜索
   */
  async search(keyword: string, page: number = 1, sources?: string[]): Promise<OnlineSearchResult> {
    const mode = this.getSourceMode();
    if (mode === MusicSourceMode.LOCAL) {
      return { songs: [], message: '当前处于纯本地模式，未启用在线检索' };
    }
    return NativeMusicEngine.getInstance().search(keyword, page, sources);
  }

  /**
   * 分类榜单歌曲获取
   */
  async fetchCategorySongs(category: string): Promise<Song[]> {
    const mode = this.getSourceMode();
    if (mode === MusicSourceMode.LOCAL) {
      return [];
    }
    let keyword = '热歌榜';
    if (category === 'chinese' || category === '华语') {
      keyword = '华语流行';
    } else if (category === 'nostalgia' || category === '怀旧') {
      keyword = '怀旧金曲';
    } else if (category === 'soft' || category === '轻声') {
      keyword = '治愈民谣';
    } else if (category === 'hot' || category === '热唱') {
      keyword = '热歌榜';
    } else {
      keyword = category;
    }
    const result = await NativeMusicEngine.getInstance().search(keyword, 1);
    return result.songs;
  }

  /**
   * 歌词获取（逐字或标准 LRC）
   */
  async fetchLyrics(song: Song): Promise<string> {
    const mode = this.getSourceMode();
    if (mode === MusicSourceMode.LOCAL) {
      return '';
    }
    return NativeMusicEngine.getInstance().fetchLyrics(song);
  }

  /**
   * 自动换源与跨平台降级
   */
  async switchSource(song: Song, targetSource?: string, excludeSources: string[] = []): Promise<Song | undefined> {
    return NativeMusicEngine.getInstance().switchSource(song, targetSource, excludeSources);
  }
}
