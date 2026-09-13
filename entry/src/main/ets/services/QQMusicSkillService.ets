import { http } from '@kit.NetworkKit';
import { buffer } from '@kit.ArkTS';
import { Song, MusicSourceKind, RecommendPlaylist } from '../domain/MusicModels';
import { AppConfig } from '../config/AppConfig';

export interface QQSongItem {
  songMid: string;
  songName: string;
  singerName: string;
  songH5Url?: string;
  albumImageUrl?: string;
}

export interface QQChartRankSong {
  rank?: number;
  songName?: string;
  singerName?: string;
  picUrl?: string;
}

export interface QQChartTopItem {
  topId: number;
  topName: string;
  listenNum?: number;
  totalNum?: number;
  songList?: QQChartRankSong[];
  topHeaderPic?: string;
  topBannerPic?: string;
}

export interface QQChartGroup {
  groupName: string;
  groupTopList: QQChartTopItem[];
}

export interface QQPlaylistDetail {
  dissId: number;
  dissName: string;
  desc?: string;
  picUrl?: string;
  totalNum?: number;
  hasMore?: boolean;
  page?: number;
  songs: Song[];
}

export interface QQChartDetail {
  topId: number;
  topName: string;
  topDesc?: string;
  topHeaderPic?: string;
  totalNum?: number;
  hasMore?: boolean;
  page?: number;
  songs: Song[];
}

export interface QQAIPlaylistItem {
  dissId: number | string;
  dissName: string;
  dissDesc?: string;
  creatorName?: string;
  picUrl?: string;
  songNum?: number;
}

interface DailyMixResponse {
  songlist?: QQSongItem[];
}

interface AIPlaylistsResponse {
  playlists?: QQAIPlaylistItem[];
}

interface ChartsResponse {
  groupList?: QQChartGroup[];
}

interface ChartDetailResponse {
  topId: number;
  topName: string;
  topDesc?: string;
  topHeaderPic?: string;
  totalNum?: number;
  hasMore?: boolean;
  trackList?: QQSongItem[];
}

interface PlaylistDetailResponse {
  dissId: number;
  dissName: string;
  desc?: string;
  picUrl?: string;
  totalNum?: number;
  hasMore?: boolean;
  trackList?: QQSongItem[];
}

interface QQMusicSkillComm {
  skill_version: string;
}

interface QQMusicSkillRequestBody {
  params: Record<string, Object | string | number | boolean>;
  comm: QQMusicSkillComm;
}

function parseResponseBody(result: string | Object | ArrayBuffer | Uint8Array): string {
  if (typeof result === 'string') return result;
  try {
    if (result instanceof Uint8Array) return buffer.from(result).toString('utf8');
    return buffer.from(result as ArrayBuffer).toString('utf8');
  } catch (_) {
    return '';
  }
}

export class QQMusicSkillService {
  private static readonly BASE_URL: string = 'https://a.y.qq.com';
  private static readonly SKILL_VERSION: string = '0.0.3';

  private getApiKey(): string {
    return AppConfig.getQQMusicApiKey();
  }

  isConfigured(): boolean {
    return this.getApiKey().length > 0;
  }

  private async postRequest<T>(path: string, params: Record<string, Object | string | number | boolean> = {}): Promise<T | undefined> {
    const apiKey = this.getApiKey();
    if (!apiKey || apiKey.length === 0) {
      return undefined;
    }

    const request = http.createHttp();
    try {
      const reqComm: QQMusicSkillComm = {
        skill_version: QQMusicSkillService.SKILL_VERSION
      };
      const reqBody: QQMusicSkillRequestBody = {
        params: params,
        comm: reqComm
      };
      const body = JSON.stringify(reqBody);

      const response = await request.request(`${QQMusicSkillService.BASE_URL}${path}`, {
        method: http.RequestMethod.POST,
        connectTimeout: 12000,
        readTimeout: 20000,
        header: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${apiKey}`,
          'User-Agent': 'PivoMic/1.0 QQMusicSkill'
        },
        extraData: body
      });

      if (response.responseCode < 200 || response.responseCode >= 300) {
        return undefined;
      }

      const rawText = parseResponseBody(response.result);
      if (!rawText || rawText.trim().length === 0) {
        return undefined;
      }

      const json = JSON.parse(rawText) as Record<string, Object>;
      if (json.ret !== undefined && Number(json.ret) !== 0) {
        return undefined;
      }
      return json as T;
    } catch (_) {
      return undefined;
    } finally {
      request.destroy();
    }
  }

  /**
   * 1. 每日推荐 (Daily Mix): 获取每日 30 首推荐歌曲
   */
  async getDailyMix(): Promise<Song[]> {
    const data = await this.postRequest<DailyMixResponse>('/discover/daily-mix', {});
    if (!data || !Array.isArray(data.songlist)) {
      return [];
    }

    return data.songlist.map((item: QQSongItem): Song => {
      return {
        id: `qqskill-${item.songMid || Math.random().toString(36).substring(2, 9)}`,
        title: item.songName || '未知歌名',
        artist: item.singerName || '未知歌手',
        uri: '',
        durationMs: 0,
        format: 'QQ',
        source: MusicSourceKind.ONLINE,
        provider: 'qq',
        remoteId: item.songMid,
        streamUrl: '',
        lyricUrl: '',
        coverUrl: item.albumImageUrl || '',
        extra: item.songH5Url || `https://i2.y.qq.com/a/song/${item.songMid}`
      };
    });
  }

  /**
   * 2. AI 歌单 (AI Playlists): 获取 AI 推荐歌单列表
   */
  async getAIPlaylists(): Promise<RecommendPlaylist[]> {
    const data = await this.postRequest<AIPlaylistsResponse>('/discover/ai-playlists', {
      'reqType': 'all'
    });
    if (!data || !Array.isArray(data.playlists)) {
      return [];
    }

    return data.playlists.map((item: QQAIPlaylistItem): RecommendPlaylist => {
      return {
        id: `qq_playlist_${item.dissId}`,
        source: 'qq_ai',
        name: item.dissName || 'AI 精选歌单',
        creator: item.creatorName || item.dissDesc || 'QQ音乐 AI',
        coverUrl: item.picUrl || '',
        trackCount: item.songNum || 0
      };
    });
  }

  /**
   * 3. 排行榜 (Charts): 获取所有榜单分组及榜单摘要
   */
  async getCharts(): Promise<QQChartGroup[]> {
    const data = await this.postRequest<ChartsResponse>('/charts', {});
    if (!data || !Array.isArray(data.groupList)) {
      return [];
    }
    return data.groupList;
  }

  /**
   * 3.1 榜单详情 (Chart Detail): 获取指定榜单内完整歌曲
   */
  async getChartSongs(topId: number, page: number = 0): Promise<QQChartDetail | undefined> {
    const data = await this.postRequest<ChartDetailResponse>('/charts/detail', {
      'topId': topId,
      'page': page
    });
    if (!data) return undefined;

    const songs: Song[] = (data.trackList || []).map((item: QQSongItem): Song => {
      return {
        id: `qqskill-${item.songMid || Math.random().toString(36).substring(2, 9)}`,
        title: item.songName || '未知歌名',
        artist: item.singerName || '未知歌手',
        uri: '',
        durationMs: 0,
        format: 'QQ',
        source: MusicSourceKind.ONLINE,
        provider: 'qq',
        remoteId: item.songMid,
        streamUrl: '',
        lyricUrl: '',
        coverUrl: item.albumImageUrl || data.topHeaderPic || '',
        extra: item.songH5Url || `https://i2.y.qq.com/a/song/${item.songMid}`
      };
    });

    return {
      topId: data.topId,
      topName: data.topName,
      topDesc: data.topDesc,
      topHeaderPic: data.topHeaderPic,
      totalNum: data.totalNum,
      hasMore: data.hasMore ?? false,
      page: page,
      songs: songs
    };
  }

  /**
   * 4. 歌单详情 (Playlist Detail): 获取指定歌单内完整歌曲
   */
  async getPlaylistSongs(dissId: number, page: number = 0): Promise<QQPlaylistDetail | undefined> {
    const data = await this.postRequest<PlaylistDetailResponse>('/playlists/detail', {
      'dissId': dissId,
      'page': page
    });
    if (!data) return undefined;

    const songs: Song[] = (data.trackList || []).map((item: QQSongItem): Song => {
      return {
        id: `qqskill-${item.songMid || Math.random().toString(36).substring(2, 9)}`,
        title: item.songName || '未知歌名',
        artist: item.singerName || '未知歌手',
        uri: '',
        durationMs: 0,
        format: 'QQ',
        source: MusicSourceKind.ONLINE,
        provider: 'qq',
        remoteId: item.songMid,
        streamUrl: '',
        lyricUrl: '',
        coverUrl: item.albumImageUrl || data.picUrl || '',
        extra: item.songH5Url || `https://i2.y.qq.com/a/song/${item.songMid}`
      };
    });

    return {
      dissId: data.dissId,
      dissName: data.dissName,
      desc: data.desc,
      picUrl: data.picUrl,
      totalNum: data.totalNum,
      hasMore: data.hasMore ?? false,
      page: page,
      songs: songs
    };
  }
}
