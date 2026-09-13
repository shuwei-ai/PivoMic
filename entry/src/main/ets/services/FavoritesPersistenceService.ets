import { fileIo } from '@kit.CoreFileKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { Song, MusicSourceMode } from '../domain/MusicModels';
import { AuthTokenResult } from './CloudAuthService';

const DOMAIN = 0x0000;
const TAG = 'PivoMicStorage';

export interface AppSettingsData {
  recordingDir?: string;
  customMusicServerUrl?: string;
  qqMusicApiKey?: string;
  musicSourceMode?: MusicSourceMode;
}

export class FavoritesPersistenceService {
  private static instance?: FavoritesPersistenceService;
  private favoritesPath: string = '';
  private localSongsPath: string = '';
  private historyPath: string = '';
  private searchHistoryPath: string = '';
  private settingsPath: string = '';
  private authPath: string = '';

  private constructor() {}

  static getInstance(): FavoritesPersistenceService {
    if (!FavoritesPersistenceService.instance) {
      FavoritesPersistenceService.instance = new FavoritesPersistenceService();
    }
    return FavoritesPersistenceService.instance;
  }

  init(filesDir: string): void {
    this.favoritesPath = `${filesDir}/pivomic_favorites.json`;
    this.localSongsPath = `${filesDir}/pivomic_local.json`;
    this.historyPath = `${filesDir}/pivomic_history.json`;
    this.searchHistoryPath = `${filesDir}/pivomic_search_history.json`;
    this.settingsPath = `${filesDir}/pivomic_settings.json`;
    this.authPath = `${filesDir}/pivomic_auth.json`;
  }

  loadAuthData(): AuthTokenResult | null {
    if (!this.authPath) return null;
    try {
      if (fileIo.accessSync(this.authPath)) {
        const text = fileIo.readTextSync(this.authPath);
        if (text && text.trim().length > 0) {
          const parsed = JSON.parse(text) as AuthTokenResult;
          if (parsed && parsed.access_token) {
            return parsed;
          }
        }
      }
    } catch (_) {}
    return null;
  }

  saveAuthData(data: AuthTokenResult | null): void {
    if (!this.authPath) return;
    try {
      if (!data) {
        if (fileIo.accessSync(this.authPath)) {
          fileIo.unlinkSync(this.authPath);
        }
        return;
      }
      const file = fileIo.openSync(this.authPath, fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC);
      fileIo.writeSync(file.fd, JSON.stringify(data));
      fileIo.closeSync(file.fd);
    } catch (_) {}
  }

  loadSettings(): AppSettingsData {
    if (!this.settingsPath) return {};
    try {
      if (fileIo.accessSync(this.settingsPath)) {
        const text = fileIo.readTextSync(this.settingsPath);
        if (text && text.trim().length > 0) {
          return JSON.parse(text) as AppSettingsData;
        }
      }
    } catch (_) {}
    return {};
  }

  saveSettings(settings: AppSettingsData): void {
    if (!this.settingsPath) return;
    try {
      const file = fileIo.openSync(this.settingsPath, fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC);
      fileIo.writeSync(file.fd, JSON.stringify(settings));
      fileIo.closeSync(file.fd);
    } catch (_) {}
  }

  loadRecordingDir(): string {
    const settings = this.loadSettings();
    return (settings && typeof settings.recordingDir === 'string') ? settings.recordingDir : '';
  }

  saveRecordingDir(dir: string): void {
    const settings = this.loadSettings();
    settings.recordingDir = dir;
    this.saveSettings(settings);
  }

  loadCustomMusicServerUrl(): string {
    const settings = this.loadSettings();
    return (settings && typeof settings.customMusicServerUrl === 'string') ? settings.customMusicServerUrl : '';
  }

  saveCustomMusicServerUrl(url: string): void {
    const settings = this.loadSettings();
    settings.customMusicServerUrl = url.trim();
    this.saveSettings(settings);
  }

  loadQQMusicApiKey(): string {
    const settings = this.loadSettings();
    return (settings && typeof settings.qqMusicApiKey === 'string') ? settings.qqMusicApiKey : '';
  }

  saveQQMusicApiKey(key: string): void {
    const settings = this.loadSettings();
    settings.qqMusicApiKey = key.trim();
    this.saveSettings(settings);
  }

  loadMusicSourceMode(): MusicSourceMode {
    const settings = this.loadSettings();
    if (settings && (settings.musicSourceMode === MusicSourceMode.LOCAL || `${settings.musicSourceMode}` === 'local')) {
      return MusicSourceMode.LOCAL;
    }
    return MusicSourceMode.ONLINE;
  }

  saveMusicSourceMode(mode: MusicSourceMode): void {
    const settings = this.loadSettings();
    settings.musicSourceMode = mode;
    this.saveSettings(settings);
  }

  loadFavorites(): Song[] {
    return this.loadSongList(this.favoritesPath, 'favorites');
  }

  saveFavorites(favorites: Song[]): void {
    this.saveSongList(this.favoritesPath, favorites, 'favorites');
  }

  loadLocalSongs(): Song[] {
    return this.loadSongList(this.localSongsPath, 'localSongs');
  }

  saveLocalSongs(songs: Song[]): void {
    this.saveSongList(this.localSongsPath, songs, 'localSongs');
  }

  loadPlayHistory(): Song[] {
    return this.loadSongList(this.historyPath, 'playHistory');
  }

  savePlayHistory(history: Song[]): void {
    this.saveSongList(this.historyPath, history, 'playHistory');
  }

  loadSearchHistory(): string[] {
    if (!this.searchHistoryPath) return [];
    try {
      if (fileIo.accessSync(this.searchHistoryPath)) {
        const text = fileIo.readTextSync(this.searchHistoryPath);
        if (text && text.trim().length > 0) {
          const parsed = JSON.parse(text) as string[];
          if (Array.isArray(parsed)) {
            hilog.info(DOMAIN, TAG, 'Loaded %{public}d search history items', parsed.length);
            return parsed.filter((item: string) => typeof item === 'string' && item.trim().length > 0);
          }
        }
      }
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'Failed to read search history file: %{public}s', JSON.stringify(err));
    }
    return [];
  }

  saveSearchHistory(history: string[]): void {
    if (!this.searchHistoryPath) return;
    try {
      const json = JSON.stringify(history);
      const file = fileIo.openSync(this.searchHistoryPath, fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC);
      fileIo.writeSync(file.fd, json);
      fileIo.closeSync(file.fd);
      hilog.info(DOMAIN, TAG, 'Successfully saved %{public}d search history items', history.length);
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'Failed to save search history file: %{public}s', JSON.stringify(err));
    }
  }

  private loadSongList(path: string, tag: string): Song[] {
    if (!path) return [];
    try {
      if (fileIo.accessSync(path)) {
        const text = fileIo.readTextSync(path);
        if (text && text.trim().length > 0) {
          const parsed = JSON.parse(text) as Song[];
          if (Array.isArray(parsed)) {
            hilog.info(DOMAIN, TAG, 'Loaded %{public}d items for %{public}s', parsed.length, tag);
            return parsed;
          }
        }
      }
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'Failed to read %{public}s file: %{public}s', tag, JSON.stringify(err));
    }
    return [];
  }

  private saveTimers: Map<string, number> = new Map();

  private saveSongList(path: string, list: Song[], tag: string): void {
    if (!path) return;
    const existingTimer = this.saveTimers.get(path);
    if (existingTimer !== undefined) {
      clearTimeout(existingTimer);
    }
    // 300ms 防抖合并持久化，消除频繁切歌/点赞时的主线程同步 I/O 掉帧
    const timerId = setTimeout(() => {
      this.saveTimers.delete(path);
      try {
        const json = JSON.stringify(list);
        const file = fileIo.openSync(path, fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC);
        fileIo.writeSync(file.fd, json);
        fileIo.closeSync(file.fd);
        hilog.info(DOMAIN, TAG, 'Successfully saved %{public}d items for %{public}s', list.length, tag);
      } catch (err) {
        hilog.error(DOMAIN, TAG, 'Failed to save %{public}s file: %{public}s', tag, JSON.stringify(err));
      }
    }, 300);
    this.saveTimers.set(path, timerId);
  }
}
