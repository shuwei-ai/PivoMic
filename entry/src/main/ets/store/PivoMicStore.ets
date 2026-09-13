import { SeparationService } from '../services/SeparationService';
import { AccompanimentAsset, SeparationSnapshot } from '../domain/AccompanimentModels';
import { resolvePlaybackSong } from '../audio/PlaybackAssetResolver';
import { SystemCacheFileStore } from '../audio/OnlineAudioCache';
import { fileIo, picker } from '@kit.CoreFileKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AudioCapability, LyricDocument, MusicSourceKind, MusicSourceMode, PlaybackSnapshot, PlaybackState, Song, RecommendPlaylist } from '../domain/MusicModels';
import { AudioCapabilityDetector } from '../audio/AudioCapabilityDetector';
import { AVPlayerEngine } from '../audio/AVPlayerEngine';
import { BackgroundTaskService } from '../audio/BackgroundTaskService';
import { AudioRouteMode, PitchScaleType, KaraokeSessionSnapshot } from '../audio/KaraokeSessionModels';
import { CachedAudioFile } from '../audio/OnlineAudioCache';
import { MicrophonePermissionStatus } from '../audio/MicrophonePermissionService';
import { findActiveLyricIndex, parseLrc } from '../services/LrcParser';
import { FileImportService } from '../services/FileImportService';
import { promptAction } from '@kit.ArkUI';
import { OnlineMusicSource, MusicServerTestResult, shuffleArray } from '../services/OnlineMusicSource';
import { FavoritesPersistenceService } from '../services/FavoritesPersistenceService';
import { CloudAuthService, UserInfo, AuthTokenResult } from '../services/CloudAuthService';
import { CloudFavoritesService } from '../services/CloudFavoritesService';
import { QQMusicSkillService, QQChartGroup } from '../services/QQMusicSkillService';
import { isValidArtist } from '../components/MusicRecommendationPage';
import { AppConfig } from '../config/AppConfig';
import { NativeMusicEngine } from '../services/NativeMusicEngine';

const AUDIO_DIAG_DOMAIN = 0x0000;
const AUDIO_DIAG_TAG = 'PivoMicAudioDiag';

export enum PlaybackQueueSource {
  RECOMMEND_OR_SEARCH = 'recommend_or_search',
  FAVORITES = 'favorites',
  LOCAL = 'local',
  HISTORY = 'history'
}

export interface KaraokePermissionPort { requestForKaraokeStart(): Promise<MicrophonePermissionStatus>; }
export interface KaraokeCachePort {
  prepare(song: Song): Promise<CachedAudioFile>;
  cancelPending(): void;
  getCachedFilePath?(song: Song): string | undefined;
  preload?(song: Song, protectedPaths?: string[] | string): Promise<boolean>;
  trimCacheToLimit?(maxCount?: number, maxBytes?: number, protectedPaths?: string[] | string): void;
}
export interface KaraokeSafetyPort { evaluate(aecSupported: boolean): string; routeLabel(): string; safeOutputConnected(): boolean; detectAudioRouteMode?(): AudioRouteMode; }
export interface KaraokeEnginePort {
  prepare(fd: number, offset: number, size: number, durationMs: number): void;
  start(): void;
  pause(): void;
  seek(positionMs: number): void;
  stop(): void;
  release(): void;
  setSafeOutputConnected(value: boolean): void;
  setAudioRoute?(route: number): void;
  setAccompanimentGain(value: number): void;
  setVocalGain(value: number): void;
  setReverbMix(value: number): void;
  setAccompanimentPitchShift?(semitones: number): void;
  setPitchCorrection?(enabled: boolean, strength: number, scaleType: number, rootNote: number): void;
  startRecording?(): void;
  stopRecording?(): void;
  exportRecording?(outputPath: string): boolean;
  getSnapshot(): KaraokeSessionSnapshot;
}
export interface KaraokeEngineProvider { acquire(): KaraokeEnginePort; }
export interface KaraokePreviewPort {
  load(song: Song, autoPlay: boolean, initialSeekMs?: number): Promise<void>;
  play?(): Promise<void>;
  pause?(): Promise<void>;
  release(): Promise<void>;
  seek?(positionMs: number): void;
  getSnapshot?(): PlaybackSnapshot;
  onStateChanged?: (state: PlaybackState, snapshot: PlaybackSnapshot) => void;
  onTimeUpdated?: (positionMs: number) => void;
}
export interface KaraokeRouteMonitorPort { subscribe(listener: () => void): void; unsubscribe(): void; }

function idleSession(): KaraokeSessionSnapshot {
  return {
    state: 'idle',
    positionMs: 0,
    durationMs: 0,
    microphonePeak: 0,
    latencyMs: 0,
    underrunCount: 0,
    fastMode: false,
    aecSupported: false,
    audioRoute: 0,
    accompanimentPitchShift: 0,
    pitchCorrectionEnabled: false,
    pitchCorrectionStrength: 0,
    isRecording: false,
    recordedDurationMs: 0,
    errorCode: 0,
    errorMessage: ''
  };
}

export function isLocalSong(song?: Song): boolean {
  if (!song) return false;
  if (song.source === MusicSourceKind.LOCAL) return true;
  if (song.uri && (song.uri.startsWith('/') || song.uri.startsWith('file://'))) return true;
  return false;
}

export function checkLocalSongFileExists(song?: Song): boolean {
  if (!song || !song.uri) return false;
  try {
    const rawPath = song.uri.startsWith('file://') ? song.uri.substring(7) : song.uri;
    return fileIo.accessSync(rawPath);
  } catch (_) {
    return false;
  }
}

export const DEFAULT_FIGMA_SONGS: Song[] = [
  {
    id: 'figma-1',
    title: '白鸽',
    artist: '你的上好佳',
    uri: '',
    durationMs: 218000,
    format: 'SQ',
    source: MusicSourceKind.DEMO,
    lyricText: '[00:00.00]白鸽 - 你的上好佳\n[00:02.00]作词：你的上好佳\n[00:04.00]作曲：你的上好佳\n[00:15.00]像一只白鸽飞过蓝天\n[00:22.00]掠过那曾经熟悉的从前\n[00:30.00]我们在风中慢慢走远\n[00:38.00]有些思念还在心底蔓延\n[00:46.00]白鸽啊 请你带走我的眷恋\n[00:54.00]飞向那没有终点的海平线\n[01:02.00]就算回忆总会有些残缺\n[01:10.00]也感谢有你路过我的世界\n[01:25.00]像一只白鸽飞过蓝天\n[01:33.00]掠过那曾经熟悉的从前\n[01:41.00]我们在风中慢慢走远\n[01:50.00]有些思念还在心底蔓延'
  },
  {
    id: 'figma-2',
    title: '下一页的我',
    artist: '林小珂',
    uri: '',
    durationMs: 196000,
    format: 'SQ',
    source: MusicSourceKind.DEMO,
    lyricText: '[00:00.00]下一页的我 - 林小珂\n[00:10.00]翻开新的这一页 迎接明天的风\n[00:20.00]下一页的我 会更加坚定从容'
  },
  {
    id: 'figma-3',
    title: '有些人错过就不再',
    artist: '周林枫',
    uri: '',
    durationMs: 242000,
    format: 'SQ',
    source: MusicSourceKind.DEMO,
    lyricText: '[00:00.00]有些人错过就不再 - 周林枫\n[00:12.00]有些人一旦错过就不在\n[00:24.00]有些梦一旦醒来便成海'
  },
  {
    id: 'figma-4',
    title: '那年那天',
    artist: '李美灵菌',
    uri: '',
    durationMs: 205000,
    format: 'SQ',
    source: MusicSourceKind.DEMO,
    lyricText: '[00:00.00]那年那天 - 李美灵菌\n[00:10.00]那年那天 阳光洒落在你的侧脸\n[00:20.00]定格成了我心中永远的画面'
  },
  {
    id: 'figma-5',
    title: '下一个雨天',
    artist: '林小珂',
    uri: '',
    durationMs: 188000,
    format: 'SQ',
    source: MusicSourceKind.DEMO,
    lyricText: '[00:00.00]下一个雨天 - 林小珂\n[00:10.00]等待下一个雨天\n[00:20.00]撑开伞走过熟悉的街'
  }
];

export const DEFAULT_FIGMA_PLAYLISTS: RecommendPlaylist[] = [
  { id: 'pl-1', source: 'local', name: '精选流行伴奏', creator: 'PivoMic', coverUrl: '', trackCount: 10 },
  { id: 'pl-2', source: 'local', name: '经典国风戏腔', creator: 'PivoMic', coverUrl: '', trackCount: 12 },
  { id: 'pl-3', source: 'local', name: '治愈系民谣', creator: 'PivoMic', coverUrl: '', trackCount: 8 },
  { id: 'pl-4', source: 'local', name: '怀旧金曲榜', creator: 'PivoMic', coverUrl: '', trackCount: 15 },
  { id: 'pl-5', source: 'local', name: '热唱 K 歌榜', creator: 'PivoMic', coverUrl: '', trackCount: 20 }
];

@Observed
export class PivoMicStore {
  separation?: SeparationService;
  separationSnapshot: SeparationSnapshot = { assets: [], model: { phase: 'missing', progress: 0, errorMessage: '' }, job: { phase: 'idle', progress: 0, errorMessage: '', songId: '' }, busy: false };
  activeAccompanimentId: string = '';
  trackSwitchPending: boolean = false;
  private releaseAssetPin?: () => void;
  private separationUnsubscribe?: () => void;
  private trackRevision: number = 0;

  configureSeparation(service: SeparationService): void {
    this.separationUnsubscribe?.(); this.separation = service;
    this.separationUnsubscribe = service.subscribe((snapshot: SeparationSnapshot): void => { this.separationSnapshot = snapshot; });
  }
  private activeAsset(): AccompanimentAsset | undefined {
    if (!this.activeAccompanimentId) return undefined;
    const asset = this.separation?.getAsset(this.activeAccompanimentId);
    if (!asset) throw new Error('AI 伴奏已丢失，请选择原曲');
    return asset;
  }
  private async loadSelectedPreview(song: Song, autoPlay: boolean = false, positionMs: number = 0): Promise<void> {
    await this.preview.load(resolvePlaybackSong(song, this.activeAsset()), autoPlay, positionMs);
  }
  private async prepareSelectedAudio(song: Song): Promise<CachedAudioFile> {
    const asset = this.activeAsset();
    if (asset) return new SystemCacheFileStore().openReadOnly(resolvePlaybackSong(song, asset).uri);
    if (!this.cache) throw new Error('音频缓存尚未初始化');
    return this.cache.prepare(song);
  }
  async generateAccompaniment(): Promise<void> {
    if (!this.selectedSong || !this.separation) return;
    if (this.isRecording) { this.statusMessage = '停止录音后才能生成伴奏'; return; }
    if (this.micEnabled) await this.toggleMicrophone();
    const song = this.selectedSong;
    try {
      const resolved = await this.resolveSongStreamSilently(song);
      await this.separation.generate(resolved);
    } catch (error) { this.statusMessage = this.errorText(error, '伴奏生成失败'); }
  }
  async switchAudioTrack(assetId: string, play: boolean = false): Promise<void> {
    if (this.isRecording || this.trackSwitchPending || !this.selectedSong) return;
    const service = this.separation;
    const next = assetId ? service?.getAsset(assetId) : undefined;
    if (assetId && !next) { this.statusMessage = '请先生成伴奏'; return; }
    const song = this.selectedSong;
    try { resolvePlaybackSong(song, next); } catch (error) { this.statusMessage = this.errorText(error, '伴奏不可用'); return; }
    const revision = ++this.trackRevision;
    const oldId = this.activeAccompanimentId;
    const oldPin = this.releaseAssetPin;
    const nextPin = assetId ? service?.pinAsset(assetId) : undefined;
    const position = this.playback.positionMs;
    const playing = play || this.playback.state === PlaybackState.PLAYING;
    this.trackSwitchPending = true;
    this.activeAccompanimentId = assetId;
    try {
      this.closeKaraokeSession();
      await this.preview.release();
      if (revision !== this.trackRevision) return;
      if (this.micEnabled) {
        await this.startKaraoke(position);
        if (this.session.state === 'error') throw new Error(this.session.errorMessage);
        if (!playing) await this.pausePlayback();
      } else await this.loadSelectedPreview(song, playing, position);
      if (revision !== this.trackRevision) return;
      oldPin?.(); this.releaseAssetPin = nextPin;
      this.statusMessage = assetId ? '正在使用 AI 伴奏' : '正在使用原曲';
      this.syncPlayback();
    } catch (error) {
      if (revision === this.trackRevision) {
        this.activeAccompanimentId = oldId;
        this.closeKaraokeSession();
        try {
          if (this.micEnabled) { await this.startKaraoke(position); if (!playing) await this.pausePlayback(); }
          else await this.loadSelectedPreview(song, playing, position);
        } catch (_) {}
        this.statusMessage = this.errorText(error, '切换失败，已恢复之前音轨');
      }
    } finally {
      if (this.releaseAssetPin !== nextPin) nextPin?.();
      if (revision === this.trackRevision) this.trackSwitchPending = false;
    }
  }
  async playAccompaniment(asset: AccompanimentAsset): Promise<void> {
    if (this.isRecording) { this.statusMessage = '请先停止录音'; return; }
    await this.selectSong(asset.song, false);
    await this.switchAudioTrack(asset.id, true);
  }
  async exportAccompaniment(asset: AccompanimentAsset): Promise<void> {
    const unpin = this.separation?.pinAsset(asset.id);
    try { await this.exportSongToSystem(resolvePlaybackSong(asset.song, asset)); }
    finally { unpin?.(); }
  }
  deleteAccompaniment(assetId: string): void {
    try {
      this.separation?.deleteAsset(assetId);
      this.statusMessage = '伴奏已删除，原曲保留';
    } catch (error) {
      this.statusMessage = (error as Error).message;
    }
  }
  songs: Song[] = [];
  selectedSong?: Song = undefined;
  lyrics: LyricDocument = parseLrc('');
  favorites: Song[] = [];
  localSongs: Song[] = [];
  playHistory: Song[] = [];
  recommendPlaylists: RecommendPlaylist[] = [];
  selectedPlaylist?: RecommendPlaylist = undefined;
  isLoadingRecommend: boolean = false;
  recommendHasMore: boolean = false;
  recommendCurrentPage: number = 0;
  recommendCurrentKind: string = '';
  recommendCurrentRawId: number = 0;
  isLoadingMoreRecommend: boolean = false;
  playbackQueueSource: PlaybackQueueSource = PlaybackQueueSource.RECOMMEND_OR_SEARCH;
  playbackQueue: Song[] = [];
  playback: PlaybackSnapshot = { state: PlaybackState.IDLE, positionMs: 0, durationMs: 0, bufferedPositionMs: 0, volume: 0.8, pitchSemitones: 0, errorMessage: '' };
  session: KaraokeSessionSnapshot = idleSession(); capability: AudioCapability = new AudioCapabilityDetector().detectForAVPlayer();
  activeLyricIndex: number = -1; statusMessage: string = '正在初始化音乐曲库…'; searchKeyword: string = ''; isSearching: boolean = false;
  selectedSearchSource: string = 'all'; searchPage: number = 1; isSearchingMore: boolean = false; hasMoreSearchResults: boolean = true;
  searchHistory: string[] = [];
  accompanimentGain: number = 0.8; vocalGain: number = 0.8; reverbMix: number = 0.25;
  audioRoute: AudioRouteMode = AudioRouteMode.Speaker;
  pitchShiftSemitones: number = 0;
  autoTuneActive: boolean = false;
  autoTuneStrength: number = 0.5;
  autoTuneScale: PitchScaleType = PitchScaleType.Chromatic;
  isRecording: boolean = false;
  recordedDurationMs: number = 0;
  private recordingStartMs: number = 0; // 录音开始时原曲的播放位置，用于歌词偏移对齐
  isHeadsetConnected: boolean = false;
  monitoringAllowed: boolean = false; blockedReason: string = ''; outputRouteLabel: string = '未检测';
  isStartPending: boolean = false;
  micEnabled: boolean = false;
  filesDir: string = '';
  recordingDir: string = '';
  musicSourceMode: MusicSourceMode = MusicSourceMode.ONLINE;
  customMusicServerUrl: string = '';
  qqMusicApiKey: string = '';
  qqChartGroups: QQChartGroup[] = [];
  selectedRecommendTab: string = 'daily';
  private qqSkillService: QQMusicSkillService = new QQMusicSkillService();
  currentUser: UserInfo | null = null;
  authToken: string = '';
  isCloudLoggedIn: boolean = false;
  isSyncingCloud: boolean = false;
  cloudSyncStatusText: string = '未登录云端账号';
  currentQueueIndex: number = 0;
  onSongChanged?: (song: Song, index: number) => void;
  onFavoritesChanged?: () => void;
  onProgressUpdate?: (positionMs: number, activeIndex: number, snapshot: PlaybackSnapshot) => void;
  private progressListeners: Array<(positionMs: number, activeIndex: number, snapshot: PlaybackSnapshot) => void> = [];
  private isAppForeground: boolean = true;
  private wasPlayingBeforeInterrupt: boolean = false;
  private interruptTimeMs: number = 0;

  isSongMatch(a: Song | undefined, b: Song | undefined): boolean {
    if (!a || !b) return false;
    if (a.id && b.id && a.id === b.id) return true;
    if (a.remoteId && b.remoteId && a.remoteId === b.remoteId) return true;
    const aTitle = (a.title || '').trim().toLowerCase();
    const bTitle = (b.title || '').trim().toLowerCase();
    if (aTitle.length > 0 && aTitle === bTitle) {
      const aArtist = (a.artist || '').trim().toLowerCase();
      const bArtist = (b.artist || '').trim().toLowerCase();
      if (aArtist.length === 0 || bArtist.length === 0 || aArtist === bArtist) {
        return true;
      }
    }
    return false;
  }

  findSongIndexInQueue(song: Song | undefined, queue: Song[]): number {
    if (!song || !queue || queue.length === 0) return -1;
    // 1. 优先严格 ID 匹配
    const idIdx = queue.findIndex((s: Song) => s.id === song.id);
    if (idIdx >= 0) return idIdx;

    // 2. 其次 remoteId 匹配
    if (song.remoteId && song.remoteId.length > 0) {
      const remoteIdx = queue.findIndex((s: Song) => s.remoteId === song.remoteId);
      if (remoteIdx >= 0) return remoteIdx;
    }

    // 3. 歌名与歌手多维匹配
    const targetTitle = (song.title || '').trim().toLowerCase();
    const targetArtist = (song.artist || '').trim().toLowerCase();
    if (targetTitle.length > 0) {
      const metaIdx = queue.findIndex((s: Song) => {
        const sTitle = (s.title || '').trim().toLowerCase();
        if (sTitle === targetTitle) {
          const sArtist = (s.artist || '').trim().toLowerCase();
          if (targetArtist.length === 0 || sArtist.length === 0 || sArtist === targetArtist) {
            return true;
          }
        }
        return false;
      });
      if (metaIdx >= 0) return metaIdx;
    }

    return -1;
  }

  addProgressListener(listener: (positionMs: number, activeIndex: number, snapshot: PlaybackSnapshot) => void): void {
    if (this.progressListeners.indexOf(listener) < 0) {
      this.progressListeners.push(listener);
    }
  }

  removeProgressListener(listener: (positionMs: number, activeIndex: number, snapshot: PlaybackSnapshot) => void): void {
    const idx = this.progressListeners.indexOf(listener);
    if (idx >= 0) {
      this.progressListeners.splice(idx, 1);
    }
  }

  private lyricsListeners: ((lyrics: LyricDocument) => void)[] = [];

  addLyricsListener(listener: (lyrics: LyricDocument) => void): void {
    if (this.lyricsListeners.indexOf(listener) < 0) {
      this.lyricsListeners.push(listener);
    }
  }

  removeLyricsListener(listener: (lyrics: LyricDocument) => void): void {
    const idx = this.lyricsListeners.indexOf(listener);
    if (idx >= 0) {
      this.lyricsListeners.splice(idx, 1);
    }
  }

  notifyLyricsUpdate(lyrics: LyricDocument): void {
    for (let i = 0; i < this.lyricsListeners.length; i++) {
      try {
        this.lyricsListeners[i](lyrics);
      } catch (_) {}
    }
  }

  private notifyProgressUpdate(positionMs: number, activeIndex: number, snapshot: PlaybackSnapshot): void {
    // AVPlayer continues emitting progress while the app is backgrounded. Keep
    // the playback model current, but do not enqueue ArkUI state mutations for
    // frozen components. Foreground recovery publishes one latest snapshot.
    if (!this.isAppForeground) return;
    if (this.onProgressUpdate) {
      this.onProgressUpdate(positionMs, activeIndex, snapshot);
    }
    for (let i = 0; i < this.progressListeners.length; i++) {
      this.progressListeners[i](positionMs, activeIndex, snapshot);
    }
  }

  private karaokeTimerId: number = -1;
  private lastTogglePlaybackTimestamp: number = 0;
  private isSwitchingSong: boolean = false;
  private lastSwitchSongTimestamp: number = 0;

  private startKaraokePolling(): void {
    this.stopKaraokePolling();
    this.karaokeTimerId = setInterval(() => {
      if (this.engine !== undefined && this.session.state === 'singing') {
        this.pollNativeSnapshot();
      } else {
        this.stopKaraokePolling();
      }
    }, 100);
  }

  private stopKaraokePolling(): void {
    if (this.karaokeTimerId >= 0) {
      clearInterval(this.karaokeTimerId);
      this.karaokeTimerId = -1;
    }
  }

  getActiveQueue(): Song[] {
    if (this.playbackQueue && this.playbackQueue.length > 0) {
      return this.playbackQueue;
    }
    if (this.playbackQueueSource === PlaybackQueueSource.FAVORITES) {
      if (this.favorites.length > 0) return this.favorites;
    } else if (this.playbackQueueSource === PlaybackQueueSource.LOCAL) {
      if (this.localSongs.length > 0) return this.localSongs;
    } else if (this.playbackQueueSource === PlaybackQueueSource.HISTORY) {
      if (this.playHistory.length > 0) return this.playHistory;
    }
    return this.songs;
  }

  initFavoritesStorage(filesDir: string): void {
    this.filesDir = filesDir;
    FavoritesPersistenceService.getInstance().init(filesDir);
    const savedRecDir = FavoritesPersistenceService.getInstance().loadRecordingDir();
    this.recordingDir = (savedRecDir && savedRecDir.length > 0) ? savedRecDir : `${filesDir}/recordings`;

    const savedServerUrl = FavoritesPersistenceService.getInstance().loadCustomMusicServerUrl();
    this.customMusicServerUrl = savedServerUrl || '';
    AppConfig.setOnlineMusicServiceOrigin(this.customMusicServerUrl);

    this.musicSourceMode = FavoritesPersistenceService.getInstance().loadMusicSourceMode();

    const savedQQKey = FavoritesPersistenceService.getInstance().loadQQMusicApiKey();
    this.qqMusicApiKey = savedQQKey || AppConfig.getQQMusicApiKey();
    AppConfig.setQQMusicApiKey(this.qqMusicApiKey);

    const savedFav = FavoritesPersistenceService.getInstance().loadFavorites();
    if (savedFav && savedFav.length > 0) {
      this.favorites = savedFav;
    }
    const savedLocal = FavoritesPersistenceService.getInstance().loadLocalSongs();
    if (savedLocal && savedLocal.length > 0) {
      this.localSongs = savedLocal;
      for (const s of savedLocal) {
        if (!this.songs.some((item: Song) => item.uri === s.uri)) {
          this.songs.push(s);
        }
      }
    }
    const savedHistory = FavoritesPersistenceService.getInstance().loadPlayHistory();
    if (savedHistory && savedHistory.length > 0) {
      this.playHistory = savedHistory;
    }
    const savedSearchHistory = FavoritesPersistenceService.getInstance().loadSearchHistory();
    if (savedSearchHistory && savedSearchHistory.length > 0) {
      this.searchHistory = savedSearchHistory;
    }

    const savedAuth = FavoritesPersistenceService.getInstance().loadAuthData();
    if (savedAuth && savedAuth.access_token) {
      this.authToken = savedAuth.access_token;
      this.currentUser = savedAuth.user;
      this.isCloudLoggedIn = true;
      this.cloudSyncStatusText = `已登录: ${savedAuth.user.nickname || savedAuth.user.username}`;
      this.syncFavoritesWithCloud(false);
    }
  }

  async selectRecordingDirectory(): Promise<void> {
    try {
      const picker = new FileImportService();
      const uri = await picker.pickSaveDirectory();
      if (uri && uri.length > 0) {
        this.updateRecordingDirectory(uri);
      }
    } catch (_) {
      this.statusMessage = '选择目录已取消';
    }
  }

  updateRecordingDirectory(pathOrName: string): void {
    if (!pathOrName || pathOrName.trim().length === 0) {
      this.resetRecordingDirectory();
      return;
    }
    let raw = pathOrName.trim();
    let folderName = raw;
    if (raw.startsWith('file://docs/storage/') || raw.startsWith('/docs/storage/')) {
      const parts = raw.split('/');
      folderName = parts[parts.length - 1] || 'Sounds';
    } else if (raw.startsWith('file://')) {
      raw = raw.substring(7);
      folderName = raw;
    }

    let targetPath = folderName;
    if (!targetPath.startsWith('/data/')) {
      targetPath = `${this.filesDir}/${folderName.replace(/^\/+/, '')}`;
    }

    try {
      if (!fileIo.accessSync(targetPath)) {
        fileIo.mkdirSync(targetPath);
      }
    } catch (_) {}

    this.recordingDir = targetPath;
    FavoritesPersistenceService.getInstance().saveRecordingDir(targetPath);
    this.statusMessage = `已成功设置录音保存目录：${targetPath}`;
  }

  resetRecordingDirectory(): void {
    if (this.filesDir && this.filesDir.length > 0) {
      this.recordingDir = `${this.filesDir}/recordings`;
      FavoritesPersistenceService.getInstance().saveRecordingDir('');
      this.statusMessage = '已恢复默认沙箱录音存储路径';
    }
  }

  async updateCustomMusicServerUrl(url: string): Promise<boolean> {
    let clean = url.trim();
    if (clean.length > 0 && !clean.startsWith('http://') && !clean.startsWith('https://')) {
      clean = `https://${clean}`;
    }
    if (clean.endsWith('/')) {
      clean = clean.substring(0, clean.length - 1);
    }
    this.customMusicServerUrl = clean;
    this.unplayableSongIds.clear();
    FavoritesPersistenceService.getInstance().saveCustomMusicServerUrl(clean);
    AppConfig.setOnlineMusicServiceOrigin(clean);

    if (this.isCloudLoggedIn && this.authToken) {
      CloudFavoritesService.getInstance().updateUserSettings(this.authToken, {
        custom_music_server_url: clean
      });
    }

    if (clean.length > 0) {
      this.statusMessage = `已连接自定义音乐服务: ${clean}`;
      await this.loadDailyRecommendations();
    } else {
      this.recommendPlaylists = [];
      this.selectedPlaylist = undefined;
      this.songs = [...this.localSongs];
      this.statusMessage = '已清除自定义音乐服务地址';
    }
    return true;
  }

  async updateMusicSourceMode(mode: MusicSourceMode): Promise<void> {
    this.musicSourceMode = mode;
    FavoritesPersistenceService.getInstance().saveMusicSourceMode(mode);
    this.unplayableSongIds.clear();
    this.failedSourceMap.clear();

    if (mode === MusicSourceMode.ONLINE) {
      this.statusMessage = '已切换为原生全网源 (5大平台直连 · 320k 智能换源)';
      await this.loadDailyRecommendations();
    } else {
      this.recommendPlaylists = [];
      this.selectedPlaylist = undefined;
      this.songs = [...this.localSongs];
      this.statusMessage = '已切换为纯本地模式 (仅使用本地曲库)';
    }
  }

  async testEngineConnection(): Promise<MusicServerTestResult> {
    const res = await NativeMusicEngine.getInstance().testEngine();
    const testResult: MusicServerTestResult = {
      success: res.success,
      message: res.message,
      statusCode: res.statusCode
    };
    return testResult;
  }

  async testHuibqConnection(): Promise<MusicServerTestResult> {
    return this.testEngineConnection();
  }

  async updateQQMusicApiKey(key: string): Promise<boolean> {
    const clean = key.trim();
    this.qqMusicApiKey = clean;
    FavoritesPersistenceService.getInstance().saveQQMusicApiKey(clean);
    AppConfig.setQQMusicApiKey(clean);

    if (this.isCloudLoggedIn && this.authToken) {
      CloudFavoritesService.getInstance().updateUserSettings(this.authToken, {
        qq_music_api_key: clean
      });
    }

    if (clean.length > 0) {
      this.statusMessage = '已保存 QQ 音乐 Skill API Key';
      await this.loadDailyRecommendations();
    } else {
      this.statusMessage = '已清空 QQ 音乐 Skill API Key';
      await this.loadDailyRecommendations();
    }
    return true;
  }

  async clearQQMusicApiKey(): Promise<void> {
    await this.updateQQMusicApiKey('');
  }

  async clearCustomMusicServerUrl(): Promise<void> {
    await this.updateCustomMusicServerUrl('');
  }

  async testMusicServerConnection(url: string): Promise<MusicServerTestResult> {
    return await this.onlineSource.testConnection(url);
  }

  isSongFavorite(song?: Song): boolean {
    if (!song) return false;
    const songTitle = (song.title || '').trim().toLowerCase();
    const songArtist = (song.artist || '').trim().toLowerCase();
    return this.favorites.some((item: Song) => {
      if (item.id === song.id) return true;
      if (songTitle.length > 0 && item.title.trim().toLowerCase() === songTitle) {
        const itemArtist = (item.artist || '').trim().toLowerCase();
        if (songArtist.length === 0 || itemArtist.length === 0 || itemArtist === songArtist) {
          return true;
        }
      }
      return false;
    });
  }

  isFavorite(songId: string, song?: Song): boolean {
    if (song) return this.isSongFavorite(song);
    if (!songId) return false;
    return this.favorites.some((item: Song) => item.id === songId);
  }

  toggleFavorite(song: Song): void {
    const songTitle = (song.title || '').trim().toLowerCase();
    const songArtist = (song.artist || '').trim().toLowerCase();
    const index = this.favorites.findIndex((item: Song) => {
      if (item.id === song.id) return true;
      if (songTitle.length > 0 && item.title.trim().toLowerCase() === songTitle) {
        const itemArtist = (item.artist || '').trim().toLowerCase();
        if (songArtist.length === 0 || itemArtist.length === 0 || itemArtist === songArtist) {
          return true;
        }
      }
      return false;
    });

    if (index >= 0) {
      this.favorites.splice(index, 1);
      this.statusMessage = `已取消收藏《${song.title}》`;
    } else {
      this.favorites.unshift(song);
      this.statusMessage = `已收藏《${song.title}》到“我的”`;
    }
    FavoritesPersistenceService.getInstance().saveFavorites(this.favorites);

    const isCurrentSong = this.selectedSong !== undefined && (this.selectedSong.id === song.id ||
      (this.selectedSong.title === song.title && this.selectedSong.artist === song.artist));
    if (isCurrentSong) {
      BackgroundTaskService.getInstance().updateFavoriteStatus(index < 0);
    }

    if (this.onFavoritesChanged) {
      this.onFavoritesChanged();
    }

    if (this.isCloudLoggedIn && this.authToken) {
      if (index >= 0) {
        CloudFavoritesService.getInstance().deleteFavorite(this.authToken, song.id).then((ok: boolean) => {
          if (ok) {
            this.cloudSyncStatusText = `云端已同步 (已移除《${song.title}》)`;
          }
        });
      } else {
        CloudFavoritesService.getInstance().addFavorite(this.authToken, song).then((ok: boolean) => {
          if (ok) {
            this.cloudSyncStatusText = `云端已同步 (已收藏《${song.title}》)`;
          }
        });
      }
    }
  }

  addFavoriteOnly(song: Song): boolean {
    if (this.isSongFavorite(song)) {
      return false;
    }
    this.toggleFavorite(song);
    return true;
  }

  async loginCloudAccount(username: string, password: string): Promise<boolean> {
    this.isSyncingCloud = true;
    this.cloudSyncStatusText = '正在登录云端账号…';
    const res = await CloudAuthService.getInstance().login(username, password);
    this.isSyncingCloud = false;
    if (res.success && res.data) {
      this.authToken = res.data.access_token;
      this.currentUser = res.data.user;
      this.isCloudLoggedIn = true;
      FavoritesPersistenceService.getInstance().saveAuthData(res.data);
      this.cloudSyncStatusText = `欢迎回来，${res.data.user.nickname || res.data.user.username}`;
      this.statusMessage = `🎉 登录成功，欢迎 ${res.data.user.nickname || res.data.user.username}`;

      if (res.data.user.custom_music_server_url && res.data.user.custom_music_server_url.trim().length > 0 && !this.customMusicServerUrl) {
        const cloudUrl = res.data.user.custom_music_server_url.trim();
        this.customMusicServerUrl = cloudUrl;
        FavoritesPersistenceService.getInstance().saveCustomMusicServerUrl(cloudUrl);
        AppConfig.setOnlineMusicServiceOrigin(cloudUrl);
      }

      if (res.data.user.qq_music_api_key && res.data.user.qq_music_api_key.trim().length > 0 && !this.qqMusicApiKey) {
        const cloudKey = res.data.user.qq_music_api_key.trim();
        this.qqMusicApiKey = cloudKey;
        FavoritesPersistenceService.getInstance().saveQQMusicApiKey(cloudKey);
        AppConfig.setQQMusicApiKey(cloudKey);
      }

      this.favorites = [];
      await this.syncFavoritesWithCloud(true);
      return true;
    } else {
      this.cloudSyncStatusText = res.message || '登录失败';
      this.statusMessage = `登录失败: ${res.message || '用户名或密码错误'}`;
      return false;
    }
  }

  async registerCloudAccount(username: string, password: string, nickname?: string): Promise<boolean> {
    this.isSyncingCloud = true;
    this.cloudSyncStatusText = '正在注册云端账号…';
    const res = await CloudAuthService.getInstance().register(username, password, nickname);
    this.isSyncingCloud = false;
    if (res.success && res.data) {
      this.authToken = res.data.access_token;
      this.currentUser = res.data.user;
      this.isCloudLoggedIn = true;
      FavoritesPersistenceService.getInstance().saveAuthData(res.data);
      this.cloudSyncStatusText = `注册成功，欢迎 ${res.data.user.nickname || res.data.user.username}`;
      this.statusMessage = `🎉 注册成功，欢迎 ${res.data.user.nickname || res.data.user.username}`;
      this.favorites = [];
      await this.syncFavoritesWithCloud(true);
      return true;
    } else {
      this.cloudSyncStatusText = res.message || '注册失败';
      this.statusMessage = `注册失败: ${res.message || '请重试'}`;
      return false;
    }
  }

  async applyWeChatLogin(token: string, user?: UserInfo): Promise<boolean> {
    if (!token) {
      return false;
    }
    this.authToken = token;
    if (user) {
      this.currentUser = user;
    } else {
      const defaultUser: UserInfo = {
        id: 'wx_user',
        username: '微信用户',
        nickname: '微信用户'
      };
      this.currentUser = defaultUser;
    }
    this.isCloudLoggedIn = true;
    const authData: AuthTokenResult = {
      access_token: token,
      token_type: 'bearer',
      expires_in_days: 30,
      user: this.currentUser
    };
    FavoritesPersistenceService.getInstance().saveAuthData(authData);
    this.cloudSyncStatusText = `欢迎回来，${this.currentUser.nickname || this.currentUser.username}`;
    this.statusMessage = `🎉 微信登录成功，欢迎 ${this.currentUser.nickname || this.currentUser.username}`;

    if (this.currentUser.custom_music_server_url && this.currentUser.custom_music_server_url.trim().length > 0 && !this.customMusicServerUrl) {
      const cloudUrl = this.currentUser.custom_music_server_url.trim();
      this.customMusicServerUrl = cloudUrl;
      FavoritesPersistenceService.getInstance().saveCustomMusicServerUrl(cloudUrl);
      AppConfig.setOnlineMusicServiceOrigin(cloudUrl);
    }

    if (this.currentUser.qq_music_api_key && this.currentUser.qq_music_api_key.trim().length > 0 && !this.qqMusicApiKey) {
      const cloudKey = this.currentUser.qq_music_api_key.trim();
      this.qqMusicApiKey = cloudKey;
      FavoritesPersistenceService.getInstance().saveQQMusicApiKey(cloudKey);
      AppConfig.setQQMusicApiKey(cloudKey);
    }

    this.favorites = [];
    await this.syncFavoritesWithCloud(true);
    return true;
  }

  logoutCloudAccount(): void {
    this.authToken = '';
    this.currentUser = null;
    this.isCloudLoggedIn = false;
    this.favorites = [];
    this.cloudSyncStatusText = '未登录云端账号';
    FavoritesPersistenceService.getInstance().saveAuthData(null);
    FavoritesPersistenceService.getInstance().saveFavorites([]);
    this.statusMessage = '已退出云端账号';
  }

  async syncFavoritesWithCloud(showToast: boolean = true): Promise<void> {
    if (!this.isCloudLoggedIn || !this.authToken) return;
    this.isSyncingCloud = true;
    this.cloudSyncStatusText = '正在与云端同步收藏…';
    try {
      const syncResult = await CloudFavoritesService.getInstance().syncFavorites(
        this.authToken,
        this.favorites,
        this.customMusicServerUrl,
        this.qqMusicApiKey
      );
      const mergedList = syncResult.favorites;
      if (mergedList && mergedList.length > 0) {
        this.favorites = mergedList;
        FavoritesPersistenceService.getInstance().saveFavorites(this.favorites);
        this.cloudSyncStatusText = `云端同步完成 (${mergedList.length} 首)`;
        if (showToast) {
          this.statusMessage = `☁️ 云端收藏已同步 (${mergedList.length} 首)`;
        }
      } else {
        this.cloudSyncStatusText = '云端同步完成';
      }

      if (syncResult.custom_music_server_url && syncResult.custom_music_server_url.trim().length > 0) {
        const cloudUrl = syncResult.custom_music_server_url.trim();
        if (cloudUrl !== this.customMusicServerUrl) {
          this.customMusicServerUrl = cloudUrl;
          FavoritesPersistenceService.getInstance().saveCustomMusicServerUrl(cloudUrl);
          AppConfig.setOnlineMusicServiceOrigin(cloudUrl);
          await this.loadDailyRecommendations();
        }
      }

      if (syncResult.qq_music_api_key && syncResult.qq_music_api_key.trim().length > 0) {
        const cloudKey = syncResult.qq_music_api_key.trim();
        if (cloudKey !== this.qqMusicApiKey) {
          this.qqMusicApiKey = cloudKey;
          FavoritesPersistenceService.getInstance().saveQQMusicApiKey(cloudKey);
          AppConfig.setQQMusicApiKey(cloudKey);
          await this.loadDailyRecommendations();
        }
      }
    } catch (_) {
      this.cloudSyncStatusText = '云端同步失败，请检查网络';
    } finally {
      this.isSyncingCloud = false;
    }
  }

  recordPlayHistory(song: Song): void {
    const idx = this.playHistory.findIndex((item: Song) => item.id === song.id);
    if (idx >= 0) {
      this.playHistory.splice(idx, 1);
    }
    this.playHistory.unshift(song);
    if (this.playHistory.length > 50) {
      this.playHistory.pop();
    }
    FavoritesPersistenceService.getInstance().savePlayHistory(this.playHistory);
  }

  clearPlayHistory(): void {
    this.playHistory = [];
    FavoritesPersistenceService.getInstance().savePlayHistory(this.playHistory);
    this.statusMessage = '已清空最近播放历史';
  }

  async exportSongToSystem(song: Song): Promise<void> {
    try {
      const documentPicker = new picker.DocumentViewPicker();
      const options = new picker.DocumentSaveOptions();
      const cleanTitle = song.title.replace(/[\/\\:*?"<>|]/g, '_');
      options.newFileNames = [`${cleanTitle}.wav`];
      const uris = await documentPicker.save(options);
      if (uris && uris.length > 0 && uris[0].length > 0) {
        const destUri = uris[0];
        const srcPath = song.uri.startsWith('file://') ? song.uri.substring(7) : song.uri;
        const srcFile = fileIo.openSync(srcPath, fileIo.OpenMode.READ_ONLY);
        const destFile = fileIo.openSync(destUri, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
        fileIo.copyFileSync(srcFile.fd, destFile.fd);
        fileIo.closeSync(srcFile);
        fileIo.closeSync(destFile);
        this.statusMessage = `🎉 已成功导出《${song.title}》到系统存储！`;
      }
    } catch (_) {
      this.statusMessage = '导出已取消或失败';
    }
  }

  private deletePhysicalFile(uri: string): void {
    if (!uri || uri.length === 0) return;
    try {
      const physicalPath = uri.startsWith('file://') ? uri.substring(7) : uri;
      if (fileIo.accessSync(physicalPath)) {
        fileIo.unlinkSync(physicalPath);
      }
    } catch (_) {}
  }

  removeLocalSong(song: Song): void {
    this.deletePhysicalFile(song.uri);
    const lIdx = this.localSongs.findIndex((s: Song) => s.uri === song.uri || s.id === song.id);
    if (lIdx >= 0) {
      this.localSongs.splice(lIdx, 1);
      FavoritesPersistenceService.getInstance().saveLocalSongs(this.localSongs);
    }
    const sIdx = this.songs.findIndex((s: Song) => s.uri === song.uri || s.id === song.id);
    if (sIdx >= 0) {
      this.songs.splice(sIdx, 1);
    }
    this.statusMessage = `已彻底删除本地音频文件《${song.title}》`;
  }

  batchRemoveFavorites(songIds: string[]): void {
    const idSet = new Set<string>(songIds);
    this.favorites = this.favorites.filter((s: Song) => !idSet.has(s.id));
    FavoritesPersistenceService.getInstance().saveFavorites(this.favorites);
    this.statusMessage = `已批量移除 ${songIds.length} 首收藏歌曲`;

    if (this.isCloudLoggedIn && this.authToken && songIds.length > 0) {
      CloudFavoritesService.getInstance().batchDeleteFavorites(this.authToken, songIds).then((ok: boolean) => {
        if (ok) {
          this.cloudSyncStatusText = `云端已同步 (已批量移除 ${songIds.length} 首)`;
        }
      });
    }
  }

  batchRemoveLocalSongs(songIds: string[]): void {
    const idSet = new Set<string>(songIds);
    const toDelete = this.localSongs.filter((s: Song) => idSet.has(s.id));
    for (const song of toDelete) {
      this.deletePhysicalFile(song.uri);
    }
    this.localSongs = this.localSongs.filter((s: Song) => !idSet.has(s.id));
    this.songs = this.songs.filter((s: Song) => s.source !== MusicSourceKind.LOCAL || !idSet.has(s.id));
    FavoritesPersistenceService.getInstance().saveLocalSongs(this.localSongs);
    this.statusMessage = `已批量彻底删除 ${songIds.length} 首本地录音与文件`;
  }

  batchRemovePlayHistory(songIds: string[]): void {
    const idSet = new Set<string>(songIds);
    this.playHistory = this.playHistory.filter((s: Song) => !idSet.has(s.id));
    FavoritesPersistenceService.getInstance().savePlayHistory(this.playHistory);
    this.statusMessage = `已批量删除 ${songIds.length} 条播放记录`;
  }

  private permission?: KaraokePermissionPort; private cache?: KaraokeCachePort; private safety?: KaraokeSafetyPort; private engineProvider?: KaraokeEngineProvider;
  private engine?: KaraokeEnginePort; private cachedFile?: CachedAudioFile;
  private preview: KaraokePreviewPort;
  private routeMonitor?: KaraokeRouteMonitorPort;
  private importer: FileImportService = new FileImportService(); private onlineSource: OnlineMusicSource = new OnlineMusicSource();
  private searchGeneration: number = 0; private selectionGeneration: number = 0; private startGeneration: number = 0; private previewGeneration: number = 0;
  private failedSourceMap: Map<string, string[]> = new Map();
  private isAutoSwitchingSource: boolean = false;
  private preloadTimerId: number = -1;
  private isPreloadRunning: boolean = false;
  private hasPreloadedNearEndForCurrentSong: boolean = false;
  private unplayableSongIds: Set<string> = new Set();

  isSongMarkedUnplayable(songId: string): boolean {
    return this.unplayableSongIds.has(songId);
  }

  markSongUnplayable(songId: string): void {
    if (songId && songId.length > 0) {
      this.unplayableSongIds.add(songId);
    }
  }

  clearUnplayableCache(): void {
    this.unplayableSongIds.clear();
  }

  constructor(permission?: KaraokePermissionPort, cache?: KaraokeCachePort, safety?: KaraokeSafetyPort,
    engineProvider?: KaraokeEngineProvider, preview: KaraokePreviewPort = new AVPlayerEngine(), routeMonitor?: KaraokeRouteMonitorPort) {
    this.permission = permission; this.cache = cache; this.safety = safety; this.engineProvider = engineProvider; this.preview = preview; this.routeMonitor = routeMonitor;
    this.bindPreviewEvents();
    this.bindBackgroundTaskControls();
    this.subscribeRouteMonitor();
  }

  private bindPreviewEvents(): void {
    if (this.preview !== undefined) {
      this.preview.onStateChanged = (state: PlaybackState, _snapshot: PlaybackSnapshot) => {
        this.syncPlayback();
        if (state === PlaybackState.COMPLETED) {
          // 歌曲播放完成，自动顺序循环切换至下一首
          this.playNextSong(false);
        } else if (state === PlaybackState.ERROR) {
          if (this.selectedSong !== undefined && this.selectedSong.source === MusicSourceKind.ONLINE && !this.isAutoSwitchingSource && !this.activeAccompanimentId && !this.trackSwitchPending) {
            this.autoSwitchSource(this.selectedSong, this.playback.positionMs, true);
          }
        }
      };
      this.preview.onTimeUpdated = (positionMs: number) => {
        if (this.engine === undefined) {
          this.playback.positionMs = positionMs;
          const newActiveIndex = findActiveLyricIndex(this.lyrics.lines, this.lyricEffectivePositionMs(positionMs));
          this.activeLyricIndex = newActiveIndex;
          this.notifyProgressUpdate(positionMs, newActiveIndex, this.playback);
          this.checkNearEndPreload(positionMs, this.playback.durationMs);
        }
      };
    }
  }

  private bindBackgroundTaskControls(): void {
    BackgroundTaskService.getInstance().setControlListener({
      onPlay: () => {
        this.resumePlayback();
      },
      onPause: () => {
        this.pausePlayback();
      },
      onPlayNext: () => {
        this.playNextSong(false);
      },
      onPlayPrevious: () => {
        this.playPrevSong();
      },
      onSeek: (positionMs: number) => {
        this.seek(positionMs);
        const isPlaying = (this.engine !== undefined && this.session.state === 'singing') ||
          (this.playback.state === PlaybackState.PLAYING);
        const dur = this.playback.durationMs > 0 ? this.playback.durationMs : (this.selectedSong?.durationMs ?? 0);
        BackgroundTaskService.getInstance().updatePlaybackState(
          isPlaying,
          this.selectedSong?.title ?? 'PivoMic 音乐',
          this.selectedSong?.artist ?? '',
          dur,
          positionMs,
          this.selectedSong?.coverUrl,
          undefined,
          this.isSongFavorite(this.selectedSong)
        );
      },
      onToggleFavorite: () => {
        if (this.selectedSong) {
          this.toggleFavorite(this.selectedSong);
        }
      }
    });
  }

  configureKaraoke(permission: KaraokePermissionPort, cache: KaraokeCachePort, safety: KaraokeSafetyPort,
    engineProvider: KaraokeEngineProvider, routeMonitor?: KaraokeRouteMonitorPort): void {
    if (this.routeMonitor !== undefined) this.routeMonitor.unsubscribe();
    this.permission = permission; this.cache = cache; this.safety = safety; this.engineProvider = engineProvider; this.routeMonitor = routeMonitor;
    if (this.safety !== undefined) {
      this.isHeadsetConnected = this.safety.safeOutputConnected();
      this.outputRouteLabel = this.safety.routeLabel();
      if (this.safety.detectAudioRouteMode) this.audioRoute = this.safety.detectAudioRouteMode();
      const initialReason = this.safety.evaluate(false);
      this.monitoringAllowed = initialReason.length === 0;
      this.blockedReason = initialReason;
    }
    this.bindPreviewEvents();
    this.bindBackgroundTaskControls();
    this.subscribeRouteMonitor();
  }

  async loadDailyRecommendations(): Promise<void> {
    this.isLoadingRecommend = true;

    // 1. 若配置了 QQ 音乐 Skill API Key，优先拉取 QQ 音乐每日 30 首
    if (this.qqMusicApiKey && this.qqMusicApiKey.trim().length > 0) {
      this.statusMessage = '正在获取 QQ 音乐每日推荐…';
      this.selectedRecommendTab = 'daily';
      try {
        const dailySongs = await this.qqSkillService.getDailyMix();
        if (dailySongs && dailySongs.length > 0) {
          this.songs = dailySongs;
          this.playbackQueueSource = PlaybackQueueSource.RECOMMEND_OR_SEARCH;
          this.playbackQueue = [...dailySongs];
          this.selectedPlaylist = {
            id: 'qq_daily_mix',
            source: 'qq_skill',
            name: 'QQ音乐每日推荐',
            creator: 'QQ音乐个性化推荐',
            coverUrl: '',
            trackCount: dailySongs.length
          };
          this.statusMessage = `QQ音乐 · 今日推荐（${dailySongs.length} 首）`;
          this.isLoadingRecommend = false;
          return;
        }
      } catch (_) {
        // QQ Skill 获取失败时平滑回退到自建音乐服务
      }
    }

    // 2. 纯本地模式直接展示本地曲库
    if (this.musicSourceMode === MusicSourceMode.LOCAL) {
      this.recommendPlaylists = [];
      this.selectedPlaylist = undefined;
      this.songs = [...this.localSongs];
      this.statusMessage = '已开启纯本地模式，未加载在线推荐';
      this.isLoadingRecommend = false;
      return;
    }

    this.statusMessage = '正在获取官方热门榜单…';
    try {
      const playlists = await this.onlineSource.fetchRecommendPlaylists();
      this.recommendPlaylists = playlists;
      if (playlists.length > 0) {
        this.selectedPlaylist = playlists[0];
        this.statusMessage = `正在载入《${playlists[0].name}》…`;
        const songs = await this.onlineSource.fetchPlaylistSongs(playlists[0]);
        if (songs.length > 0) {
          this.songs = songs;
          this.statusMessage = `每日推荐 · 《${playlists[0].name}》（${songs.length} 首）`;
          // 首次打开默认加载第一个榜单/歌单的第一首歌曲（仅在未选择歌曲时就绪）
          if (this.selectedSong === undefined) {
            await this.selectSong(songs[0], false);
            this.playbackQueue = [...songs];
          }
        } else {
          this.statusMessage = `《${playlists[0].name}》暂无歌曲`;
        }
      } else {
        this.statusMessage = '暂无每日推荐数据，请输入歌曲搜索';
      }
    } catch (_) {
      this.statusMessage = '获取每日推荐失败，请检查网络';
    } finally {
      this.isLoadingRecommend = false;
    }
  }

  async loadQQDailyMix(): Promise<void> {
    this.isLoadingRecommend = true;
    this.selectedRecommendTab = 'daily';
    this.searchKeyword = '';
    this.statusMessage = '正在获取 QQ 音乐每日推荐…';
    try {
      const dailySongs = await this.qqSkillService.getDailyMix();
      if (dailySongs && dailySongs.length > 0) {
        this.songs = dailySongs;
        this.playbackQueueSource = PlaybackQueueSource.RECOMMEND_OR_SEARCH;
        this.playbackQueue = [...dailySongs];
        this.selectedPlaylist = {
          id: 'qq_daily_mix',
          source: 'qq_skill',
          name: 'QQ音乐每日推荐',
          creator: 'QQ音乐个性化推荐',
          coverUrl: '',
          trackCount: dailySongs.length
        };
        this.statusMessage = `QQ音乐 · 今日推荐（${dailySongs.length} 首）`;
      } else {
        this.statusMessage = '获取每日推荐为空，请检查 QQ 音乐 API Key';
      }
    } catch (_) {
      this.statusMessage = '获取 QQ 音乐每日推荐失败';
    } finally {
      this.isLoadingRecommend = false;
    }
  }

  async loadQQAIPlaylists(): Promise<void> {
    this.isLoadingRecommend = true;
    this.selectedRecommendTab = 'ai_playlist';
    this.searchKeyword = '';
    this.statusMessage = '正在获取 QQ 音乐 AI 歌单…';
    try {
      const playlists = await this.qqSkillService.getAIPlaylists();
      this.recommendPlaylists = playlists;
      if (playlists.length > 0) {
        this.selectedPlaylist = playlists[0];
        await this.selectQQPlaylist(playlists[0]);
      } else {
        this.statusMessage = '暂无 AI 推荐歌单，请检查 QQ 音乐 Key';
      }
    } catch (_) {
      this.statusMessage = '获取 QQ 音乐 AI 歌单失败';
    } finally {
      this.isLoadingRecommend = false;
    }
  }

  async selectQQPlaylist(playlist: RecommendPlaylist): Promise<void> {
    this.selectedPlaylist = playlist;
    this.isLoadingRecommend = true;
    this.searchKeyword = '';
    this.statusMessage = `正在载入 AI 歌单《${playlist.name}》…`;
    try {
      const rawId = playlist.id.replace('qq_playlist_', '');
      const dissId = Number(rawId);
      this.recommendCurrentKind = 'playlist';
      this.recommendCurrentRawId = dissId;
      this.recommendCurrentPage = 0;
      this.recommendHasMore = false;

      const detail = await this.qqSkillService.getPlaylistSongs(dissId, 0);
      if (detail && detail.songs.length > 0) {
        this.songs = detail.songs;
        this.playbackQueueSource = PlaybackQueueSource.RECOMMEND_OR_SEARCH;
        this.playbackQueue = [...detail.songs];
        this.recommendHasMore = detail.hasMore ?? false;
        if (this.recommendHasMore && (playlist.trackCount ?? 0) > detail.songs.length) {
          this.statusMessage = `《${detail.dissName}》（已加载 ${detail.songs.length}/${playlist.trackCount} 首）`;
        } else {
          this.statusMessage = `《${detail.dissName}》（${detail.songs.length} 首）`;
        }
      } else {
        this.statusMessage = `《${playlist.name}》暂无歌曲`;
      }
    } catch (_) {
      this.statusMessage = `载入《${playlist.name}》失败`;
    } finally {
      this.isLoadingRecommend = false;
    }
  }

  async loadQQCharts(): Promise<void> {
    this.isLoadingRecommend = true;
    this.selectedRecommendTab = 'charts';
    this.searchKeyword = '';
    this.statusMessage = '正在获取 QQ 音乐排行榜…';
    try {
      const groups = await this.qqSkillService.getCharts();
      this.qqChartGroups = groups;
      const flatCharts: RecommendPlaylist[] = [];
      for (let i = 0; i < groups.length; i++) {
        const g = groups[i];
        for (let j = 0; j < g.groupTopList.length; j++) {
          const item = g.groupTopList[j];
          let chartCover: string = item.topHeaderPic || item.topBannerPic || '';
          if (chartCover.length === 0 && item.songList && item.songList.length > 0) {
            chartCover = item.songList[0].picUrl || '';
          }
          flatCharts.push({
            id: `qq_chart_${item.topId}`,
            source: 'qq_chart',
            name: `${item.topName}`,
            creator: item.listenNum ? `${Math.round(item.listenNum / 10000)}万人收听 · ${g.groupName}` : g.groupName,
            coverUrl: chartCover,
            trackCount: item.totalNum ?? 0
          });
        }
      }
      this.recommendPlaylists = flatCharts;
      if (flatCharts.length > 0) {
        this.selectedPlaylist = flatCharts[0];
        await this.selectQQChart(flatCharts[0]);
      } else {
        this.statusMessage = '暂无排行榜数据，请检查 QQ 音乐 Key';
      }
    } catch (_) {
      this.statusMessage = '获取 QQ 音乐排行榜失败';
    } finally {
      this.isLoadingRecommend = false;
    }
  }

  async selectQQChart(chartItem: RecommendPlaylist): Promise<void> {
    this.selectedPlaylist = chartItem;
    this.isLoadingRecommend = true;
    this.searchKeyword = '';
    this.statusMessage = `正在载入榜单《${chartItem.name}》…`;
    try {
      const rawId = chartItem.id.replace('qq_chart_', '');
      const topId = Number(rawId);
      this.recommendCurrentKind = 'chart';
      this.recommendCurrentRawId = topId;
      this.recommendCurrentPage = 0;
      this.recommendHasMore = false;

      const detail = await this.qqSkillService.getChartSongs(topId, 0);
      if (detail && detail.songs.length > 0) {
        this.songs = detail.songs;
        this.playbackQueueSource = PlaybackQueueSource.RECOMMEND_OR_SEARCH;
        this.playbackQueue = [...detail.songs];
        this.recommendHasMore = detail.hasMore ?? false;
        if (this.recommendHasMore && (chartItem.trackCount ?? 0) > detail.songs.length) {
          this.statusMessage = `《${detail.topName}》（已加载 ${detail.songs.length}/${chartItem.trackCount} 首）`;
        } else {
          this.statusMessage = `《${detail.topName}》（${detail.songs.length} 首）`;
        }
      } else {
        this.statusMessage = `《${chartItem.name}》暂无歌曲`;
      }
    } catch (_) {
      this.statusMessage = `载入《${chartItem.name}》失败`;
    } finally {
      this.isLoadingRecommend = false;
    }
  }

  async loadMoreRecommendSongs(): Promise<void> {
    if (!this.recommendHasMore || this.isLoadingMoreRecommend || this.isLoadingRecommend) {
      return;
    }
    this.isLoadingMoreRecommend = true;
    const nextPage = this.recommendCurrentPage + 1;
    try {
      if (this.recommendCurrentKind === 'chart') {
        const detail = await this.qqSkillService.getChartSongs(this.recommendCurrentRawId, nextPage);
        if (detail && detail.songs.length > 0) {
          this.songs = [...this.songs, ...detail.songs];
          this.playbackQueue = [...this.songs];
          this.recommendCurrentPage = nextPage;
          this.recommendHasMore = detail.hasMore ?? false;
          const total = this.selectedPlaylist?.trackCount ?? this.songs.length;
          if (this.recommendHasMore && total > this.songs.length) {
            this.statusMessage = `《${detail.topName}》（已加载 ${this.songs.length}/${total} 首）`;
          } else {
            this.statusMessage = `《${detail.topName}》（${this.songs.length} 首）`;
          }
        } else {
          this.recommendHasMore = false;
        }
      } else if (this.recommendCurrentKind === 'playlist') {
        const detail = await this.qqSkillService.getPlaylistSongs(this.recommendCurrentRawId, nextPage);
        if (detail && detail.songs.length > 0) {
          this.songs = [...this.songs, ...detail.songs];
          this.playbackQueue = [...this.songs];
          this.recommendCurrentPage = nextPage;
          this.recommendHasMore = detail.hasMore ?? false;
          const total = this.selectedPlaylist?.trackCount ?? this.songs.length;
          if (this.recommendHasMore && total > this.songs.length) {
            this.statusMessage = `《${detail.dissName}》（已加载 ${this.songs.length}/${total} 首）`;
          } else {
            this.statusMessage = `《${detail.dissName}》（${this.songs.length} 首）`;
          }
        } else {
          this.recommendHasMore = false;
        }
      }
    } catch (_) {
      // ignore
    } finally {
      this.isLoadingMoreRecommend = false;
    }
  }

  async shuffleRecommendPlaylists(): Promise<void> {
    if (this.selectedRecommendTab === 'daily') {
      await this.loadQQDailyMix();
      return;
    }
    if (this.selectedRecommendTab === 'ai_playlist') {
      await this.loadQQAIPlaylists();
      return;
    }
    if (this.selectedRecommendTab === 'charts') {
      await this.loadQQCharts();
      return;
    }

    if (this.musicSourceMode === MusicSourceMode.LOCAL) {
      this.statusMessage = '当前为纯本地模式';
      return;
    }
    if (this.recommendPlaylists.length > 1) {
      this.recommendPlaylists = shuffleArray(this.recommendPlaylists);
      this.statusMessage = '已换一批推荐歌单';
      if (this.recommendPlaylists.length > 0) {
        const topPlaylist = this.recommendPlaylists[0];
        await this.selectRecommendPlaylist(topPlaylist);
      }
    } else {
      await this.loadDailyRecommendations();
    }
  }

  async selectRecommendPlaylist(playlist: RecommendPlaylist): Promise<void> {
    if (playlist.source === 'qq_ai') {
      await this.selectQQPlaylist(playlist);
      return;
    }
    if (playlist.source === 'qq_chart') {
      await this.selectQQChart(playlist);
      return;
    }

    if (this.musicSourceMode === MusicSourceMode.LOCAL) {
      this.statusMessage = '当前为纯本地模式';
      return;
    }
    this.selectedPlaylist = playlist;
    this.isLoadingRecommend = true;
    this.searchKeyword = '';
    this.statusMessage = `正在载入《${playlist.name}》…`;
    try {
      const songs = await this.onlineSource.fetchPlaylistSongs(playlist);
      if (songs.length > 0) {
        this.songs = songs;
        this.statusMessage = `已载入《${playlist.name}》（${songs.length} 首）`;
        // 仅在尚未选择歌曲时默认就绪第1首；已选歌或正在播放时不中断、不重置
        if (this.selectedSong === undefined) {
          await this.selectSong(songs[0], false);
          this.playbackQueue = [...songs];
        }
      } else {
        this.statusMessage = `《${playlist.name}》暂无歌曲`;
      }
    } catch (_) {
      this.statusMessage = `载入《${playlist.name}》失败`;
    } finally {
      this.isLoadingRecommend = false;
    }
  }

  async loadCategory(categoryKey: string, autoSelect: boolean = false): Promise<void> {
    if (categoryKey === 'daily') {
      await this.loadQQDailyMix();
      return;
    }
    if (categoryKey === 'ai_playlist') {
      await this.loadQQAIPlaylists();
      return;
    }
    if (categoryKey === 'charts') {
      await this.loadQQCharts();
      return;
    }

    this.selectedRecommendTab = categoryKey;
    if (this.musicSourceMode === MusicSourceMode.LOCAL) {
      this.statusMessage = '当前为纯本地模式';
      return;
    }
    this.isLoadingRecommend = true;
    this.searchKeyword = '';
    let categoryName = '热唱';
    if (categoryKey === 'chinese' || categoryKey === '华语') categoryName = '华语';
    else if (categoryKey === 'nostalgia' || categoryKey === '怀旧') categoryName = '怀旧';
    else if (categoryKey === 'soft' || categoryKey === '轻声') categoryName = '轻声';
    this.statusMessage = `正在获取【${categoryName}】精选曲库…`;

    try {
      const categorySongs = await this.onlineSource.fetchCategorySongs(categoryKey);
      if (categorySongs.length > 0) {
        this.songs = categorySongs;
        this.statusMessage = `已载入【${categoryName}】曲库（${categorySongs.length} 首）`;
        if (this.selectedSong === undefined) {
          await this.selectSong(categorySongs[0], false);
          this.playbackQueue = [...categorySongs];
        }
      } else {
        this.statusMessage = `【${categoryName}】暂无在线歌曲`;
      }
    } catch (_) {
      this.statusMessage = `获取【${categoryName}】曲库失败，请检查网络`;
    } finally {
      this.isLoadingRecommend = false;
    }
  }

  async playSongWithSearchMatch(song: Song, autoPlay: boolean = true, silentToast: boolean = false): Promise<boolean> {
    if (isLocalSong(song)) {
      if (checkLocalSongFileExists(song)) {
        this.unplayableSongIds.delete(song.id);
        await this.selectSong(song, autoPlay);
        return true;
      } else {
        this.unplayableSongIds.add(song.id);
        if (!silentToast) {
          try {
            promptAction.showToast({
              message: '本地音频文件不存在或已失效',
              duration: 2500
            });
          } catch (_) {}
        }
        this.statusMessage = '本地音频文件不存在或已失效';
        return false;
      }
    }

    if (song.streamUrl && song.streamUrl.length > 0) {
      this.unplayableSongIds.delete(song.id);
      await this.selectSong(song, autoPlay);
      return true;
    }

    if (this.unplayableSongIds.has(song.id) && silentToast) {
      return false;
    }

    const artistStr = (isValidArtist(song.artist)) ? song.artist : '';
    const keyword = `${song.title} ${artistStr}`.trim();

    if (this.musicSourceMode === MusicSourceMode.LOCAL) {
      this.unplayableSongIds.add(song.id);
      if (!silentToast) {
        try {
          promptAction.showToast({
            message: '当前为纯本地模式，未连接在线服务',
            duration: 2500
          });
        } catch (_) {}
      }
      this.statusMessage = '当前为纯本地模式';
      return false;
    }

    // 1. 尝试通过原生多源引擎直连换取 320k 直链
    this.statusMessage = `正在解析《${song.title}》320k 高清音频…`;
    try {
      const playUrl = await NativeMusicEngine.getInstance().resolvePlayUrl(song, '320k');
      if (playUrl && playUrl.length > 0) {
        song.streamUrl = playUrl;
        song.uri = playUrl;
        this.unplayableSongIds.delete(song.id);
        this.statusMessage = `已解析《${song.title}》`;
        await this.selectSong(song, autoPlay);
        return true;
      }
    } catch (_) {}

    // 2. 当前直连未能获取，全网检索并自动换源
    this.statusMessage = `正在全网匹配《${song.title}》…`;
    try {
      const searchResult = await this.onlineSource.search(keyword, 1, undefined);
      if (searchResult.songs && searchResult.songs.length > 0) {
        for (let i = 0; i < Math.min(3, searchResult.songs.length); i++) {
          const rawMatched = searchResult.songs[i];
          const playUrl = await NativeMusicEngine.getInstance().resolvePlayUrl(rawMatched, '320k');
          if (playUrl && playUrl.length > 0) {
            rawMatched.streamUrl = playUrl;
            rawMatched.uri = playUrl;
            const matchedSong: Song = {
              id: song.id,
              title: rawMatched.title,
              artist: rawMatched.artist,
              durationMs: rawMatched.durationMs,
              format: rawMatched.format,
              uri: rawMatched.uri,
              source: rawMatched.source,
              streamUrl: rawMatched.streamUrl,
              lyricUrl: rawMatched.lyricUrl,
              lyricText: rawMatched.lyricText,
              coverUrl: rawMatched.coverUrl,
              remoteId: (rawMatched.remoteId && rawMatched.remoteId.length > 0) ? rawMatched.remoteId : song.remoteId,
              provider: rawMatched.provider || song.provider
            };
            if (!matchedSong.coverUrl && song.coverUrl) {
              matchedSong.coverUrl = song.coverUrl;
            }
            const qIdx = this.findSongIndexInQueue(song, this.playbackQueue);
            if (qIdx >= 0) {
              this.playbackQueue[qIdx] = matchedSong;
              this.currentQueueIndex = qIdx;
            }
            const sIdx = this.findSongIndexInQueue(song, this.songs);
            if (sIdx >= 0) {
              this.songs[sIdx] = matchedSong;
            }
            const fIdx = this.findSongIndexInQueue(song, this.favorites);
            if (fIdx >= 0) {
              this.favorites[fIdx] = matchedSong;
            }
            this.statusMessage = `已匹配歌曲: ${matchedSong.title} - ${matchedSong.artist}`;
            this.unplayableSongIds.delete(song.id);
            await this.selectSong(matchedSong, autoPlay);
            return true;
          }
        }
      }
    } catch (_) {}

    this.unplayableSongIds.add(song.id);
    if (!silentToast) {
      try {
        promptAction.showToast({
          message: `未获取到《${song.title}》的可用播放源`,
          duration: 3000
        });
      } catch (_) {}
    }
    this.statusMessage = `未获取到《${song.title}》可用播放源`;
    return false;
  }

  getUpcomingSongs(): Song[] {
    const queue = this.getActiveQueue();
    if (queue.length === 0) {
      return [];
    }
    let currentIdx = -1;
    if (this.currentQueueIndex >= 0 && this.currentQueueIndex < queue.length) {
      const s = queue[this.currentQueueIndex];
      if (this.selectedSong && this.isSongMatch(s, this.selectedSong)) {
        currentIdx = this.currentQueueIndex;
      }
    }
    if (currentIdx < 0 && this.selectedSong) {
      currentIdx = this.findSongIndexInQueue(this.selectedSong, queue);
    }
    if (currentIdx < 0) {
      currentIdx = (this.currentQueueIndex >= 0 && this.currentQueueIndex < queue.length) ?
        this.currentQueueIndex : 0;
    }
    const result: Song[] = [];
    const count = Math.min(3, queue.length);
    for (let i = 1; i <= count; i++) {
      const nextIdx = (currentIdx + i) % queue.length;
      if (nextIdx >= 0 && nextIdx < queue.length && queue[nextIdx]) {
        result.push(queue[nextIdx]);
      }
    }
    return result;
  }

  async searchOnline(keyword: string, source: string = 'all', page: number = 1): Promise<void> {
    const generation = ++this.searchGeneration;
    this.searchKeyword = keyword.trim();
    this.selectedSearchSource = source;
    this.searchPage = page;
    this.hasMoreSearchResults = true;
    if (this.searchKeyword.length === 0) {
      if (this.selectedPlaylist !== undefined) {
        await this.selectRecommendPlaylist(this.selectedPlaylist);
      } else {
        await this.loadDailyRecommendations();
      }
      return;
    }
    if (this.musicSourceMode === MusicSourceMode.LOCAL) {
      this.isSearching = false;
      this.statusMessage = '当前处于纯本地模式，未启用在线检索';
      return;
    }
    this.isSearching = true;
    const sourceLabel = this.selectedSearchSource === 'all' ? '' : ` [${this.getSourceName(this.selectedSearchSource)}]`;
    this.statusMessage = `正在搜索“${this.searchKeyword}”${sourceLabel}…`;
    const result = await this.onlineSource.search(
      this.searchKeyword,
      page,
      this.selectedSearchSource === 'all' ? undefined : [this.selectedSearchSource]
    );
    if (generation !== this.searchGeneration) return;
    this.isSearching = false;
    this.statusMessage = result.message;
    if (result.songs.length > 0) {
      this.songs = result.songs;
      this.playbackQueueSource = PlaybackQueueSource.RECOMMEND_OR_SEARCH;
      this.playbackQueue = [...result.songs];
      if (this.selectedSong === undefined) {
        await this.selectSong(result.songs[0], false);
      }
      if (result.songs.length < 5) {
        this.hasMoreSearchResults = false;
      }
    } else {
      this.songs = [];
      this.hasMoreSearchResults = false;
    }
  }

  async switchSearchSource(source: string): Promise<void> {
    if (this.selectedSearchSource === source && this.songs.length > 0) {
      return;
    }
    this.selectedSearchSource = source;
    if (this.searchKeyword.length > 0) {
      await this.searchOnline(this.searchKeyword, source, 1);
    }
  }

  async loadMoreSearchResults(): Promise<void> {
    if (this.isSearching || this.isSearchingMore || !this.hasMoreSearchResults) {
      return;
    }
    if (this.searchKeyword.trim().length === 0) {
      return;
    }
    if (this.musicSourceMode === MusicSourceMode.LOCAL) {
      return;
    }
    const generation = this.searchGeneration;
    const nextPage = this.searchPage + 1;
    this.isSearchingMore = true;
    try {
      const result = await this.onlineSource.search(
        this.searchKeyword,
        nextPage,
        this.selectedSearchSource === 'all' ? undefined : [this.selectedSearchSource]
      );
      if (generation !== this.searchGeneration) return;
      this.isSearchingMore = false;
      if (result.songs.length > 0) {
        this.searchPage = nextPage;
        const existingIds = new Set(this.songs.map((s: Song) => s.id));
        const newSongs: Song[] = [];
        for (let i = 0; i < result.songs.length; i++) {
          const item = result.songs[i];
          if (!existingIds.has(item.id)) {
            existingIds.add(item.id);
            newSongs.push(item);
          }
        }
        if (newSongs.length > 0) {
          this.songs = this.songs.concat(newSongs);
          if (this.playbackQueueSource === PlaybackQueueSource.RECOMMEND_OR_SEARCH) {
            this.playbackQueue = this.songs.slice();
          }
        } else {
          this.hasMoreSearchResults = false;
        }
      } else {
        this.hasMoreSearchResults = false;
      }
    } catch (_) {
      this.isSearchingMore = false;
    }
  }

  addSearchHistory(keyword: string): void {
    const trimmed = keyword.trim();
    if (trimmed.length === 0) return;
    // LRU 置顶去重：移除既有同名（不区分大小写）项
    const filtered = this.searchHistory.filter((item: string) => item.toLowerCase() !== trimmed.toLowerCase());
    filtered.unshift(trimmed);
    // 上限 15 条
    this.searchHistory = filtered.slice(0, 15);
    FavoritesPersistenceService.getInstance().saveSearchHistory(this.searchHistory);
  }

  removeSearchHistory(keyword: string): void {
    const trimmed = keyword.trim();
    this.searchHistory = this.searchHistory.filter((item: string) => item.toLowerCase() !== trimmed.toLowerCase());
    FavoritesPersistenceService.getInstance().saveSearchHistory(this.searchHistory);
  }

  clearSearchHistory(): void {
    this.searchHistory = [];
    FavoritesPersistenceService.getInstance().saveSearchHistory(this.searchHistory);
  }

  private getSourceName(source: string): string {
    const lower = source.toLowerCase();
    if (lower === 'netease') return '网易云';
    if (lower === 'qq') return 'QQ音乐';
    if (lower === 'kugou') return '酷狗';
    if (lower === 'kuwo') return '酷我';
    if (lower === 'migu') return '咪咕';
    if (lower === 'qianqian') return '千千';
    if (lower === 'soda') return '汽水';
    if (lower === 'apple') return 'Apple';
    return source.toUpperCase();
  }

  async importLocalFiles(): Promise<void> {
    const result = await this.importer.pickAudioFiles();
    if (result.songs.length > 0) {
      for (const s of result.songs) {
        if (!this.localSongs.some((item: Song) => item.uri === s.uri)) {
          this.localSongs.unshift(s);
        }
        if (!this.songs.some((item: Song) => item.uri === s.uri)) {
          this.songs.unshift(s);
        }
      }
      FavoritesPersistenceService.getInstance().saveLocalSongs(this.localSongs);
    }
    this.statusMessage = result.message;
  }

  async selectSong(song: Song, autoPlay: boolean = false): Promise<void> {
    if (this.isRecording) { this.statusMessage = '请先停止录音再切歌'; return; }
    this.trackRevision++; this.trackSwitchPending = false;
    this.activeAccompanimentId = '';
    const oldAssetPin = this.releaseAssetPin; this.releaseAssetPin = undefined;
    const generation = ++this.selectionGeneration;
    this.wasPlayingBeforeInterrupt = false;
    this.interruptTimeMs = 0;
    this.startGeneration++;
    this.previewGeneration++;
    this.isStartPending = false;
    this.closeKaraokeSession();
    try { await this.preview.release(); } finally { oldAssetPin?.(); }
    if (generation !== this.selectionGeneration) return;
    this.clearPreloadTimer();
    this.hasPreloadedNearEndForCurrentSong = false;
    this.selectedSong = song;
    const activeQ = this.getActiveQueue();
    const foundIdx = this.findSongIndexInQueue(song, activeQ);
    if (foundIdx >= 0) {
      this.currentQueueIndex = foundIdx;
    }
    this.lyrics = parseLrc(song.lyricText ?? '');
    this.notifyLyricsUpdate(this.lyrics);
    this.activeLyricIndex = -1;
    this.session = idleSession();
    this.session.durationMs = song.durationMs;
    this.playback = {
      state: autoPlay ? PlaybackState.PLAYING : PlaybackState.READY,
      positionMs: 0,
      durationMs: song.durationMs,
      bufferedPositionMs: song.source === MusicSourceKind.LOCAL ? song.durationMs : 0,
      volume: this.accompanimentGain,
      pitchSemitones: 0,
      errorMessage: ''
    };
    this.monitoringAllowed = false;
    this.blockedReason = '';
    this.statusMessage = autoPlay ? `正在播放《${song.title}》…` : `已就绪《${song.title}》`;
    this.recordPlayHistory(song);

    if (autoPlay) {
      const dur = song.durationMs > 0 ? song.durationMs : 0;
      BackgroundTaskService.getInstance().updatePlaybackState(
        true,
        song.title,
        song.artist,
        dur,
        0,
        song.coverUrl,
        undefined,
        this.isSongFavorite(song)
      );
    }

    this.notifyProgressUpdate(0, -1, this.playback);
    if (this.onSongChanged) {
      this.onSongChanged(song, this.currentQueueIndex);
    }

    // 1. Asynchronously fetch lyrics if not cached (non-blocking)
    const isLocalRecording = song.id.startsWith('rec_');
    if (song.lyricText === undefined && !isLocalRecording) {
      this.onlineSource.fetchLyrics(song).then((text: string) => {
        if (generation === this.selectionGeneration && this.selectedSong?.id === song.id && text.length > 0) {
          song.lyricText = text;
          this.lyrics = parseLrc(text);
          this.activeLyricIndex = findActiveLyricIndex(this.lyrics.lines, this.lyricEffectivePositionMs(this.playback.positionMs));
          this.notifyLyricsUpdate(this.lyrics);
          this.notifyProgressUpdate(this.playback.positionMs, this.activeLyricIndex, this.playback);
        }
      }).catch(() => {});
    }

    // 2. Immediate auto-play without waiting for user click
    if (autoPlay) {
      const isHeadset = this.safety ? this.safety.safeOutputConnected() : false;
      this.isHeadsetConnected = isHeadset;
      if (this.micEnabled) {
        await this.startKaraoke();
      } else {
        let songToPlay = song;
        if (this.cache !== undefined && this.cache.getCachedFilePath !== undefined) {
          const cachedPath = this.cache.getCachedFilePath(song);
          if (cachedPath !== undefined && cachedPath.length > 0) {
            songToPlay = {
              id: song.id,
              title: song.title,
              artist: song.artist,
              durationMs: song.durationMs,
              format: song.format,
              uri: cachedPath,
              source: song.source,
              streamUrl: song.streamUrl,
              lyricUrl: song.lyricUrl,
              lyricText: song.lyricText,
              coverUrl: song.coverUrl,
              remoteId: song.remoteId,
              provider: song.provider
            };
          }
        }
        await this.loadSelectedPreview(songToPlay, true);
        if (generation !== this.selectionGeneration) return;
        // The user can enable the microphone while the asynchronous preview
        // load is still in flight. Re-check after load so the stale preview
        // decision cannot leave a lit microphone button with no capturer.
        if (this.micEnabled) {
          hilog.info(AUDIO_DIAG_DOMAIN, AUDIO_DIAG_TAG,
            '[PivoMicAudioDiag] preview completed after mic enabled; switching to karaoke');
          await this.startKaraoke();
        } else {
          this.syncPlayback();
        }
      }
      // 3. Intelligently preload adjacent songs after 2 seconds of stable playback
      this.scheduleAdjacentPreload();
    }
  }

  async selectSongAndPlay(song: Song, queueSource?: PlaybackQueueSource, sourceList?: Song[]): Promise<void> {
    const isSameSong = this.selectedSong !== undefined && this.isSongMatch(this.selectedSong, song);
    const isCompleted = this.playback.state === PlaybackState.COMPLETED;

    if (queueSource !== undefined) {
      this.playbackQueueSource = queueSource;
    } else {
      // 智能推断来源与同步队列
      if (sourceList && sourceList.length > 0) {
        this.playbackQueueSource = PlaybackQueueSource.RECOMMEND_OR_SEARCH;
      } else if (this.songs.some((s: Song) => this.isSongMatch(s, song))) {
        this.playbackQueueSource = PlaybackQueueSource.RECOMMEND_OR_SEARCH;
      } else if (this.favorites.some((s: Song) => this.isSongMatch(s, song))) {
        this.playbackQueueSource = PlaybackQueueSource.FAVORITES;
      } else if (this.localSongs.some((s: Song) => this.isSongMatch(s, song))) {
        this.playbackQueueSource = PlaybackQueueSource.LOCAL;
      } else if (this.playHistory.some((s: Song) => this.isSongMatch(s, song))) {
        this.playbackQueueSource = PlaybackQueueSource.HISTORY;
      } else {
        this.playbackQueueSource = PlaybackQueueSource.RECOMMEND_OR_SEARCH;
      }
    }

    // 同步当前队列快照
    if (sourceList && sourceList.length > 0) {
      this.playbackQueue = [...sourceList];
    } else if (this.playbackQueueSource === PlaybackQueueSource.RECOMMEND_OR_SEARCH) {
      this.playbackQueue = [...this.songs];
    } else if (this.playbackQueueSource === PlaybackQueueSource.FAVORITES) {
      this.playbackQueue = [...this.favorites];
    } else if (this.playbackQueueSource === PlaybackQueueSource.LOCAL) {
      this.playbackQueue = [...this.localSongs];
    } else if (this.playbackQueueSource === PlaybackQueueSource.HISTORY) {
      this.playbackQueue = [...this.playHistory];
    }

    const matchedIdx = this.findSongIndexInQueue(song, this.playbackQueue);
    this.currentQueueIndex = matchedIdx >= 0 ? matchedIdx : 0;

    if (isSameSong && !isCompleted) {
      // 点击的是当前同一首歌曲且未播放完：保持播放或从当前进度恢复，不从头重置
      const isPlaying = (this.playback.state === PlaybackState.PLAYING || this.session.state === 'singing');
      if (isPlaying) {
        this.statusMessage = `正在播放《${song.title}》…`;
        this.syncPlayback();
      } else {
        // 处于暂停或就绪状态，从当前进度恢复播放
        if (this.micEnabled) {
          const currentPos = (this.engine !== undefined) ? this.session.positionMs : this.playback.positionMs;
          if (this.engine === undefined) {
            await this.startKaraoke(currentPos);
          } else {
            this.engine.start();
            this.session.state = 'singing';
            this.startKaraokePolling();
            this.pollNativeSnapshot();
          }
        } else {
          const snap = this.preview.getSnapshot ? this.preview.getSnapshot() : this.playback;
          if (snap.state === PlaybackState.PAUSED) {
            if (this.preview.play) {
              await this.preview.play();
            }
          } else {
            await this.loadSelectedPreview(song, true, this.playback.positionMs);
          }
          this.syncPlayback();
        }
        this.statusMessage = `正在播放《${song.title}》…`;
      }
      return;
    }

    this.unplayableSongIds.delete(song.id);

    if (isLocalSong(song)) {
      if (checkLocalSongFileExists(song)) {
        await this.selectSong(song, true);
        return;
      } else {
        this.unplayableSongIds.add(song.id);
        this.statusMessage = '本地音频文件不存在或已失效';
        try {
          promptAction.showToast({
            message: '本地音频文件不存在或已失效',
            duration: 2500
          });
        } catch (_) {}
        return;
      }
    }

    if (!song.streamUrl || song.streamUrl.length === 0) {
      await this.playSongWithSearchMatch(song, true);
      return;
    }

    await this.selectSong(song, true);
  }

  async playNextSong(random: boolean = false): Promise<void> {
    const now = Date.now();
    if (this.isSwitchingSong || (now - this.lastSwitchSongTimestamp < 350)) {
      hilog.info(AUDIO_DIAG_DOMAIN, AUDIO_DIAG_TAG, 'playNextSong debounced or switch in flight');
      return;
    }
    this.isSwitchingSong = true;
    this.lastSwitchSongTimestamp = now;

    try {
      this.wasPlayingBeforeInterrupt = false;
      this.interruptTimeMs = 0;
      this.clearPreloadTimer();
      const queue = this.getActiveQueue();
      if (queue.length === 0) {
        if (this.recommendPlaylists.length > 0) {
          const topPlaylist = this.recommendPlaylists[0];
          await this.selectRecommendPlaylist(topPlaylist);
        } else {
          await this.loadDailyRecommendations();
        }
      }
      const currentQueue = this.getActiveQueue();
      if (currentQueue.length === 0) {
        this.statusMessage = '当前列表暂无可用歌曲';
        return;
      }

      let baseIdx = this.findSongIndexInQueue(this.selectedSong, currentQueue);

      // Fallback: 若在当前队列未找到正在播放的歌曲，优先在 this.songs 中匹配并重置为推荐队列
      if (baseIdx < 0 && this.songs.length > 0) {
        const fallbackIdx = this.findSongIndexInQueue(this.selectedSong, this.songs);
        if (fallbackIdx >= 0) {
          this.playbackQueue = [...this.songs];
          this.playbackQueueSource = PlaybackQueueSource.RECOMMEND_OR_SEARCH;
          baseIdx = fallbackIdx;
        }
      }

      // Fallback: 若匹配仍失败，且已有记录的 currentQueueIndex 合法有效，则以该下标为基准
      if (baseIdx < 0 && this.currentQueueIndex >= 0 && this.currentQueueIndex < currentQueue.length) {
        baseIdx = this.currentQueueIndex;
      }

      if (baseIdx < 0) {
        baseIdx = 0;
      }
      this.currentQueueIndex = baseIdx;

      const effectiveQueue = this.getActiveQueue();
      if (effectiveQueue.length === 0) return;

      const maxAttempts = effectiveQueue.length;
      let attempts = 0;
      let targetIdx = baseIdx;
      let skippedCount = 0;

      while (attempts < maxAttempts) {
        attempts++;
        if (random && effectiveQueue.length > 1) {
          let randAttempts = 0;
          do {
            targetIdx = Math.floor(Math.random() * effectiveQueue.length);
            randAttempts++;
          } while (targetIdx === baseIdx && randAttempts < 10);
        } else {
          targetIdx = (targetIdx + 1) % effectiveQueue.length;
        }

        const candidateSong = effectiveQueue[targetIdx];
        if (!candidateSong) break;

        // 1. 快速检查是否已知无伴奏，若是直接跳过，零网络等待
        if (this.unplayableSongIds.has(candidateSong.id)) {
          skippedCount++;
          hilog.info(AUDIO_DIAG_DOMAIN, AUDIO_DIAG_TAG,
            '[QueueSync] playNextSong skipping known unplayable song: %{public}s', candidateSong.title);
          continue;
        }

        const sourceLabel = this.playbackQueueSource === PlaybackQueueSource.FAVORITES ? '【我的收藏】' :
                            (this.playbackQueueSource === PlaybackQueueSource.LOCAL ? '【本地音乐】' :
                            (this.playbackQueueSource === PlaybackQueueSource.HISTORY ? '【播放历史】' : '【当前歌单】'));
        if (skippedCount > 0) {
          this.statusMessage = `播放源不可用，自动为您尝试下一首：《${candidateSong.title}》`;
        } else {
          this.statusMessage = `✨ ${sourceLabel} 为您顺序播放下一首：《${candidateSong.title}》`;
        }

        let success = false;
        if (isLocalSong(candidateSong)) {
          if (checkLocalSongFileExists(candidateSong)) {
            await this.selectSong(candidateSong, true);
            success = true;
          } else {
            this.unplayableSongIds.add(candidateSong.id);
            skippedCount++;
            hilog.warn(AUDIO_DIAG_DOMAIN, AUDIO_DIAG_TAG,
              '[QueueSync] Local song file missing for %{public}s, skipping', candidateSong.title);
            continue;
          }
        } else if (!candidateSong.streamUrl || candidateSong.streamUrl.length === 0) {
          success = await this.playSongWithSearchMatch(candidateSong, true, true);
        } else {
          await this.selectSong(candidateSong, true);
          success = true;
        }

        if (success) {
          this.currentQueueIndex = targetIdx;
          hilog.info(AUDIO_DIAG_DOMAIN, AUDIO_DIAG_TAG,
            '[QueueSync] playNextSong switched successfully to index=%{public}d, title=%{public}s (skipped %{public}d)',
            targetIdx, candidateSong.title, skippedCount);
          return;
        }
        skippedCount++;
        hilog.warn(AUDIO_DIAG_DOMAIN, AUDIO_DIAG_TAG,
          'Song %{public}s could not be played, skipping to next candidate (attempt %{public}d/%{public}d)',
          candidateSong.title, attempts, maxAttempts);
      }
      this.statusMessage = '当前队列多首歌曲暂无可用播放源';
      if (skippedCount > 0) {
        try {
          promptAction.showToast({
            message: '当前队列歌曲暂无可用播放源，已全数跳过',
            duration: 2500
          });
        } catch (_) {}
      }
    } finally {
      this.isSwitchingSong = false;
    }
  }

  async playPrevSong(): Promise<void> {
    const now = Date.now();
    if (this.isSwitchingSong || (now - this.lastSwitchSongTimestamp < 350)) {
      hilog.info(AUDIO_DIAG_DOMAIN, AUDIO_DIAG_TAG, 'playPrevSong debounced or switch in flight');
      return;
    }
    this.isSwitchingSong = true;
    this.lastSwitchSongTimestamp = now;

    try {
      this.wasPlayingBeforeInterrupt = false;
      this.interruptTimeMs = 0;
      this.clearPreloadTimer();
      const currentQueue = this.getActiveQueue();
      if (currentQueue.length === 0) {
        this.statusMessage = '当前列表暂无可用歌曲';
        return;
      }

      let baseIdx = this.findSongIndexInQueue(this.selectedSong, currentQueue);

      // Fallback: 若在当前队列未找到正在播放的歌曲，优先在 this.songs 中匹配并重置为推荐队列
      if (baseIdx < 0 && this.songs.length > 0) {
        const fallbackIdx = this.findSongIndexInQueue(this.selectedSong, this.songs);
        if (fallbackIdx >= 0) {
          this.playbackQueue = [...this.songs];
          this.playbackQueueSource = PlaybackQueueSource.RECOMMEND_OR_SEARCH;
          baseIdx = fallbackIdx;
        }
      }

      // Fallback: 若匹配仍失败，且已有记录的 currentQueueIndex 合法有效，则以该下标为基准
      if (baseIdx < 0 && this.currentQueueIndex >= 0 && this.currentQueueIndex < currentQueue.length) {
        baseIdx = this.currentQueueIndex;
      }

      if (baseIdx < 0) {
        baseIdx = 0;
      }
      this.currentQueueIndex = baseIdx;

      const effectiveQueue = this.getActiveQueue();
      if (effectiveQueue.length === 0) return;

      const maxAttempts = effectiveQueue.length;
      let attempts = 0;
      let targetIdx = baseIdx;
      let skippedCount = 0;

      while (attempts < maxAttempts) {
        attempts++;
        targetIdx = (targetIdx - 1 + effectiveQueue.length) % effectiveQueue.length;
        const candidateSong = effectiveQueue[targetIdx];
        if (!candidateSong) break;

        // 1. 快速检查是否已知无伴奏，若是直接跳过
        if (this.unplayableSongIds.has(candidateSong.id)) {
          skippedCount++;
          hilog.info(AUDIO_DIAG_DOMAIN, AUDIO_DIAG_TAG,
            '[QueueSync] playPrevSong skipping known unplayable song: %{public}s', candidateSong.title);
          continue;
        }

        const sourceLabel = this.playbackQueueSource === PlaybackQueueSource.FAVORITES ? '【我的收藏】' :
                            (this.playbackQueueSource === PlaybackQueueSource.LOCAL ? '【本地音乐】' :
                            (this.playbackQueueSource === PlaybackQueueSource.HISTORY ? '【播放历史】' : '【当前歌单】'));
        if (skippedCount > 0) {
          this.statusMessage = `播放源不可用，自动为您尝试上一首：《${candidateSong.title}》`;
        } else {
          this.statusMessage = `✨ ${sourceLabel} 为您顺序播放上一首：《${candidateSong.title}》`;
        }

        let success = false;
        if (isLocalSong(candidateSong)) {
          if (checkLocalSongFileExists(candidateSong)) {
            await this.selectSong(candidateSong, true);
            success = true;
          } else {
            this.unplayableSongIds.add(candidateSong.id);
            skippedCount++;
            hilog.warn(AUDIO_DIAG_DOMAIN, AUDIO_DIAG_TAG,
              '[QueueSync] Local song file missing for %{public}s, skipping', candidateSong.title);
            continue;
          }
        } else if (!candidateSong.streamUrl || candidateSong.streamUrl.length === 0) {
          success = await this.playSongWithSearchMatch(candidateSong, true, true);
        } else {
          await this.selectSong(candidateSong, true);
          success = true;
        }

        if (success) {
          this.currentQueueIndex = targetIdx;
          hilog.info(AUDIO_DIAG_DOMAIN, AUDIO_DIAG_TAG,
            '[QueueSync] playPrevSong switched successfully to index=%{public}d, title=%{public}s (skipped %{public}d)',
            targetIdx, candidateSong.title, skippedCount);
          return;
        }
        skippedCount++;
        hilog.warn(AUDIO_DIAG_DOMAIN, AUDIO_DIAG_TAG,
          'Song %{public}s could not be played, skipping to prev candidate (attempt %{public}d/%{public}d)',
          candidateSong.title, attempts, maxAttempts);
      }
      this.statusMessage = '当前队列多首歌曲暂无可用播放源';
      if (skippedCount > 0) {
        try {
          promptAction.showToast({
            message: '当前队列歌曲暂无可用播放源，已全数跳过',
            duration: 2500
          });
        } catch (_) {}
      }
    } finally {
      this.isSwitchingSong = false;
    }
  }

  private clearPreloadTimer(): void {
    if (this.preloadTimerId !== -1) {
      clearTimeout(this.preloadTimerId);
      this.preloadTimerId = -1;
    }
  }

  private scheduleAdjacentPreload(): void {
    this.clearPreloadTimer();
    this.preloadTimerId = setTimeout(() => {
      this.preloadAdjacentSongs();
    }, 2000);
  }

  private checkNearEndPreload(positionMs: number, durationMs: number): void {
    if (this.hasPreloadedNearEndForCurrentSong) return;
    if (durationMs > 30000 && positionMs > 0) {
      const remainingMs = durationMs - positionMs;
      if (remainingMs <= 15000 && remainingMs > 0) {
        this.hasPreloadedNearEndForCurrentSong = true;
        const queue = this.getActiveQueue();
        if (queue.length > 1) {
          let currentIdx = this.findSongIndexInQueue(this.selectedSong, queue);
          if (currentIdx < 0 && this.currentQueueIndex >= 0 && this.currentQueueIndex < queue.length) {
            currentIdx = this.currentQueueIndex;
          }
          if (currentIdx >= 0) {
            hilog.info(AUDIO_DIAG_DOMAIN, AUDIO_DIAG_TAG, '[Preload] Near-end fallback preload triggered');
            this.preloadAdjacentSongs();
          }
        }
      }
    }
  }

  private async resolveSongStreamSilently(song: Song): Promise<Song> {
    if (isLocalSong(song)) {
      return song;
    }
    if (song.streamUrl && song.streamUrl.length > 0) {
      return song;
    }
    if (this.unplayableSongIds.has(song.id)) {
      return song;
    }
    if (this.musicSourceMode === MusicSourceMode.LOCAL) {
      return song;
    }
    try {
      if (song.remoteId && song.remoteId.length > 0) {
        const playUrl = await NativeMusicEngine.getInstance().resolvePlayUrl(song, '320k');
        if (playUrl && playUrl.length > 0) {
          song.streamUrl = playUrl;
          song.uri = playUrl;
          this.unplayableSongIds.delete(song.id);
          hilog.info(AUDIO_DIAG_DOMAIN, AUDIO_DIAG_TAG, '[Native] Silently resolved stream for %{public}s -> %{public}s', song.title, playUrl);
          return song;
        }
      }
      const artistStr = (isValidArtist(song.artist)) ? song.artist : '';
      const keyword = `${song.title} ${artistStr}`.trim();
      const searchResult = await this.onlineSource.search(keyword, 1, undefined);
      if (searchResult.songs && searchResult.songs.length > 0) {
        const matchedSong = searchResult.songs[0];
        const playUrl = await NativeMusicEngine.getInstance().resolvePlayUrl(matchedSong, '320k');
        if (playUrl && playUrl.length > 0) {
          matchedSong.streamUrl = playUrl;
          matchedSong.uri = playUrl;
          matchedSong.id = song.id;
          if (!matchedSong.coverUrl && song.coverUrl) {
            matchedSong.coverUrl = song.coverUrl;
          }
          const qIdx = this.findSongIndexInQueue(song, this.playbackQueue);
          if (qIdx >= 0) this.playbackQueue[qIdx] = matchedSong;
          const sIdx = this.findSongIndexInQueue(song, this.songs);
          if (sIdx >= 0) this.songs[sIdx] = matchedSong;
          const fIdx = this.findSongIndexInQueue(song, this.favorites);
          if (fIdx >= 0) this.favorites[fIdx] = matchedSong;
          this.unplayableSongIds.delete(song.id);
          hilog.info(AUDIO_DIAG_DOMAIN, AUDIO_DIAG_TAG, '[Native] Silently resolved stream for %{public}s -> %{public}s', song.title, playUrl);
          return matchedSong;
        }
      }
      this.unplayableSongIds.add(song.id);
    } catch (_) {
      this.unplayableSongIds.add(song.id);
    }
    return song;
  }

  private async preloadAdjacentSongs(): Promise<void> {
    if (this.isPreloadRunning) return;
    const queue = this.getActiveQueue();
    if (queue.length <= 1) return;
    let currentIdx = this.findSongIndexInQueue(this.selectedSong, queue);
    if (currentIdx < 0 && this.currentQueueIndex >= 0 && this.currentQueueIndex < queue.length) {
      currentIdx = this.currentQueueIndex;
    }
    if (currentIdx < 0) return;
    const currentId = this.selectedSong?.id;

    this.isPreloadRunning = true;
    try {
      // 1. Candidate 1: 向前探测直到找到首首可用伴奏的歌曲
      let candidate1: Song | undefined = undefined;
      let candidate1Idx = -1;
      for (let offset = 1; offset < queue.length; offset++) {
        const idx = (currentIdx + offset) % queue.length;
        const candidate = queue[idx];
        if (!candidate || candidate.id === currentId) continue;
        if (this.unplayableSongIds.has(candidate.id)) {
          continue;
        }
        if (isLocalSong(candidate)) {
          if (checkLocalSongFileExists(candidate)) {
            candidate1 = candidate;
            candidate1Idx = idx;
            break;
          } else {
            this.unplayableSongIds.add(candidate.id);
            continue;
          }
        }
        if (candidate.streamUrl && candidate.streamUrl.length > 0) {
          candidate1 = candidate;
          candidate1Idx = idx;
          break;
        }
        const resolved = await this.resolveSongStreamSilently(candidate);
        if (resolved.streamUrl && resolved.streamUrl.length > 0) {
          candidate1 = resolved;
          candidate1Idx = idx;
          break;
        }
      }

      // 2. Candidate 2: 优先选取上一首（若可用且未缓存），若已缓存或不可用则在 Candidate 1 之后顺延探测
      let candidate2: Song | undefined = undefined;
      const prevIdx = (currentIdx - 1 + queue.length) % queue.length;
      const prevCandidate = queue[prevIdx];
      const isPrevCached = (prevCandidate && this.cache && this.cache.getCachedFilePath) ?
        this.cache.getCachedFilePath(prevCandidate) !== undefined : false;

      if (prevIdx !== candidate1Idx && prevIdx !== currentIdx && prevCandidate && prevCandidate.id !== currentId && !this.unplayableSongIds.has(prevCandidate.id)) {
        if (!isPrevCached) {
          if (isLocalSong(prevCandidate)) {
            if (checkLocalSongFileExists(prevCandidate)) {
              candidate2 = prevCandidate;
              hilog.info(AUDIO_DIAG_DOMAIN, AUDIO_DIAG_TAG,
                '[Preload] Candidate 2 chosen as prev song (-1, local): %{public}s', candidate2.title);
            } else {
              this.unplayableSongIds.add(prevCandidate.id);
            }
          } else if (prevCandidate.streamUrl && prevCandidate.streamUrl.length > 0) {
            candidate2 = prevCandidate;
            hilog.info(AUDIO_DIAG_DOMAIN, AUDIO_DIAG_TAG,
              '[Preload] Candidate 2 chosen as prev song (-1, uncached): %{public}s', candidate2.title);
          } else {
            const resolvedPrev = await this.resolveSongStreamSilently(prevCandidate);
            if (resolvedPrev.streamUrl && resolvedPrev.streamUrl.length > 0) {
              candidate2 = resolvedPrev;
              hilog.info(AUDIO_DIAG_DOMAIN, AUDIO_DIAG_TAG,
                '[Preload] Candidate 2 chosen as prev song (-1, resolved): %{public}s', candidate2.title);
            }
          }
        }
      }

      // 若上一首已缓存或无可用伴奏，则在 Candidate 1 后顺延寻找第 2 首有效曲目
      if (!candidate2 && candidate1Idx >= 0) {
        for (let offset = 1; offset < queue.length; offset++) {
          const idx = (candidate1Idx + offset) % queue.length;
          if (idx === currentIdx || idx === candidate1Idx) continue;
          const candidate = queue[idx];
          if (!candidate || candidate.id === currentId || this.unplayableSongIds.has(candidate.id)) continue;
          if (isLocalSong(candidate)) {
            if (checkLocalSongFileExists(candidate)) {
              candidate2 = candidate;
              hilog.info(AUDIO_DIAG_DOMAIN, AUDIO_DIAG_TAG,
                '[Preload] Candidate 2 chosen as next playable (+2, local): %{public}s', candidate2.title);
              break;
            } else {
              this.unplayableSongIds.add(candidate.id);
              continue;
            }
          }
          if (candidate.streamUrl && candidate.streamUrl.length > 0) {
            candidate2 = candidate;
            hilog.info(AUDIO_DIAG_DOMAIN, AUDIO_DIAG_TAG,
              '[Preload] Candidate 2 chosen as next playable (+2): %{public}s', candidate2.title);
            break;
          }
          const resolved = await this.resolveSongStreamSilently(candidate);
          if (resolved.streamUrl && resolved.streamUrl.length > 0) {
            candidate2 = resolved;
            hilog.info(AUDIO_DIAG_DOMAIN, AUDIO_DIAG_TAG,
              '[Preload] Candidate 2 chosen as next playable (+2, resolved): %{public}s', candidate2.title);
            break;
          }
        }
      }

      if (this.selectedSong?.id !== currentId) {
        return; // playback changed while probing
      }

      // Collect protected paths for LRU eviction whitelist
      const protectedPaths: string[] = [];
      if (this.selectedSong && this.cache && this.cache.getCachedFilePath) {
        const curPath = this.cache.getCachedFilePath(this.selectedSong);
        if (curPath) protectedPaths.push(curPath);
      }
      if (candidate1 && this.cache && this.cache.getCachedFilePath) {
        const p1 = this.cache.getCachedFilePath(candidate1);
        if (p1) protectedPaths.push(p1);
      }
      if (candidate2 && this.cache && this.cache.getCachedFilePath) {
        const p2 = this.cache.getCachedFilePath(candidate2);
        if (p2) protectedPaths.push(p2);
      }

      // Phase 1: 异步补齐候选歌曲歌词 (non-blocking)
      if (candidate1 && candidate1.lyricText === undefined && candidate1.lyricUrl !== undefined) {
        this.onlineSource.fetchLyrics(candidate1).then((text: string) => {
          if (text.length > 0) candidate1!.lyricText = text;
        }).catch(() => {});
      }
      if (candidate2 && candidate2.lyricText === undefined && candidate2.lyricUrl !== undefined) {
        this.onlineSource.fetchLyrics(candidate2).then((text: string) => {
          if (text.length > 0) candidate2!.lyricText = text;
        }).catch(() => {});
      }

      // Phase 2: Staggered Audio Download Pool Execution
      const audioPromises: Promise<boolean>[] = [];
      if (candidate1 && this.cache && candidate1.source === MusicSourceKind.ONLINE) {
        hilog.info(AUDIO_DIAG_DOMAIN, AUDIO_DIAG_TAG,
          '[Preload] Starting audio preload for Candidate 1: %{public}s', candidate1.title);
        const p1 = this.cache.preload ? this.cache.preload(candidate1, protectedPaths) : Promise.resolve(false);
        audioPromises.push(p1);

        if (candidate2 && this.cache && candidate2.source === MusicSourceKind.ONLINE) {
          // Staggered launch: wait 1.5s before kicking off Candidate 2
          await new Promise<void>((resolve) => setTimeout(resolve, 1500));
          if (this.selectedSong?.id === currentId && this.cache) {
            hilog.info(AUDIO_DIAG_DOMAIN, AUDIO_DIAG_TAG,
              '[Preload] Staggered start audio preload for Candidate 2: %{public}s', candidate2.title);
            const p2 = this.cache.preload ? this.cache.preload(candidate2, protectedPaths) : Promise.resolve(false);
            audioPromises.push(p2);
          }
        }
      } else if (candidate2 && this.cache && candidate2.source === MusicSourceKind.ONLINE) {
        hilog.info(AUDIO_DIAG_DOMAIN, AUDIO_DIAG_TAG,
          '[Preload] Starting audio preload for Candidate 2: %{public}s', candidate2.title);
        const p2 = this.cache.preload ? this.cache.preload(candidate2, protectedPaths) : Promise.resolve(false);
        audioPromises.push(p2);
      }

      if (audioPromises.length > 0) {
        await Promise.all(audioPromises);
      }
    } catch (err) {
      hilog.warn(AUDIO_DIAG_DOMAIN, AUDIO_DIAG_TAG, '[Preload] Adjacent preload error: %{public}s', JSON.stringify(err));
    } finally {
      this.isPreloadRunning = false;
    }
  }

  async startKaraoke(initialSeekMs: number = 0): Promise<void> {
    if (this.separationSnapshot.busy) { this.statusMessage = '请先取消伴奏生成再开启麦克风'; return; }
    const song = this.selectedSong; const permission = this.permission; const cache = this.cache; const safety = this.safety; const provider = this.engineProvider;
    hilog.info(AUDIO_DIAG_DOMAIN, AUDIO_DIAG_TAG,
      '[PivoMicAudioDiag] startKaraoke enter seek=%{public}d micEnabled=%{public}s playback=%{public}s session=%{public}s song=%{public}s',
      initialSeekMs, `${this.micEnabled}`, `${this.playback.state}`, this.session.state, song?.title ?? '<none>');
    if (song === undefined) { this.statusMessage = '请先选择歌曲'; return; }
    if (this.isStartPending) {
      hilog.warn(AUDIO_DIAG_DOMAIN, AUDIO_DIAG_TAG, '[PivoMicAudioDiag] startKaraoke skipped startPending=true');
      return;
    }
    const generation = ++this.startGeneration;
    if (permission === undefined || cache === undefined || safety === undefined || provider === undefined) { this.setError('K歌服务尚未初始化'); return; }

    const isHeadset = safety.safeOutputConnected();
    this.isHeadsetConnected = isHeadset;
    this.outputRouteLabel = safety.routeLabel();
    if (safety.detectAudioRouteMode) this.audioRoute = safety.detectAudioRouteMode();
    hilog.info(AUDIO_DIAG_DOMAIN, AUDIO_DIAG_TAG,
      '[PivoMicAudioDiag] route detected route=%{public}d headset=%{public}s label=%{public}s',
      this.audioRoute, `${isHeadset}`, this.outputRouteLabel);

    let file: CachedAudioFile | undefined = undefined; let engine: KaraokeEnginePort | undefined = undefined; let committed = false;
    this.isStartPending = true; this.session.state = 'preparing'; this.blockedReason = ''; this.monitoringAllowed = false; this.statusMessage = '正在请求麦克风权限…';
    try {
      const permissionStatus = await permission.requestForKaraokeStart();
      hilog.info(AUDIO_DIAG_DOMAIN, AUDIO_DIAG_TAG,
        '[PivoMicAudioDiag] permission result=%{public}s generationCurrent=%{public}s',
        `${permissionStatus}`, `${generation === this.startGeneration}`);
      if (permissionStatus !== MicrophonePermissionStatus.GRANTED) {
        if (generation === this.startGeneration) this.setError('麦克风权限被拒绝，无法开始耳机K歌');
        return;
      }
      this.statusMessage = '正在缓存歌曲音频…';
      try {
        file = await this.prepareSelectedAudio(song);
      } catch (cacheError) {
        if (generation !== this.startGeneration) return;
        if (song.source === MusicSourceKind.ONLINE && !this.activeAccompanimentId) {
          this.statusMessage = '音频下载失败，正在尝试自动换源…';
          const songKey = `${song.title}-${song.artist}`;
          const failed = this.failedSourceMap.get(songKey) ?? [];
          if (song.provider !== undefined && !failed.includes(song.provider)) {
            failed.push(song.provider);
            this.failedSourceMap.set(songKey, failed);
          }
          const swapped = await this.onlineSource.switchSource(song, undefined, failed);
          if (generation !== this.startGeneration) return;
          if (swapped !== undefined && swapped.provider !== undefined) {
            swapped.id = song.id;
            this.selectedSong = swapped;
            const idx = this.findSongIndexInQueue(song, this.songs);
            if (idx !== -1) this.songs[idx] = swapped;
            const qIdx = this.findSongIndexInQueue(song, this.playbackQueue);
            if (qIdx !== -1) this.playbackQueue[qIdx] = swapped;
            const fIdx = this.findSongIndexInQueue(song, this.favorites);
            if (fIdx !== -1) this.favorites[fIdx] = swapped;
            this.statusMessage = `已自动无缝切换音源至 ${swapped.provider.toUpperCase()}，正在重新缓存…`;
            file = await this.prepareSelectedAudio(swapped);
          } else {
            throw cacheError instanceof Error ? cacheError : new Error('音频缓存失败且无备选可用音源');
          }
        } else {
          throw cacheError instanceof Error ? cacheError : new Error('音频缓存失败');
        }
      }
      if (generation !== this.startGeneration) return;
      this.previewGeneration++; await this.preview.release();
      if (generation !== this.startGeneration) return;
      engine = provider.acquire();
      hilog.info(AUDIO_DIAG_DOMAIN, AUDIO_DIAG_TAG,
        '[PivoMicAudioDiag] engine acquired route=%{public}d headset=%{public}s fd=%{public}d size=%{public}d',
        this.audioRoute, `${isHeadset}`, file.fd, file.size);
      if (engine.setAudioRoute) engine.setAudioRoute(this.audioRoute);
      engine.setSafeOutputConnected(isHeadset);
      hilog.info(AUDIO_DIAG_DOMAIN, AUDIO_DIAG_TAG, '[PivoMicAudioDiag] engine prepare begin');
      let effectiveSongDuration = song.durationMs > 0 ? song.durationMs : 0;
      if (effectiveSongDuration <= 0 && this.lyrics.lines.length > 0) {
        const lastLine = this.lyrics.lines[this.lyrics.lines.length - 1];
        if (lastLine && lastLine.timeMs > 0) {
          effectiveSongDuration = lastLine.timeMs + 5000;
        }
      }
      engine.prepare(file.fd, file.offset, file.size, effectiveSongDuration); const prepared = engine.getSnapshot();
      hilog.info(AUDIO_DIAG_DOMAIN, AUDIO_DIAG_TAG,
        '[PivoMicAudioDiag] engine prepare end state=%{public}s fast=%{public}s aec=%{public}s error=%{public}s',
        prepared.state, `${prepared.fastMode}`, `${prepared.aecSupported}`, prepared.errorMessage);
      const reason = safety.evaluate(prepared.aecSupported);
      if (reason.length > 0) { this.blockedReason = reason; this.statusMessage = reason; return; }
      const refreshedRoute = safety.detectAudioRouteMode ? safety.detectAudioRouteMode() :
        (safety.safeOutputConnected() ? AudioRouteMode.Wired : AudioRouteMode.Speaker);
      const refreshedHeadset = refreshedRoute === AudioRouteMode.Wired || refreshedRoute === AudioRouteMode.Bluetooth;
      this.audioRoute = refreshedRoute;
      this.isHeadsetConnected = refreshedHeadset;
      this.outputRouteLabel = safety.routeLabel();
      this.monitoringAllowed = true;
      engine.setSafeOutputConnected(refreshedHeadset);
      if (engine.setAudioRoute) engine.setAudioRoute(refreshedRoute);
      if (initialSeekMs > 0) {
        try { engine.seek(initialSeekMs); } catch (_) {}
      }
      engine.start();
      hilog.info(AUDIO_DIAG_DOMAIN, AUDIO_DIAG_TAG,
        '[PivoMicAudioDiag] engine start returned route=%{public}d headset=%{public}s',
        refreshedRoute, `${refreshedHeadset}`);
      engine.setAccompanimentGain(this.accompanimentGain);
      engine.setVocalGain(this.vocalGain);
      engine.setReverbMix(this.reverbMix);
      if (engine.setAccompanimentPitchShift) engine.setAccompanimentPitchShift(this.pitchShiftSemitones);
      if (engine.setPitchCorrection) engine.setPitchCorrection(this.autoTuneActive, this.autoTuneStrength, this.autoTuneScale, 0);
      if (generation !== this.startGeneration) return;
      this.engine = engine; this.cachedFile = file; committed = true;
      this.session.state = 'singing';
      this.startKaraokePolling();
      BackgroundTaskService.getInstance().startContinuousAudioTask(
        undefined,
        song.title ?? 'PivoMic 音乐',
        song.artist ?? ''
      );
      this.pollNativeSnapshot();
      if (this.engine === engine) this.statusMessage = this.activeKaraokeStatus();
    } catch (error) {
      hilog.error(AUDIO_DIAG_DOMAIN, AUDIO_DIAG_TAG,
        '[PivoMicAudioDiag] startKaraoke failed error=%{public}s', this.errorText(error, 'K歌启动失败'));
      if (generation === this.startGeneration) this.setError(this.errorText(error, 'K歌启动失败'));
    } finally {
      if (!committed) {
        if (engine !== undefined) { try { engine.stop(); } catch (_) {} try { engine.release(); } catch (_) {} }
        if (file !== undefined) { try { file.close(); } catch (_) {} }
      }
      if (generation === this.startGeneration) this.isStartPending = false;
    }
  }

  async switchCurrentSongSource(targetSource?: string): Promise<boolean> {
    if (this.selectedSong === undefined) {
      this.statusMessage = '请先选择歌曲';
      return false;
    }
    const currentPos = (this.engine !== undefined) ? this.session.positionMs : this.playback.positionMs;
    const wasPlaying = (this.playback.state === PlaybackState.PLAYING || this.session.state === 'singing');
    return this.autoSwitchSource(this.selectedSong, currentPos, wasPlaying, targetSource);
  }

  async autoSwitchSource(song: Song, currentPos: number = 0, autoPlay: boolean = true, targetSource?: string): Promise<boolean> {
    if (this.activeAccompanimentId || this.trackSwitchPending) { this.statusMessage = '请先切换为原曲再更换音源'; return false; }
    if (song.source !== MusicSourceKind.ONLINE) {
      return false;
    }
    if (this.isAutoSwitchingSource) {
      return false;
    }
    this.isAutoSwitchingSource = true;
    const songKey = `${song.title}-${song.artist}`;
    const failed = this.failedSourceMap.get(songKey) ?? [];
    if (song.provider !== undefined && song.provider.length > 0 && !failed.includes(song.provider)) {
      failed.push(song.provider);
      this.failedSourceMap.set(songKey, failed);
    }

    const currentProviderName = (song.provider ?? '未知').toUpperCase();
    this.statusMessage = `当前【${currentProviderName}】音源异常，正在自动为您切换可用音源…`;

    try {
      const swapped = await this.onlineSource.switchSource(song, targetSource, failed);
      if (swapped !== undefined && swapped.provider !== undefined) {
        swapped.id = song.id;
        this.selectedSong = swapped;
        const idx = this.findSongIndexInQueue(song, this.songs);
        if (idx !== -1) {
          this.songs[idx] = swapped;
        }
        const qIdx = this.findSongIndexInQueue(song, this.playbackQueue);
        if (qIdx !== -1) {
          this.playbackQueue[qIdx] = swapped;
        }
        const fIdx = this.findSongIndexInQueue(song, this.favorites);
        if (fIdx !== -1) {
          this.favorites[fIdx] = swapped;
        }

        if (swapped.lyricUrl !== undefined) {
          this.onlineSource.fetchLyrics(swapped).then((text: string) => {
            if (this.selectedSong?.id === swapped.id && text.length > 0) {
              swapped.lyricText = text;
              this.lyrics = parseLrc(text);
            }
          }).catch(() => {});
        }

        this.statusMessage = `已自动无缝切换至【${swapped.provider.toUpperCase()}】音源，正在缓冲播放…`;

        if (this.micEnabled) {
          this.isAutoSwitchingSource = false;
          await this.startKaraoke(currentPos);
        } else {
          this.previewGeneration++;
          await this.preview.release();
          await this.loadSelectedPreview(swapped, autoPlay, currentPos);
          this.syncPlayback();
          this.isAutoSwitchingSource = false;
        }
        return true;
      } else {
        this.isAutoSwitchingSource = false;
        this.statusMessage = `该歌曲暂无其它可用音源，建议切换下一首`;
        return false;
      }
    } catch (_) {
      this.isAutoSwitchingSource = false;
      this.statusMessage = `切换音源失败，建议选择其他歌曲`;
      return false;
    }
  }

  async toggleMicrophone(): Promise<void> {
    if (this.isRecording || this.trackSwitchPending) { this.statusMessage = '请先停止录音或等待音轨切换完成'; return; }
    if (!this.micEnabled && this.separationSnapshot.busy) { this.statusMessage = '请先取消伴奏生成再开启麦克风'; return; }
    const isHeadset = this.safety ? this.safety.safeOutputConnected() : false;
    this.isHeadsetConnected = isHeadset;
    if (this.safety) {
      this.outputRouteLabel = this.safety.routeLabel();
    }
    const currentPos = (this.engine !== undefined) ? this.session.positionMs : this.playback.positionMs;
    const wasPlaying = (this.playback.state === PlaybackState.PLAYING || this.session.state === 'singing');
    hilog.info(AUDIO_DIAG_DOMAIN, AUDIO_DIAG_TAG,
      '[PivoMicAudioDiag] toggleMicrophone before enabled=%{public}s wasPlaying=%{public}s playback=%{public}s session=%{public}s engine=%{public}s',
      `${this.micEnabled}`, `${wasPlaying}`, `${this.playback.state}`, this.session.state, `${this.engine !== undefined}`);

    if (!this.micEnabled) {
      this.micEnabled = true;
      this.statusMessage = isHeadset ? '已开启：48kHz 双工低延迟耳机K歌模式' : '已开启：扬声器实时人声K歌模式';
      // Enabling the microphone is an explicit request to enter karaoke.
      // AVPlayer state callbacks are asynchronous and can still report IDLE
      // while playback is already preparing, so do not gate capture startup on
      // the stale wasPlaying snapshot.
      if (this.selectedSong !== undefined) {
        try {
          await this.startKaraoke(currentPos);
        } catch (_) {
          this.statusMessage = 'K歌引擎准备中，继续听歌模式';
          this.micEnabled = false;
          if (this.selectedSong) {
            await this.loadSelectedPreview(this.selectedSong, wasPlaying, currentPos);
          }
        }
      }
    } else {
      this.micEnabled = false;
      this.statusMessage = '已切换：纯音乐高清听歌模式';
      if (this.engine !== undefined) {
        this.closeKaraokeSession();
        if (this.selectedSong) {
          await this.loadSelectedPreview(this.selectedSong, wasPlaying, currentPos);
        }
      }
    }
  }

  async pausePlayback(): Promise<void> {
    this.wasPlayingBeforeInterrupt = false;
    this.interruptTimeMs = 0;
    if (this.micEnabled) {
      if (this.engine !== undefined && (this.session.state === 'singing' || this.session.state === 'interrupted')) {
        try {
          this.engine.pause();
          this.stopKaraokePolling();
          this.pollNativeSnapshot();
        } catch (error) {
          this.setError(this.errorText(error, '音频暂停失败'));
        }
      }
    } else {
      if (this.preview.pause) {
        await this.preview.pause();
      }
      this.syncPlayback();
    }
  }

  async resumePlayback(): Promise<void> {
    this.wasPlayingBeforeInterrupt = false;
    this.interruptTimeMs = 0;
    if (this.micEnabled) {
      if (this.engine === undefined) {
        await this.startKaraoke();
        return;
      }
      try {
        if (this.session.state !== 'singing') {
          if (this.safety === undefined) return;
          const reason = this.safety.evaluate(this.session.aecSupported);
          if (reason.length > 0) {
            this.blockedReason = reason;
            this.monitoringAllowed = false;
            this.statusMessage = reason;
            return;
          }
          this.engine.setSafeOutputConnected(this.safety.safeOutputConnected());
          this.engine.start();
          this.startKaraokePolling();
        }
        this.pollNativeSnapshot();
      } catch (error) {
        this.setError(this.errorText(error, '音频控制失败'));
      }
    } else {
      if (this.selectedSong === undefined) {
        this.statusMessage = '请先选择歌曲';
        return;
      }
      const snap = this.preview.getSnapshot ? this.preview.getSnapshot() : this.playback;
      if (snap.state === PlaybackState.PAUSED) {
        if (this.preview.play) await this.preview.play();
      } else if (snap.state !== PlaybackState.PLAYING) {
        await this.loadSelectedPreview(this.selectedSong, true);
      }
      this.syncPlayback();
    }
  }

  async togglePlayback(): Promise<void> {
    const now = Date.now();
    if (now - this.lastTogglePlaybackTimestamp < 350) {
      hilog.info(AUDIO_DIAG_DOMAIN, AUDIO_DIAG_TAG, 'togglePlayback debounced (interval < 350ms)');
      return;
    }
    this.lastTogglePlaybackTimestamp = now;

    const isPlaying = (this.engine !== undefined && this.session.state === 'singing') ||
      (this.playback.state === PlaybackState.PLAYING);
    if (isPlaying) {
      await this.pausePlayback();
    } else {
      await this.resumePlayback();
    }
  }

  async startPreviewOnly(): Promise<void> {
    const song = this.selectedSong; if (song === undefined || this.isStartPending || this.engine !== undefined) return;
    const generation = ++this.previewGeneration; await this.preview.release(); if (generation !== this.previewGeneration) return;
    try { await this.loadSelectedPreview(song, true); } catch (error) { if (generation === this.previewGeneration) this.statusMessage = this.errorText(error, '音频预览失败'); return; }
    if (generation !== this.previewGeneration || this.engine !== undefined || song !== this.selectedSong) { await this.preview.release(); return; }
    this.statusMessage = '当前播放歌曲：未开启麦克风';
  }
  /**
   * 计算歌词查找时使用的有效位置。
   * 普通歌曲：直接返回 positionMs。
   * 本地录音（含 lyricOffsetMs）：返回 positionMs + lyricOffsetMs，
   * 使歌词从录音按下录制键的那一刻开始对齐，而非从原曲头部开始。
   */
  private lyricEffectivePositionMs(positionMs: number): number {
    const offset = this.selectedSong?.lyricOffsetMs ?? 0;
    return positionMs + offset;
  }

  seek(positionMs: number): void {
    const duration = this.playback.durationMs > 0 ? this.playback.durationMs : (this.selectedSong?.durationMs ?? 0);
    if (duration <= 0) return;
    const safeTarget = Math.max(0, Math.min(positionMs, duration));

    // 立即乐观更新当前播放快照与歌词，防止异步跳转期间轮询返回旧时间戳导致 UI 回弹
    this.playback.positionMs = safeTarget;
    this.session.positionMs = safeTarget;
    this.activeLyricIndex = findActiveLyricIndex(this.lyrics.lines, this.lyricEffectivePositionMs(safeTarget));
    this.notifyProgressUpdate(safeTarget, this.activeLyricIndex, this.playback);

    if (this.engine !== undefined && (this.session.state === 'singing' || this.session.state === 'paused')) {
      try {
        this.engine.seek(safeTarget);
        this.pollNativeSnapshot();
      } catch (error) {
        this.setError(this.errorText(error, '跳转失败'));
      }
    } else if (this.preview !== undefined && (this.playback.state === PlaybackState.PLAYING || this.playback.state === PlaybackState.PAUSED || this.playback.state === PlaybackState.READY)) {
      try {
        if (this.preview.seek !== undefined) {
          this.preview.seek(safeTarget);
          this.syncPlayback();
        }
      } catch (_) {}
    }
  }

  setAccompanimentGain(value: number): void { this.accompanimentGain = value; try { if (this.engine !== undefined) this.engine.setAccompanimentGain(value); } catch (error) { this.setError(this.errorText(error, '伴奏音量设置失败')); } this.syncPlayback(); }
  setVocalGain(value: number): void { this.vocalGain = value; try { if (this.engine !== undefined) this.engine.setVocalGain(value); } catch (error) { this.setError(this.errorText(error, '人声音量设置失败')); } }
  setReverbMix(value: number): void { this.reverbMix = value; try { if (this.engine !== undefined) this.engine.setReverbMix(value); } catch (error) { this.setError(this.errorText(error, '混响设置失败')); } }
  setVolume(value: number): void { this.setAccompanimentGain(value); }

  setAudioRoute(route: AudioRouteMode): void {
    this.audioRoute = route;
    try {
      if (this.engine !== undefined && this.engine.setAudioRoute) {
        this.engine.setAudioRoute(route);
      }
    } catch (error) {
      this.setError(this.errorText(error, '音频路由设置失败'));
    }
  }

  setPitchShift(semitones: number): void {
    this.pitchShiftSemitones = Math.max(-6, Math.min(6, Math.round(semitones)));
    try {
      if (this.engine !== undefined && this.engine.setAccompanimentPitchShift) {
        this.engine.setAccompanimentPitchShift(this.pitchShiftSemitones);
      }
    } catch (error) {
      this.setError(this.errorText(error, '伴奏升降调设置失败'));
    }
    this.syncPlayback();
  }

  changePitch(semitones: number): void {
    this.setPitchShift(semitones);
  }

  setAutoTune(enabled: boolean, strength: number = 0.5, scale: PitchScaleType = PitchScaleType.Chromatic): void {
    this.autoTuneActive = enabled;
    this.autoTuneStrength = strength;
    this.autoTuneScale = scale;
    try {
      if (this.engine !== undefined && this.engine.setPitchCorrection) {
        this.engine.setPitchCorrection(enabled, strength, scale, 0);
      }
    } catch (error) {
      this.setError(this.errorText(error, '修音设置失败'));
    }
  }

  toggleRecording(): void {
    try {
      if (this.engine !== undefined) {
        if (this.isRecording) {
          if (this.engine.stopRecording) this.engine.stopRecording();
          this.isRecording = false;

          // 1. Export primary WAV to app filesDir for instant C++ write & zero-latency playback
          let appInternalDir = `${this.filesDir}/recordings`;
          if (this.recordingDir && !this.recordingDir.startsWith('/storage/Users/')) {
            let rel = this.recordingDir.replace('file://', '');
            if (!rel.startsWith('/')) rel = `${this.filesDir}/${rel}`;
            if (rel.startsWith(this.filesDir)) appInternalDir = rel;
          }

          try {
            if (!fileIo.accessSync(appInternalDir)) {
              fileIo.mkdirSync(appInternalDir);
            }
          } catch (_) {}

          const timestamp = Date.now();
          const songTitle = this.selectedSong?.title ?? '我的录音';
          const fileName = `rec_${timestamp}.wav`;
          const filePath = `${appInternalDir}/${fileName}`;

          let exported = false;
          if (this.engine.exportRecording) {
            exported = this.engine.exportRecording(filePath);
          }

          // 2. If user chose a user space public directory (e.g. /storage/Users/currentUser/Download or Sounds), copy directly there
          if (exported && this.recordingDir && this.recordingDir.startsWith('/storage/Users/')) {
            try {
              const publicDir = this.recordingDir;
              if (!fileIo.accessSync(publicDir)) {
                fileIo.mkdirSync(publicDir);
              }
              const publicFilePath = `${publicDir}/${fileName}`;
              fileIo.copyFileSync(filePath, publicFilePath);
            } catch (_) {}
          }

          if (exported) {
            const dur = this.recordedDurationMs > 0 ? this.recordedDurationMs : (this.session.recordedDurationMs > 0 ? this.session.recordedDurationMs : 30000);
            const newLocalSong: Song = {
              id: `rec_${timestamp}`,
              title: `${songTitle} (我的录音)`,
              artist: '我 (本地作品)',
              album: 'PivoMic 录音作品库',
              durationMs: dur,
              format: 'wav',
              source: MusicSourceKind.LOCAL,
              uri: `file://${filePath}`,
              coverUrl: this.selectedSong?.coverUrl,
              lyricText: this.selectedSong?.lyricText,
              lyricOffsetMs: this.recordingStartMs > 0 ? this.recordingStartMs : undefined
            };

            this.localSongs.unshift(newLocalSong);
            if (!this.songs.some((s: Song) => s.id === newLocalSong.id)) {
              this.songs.unshift(newLocalSong);
            }
            FavoritesPersistenceService.getInstance().saveLocalSongs(this.localSongs);
            const savedDir = (this.recordingDir && this.recordingDir.length > 0) ? this.recordingDir : appInternalDir;
            this.statusMessage = `🎉 录音已成功保存至「${savedDir}」！`;
          } else {
            this.statusMessage = '录音已完成并保存至本地双轨库';
          }
        } else {
          // 记录录音开始时的原曲播放位置，用于后续播放录音时歌词对齐
          this.recordingStartMs = this.session.positionMs > 0 ? this.session.positionMs : 0;
          if (this.engine.startRecording) this.engine.startRecording();
          this.isRecording = true;
          this.statusMessage = '正在实时双轨录音中…';
        }
      }
    } catch (error) {
      this.setError(this.errorText(error, '录音操作失败'));
    }
  }
  pollNativeSnapshot(): void {
    if (this.engine !== undefined) {
      try {
        const prevSessionState = this.session.state;
        this.session = this.engine.getSnapshot();
        this.isRecording = this.session.isRecording;
        this.recordedDurationMs = this.session.recordedDurationMs;

        if (this.session.state === 'interrupted' && prevSessionState !== 'interrupted') {
          if (prevSessionState === 'singing') {
            this.wasPlayingBeforeInterrupt = true;
            this.interruptTimeMs = Date.now();
          }
          this.statusMessage = '音频已被外部应用打断，结束后自动恢复';
        } else if (this.session.resumeRequested) {
          const elapsed = Date.now() - this.interruptTimeMs;
          const maxTimeoutMs = 30 * 60 * 1000;
          if (this.wasPlayingBeforeInterrupt && (this.interruptTimeMs === 0 || elapsed <= maxTimeoutMs)) {
            this.wasPlayingBeforeInterrupt = false;
            this.interruptTimeMs = 0;
            this.resumePlayback();
          }
        }
      } catch (error) {
        this.setError(this.errorText(error, '读取音频状态失败'));
      }
    }
    this.syncPlayback();
  }
  syncPlayback(): void {
    if (this.engine !== undefined) {
      const state = this.session.state === 'singing' ? PlaybackState.PLAYING : (this.session.state === 'paused' || this.session.state === 'interrupted' ? PlaybackState.PAUSED : (this.session.state === 'error' ? PlaybackState.ERROR : (this.selectedSong === undefined ? PlaybackState.IDLE : PlaybackState.READY)));
      let dur = this.session.durationMs > 0 ? this.session.durationMs : (this.selectedSong?.durationMs ?? 0);
      if (dur <= 0 && this.lyrics.lines.length > 0) {
        const lastLine = this.lyrics.lines[this.lyrics.lines.length - 1];
        if (lastLine && lastLine.timeMs > 0) {
          dur = lastLine.timeMs + 5000;
        }
      }
      if (this.selectedSong && dur > 0 && (!this.selectedSong.durationMs || this.selectedSong.durationMs <= 0)) {
        this.selectedSong.durationMs = dur;
      }
      let buffered = 0;
      if (this.cachedFile !== undefined) {
        buffered = dur;
      } else if (this.selectedSong?.source === MusicSourceKind.LOCAL) {
        buffered = dur;
      }
      this.playback = {
        state: state,
        positionMs: this.session.positionMs,
        durationMs: dur,
        bufferedPositionMs: buffered,
        volume: this.accompanimentGain,
        pitchSemitones: 0,
        errorMessage: this.session.errorMessage
      };
      this.activeLyricIndex = findActiveLyricIndex(this.lyrics.lines, this.lyricEffectivePositionMs(this.session.positionMs));
      if (this.session.errorMessage.length > 0) this.statusMessage = this.session.errorMessage;
    } else if (this.preview !== undefined && this.preview.getSnapshot !== undefined) {
      const snap = this.preview.getSnapshot();
      this.playback = snap;
      this.activeLyricIndex = findActiveLyricIndex(this.lyrics.lines, this.lyricEffectivePositionMs(snap.positionMs));
    }

    this.notifyProgressUpdate(this.playback.positionMs, this.activeLyricIndex, this.playback);
    this.checkNearEndPreload(this.playback.positionMs, this.playback.durationMs);

    const isPlaying = (this.engine !== undefined && this.session.state === 'singing') ||
      (this.playback.state === PlaybackState.PLAYING);
    const isPaused = (this.session.state === 'paused') || (this.playback.state === PlaybackState.PAUSED);

    if (isPlaying || isPaused || this.playback.state === PlaybackState.READY) {
      const dur = this.playback.durationMs > 0 ? this.playback.durationMs : (this.selectedSong?.durationMs ?? 0);
      BackgroundTaskService.getInstance().updatePlaybackState(
        isPlaying,
        this.selectedSong?.title ?? 'PivoMic 音乐',
        this.selectedSong?.artist ?? '',
        dur,
        this.playback.positionMs,
        this.selectedSong?.coverUrl,
        undefined,
        this.isSongFavorite(this.selectedSong)
      );
    } else if (this.playback.state === PlaybackState.IDLE || this.playback.state === PlaybackState.ERROR) {
      if (!this.isSwitchingSong) {
        BackgroundTaskService.getInstance().stopContinuousAudioTask();
      }
    }
  }
  handleBackground(): void {
    this.separation?.cancel();
    if (!this.isAppForeground) return;
    this.isAppForeground = false;
    const isPlaying = (this.engine !== undefined && this.session.state === 'singing') ||
      (this.playback.state === PlaybackState.PLAYING);
    const isPaused = (this.session.state === 'paused') || (this.playback.state === PlaybackState.PAUSED);
    if (isPlaying || isPaused || this.playback.state === PlaybackState.READY) {
      try {
        const dur = this.playback.durationMs > 0 ? this.playback.durationMs : (this.selectedSong?.durationMs ?? 0);
        BackgroundTaskService.getInstance().updatePlaybackState(
          isPlaying,
          this.selectedSong?.title ?? 'PivoMic 音乐',
          this.selectedSong?.artist ?? '',
          dur,
          this.playback.positionMs,
          this.selectedSong?.coverUrl,
          undefined,
          this.isSongFavorite(this.selectedSong)
        );
        if (this.engine !== undefined) {
          this.pollNativeSnapshot();
        }
      } catch (_) {}
    }
  }
  handleForeground(): void {
    if (this.isAppForeground) return;
    this.isAppForeground = true;
    // Collapse all background progress/song/lyric changes into one atomic UI
    // publication. syncPlayback reads the latest native or preview snapshot.
    this.syncPlayback();
  }
  stopKaraoke(): void {
    this.startGeneration++;
    this.isStartPending = false;
    this.closeKaraokeSession();
    this.session = idleSession();
    this.syncPlayback();
    BackgroundTaskService.getInstance().stopContinuousAudioTask();
    this.statusMessage = 'K歌已停止';
  }

  async release(): Promise<void> {
    this.separation?.cancel(); this.separationUnsubscribe?.();
    this.releaseAssetPin?.(); this.releaseAssetPin = undefined;
    this.startGeneration++;
    this.previewGeneration++;
    this.isStartPending = false;
    this.closeKaraokeSession();
    BackgroundTaskService.getInstance().stopContinuousAudioTask();
    BackgroundTaskService.getInstance().releaseSession();
    if (this.routeMonitor !== undefined) this.routeMonitor.unsubscribe();
    await this.preview.release();
  }
  private closeKaraokeSession(): void {
    this.stopKaraokePolling();
    try { if (this.cache !== undefined) this.cache.cancelPending(); } catch (_) {}
    const engine = this.engine; const file = this.cachedFile; this.engine = undefined; this.cachedFile = undefined;
    try {
      if (engine !== undefined) { try { engine.stop(); } catch (_) {} try { engine.release(); } catch (_) {} }
    } finally {
      try { if (file !== undefined) file.close(); } catch (_) {}
      this.monitoringAllowed = false; this.blockedReason = ''; this.outputRouteLabel = '未检测';
      if (this.playback.state !== PlaybackState.PLAYING && this.playback.state !== PlaybackState.PAUSED) {
        BackgroundTaskService.getInstance().stopContinuousAudioTask();
      }
    }
  }
  private setError(message: string): void { this.closeKaraokeSession(); this.session = idleSession(); this.session.state = 'error'; this.session.errorMessage = message; this.playback.state = PlaybackState.ERROR; this.playback.errorMessage = message; this.statusMessage = message; }
  private errorText(error: Object, fallback: string): string { return error instanceof Error && error.message.length > 0 ? error.message : fallback; }
  private activeKaraokeStatus(): string {
    if (this.audioRoute === AudioRouteMode.Wired) return '耳机K歌进行中（实时耳返已开启）';
    if (this.audioRoute === AudioRouteMode.Bluetooth) return '蓝牙K歌进行中（48kHz 高清耳返已开启）';
    return '无耳机K歌进行中（扬声器正在输出伴奏与实时人声）';
  }
  private subscribeRouteMonitor(): void { if (this.routeMonitor !== undefined) this.routeMonitor.subscribe((): void => this.handleRouteChanged()); }
  private handleRouteChanged(): void {
    const safety = this.safety;
    if (safety === undefined) return;
    try {
      const isHeadset = safety.safeOutputConnected();
      this.isHeadsetConnected = isHeadset;
      this.outputRouteLabel = safety.routeLabel();
      const route = safety.detectAudioRouteMode ? safety.detectAudioRouteMode() :
        (isHeadset ? AudioRouteMode.Wired : AudioRouteMode.Speaker);
      this.setAudioRoute(route);
      this.blockedReason = '';
      this.monitoringAllowed = true;
      if (this.engine !== undefined) {
        this.engine.setSafeOutputConnected(isHeadset);
        this.statusMessage = this.activeKaraokeStatus();
      } else if (isHeadset) {
        this.statusMessage = '已连接耳机，可开启麦克风体验K歌与实时耳返';
      } else {
        this.statusMessage = '当前为扬声器外放，可开启实时人声K歌';
      }
    } catch (error) {
      this.setError(this.errorText(error, '输出设备安全检查失败'));
    }
  }
}
