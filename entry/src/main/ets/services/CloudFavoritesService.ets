import { http } from '@kit.NetworkKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { Song } from '../domain/MusicModels';
import { AppConfig } from '../config/AppConfig';

const DOMAIN = 0x0000;
const TAG = 'CloudFavoritesService';
const BASE_URL = AppConfig.CLOUD_API_BASE_URL;

export interface FavoriteListResponse {
  total: number;
  items: Song[];
}

export interface FavoriteSyncResponse {
  total: number;
  favorites: Song[];
  custom_music_server_url?: string;
  qq_music_api_key?: string;
  synced_at: string;
}

export interface FavoriteSyncResult {
  favorites: Song[];
  custom_music_server_url?: string;
  qq_music_api_key?: string;
}

export interface UserSettingsData {
  custom_music_server_url?: string;
  qq_music_api_key?: string;
  recording_dir?: string;
  updated_at?: string;
}

export interface ToggleFavoriteResult {
  is_favorite: boolean;
  song_id: string;
  message: string;
}

export class CloudFavoritesService {
  private static instance?: CloudFavoritesService;

  private constructor() {}

  static getInstance(): CloudFavoritesService {
    if (!CloudFavoritesService.instance) {
      CloudFavoritesService.instance = new CloudFavoritesService();
    }
    return CloudFavoritesService.instance;
  }

  async fetchFavorites(token: string): Promise<Song[]> {
    const request = http.createHttp();
    try {
      const response = await request.request(`${BASE_URL}/favorites?limit=500`, {
        method: http.RequestMethod.GET,
        header: {
          'Accept': 'application/json',
          'Authorization': `Bearer ${token}`
        },
        connectTimeout: 10000,
        readTimeout: 15000
      });

      if (response.responseCode >= 200 && response.responseCode < 300) {
        const resStr = typeof response.result === 'string' ? response.result : JSON.stringify(response.result);
        const data = JSON.parse(resStr) as FavoriteListResponse;
        return data.items || [];
      }
      return [];
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'fetchFavorites error: %{public}s', JSON.stringify(err));
      return [];
    } finally {
      request.destroy();
    }
  }

  async addFavorite(token: string, song: Song): Promise<boolean> {
    const request = http.createHttp();
    try {
      const response = await request.request(`${BASE_URL}/favorites`, {
        method: http.RequestMethod.POST,
        header: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'Authorization': `Bearer ${token}`
        },
        extraData: JSON.stringify({ song: song }),
        connectTimeout: 8000,
        readTimeout: 10000
      });

      return response.responseCode >= 200 && response.responseCode < 300;
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'addFavorite error: %{public}s', JSON.stringify(err));
      return false;
    } finally {
      request.destroy();
    }
  }

  async deleteFavorite(token: string, songId: string): Promise<boolean> {
    const request = http.createHttp();
    try {
      const response = await request.request(`${BASE_URL}/favorites/${encodeURIComponent(songId)}`, {
        method: http.RequestMethod.DELETE,
        header: {
          'Accept': 'application/json',
          'Authorization': `Bearer ${token}`
        },
        connectTimeout: 8000,
        readTimeout: 10000
      });

      return response.responseCode >= 200 && response.responseCode < 300;
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'deleteFavorite error: %{public}s', JSON.stringify(err));
      return false;
    } finally {
      request.destroy();
    }
  }

  async toggleFavorite(token: string, song: Song): Promise<boolean | null> {
    const request = http.createHttp();
    try {
      const response = await request.request(`${BASE_URL}/favorites/toggle`, {
        method: http.RequestMethod.POST,
        header: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'Authorization': `Bearer ${token}`
        },
        extraData: JSON.stringify({ song: song }),
        connectTimeout: 8000,
        readTimeout: 10000
      });

      if (response.responseCode >= 200 && response.responseCode < 300) {
        const resStr = typeof response.result === 'string' ? response.result : JSON.stringify(response.result);
        const data = JSON.parse(resStr) as ToggleFavoriteResult;
        return data.is_favorite;
      }
      return null;
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'toggleFavorite error: %{public}s', JSON.stringify(err));
      return null;
    } finally {
      request.destroy();
    }
  }

  async syncFavorites(token: string, localSongs: Song[], customMusicServerUrl?: string, qqMusicApiKey?: string): Promise<FavoriteSyncResult> {
    const request = http.createHttp();
    try {
      const payload: Record<string, Object> = {
        'local_songs': localSongs
      };
      if (customMusicServerUrl !== undefined && customMusicServerUrl.length > 0) {
        payload['custom_music_server_url'] = customMusicServerUrl;
      }
      if (qqMusicApiKey !== undefined && qqMusicApiKey.length > 0) {
        payload['qq_music_api_key'] = qqMusicApiKey;
      }
      const response = await request.request(`${BASE_URL}/favorites/sync`, {
        method: http.RequestMethod.POST,
        header: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'Authorization': `Bearer ${token}`
        },
        extraData: JSON.stringify(payload),
        connectTimeout: 15000,
        readTimeout: 20000
      });

      if (response.responseCode >= 200 && response.responseCode < 300) {
        const resStr = typeof response.result === 'string' ? response.result : JSON.stringify(response.result);
        const data = JSON.parse(resStr) as FavoriteSyncResponse;
        const res: FavoriteSyncResult = {
          favorites: data.favorites || [],
          custom_music_server_url: data.custom_music_server_url,
          qq_music_api_key: data.qq_music_api_key
        };
        return res;
      }
      const fallback: FavoriteSyncResult = { favorites: [] };
      return fallback;
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'syncFavorites error: %{public}s', JSON.stringify(err));
      const fallback: FavoriteSyncResult = { favorites: [] };
      return fallback;
    } finally {
      request.destroy();
    }
  }

  async updateUserSettings(token: string, settings: UserSettingsData): Promise<boolean> {
    const request = http.createHttp();
    try {
      const response = await request.request(`${BASE_URL}/user/settings`, {
        method: http.RequestMethod.POST,
        header: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'Authorization': `Bearer ${token}`
        },
        extraData: JSON.stringify(settings),
        connectTimeout: 10000,
        readTimeout: 15000
      });

      return response.responseCode >= 200 && response.responseCode < 300;
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'updateUserSettings error: %{public}s', JSON.stringify(err));
      return false;
    } finally {
      request.destroy();
    }
  }

  async batchDeleteFavorites(token: string, songIds: string[]): Promise<boolean> {
    const request = http.createHttp();
    try {
      const response = await request.request(`${BASE_URL}/favorites/batch-delete`, {
        method: http.RequestMethod.POST,
        header: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'Authorization': `Bearer ${token}`
        },
        extraData: JSON.stringify({ song_ids: songIds }),
        connectTimeout: 10000,
        readTimeout: 15000
      });

      return response.responseCode >= 200 && response.responseCode < 300;
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'batchDeleteFavorites error: %{public}s', JSON.stringify(err));
      return false;
    } finally {
      request.destroy();
    }
  }
}
