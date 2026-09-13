import { AccompanimentPanel } from '../components/AccompanimentPanel';
import { AccompanimentAsset } from '../domain/AccompanimentModels';
import { getSystemSeparationService } from '../audio/SystemNativeSeparationPort';
import { MusicRecommendationPage } from '../components/MusicRecommendationPage';
import { SongLibrary } from '../components/SongLibrary';
import { KaraokeStage } from '../components/KaraokeStage';
import { MyProfilePage } from '../components/MyProfilePage';
import { AuthLoginPage } from '../components/AuthLoginPage';
import { StatusBanner } from '../components/StatusBanner';
import { KaraokeCachePort, KaraokeEnginePort, KaraokeEngineProvider, KaraokePermissionPort, KaraokeRouteMonitorPort, KaraokeSafetyPort, PivoMicStore, PlaybackQueueSource } from '../store/PivoMicStore';
import { Song, RecommendPlaylist, PlaybackState, PlaybackSnapshot, MusicSourceMode } from '../domain/MusicModels';
import { MusicServerTestResult } from '../services/OnlineMusicSource';
import { PivoTheme } from '../theme/PivoTheme';
import { UserInfo } from '../services/CloudAuthService';
import { getMicrophonePermissionService, MicrophonePermissionStatus } from '../audio/MicrophonePermissionService';
import { CachedAudioFile, OnlineAudioCache, SystemCacheFileStore, SystemCacheNetworkClient } from '../audio/OnlineAudioCache';
import { AudioOutputRoute, canStartMonitoring, classifyPreferredOutput, isHeadsetRoute } from '../audio/KaraokeSafetyPolicy';
import { AudioRouteMode } from '../audio/KaraokeSessionModels';
import { BackgroundTaskService } from '../audio/BackgroundTaskService';
import { getSystemKaraokeAudioEngine } from '../audio/SystemNativeKaraokePort';
import { audioDeviceService, DeviceSelectionListener, FormattedAudioDevice } from '../domain/AudioDeviceService';
import { audio } from '@kit.AudioKit';
import { AppLifecycleListener, systemAppLifecycleEvents } from '../store/AppLifecycleEvents';
import { common } from '@kit.AbilityKit';
import { promptAction, window, display } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { deviceInfo } from '@kit.BasicServicesKit';

const DOMAIN = 0x0000;
const TAG = 'Index_Window';

class SystemEngineProvider implements KaraokeEngineProvider {
  acquire(): KaraokeEnginePort { return getSystemKaraokeAudioEngine(); }
}
class SystemPermissionPort implements KaraokePermissionPort {
  async requestForKaraokeStart(): Promise<MicrophonePermissionStatus> { return getMicrophonePermissionService().requestForKaraokeStart(); }
}
class SystemCachePort implements KaraokeCachePort {
  private cache: OnlineAudioCache;
  constructor(cacheDirectory: string) { this.cache = new OnlineAudioCache(cacheDirectory, new SystemCacheNetworkClient(), new SystemCacheFileStore()); }
  prepare(song: Song): Promise<CachedAudioFile> { return this.cache.prepare(song); }
  cancelPending(): void { this.cache.cancelPending(); }
  getCachedFilePath(song: Song): string | undefined { return this.cache.getCachedFilePath(song); }
  preload(song: Song, protectedPaths?: string[] | string): Promise<boolean> { return this.cache.preload(song, protectedPaths); }
  trimCacheToLimit(maxCount?: number, maxBytes?: number, protectedPaths?: string[] | string): void { this.cache.trimCacheToLimit(maxCount, maxBytes, protectedPaths); }
}
class CurrentSafetyPolicy implements KaraokeSafetyPort, KaraokeRouteMonitorPort {
  private route: AudioOutputRoute = AudioOutputRoute.UNKNOWN;
  private routing: audio.AudioRoutingManager = audio.getAudioManager().getRoutingManager();
  private callback?: (action: audio.DeviceChangeAction) => void;
  evaluate(aecSupported: boolean): string {
    this.route = this.detectRoute();
    const result = canStartMonitoring({ aecSupported: aecSupported, safeOutputConnected: this.safeOutputConnected(), outputRoute: this.route });
    return result.allowed ? '' : result.reason;
  }
  routeLabel(): string {
    if (this.route === AudioOutputRoute.WIRED) return '有线耳机 (支持K歌)';
    if (this.route === AudioOutputRoute.USB) return 'USB耳机 (支持K歌)';
    if (this.route === AudioOutputRoute.BLUETOOTH_LOW_LATENCY || this.route === AudioOutputRoute.BLUETOOTH_UNVERIFIED) return '蓝牙设备 (媒体音乐输出，已自动优化车载防延迟耳返)';
    if (this.route === AudioOutputRoute.SPEAKER) return '扬声器外放 (支持实时人声K歌)';
    return '输出设备未知 (暂不可K歌)';
  }
  safeOutputConnected(): boolean {
    this.route = this.detectRoute();
    return isHeadsetRoute(this.route);
  }
  detectAudioRouteMode(): AudioRouteMode {
    const route = this.detectRoute();
    this.route = route;
    if (route === AudioOutputRoute.WIRED || route === AudioOutputRoute.USB) {
      return AudioRouteMode.Wired;
    }
    if (route === AudioOutputRoute.BLUETOOTH_UNVERIFIED || route === AudioOutputRoute.BLUETOOTH_LOW_LATENCY) {
      return AudioRouteMode.Bluetooth;
    }
    return AudioRouteMode.Speaker;
  }
  subscribe(listener: () => void): void { this.unsubscribe(); this.callback = (_action: audio.DeviceChangeAction): void => listener(); this.routing.on('deviceChange', audio.DeviceFlag.OUTPUT_DEVICES_FLAG, this.callback); }
  unsubscribe(): void { if (this.callback !== undefined) { try { this.routing.off('deviceChange', this.callback); } catch (_) {} this.callback = undefined; } }
  private detectRoute(): AudioOutputRoute {
    try {
      // 1. Check preferred device for music playback (A2DP / Speaker / Wired)
      const rendererInfo: audio.AudioRendererInfo = {
        content: audio.ContentType.CONTENT_TYPE_MUSIC,
        usage: audio.StreamUsage.STREAM_USAGE_MUSIC,
        rendererFlags: 0
      };
      const devices: audio.AudioDeviceDescriptors = this.routing.getPreferredOutputDeviceForRendererInfoSync(rendererInfo);
      const routes: AudioOutputRoute[] = [];
      for (let index = 0; index < devices.length; index++) {
        const type: audio.DeviceType = devices[index].deviceType;
        if (type === audio.DeviceType.WIRED_HEADSET || type === audio.DeviceType.WIRED_HEADPHONES) routes.push(AudioOutputRoute.WIRED);
        else if (type === audio.DeviceType.USB_HEADSET || type === audio.DeviceType.USB_DEVICE) routes.push(AudioOutputRoute.USB);
        else if (type === audio.DeviceType.BLUETOOTH_A2DP || type === audio.DeviceType.BLUETOOTH_SCO) routes.push(AudioOutputRoute.BLUETOOTH_LOW_LATENCY);
        else if (type === audio.DeviceType.SPEAKER) routes.push(AudioOutputRoute.SPEAKER);
        else routes.push(AudioOutputRoute.UNKNOWN);
      }
      const primary = classifyPreferredOutput(routes);
      if (primary !== AudioOutputRoute.UNKNOWN) {
        return primary;
      }

      // 2. Fallback: check preferred device for communication if music route is ambiguous
      const commInfo: audio.AudioRendererInfo = {
        content: audio.ContentType.CONTENT_TYPE_SPEECH,
        usage: audio.StreamUsage.STREAM_USAGE_VOICE_COMMUNICATION,
        rendererFlags: 0
      };
      const commDevices: audio.AudioDeviceDescriptors = this.routing.getPreferredOutputDeviceForRendererInfoSync(commInfo);
      for (let index = 0; index < commDevices.length; index++) {
        const type: audio.DeviceType = commDevices[index].deviceType;
        if (type === audio.DeviceType.WIRED_HEADSET || type === audio.DeviceType.WIRED_HEADPHONES) return AudioOutputRoute.WIRED;
        if (type === audio.DeviceType.USB_HEADSET || type === audio.DeviceType.USB_DEVICE) return AudioOutputRoute.USB;
        if (type === audio.DeviceType.BLUETOOTH_A2DP || type === audio.DeviceType.BLUETOOTH_SCO) return AudioOutputRoute.BLUETOOTH_LOW_LATENCY;
      }
    } catch (_) {}
    return AudioOutputRoute.UNKNOWN;
  }
}
class StoreLifecycleListener implements AppLifecycleListener {
  private store: PivoMicStore;
  private onVisibilityChanged: (foreground: boolean) => void;
  constructor(store: PivoMicStore, onVisibilityChanged: (foreground: boolean) => void) {
    this.store = store;
    this.onVisibilityChanged = onVisibilityChanged;
  }
  onBackground(): void { this.store.handleBackground(); this.onVisibilityChanged(false); }
  onForeground(): void { this.store.handleForeground(); this.onVisibilityChanged(true); }
  onDestroy(): void { this.store.release(); }
}

class AudioDeviceSelectionHandler implements DeviceSelectionListener {
  private store: PivoMicStore;
  private refreshFn: () => void;
  constructor(store: PivoMicStore, refreshFn: () => void) {
    this.store = store;
    this.refreshFn = refreshFn;
  }
  onOutputSelected(_device: FormattedAudioDevice, routeMode: AudioRouteMode): void {
    this.store.setAudioRoute(routeMode);
    this.refreshFn();
  }
  onInputSelected(_device: FormattedAudioDevice): void {
    this.refreshFn();
  }
}

@Entry
@Component
struct Index {
  @State showAccompanimentPanel: boolean = false;
  @State store: PivoMicStore = new PivoMicStore();
  @State currentSelectedSongId: string = '';
  @State currentPlaybackState: PlaybackState = PlaybackState.IDLE;
  @State cachedFavoriteIds: string[] = [];
  private lifecycleId: number = -1;
  private windowClass?: window.Window;
  private sizeCallback?: (size: window.Size) => void;
  private displayCallback?: (displayId: number) => void;
  private audioDeviceHandler?: DeviceSelectionListener;
  private swiperController: SwiperController = new SwiperController();
  private lastStageEnterTime: number = 0;
  private stageEnterTimerId: number = -1;
  @State activeTab: number = 0; // Default to Screen 3 Discovery / Category Home
  @State viewportWidth: number = 960;
  @State isTvLayout: boolean = true;
  @State isAppForeground: boolean = true;
  @State showServerConfigModal: boolean = false;
  @State serverModalInputMode: MusicSourceMode = MusicSourceMode.ONLINE;
  @State serverModalInputUrl: string = '';
  @State isTestingHuibqModal: boolean = false;
  @State huibqModalTestMsg: string = '';
  @State huibqModalTestSuccess: boolean = false;
  @State isTestingServerModal: boolean = false;
  @State serverModalTestMsg: string = '';
  @State serverModalTestSuccess: boolean = false;

  private openServerConfigModal(): void {
    this.serverModalInputMode = this.store.musicSourceMode;
    this.serverModalInputUrl = this.store.customMusicServerUrl;
    this.huibqModalTestMsg = '';
    this.huibqModalTestSuccess = false;
    this.serverModalTestMsg = '';
    this.serverModalTestSuccess = false;
    this.showServerConfigModal = true;
  }

  private switchTab(tabIndex: number, smooth: boolean = true): void {
    this.activeTab = tabIndex;
    try {
      this.swiperController.changeIndex(tabIndex, smooth);
    } catch (_) {}
    this.refresh();
    this.requestInitialFocus();
  }

  // Resolve layout mode by querying the PHYSICAL display's dimensions via displayId.
  // This is the only reliable way to distinguish:
  //   - Phone running on its own screen (displayId=0, portrait 1256x2760)
  //   - Phone app cast to TV (displayId=1032, TV is 1920x1080 landscape)
  //   - Native TV / 2in1 (always landscape)
  //   - Tablet / foldable (aspect ratio driven)
  private updateLayoutMode(widthVp: number, heightVp: number): void {
    if (widthVp > 0) {
      this.viewportWidth = widthVp;
    }

    // KEY INSIGHT from logs: In HarmonyOS distributed/compatible mode,
    // display.getDefaultDisplaySync() always returns the APP's logical dimensions
    // (e.g., 1256×2760), NOT the TV's physical resolution (1920×1080).
    // So we CANNOT use the aspect ratio of getDefaultDisplaySync() to detect TV.
    //
    // However, the displayId IS reliable:
    //   - Phone's own screen: displayId = 0  (primary display)
    //   - External TV/projector: displayId != 0  (e.g., 1032, always non-zero)
    //
    // So rule: displayId != 0 → external display → widescreen layout
    //          displayId == 0 → primary display → use logical aspect ratio
    try {
      const defaultDisplay = display.getDefaultDisplaySync();
      if (defaultDisplay) {
        hilog.info(DOMAIN, TAG,
          '[PivoLayout] displayId=%{public}d, displayW=%{public}d, displayH=%{public}d',
          defaultDisplay.id, defaultDisplay.width, defaultDisplay.height);

        if (defaultDisplay.id !== 0) {
          // External display (TV, projector, other device): always widescreen layout
          this.isTvLayout = true;
          hilog.info(DOMAIN, TAG, '[PivoLayout] External display (id=%{public}d) → TV widescreen layout', defaultDisplay.id);
          return;
        }

        // Primary display (id=0):
        if (deviceInfo.deviceType === 'phone') {
          this.isTvLayout = false;
          hilog.info(DOMAIN, TAG, '[PivoLayout] Primary display (id=0) + phone → portrait phone layout');
          return;
        } else if (deviceInfo.deviceType === 'tv' || deviceInfo.deviceType === '2in1') {
          this.isTvLayout = true;
          hilog.info(DOMAIN, TAG, '[PivoLayout] Primary display (id=0) + TV/2in1 → widescreen layout');
          return;
        }

        // Tablet / Foldable: use aspect ratio only when both dimensions are strictly valid
        if (defaultDisplay.width > 0 && defaultDisplay.height > 0) {
          const ratio = defaultDisplay.width / defaultDisplay.height;
          this.isTvLayout = (ratio >= 1.25);
          hilog.info(DOMAIN, TAG,
            '[PivoLayout] Primary display (id=0), ratio=%{public}s, isTvLayout=%{public}s',
            ratio.toFixed(2), `${this.isTvLayout}`);
          return;
        }
      }
    } catch (e) {
      hilog.warn(DOMAIN, TAG, '[PivoLayout] display query failed: %{public}s', JSON.stringify(e));
    }

    // Fallback: use window aspect ratio only if both dimensions are valid
    if (heightVp > 0 && widthVp > 0) {
      const ratio = widthVp / heightVp;
      this.isTvLayout = (ratio >= 1.25);
      hilog.info(DOMAIN, TAG, '[PivoLayout] (fallback) windowRatio=%{public}s, isTvLayout=%{public}s',
        ratio.toFixed(2), `${this.isTvLayout}`);
    }
  }

  aboutToAppear(): void {
    const context = getContext(this) as common.UIAbilityContext;
    BackgroundTaskService.getInstance().setContext(context);
    // Initial value: widescreen for TV/2in1, otherwise will be resolved after window size is read
    this.isTvLayout = (deviceInfo.deviceType === 'tv' || deviceInfo.deviceType === '2in1');
    this.activeTab = 0; // Default to Screen 3 Discovery / Category Home
    try {
      this.windowClass = context.windowStage?.getMainWindowSync();
      if (this.windowClass) {
        try {
          this.windowClass.setWindowFocusable(true);
        } catch (_) {}
        const props = this.windowClass.getWindowProperties();
        const uiContext = this.getUIContext();
        if (uiContext && props.windowRect.width > 0 && props.windowRect.height > 0) {
          const widthVp = uiContext.px2vp(props.windowRect.width);
          const heightVp = uiContext.px2vp(props.windowRect.height);
          this.updateLayoutMode(widthVp, heightVp);
          hilog.info(DOMAIN, TAG, '[PivoDiagUI] aboutToAppear | rect: %{public}s, widthVp: %{public}d, heightVp: %{public}d, isTvLayout: %{public}s',
            JSON.stringify(props.windowRect), widthVp, heightVp, `${this.isTvLayout}`);
        }
        this.sizeCallback = (size: window.Size) => {
          const uic = this.getUIContext();
          if (uic && size.width > 0 && size.height > 0) {
            const wVp = uic.px2vp(size.width);
            const hVp = uic.px2vp(size.height);
            this.updateLayoutMode(wVp, hVp);
            this.refresh();
          }
        };
        this.windowClass.on('windowSizeChange', this.sizeCallback);

        // Also listen to display changes (e.g. phone cast to TV changes displayId)
        // When displayId changes, onAreaChange fires with reason=0 but window size stays same;
        // updateLayoutMode now queries the physical display via displayId, so we just need refresh.
        this.displayCallback = (_displayId: number) => {
          const uic = this.getUIContext();
          if (uic && this.windowClass) {
            const p = this.windowClass.getWindowProperties();
            const wVp = uic.px2vp(p.windowRect.width);
            const hVp = uic.px2vp(p.windowRect.height);
            const oldLayout = this.isTvLayout;
            this.updateLayoutMode(wVp, hVp);
            if (oldLayout !== this.isTvLayout) {
              this.refresh();
            }
          }
        };
        try {
          display.on('change', this.displayCallback);
        } catch (_e) {}
      }
    } catch (err) {
      hilog.error(DOMAIN, TAG, '[PivoWindowUI] window sync failed: %{public}s', JSON.stringify(err));
    }

    const safety = new CurrentSafetyPolicy();
    this.store.initFavoritesStorage(context.filesDir);
    try {
      const separation = getSystemSeparationService();
      separation.init(context.filesDir, context.cacheDir, context.resourceManager);
      this.store.configureSeparation(separation);
    } catch (_) { this.store.statusMessage = '伴奏生成暂不可用，原曲仍可播放'; }
    this.store.setAudioRoute(safety.detectAudioRouteMode());
    this.store.configureKaraoke(new SystemPermissionPort(), new SystemCachePort(context.cacheDir),
      safety, new SystemEngineProvider(), safety);

    this.store.onProgressUpdate = (_positionMs: number, _activeIndex: number, playback: PlaybackSnapshot) => {
      const songId = this.store.selectedSong?.id ?? '';
      if (this.currentSelectedSongId !== songId) {
        this.currentSelectedSongId = songId;
      }
      if (this.currentPlaybackState !== playback.state) {
        this.currentPlaybackState = playback.state;
      }
    };

    this.store.onSongChanged = (_song: Song, _index: number) => {
      this.syncStateFromStore();
      this.refresh();
    };

    this.store.onFavoritesChanged = () => {
      this.updateCachedFavoriteIds();
      this.refresh();
    };

    this.lifecycleId = systemAppLifecycleEvents.subscribe(new StoreLifecycleListener(this.store, (foreground: boolean): void => {
      this.isAppForeground = foreground;
      if (foreground) {
        this.syncStateFromStore();
        try { this.swiperController.changeIndex(this.activeTab, false); } catch (_) {}
      }
      this.refresh();
    }));
    this.audioDeviceHandler = new AudioDeviceSelectionHandler(this.store, () => this.refresh());
    audioDeviceService.addListener(this.audioDeviceHandler);
    this.store.loadDailyRecommendations().then(() => {
      this.syncStateFromStore();
      this.updateCachedFavoriteIds();
    });
  }

  private syncStateFromStore(): void {
    this.currentPlaybackState = this.store.playback.state;
    this.currentSelectedSongId = this.store.selectedSong?.id ?? '';
  }

  private updateCachedFavoriteIds(): void {
    const list: string[] = [];
    for (const s of this.store.favorites) {
      list.push(s.id);
      if (s.title) {
        list.push(`${s.title.trim().toLowerCase()}:::${(s.artist || '').trim().toLowerCase()}`);
      }
    }
    this.cachedFavoriteIds = list;
  }

  private isSongFavoriteWithCache(song?: Song): boolean {
    if (!song) return false;
    if (this.cachedFavoriteIds.includes(song.id)) return true;
    if (song.title) {
      const key = `${song.title.trim().toLowerCase()}:::${(song.artist || '').trim().toLowerCase()}`;
      if (this.cachedFavoriteIds.includes(key)) return true;
    }
    return false;
  }

  private getActiveQueue(): Song[] {
    const q = this.store.getActiveQueue();
    if (q && q.length > 0) return q;
    return this.store.songs;
  }

  private getCurrentQueueIndex(): number {
    if (this.store.currentQueueIndex >= 0) {
      return this.store.currentQueueIndex;
    }
    const queue = this.getActiveQueue();
    const currentSong = this.store.selectedSong;
    if (!currentSong || queue.length === 0) return 0;
    const idx = this.store.findSongIndexInQueue(currentSong, queue);
    return idx >= 0 ? idx : 0;
  }

  private getFavoriteIds(): string[] {
    const list: string[] = [];
    for (const s of this.store.favorites) {
      list.push(s.id);
      if (s.title) {
        list.push(`${s.title.trim().toLowerCase()}:::${(s.artist || '').trim().toLowerCase()}`);
      }
    }
    return list;
  }

  onBackPress(): boolean {
    if (this.showAccompanimentPanel) { this.showAccompanimentPanel = false; return true; }
    if (this.activeTab !== 0) {
      this.switchTab(0);
      return true; // prevent exit, return to Discovery page
    }
    return false;
  }

  private requestInitialFocus(attempt: number = 0): void {
    const targetId = this.activeTab === 0 ? 'tv_category_tab_0' :
      (this.activeTab === 1 ? 'tv_play_pause_btn' : 'profile_subtab_0');
    try {
      if (this.windowClass) {
        try {
          this.windowClass.setWindowFocusable(true);
        } catch (_) {}
      }
      const success = focusControl.requestFocus(targetId);
      hilog.info(DOMAIN, TAG, '[PivoFocus] requestFocus(%{public}s) attempt=%{public}d, result=%{public}s',
        targetId, attempt, `${success}`);
      if (!success && attempt < 8) {
        setTimeout(() => {
          this.requestInitialFocus(attempt + 1);
        }, 100 * (attempt + 1));
      }
    } catch (err) {
      hilog.error(DOMAIN, TAG, '[PivoFocus] requestFocus exception: %{public}s', JSON.stringify(err));
    }
  }

  onPageShow(): void {
    this.requestInitialFocus();
  }

  aboutToDisappear(): void {
    if (this.windowClass && this.sizeCallback) {
      try {
        this.windowClass.off('windowSizeChange', this.sizeCallback);
      } catch (_) {}
      this.sizeCallback = undefined;
    }
    if (this.displayCallback) {
      try {
        display.off('change', this.displayCallback);
      } catch (_) {}
      this.displayCallback = undefined;
    }
    if (this.lifecycleId >= 0) systemAppLifecycleEvents.unsubscribe(this.lifecycleId);
    if (this.audioDeviceHandler) {
      audioDeviceService.removeListener(this.audioDeviceHandler);
      this.audioDeviceHandler = undefined;
    }
    if (this.stageEnterTimerId !== -1) {
      clearTimeout(this.stageEnterTimerId);
      this.stageEnterTimerId = -1;
    }
    BackgroundTaskService.getInstance().stopContinuousAudioTask();
    this.store.release();
  }

  private refresh(): void {
    this.updateCachedFavoriteIds();
  }

  private toggleOrientation(): void {
    if (!this.windowClass) return;
    this.isTvLayout = !this.isTvLayout;
    const targetOrientation = this.isTvLayout ? window.Orientation.LANDSCAPE : window.Orientation.PORTRAIT;
    if (this.isTvLayout) {
      this.switchTab(1); // Switch to 16:9 Stage in TV mode
      this.windowClass.setWindowSystemBarEnable([]).catch(() => {});
    } else {
      this.windowClass.setWindowSystemBarEnable(['status', 'navigation']).catch(() => {});
    }
    this.windowClass.setWindowLayoutFullScreen(true).catch(() => {});
    hilog.info(DOMAIN, TAG, '[PivoWindowUI] toggleOrientation triggered, isTvLayout=%{public}s, setting: %{public}s',
      `${this.isTvLayout}`, `${targetOrientation}`);
    this.windowClass.setPreferredOrientation(targetOrientation).then(() => {
      hilog.info(DOMAIN, TAG, '[PivoWindowUI] toggleOrientation succeeded');
    }).catch((err: Error) => {
      hilog.error(DOMAIN, TAG, '[PivoWindowUI] toggleOrientation failed: %{public}s', err.message);
    });
    this.refresh();
    this.requestInitialFocus();
  }

  // 1. 电视端 / 16:9 大屏全屏沉浸布局 (TV Layout - 100% 满屏无黑边，采用全屏 Swiper 左右丝滑滑动)
  @Builder
  tvWidescreenLayout() {
    Column() {
      Swiper(this.swiperController) {
        // Page 0: 搜索推荐首页（宽屏双栏布局）
        Column() {
          MusicRecommendationPage({
            wide: true,
            activeCategory: this.store.selectedRecommendTab || 'daily',
            featuredSong: this.store.selectedSong ?? (this.store.songs.length > 0 ? this.store.songs[0] : undefined),
            songs: this.store.songs,
            recommendPlaylists: this.store.recommendPlaylists,
            selectedPlaylistId: this.store.selectedPlaylist?.id ?? '',
            currentPlaylistName: this.store.selectedPlaylist?.name ?? '',
            favoriteIds: this.cachedFavoriteIds,
            searchKeyword: this.store.searchKeyword,
            searchHistory: this.store.searchHistory,
            playbackState: this.currentPlaybackState,
            loadingRecommend: this.store.isLoadingRecommend,
            isSearching: this.store.isSearching,
            selectedSearchSource: this.store.selectedSearchSource,
            isSearchingMore: this.store.isSearchingMore,
            hasMoreSearchResults: this.store.hasMoreSearchResults,
            musicSourceMode: this.store.musicSourceMode,
            customMusicServerUrl: this.store.customMusicServerUrl,
            hasMoreRecommend: this.store.recommendHasMore,
            isLoadingMoreRecommend: this.store.isLoadingMoreRecommend,
            currentPlaylistTotal: this.store.selectedPlaylist?.trackCount ?? this.store.songs.length,
            onSelectSong: (song: Song): void => {
              this.switchTab(1); // Jump to Stage
              this.store.selectSongAndPlay(song, PlaybackQueueSource.RECOMMEND_OR_SEARCH, this.store.songs).then(() => {
                this.refresh();
                this.requestInitialFocus();
              });
              this.refresh();
              this.requestInitialFocus();
            },
            onToggleFavorite: (song: Song): void => {
              this.store.toggleFavorite(song);
              this.refresh();
            },
            onSelectPlaylist: (playlist: RecommendPlaylist): void => {
              this.store.selectRecommendPlaylist(playlist).then(() => this.refresh());
              this.refresh();
            },
            onRefreshRecommend: (): void => {
              this.store.shuffleRecommendPlaylists().then(() => {
                this.refresh();
              });
              this.refresh();
            },
            onSelectCategory: (categoryId: string, _categoryName: string): void => {
              this.store.loadCategory(categoryId, false).then(() => this.refresh());
              this.refresh();
            },
            onSearch: (keyword: string, saveToHistory?: boolean): void => {
              if (saveToHistory && keyword && keyword.trim().length > 0) {
                this.store.addSearchHistory(keyword.trim());
              }
              this.store.searchOnline(keyword, this.store.selectedSearchSource, 1).then(() => this.refresh());
              this.refresh();
            },
            onRemoveSearchHistory: (keyword: string): void => {
              this.store.removeSearchHistory(keyword);
              this.refresh();
            },
            onClearSearchHistory: (): void => {
              this.store.clearSearchHistory();
              this.refresh();
            },
            onSwitchSearchSource: (source: string): void => {
              this.store.switchSearchSource(source).then(() => this.refresh());
              this.refresh();
            },
            onLoadMoreSearch: (): void => {
              this.store.loadMoreSearchResults().then(() => this.refresh());
              this.refresh();
            },
            onLoadMoreRecommend: (): void => {
              this.store.loadMoreRecommendSongs().then(() => this.refresh());
              this.refresh();
            },
            onNavigateTab: (tabIndex: number): void => {
              this.switchTab(tabIndex);
            },
            onOpenServerConfig: (): void => {
              this.openServerConfigModal();
            }
          })
        }
        .width('100%')
        .height('100%')
        .clip(true)

        // Page 1: 演唱沉浸舞台（16:9 全屏）
        Column() {
          KaraokeStage({
            store: this.store,
            activeAccompanimentId: this.store.activeAccompanimentId,
            separationBusy: this.store.separationSnapshot.busy,
            trackSwitchPending: this.store.trackSwitchPending,
            onAccompaniment: (): void => { this.showAccompanimentPanel = true; },
            onOriginalTrack: (): void => { this.store.switchAudioTrack(''); },
            songId: this.store.selectedSong?.id ?? '',
            title: this.store.selectedSong?.title ?? '暂无歌曲播放',
            artist: this.store.selectedSong?.artist ?? '',
            coverUrl: this.store.selectedSong?.coverUrl ?? '',
            lines: this.store.lyrics.lines,
            activeIndex: this.store.activeLyricIndex,
            positionMs: this.store.playback.positionMs,
            durationMs: this.store.playback.durationMs,
            state: this.currentPlaybackState,
            volume: this.store.playback.volume,
            wide: true,
            isVisible: this.activeTab === 1 && this.isAppForeground,
            isFavorite: this.isSongFavoriteWithCache(this.store.selectedSong),
            upcomingSongs: this.store.getUpcomingSongs(),
            queue: this.getActiveQueue(),
            currentQueueIndex: this.getCurrentQueueIndex(),
            capability: this.store.capability,
            microphonePeak: this.store.session.microphonePeak,
            latencyMs: this.store.session.latencyMs,
            fastMode: this.store.session.fastMode,
            aecSupported: this.store.session.aecSupported,
            monitoringAllowed: this.store.monitoringAllowed,
            blockedReason: this.store.blockedReason,
            outputRoute: this.store.outputRouteLabel,
            startPending: this.store.isStartPending,
            accompanimentGain: this.store.accompanimentGain,
            vocalGain: this.store.vocalGain,
            reverbMix: this.store.reverbMix,
            audioRoute: this.store.audioRoute,
            pitchShiftSemitones: this.store.pitchShiftSemitones,
            autoTuneActive: this.store.autoTuneActive,
            autoTuneStrength: this.store.autoTuneStrength,
            isRecording: this.store.isRecording,
            recordedDurationMs: this.store.recordedDurationMs,
            micEnabled: this.store.micEnabled,
            isHeadsetConnected: this.store.isHeadsetConnected,
            onSwipeChangeSong: (song: Song, _targetIndex: number): void => {
              this.store.selectSong(song, true).then(() => {
                this.refresh();
              });
              this.refresh();
            },
            onSelectSong: (song: Song): void => {
              this.store.selectSongAndPlay(song).then(() => {
                this.refresh();
                this.requestInitialFocus();
              });
              this.refresh();
              this.requestInitialFocus();
            },
            onToggleOrientation: (): void => { this.toggleOrientation(); },
            onToggle: (): void => {
              this.store.togglePlayback().then(() => {
                this.refresh();
              });
            },
            onStop: (): void => {
              this.store.stopKaraoke();
              this.refresh();
            },
            onPreview: (): void => { this.store.startPreviewOnly().then(() => this.refresh()); },
            onToggleMicrophone: (): void => { this.store.toggleMicrophone().then(() => this.refresh()); },
            onNextSong: (): Promise<void> => { return this.store.playNextSong(false).then(() => this.refresh()); },
            onPrevSong: (): Promise<void> => { return this.store.playPrevSong().then(() => this.refresh()); },
            onSeek: (value: number): void => { this.store.seek(value); this.refresh(); },
            onVolume: (value: number): void => { this.store.setAccompanimentGain(value); this.refresh(); },
            onVocalGain: (value: number): void => { this.store.setVocalGain(value); this.refresh(); },
            onReverbMix: (value: number): void => { this.store.setReverbMix(value); this.refresh(); },
            onRouteChange: (route: number): void => { this.store.setAudioRoute(route); this.refresh(); },
            onPitchShiftChange: (semitones: number): void => { this.store.setPitchShift(semitones); this.refresh(); },
            onAutoTuneToggle: (active: boolean): void => { this.store.setAutoTune(active, this.store.autoTuneStrength); this.refresh(); },
            onAutoTuneStrengthChange: (strength: number): void => { this.store.setAutoTune(this.store.autoTuneActive, strength); this.refresh(); },
            onRecordingToggle: (): void => { this.store.toggleRecording(); this.refresh(); },
            onToggleFavorite: (): void => {
              if (this.store.selectedSong) {
                this.store.toggleFavorite(this.store.selectedSong);
                this.refresh();
              }
            },
            onOpenLibrary: (): void => {
              this.switchTab(0); // Screen Home
            },
            onOpenProfile: (): void => {
              this.switchTab(2); // Screen Profile
            },
            onSearchArtist: (artist: string): void => {
              this.switchTab(0);
              this.store.searchOnline(artist).then(() => {
                this.refresh();
              });
              this.refresh();
            }
          })
        }
        .width('100%')
        .height('100%')
        .clip(true)

        // Page 2: 个人中心（宽屏我的）
        Column() {
          MyProfilePage({
            accompanimentCount: this.store.separationSnapshot.assets.length,
            accompanimentAssets: this.store.separationSnapshot.assets,
            onAccompaniment: (): void => { this.showAccompanimentPanel = true; },
            onPlayAccompaniment: (asset: AccompanimentAsset): void => {
              this.switchTab(1);
              this.store.playAccompaniment(asset).then(() => { this.refresh(); });
            },
            onDeleteAccompaniment: (assetId: string): void => {
              this.store.deleteAccompaniment(assetId);
              this.refresh();
            },
            onExportAccompaniment: (asset: AccompanimentAsset): void => {
              this.store.exportAccompaniment(asset).then(() => { this.refresh(); });
            },
            favorites: this.store.favorites,
            localSongs: this.store.localSongs,
            playHistory: this.store.playHistory,
            totalSongCount: this.store.songs.length,
            latencyMs: this.store.session.latencyMs,
            fastMode: this.store.session.fastMode,
            expanded: true,
            recordingDir: this.store.recordingDir,
            musicSourceMode: this.store.musicSourceMode,
            customMusicServerUrl: this.store.customMusicServerUrl,
            qqMusicApiKey: this.store.qqMusicApiKey,
            currentSongId: this.store.selectedSong?.id ?? '',
            isPlaying: (this.currentPlaybackState === PlaybackState.PLAYING || this.store.session.state === 'singing'),
            onSelectSong: (song: Song, queueSource?: string): void => {
              this.switchTab(1); // Jump to Stage
              const sourceEnum = queueSource === 'favorites' ? PlaybackQueueSource.FAVORITES :
                                 (queueSource === 'local' ? PlaybackQueueSource.LOCAL :
                                 (queueSource === 'history' ? PlaybackQueueSource.HISTORY : PlaybackQueueSource.RECOMMEND_OR_SEARCH));
              this.store.selectSongAndPlay(song, sourceEnum).then(() => {
                this.refresh();
                this.requestInitialFocus();
              });
              this.refresh();
              this.requestInitialFocus();
            },
            onRemoveFavorite: (song: Song): void => {
              this.store.toggleFavorite(song);
              this.refresh();
            },
            onRemoveLocal: (song: Song): void => {
              this.store.removeLocalSong(song);
              this.refresh();
            },
            onExportSong: (song: Song): void => {
              this.store.exportSongToSystem(song).then(() => this.refresh());
            },
            onBatchRemoveFavorites: (songIds: string[]): void => {
              this.store.batchRemoveFavorites(songIds);
              this.refresh();
            },
            onBatchRemoveLocal: (songIds: string[]): void => {
              this.store.batchRemoveLocalSongs(songIds);
              this.refresh();
            },
            onBatchRemoveHistory: (songIds: string[]): void => {
              this.store.batchRemovePlayHistory(songIds);
              this.refresh();
            },
            onImportLocal: (): void => {
              this.store.importLocalFiles().then(() => this.refresh());
            },
            onSelectRecordingDir: (): void => {
              this.store.selectRecordingDirectory().then(() => this.refresh());
            },
            onUpdateRecordingDir: (path: string): void => {
              this.store.updateRecordingDirectory(path);
              this.refresh();
            },
            onResetRecordingDir: (): void => {
              this.store.resetRecordingDirectory();
              this.refresh();
            },
            onUpdateMusicSourceMode: async (mode: MusicSourceMode): Promise<void> => {
              await this.store.updateMusicSourceMode(mode);
              this.refresh();
            },
            onTestEngineConnection: async (): Promise<MusicServerTestResult> => {
              return await this.store.testEngineConnection();
            },
            onTestHuibqConnection: async (): Promise<MusicServerTestResult> => {
              return await this.store.testEngineConnection();
            },
            onUpdateCustomMusicServerUrl: async (url: string): Promise<boolean> => {
              const ok = await this.store.updateCustomMusicServerUrl(url);
              this.refresh();
              return ok;
            },
            onClearCustomMusicServerUrl: async (): Promise<void> => {
              await this.store.clearCustomMusicServerUrl();
              this.refresh();
            },
            onUpdateQQMusicApiKey: async (key: string): Promise<boolean> => {
              const ok = await this.store.updateQQMusicApiKey(key);
              this.refresh();
              return ok;
            },
            onClearQQMusicApiKey: async (): Promise<void> => {
              await this.store.clearQQMusicApiKey();
              this.refresh();
            },
            onTestCustomMusicServerUrl: async (url: string): Promise<MusicServerTestResult> => {
              return await this.store.testMusicServerConnection(url);
            },
            onClearHistory: (): void => {
              this.store.clearPlayHistory();
              this.refresh();
            },
            onGoLibrary: (): void => {
              this.switchTab(0);
            },
            onSearchArtist: (artist: string): void => {
              this.switchTab(0);
              this.store.searchOnline(artist).then(() => {
                this.refresh();
              });
              this.refresh();
            },
            isCloudLoggedIn: this.store.isCloudLoggedIn,
            currentUserNickname: this.store.currentUser?.nickname ?? '',
            currentUserUsername: this.store.currentUser?.username ?? '',
            isSyncingCloud: this.store.isSyncingCloud,
            cloudSyncStatusText: this.store.cloudSyncStatusText,
            onLoginCloud: async (username: string, password: string): Promise<boolean> => {
              const ok = await this.store.loginCloudAccount(username, password);
              this.refresh();
              return ok;
            },
            onRegisterCloud: async (username: string, password: string, nickname?: string): Promise<boolean> => {
              const ok = await this.store.registerCloudAccount(username, password, nickname);
              this.refresh();
              return ok;
            },
            onLogoutCloud: (): void => {
              this.store.logoutCloudAccount();
              this.refresh();
            },
            onSyncCloud: (): void => {
              this.store.syncFavoritesWithCloud(true).then(() => this.refresh());
            }
          })
        }
        .width('100%')
        .height('100%')
        .clip(true)
      }
      .index(this.activeTab)
      .indicator(false)
      .loop(false)
      .duration(260)
      .curve(Curve.EaseInOut)
      .onChange((index: number) => {
        this.activeTab = index;
      })
      .width('100%')
      .height('100%')
      .clip(true)
    }
    .width('100%')
    .height('100%')
    .clip(true)
  }

  // 2. 手机端 / 竖屏单手触控布局 (无底部TabBar，通过全屏流畅横滑切换 0: 搜索推荐首页, 1: 演唱舞台, 2: 个人中心)
  @Builder
  phonePortraitLayout() {
    Column() {
      Swiper(this.swiperController) {
        // Page 0: 搜索推荐首页（带分类Tab与直接曲库列表）
        Column() {
          MusicRecommendationPage({
            wide: false,
            activeCategory: this.store.selectedRecommendTab || 'daily',
            featuredSong: this.store.selectedSong ?? (this.store.songs.length > 0 ? this.store.songs[0] : undefined),
            songs: this.store.songs,
            recommendPlaylists: this.store.recommendPlaylists,
            selectedPlaylistId: this.store.selectedPlaylist?.id ?? '',
            currentPlaylistName: this.store.selectedPlaylist?.name ?? '',
            favoriteIds: this.cachedFavoriteIds,
            searchKeyword: this.store.searchKeyword,
            searchHistory: this.store.searchHistory,
            playbackState: this.currentPlaybackState,
            loadingRecommend: this.store.isLoadingRecommend,
            isSearching: this.store.isSearching,
            selectedSearchSource: this.store.selectedSearchSource,
            isSearchingMore: this.store.isSearchingMore,
            hasMoreSearchResults: this.store.hasMoreSearchResults,
            musicSourceMode: this.store.musicSourceMode,
            customMusicServerUrl: this.store.customMusicServerUrl,
            hasMoreRecommend: this.store.recommendHasMore,
            isLoadingMoreRecommend: this.store.isLoadingMoreRecommend,
            currentPlaylistTotal: this.store.selectedPlaylist?.trackCount ?? this.store.songs.length,
            onSelectSong: (song: Song): void => {
              this.switchTab(1); // Jump to Stage
              this.store.selectSongAndPlay(song, PlaybackQueueSource.RECOMMEND_OR_SEARCH, this.store.songs).then(() => {
                this.refresh();
              });
              this.refresh();
            },
            onToggleFavorite: (song: Song): void => {
              this.store.toggleFavorite(song);
              this.refresh();
            },
            onSelectPlaylist: (playlist: RecommendPlaylist): void => {
              this.store.selectRecommendPlaylist(playlist).then(() => this.refresh());
              this.refresh();
            },
            onRefreshRecommend: (): void => {
              this.store.shuffleRecommendPlaylists().then(() => {
                this.refresh();
              });
              this.refresh();
            },
            onSelectCategory: (categoryId: string, _categoryName: string): void => {
              this.store.loadCategory(categoryId, false).then(() => this.refresh());
              this.refresh();
            },
            onSearch: (keyword: string, saveToHistory?: boolean): void => {
              if (saveToHistory && keyword && keyword.trim().length > 0) {
                this.store.addSearchHistory(keyword.trim());
              }
              this.store.searchOnline(keyword, this.store.selectedSearchSource, 1).then(() => this.refresh());
              this.refresh();
            },
            onRemoveSearchHistory: (keyword: string): void => {
              this.store.removeSearchHistory(keyword);
              this.refresh();
            },
            onClearSearchHistory: (): void => {
              this.store.clearSearchHistory();
              this.refresh();
            },
            onSwitchSearchSource: (source: string): void => {
              this.store.switchSearchSource(source).then(() => this.refresh());
              this.refresh();
            },
            onLoadMoreSearch: (): void => {
              this.store.loadMoreSearchResults().then(() => this.refresh());
              this.refresh();
            },
            onLoadMoreRecommend: (): void => {
              this.store.loadMoreRecommendSongs().then(() => this.refresh());
              this.refresh();
            },
            onNavigateTab: (tabIndex: number): void => {
              this.switchTab(tabIndex);
            },
            onOpenServerConfig: (): void => {
              this.openServerConfigModal();
            }
          })
        }
        .width('100%')
        .height('100%')
        .clip(true)

        // Page 1: 演唱沉浸舞台
        Column() {
          KaraokeStage({
            store: this.store,
            activeAccompanimentId: this.store.activeAccompanimentId,
            separationBusy: this.store.separationSnapshot.busy,
            trackSwitchPending: this.store.trackSwitchPending,
            onAccompaniment: (): void => { this.showAccompanimentPanel = true; },
            onOriginalTrack: (): void => { this.store.switchAudioTrack(''); },
            songId: this.store.selectedSong?.id ?? '',
            title: this.store.selectedSong?.title ?? '暂无歌曲播放',
            artist: this.store.selectedSong?.artist ?? '',
            coverUrl: this.store.selectedSong?.coverUrl ?? '',
            lines: this.store.lyrics.lines,
            activeIndex: this.store.activeLyricIndex,
            positionMs: this.store.playback.positionMs,
            durationMs: this.store.playback.durationMs,
            state: this.currentPlaybackState,
            volume: this.store.playback.volume,
            wide: false,
            isVisible: this.activeTab === 1 && this.isAppForeground,
            isFavorite: this.isSongFavoriteWithCache(this.store.selectedSong),
            upcomingSongs: this.store.getUpcomingSongs(),
            queue: this.getActiveQueue(),
            currentQueueIndex: this.getCurrentQueueIndex(),
            capability: this.store.capability,
            microphonePeak: this.store.session.microphonePeak,
            latencyMs: this.store.session.latencyMs,
            fastMode: this.store.session.fastMode,
            aecSupported: this.store.session.aecSupported,
            monitoringAllowed: this.store.monitoringAllowed,
            blockedReason: this.store.blockedReason,
            outputRoute: this.store.outputRouteLabel,
            startPending: this.store.isStartPending,
            accompanimentGain: this.store.accompanimentGain,
            vocalGain: this.store.vocalGain,
            reverbMix: this.store.reverbMix,
            audioRoute: this.store.audioRoute,
            pitchShiftSemitones: this.store.pitchShiftSemitones,
            autoTuneActive: this.store.autoTuneActive,
            autoTuneStrength: this.store.autoTuneStrength,
            isRecording: this.store.isRecording,
            recordedDurationMs: this.store.recordedDurationMs,
            micEnabled: this.store.micEnabled,
            isHeadsetConnected: this.store.isHeadsetConnected,
            onSwipeChangeSong: (song: Song, _targetIndex: number): void => {
              this.store.selectSong(song, true).then(() => {
                this.refresh();
              });
              this.refresh();
            },
            onSelectSong: (song: Song): void => {
              this.store.selectSongAndPlay(song).then(() => {
                this.refresh();
              });
              this.refresh();
            },
            onToggleOrientation: (): void => { this.toggleOrientation(); },
            onToggle: (): void => {
              this.store.togglePlayback().then(() => {
                this.refresh();
              });
            },
            onStop: (): void => {
              this.store.stopKaraoke();
              this.refresh();
            },
            onPreview: (): void => { this.store.startPreviewOnly().then(() => this.refresh()); },
            onToggleMicrophone: (): void => { this.store.toggleMicrophone().then(() => this.refresh()); },
            onNextSong: (): Promise<void> => { return this.store.playNextSong(false).then(() => this.refresh()); },
            onPrevSong: (): Promise<void> => { return this.store.playPrevSong().then(() => this.refresh()); },
            onSeek: (value: number): void => { this.store.seek(value); this.refresh(); },
            onVolume: (value: number): void => { this.store.setAccompanimentGain(value); this.refresh(); },
            onVocalGain: (value: number): void => { this.store.setVocalGain(value); this.refresh(); },
            onReverbMix: (value: number): void => { this.store.setReverbMix(value); this.refresh(); },
            onRouteChange: (route: number): void => { this.store.setAudioRoute(route); this.refresh(); },
            onPitchShiftChange: (semitones: number): void => { this.store.setPitchShift(semitones); this.refresh(); },
            onAutoTuneToggle: (active: boolean): void => { this.store.setAutoTune(active, this.store.autoTuneStrength); this.refresh(); },
            onAutoTuneStrengthChange: (strength: number): void => { this.store.setAutoTune(this.store.autoTuneActive, strength); this.refresh(); },
            onRecordingToggle: (): void => { this.store.toggleRecording(); this.refresh(); },
            onToggleFavorite: (): void => {
              if (this.store.selectedSong) {
                this.store.toggleFavorite(this.store.selectedSong);
                this.refresh();
              }
            },
            onOpenLibrary: (): void => {
              this.switchTab(0); // Screen Home
            },
            onOpenProfile: (): void => {
              this.switchTab(2); // Screen Profile
            },
            onSearchArtist: (artist: string): void => {
              this.switchTab(0);
              this.store.searchOnline(artist).then(() => {
                this.refresh();
              });
              this.refresh();
            }
          })
        }
        .width('100%')
        .height('100%')
        .clip(true)

        // Page 2: 我的个人中心
        Column() {
          MyProfilePage({
            accompanimentCount: this.store.separationSnapshot.assets.length,
            accompanimentAssets: this.store.separationSnapshot.assets,
            onAccompaniment: (): void => { this.showAccompanimentPanel = true; },
            onPlayAccompaniment: (asset: AccompanimentAsset): void => {
              this.switchTab(1);
              this.store.playAccompaniment(asset).then(() => { this.refresh(); });
            },
            onDeleteAccompaniment: (assetId: string): void => {
              this.store.deleteAccompaniment(assetId);
              this.refresh();
            },
            onExportAccompaniment: (asset: AccompanimentAsset): void => {
              this.store.exportAccompaniment(asset).then(() => { this.refresh(); });
            },
            favorites: this.store.favorites,
            localSongs: this.store.localSongs,
            playHistory: this.store.playHistory,
            totalSongCount: this.store.songs.length,
            latencyMs: this.store.session.latencyMs,
            fastMode: this.store.session.fastMode,
            expanded: false,
            recordingDir: this.store.recordingDir,
            musicSourceMode: this.store.musicSourceMode,
            customMusicServerUrl: this.store.customMusicServerUrl,
            qqMusicApiKey: this.store.qqMusicApiKey,
            currentSongId: this.store.selectedSong?.id ?? '',
            isPlaying: (this.currentPlaybackState === PlaybackState.PLAYING || this.store.session.state === 'singing'),
            onSelectSong: (song: Song, queueSource?: string): void => {
              this.switchTab(1); // Jump to Stage
              const sourceEnum = queueSource === 'favorites' ? PlaybackQueueSource.FAVORITES :
                                 (queueSource === 'local' ? PlaybackQueueSource.LOCAL :
                                 (queueSource === 'history' ? PlaybackQueueSource.HISTORY : PlaybackQueueSource.RECOMMEND_OR_SEARCH));
              this.store.selectSongAndPlay(song, sourceEnum).then(() => {
                this.refresh();
              });
              this.refresh();
            },
            onRemoveFavorite: (song: Song): void => {
              this.store.toggleFavorite(song);
              this.refresh();
            },
            onRemoveLocal: (song: Song): void => {
              this.store.removeLocalSong(song);
              this.refresh();
            },
            onExportSong: (song: Song): void => {
              this.store.exportSongToSystem(song).then(() => this.refresh());
            },
            onBatchRemoveFavorites: (songIds: string[]): void => {
              this.store.batchRemoveFavorites(songIds);
              this.refresh();
            },
            onBatchRemoveLocal: (songIds: string[]): void => {
              this.store.batchRemoveLocalSongs(songIds);
              this.refresh();
            },
            onBatchRemoveHistory: (songIds: string[]): void => {
              this.store.batchRemovePlayHistory(songIds);
              this.refresh();
            },
            onImportLocal: (): void => {
              this.store.importLocalFiles().then(() => this.refresh());
            },
            onSelectRecordingDir: (): void => {
              this.store.selectRecordingDirectory().then(() => this.refresh());
            },
            onUpdateRecordingDir: (path: string): void => {
              this.store.updateRecordingDirectory(path);
              this.refresh();
            },
            onResetRecordingDir: (): void => {
              this.store.resetRecordingDirectory();
              this.refresh();
            },
            onUpdateMusicSourceMode: async (mode: MusicSourceMode): Promise<void> => {
              await this.store.updateMusicSourceMode(mode);
              this.refresh();
            },
            onTestEngineConnection: async (): Promise<MusicServerTestResult> => {
              return await this.store.testEngineConnection();
            },
            onTestHuibqConnection: async (): Promise<MusicServerTestResult> => {
              return await this.store.testEngineConnection();
            },
            onUpdateCustomMusicServerUrl: async (url: string): Promise<boolean> => {
              const ok = await this.store.updateCustomMusicServerUrl(url);
              this.refresh();
              return ok;
            },
            onClearCustomMusicServerUrl: async (): Promise<void> => {
              await this.store.clearCustomMusicServerUrl();
              this.refresh();
            },
            onUpdateQQMusicApiKey: async (key: string): Promise<boolean> => {
              const ok = await this.store.updateQQMusicApiKey(key);
              this.refresh();
              return ok;
            },
            onClearQQMusicApiKey: async (): Promise<void> => {
              await this.store.clearQQMusicApiKey();
              this.refresh();
            },
            onTestCustomMusicServerUrl: async (url: string): Promise<MusicServerTestResult> => {
              return await this.store.testMusicServerConnection(url);
            },
            onClearHistory: (): void => {
              this.store.clearPlayHistory();
              this.refresh();
            },
            onGoLibrary: (): void => {
              this.switchTab(0);
            },
            onSearchArtist: (artist: string): void => {
              this.switchTab(0);
              this.store.searchOnline(artist).then(() => {
                this.refresh();
              });
              this.refresh();
            },
            isCloudLoggedIn: this.store.isCloudLoggedIn,
            currentUserNickname: this.store.currentUser?.nickname ?? '',
            currentUserUsername: this.store.currentUser?.username ?? '',
            isSyncingCloud: this.store.isSyncingCloud,
            cloudSyncStatusText: this.store.cloudSyncStatusText,
            onLoginCloud: async (username: string, password: string): Promise<boolean> => {
              const ok = await this.store.loginCloudAccount(username, password);
              this.refresh();
              return ok;
            },
            onRegisterCloud: async (username: string, password: string, nickname?: string): Promise<boolean> => {
              const ok = await this.store.registerCloudAccount(username, password, nickname);
              this.refresh();
              return ok;
            },
            onLogoutCloud: (): void => {
              this.store.logoutCloudAccount();
              this.refresh();
            },
            onSyncCloud: (): void => {
              this.store.syncFavoritesWithCloud(true).then(() => this.refresh());
            }
          })
        }
        .width('100%')
        .height('100%')
        .clip(true)
      }
      .index(this.activeTab)
      .indicator(false)
      .loop(false)
      .duration(260)
      .curve(Curve.EaseInOut)
      .onChange((index: number) => {
        this.activeTab = index;
      })
      .width('100%')
      .height('100%')
      .clip(true)
    }
    .width('100%')
    .height('100%')
    .padding({ top: 32 })
    .clip(true)
  }



  private handleKeyEvent(event: KeyEvent): void {
    if (event.type !== KeyType.Down) return;
    const kc = event.keyCode;
    hilog.info(DOMAIN, TAG, '[PivoKeyEvent] onKeyEvent keyCode=%{public}d, keyText=%{public}s, activeTab=%{public}d',
      kc, event.keyText, this.activeTab);

    // 1. Play / Pause / Start Singing (TV Remote & Keyboard navigation keys: DPAD_CENTER, Enter, Space)
    // Note: Hardware media keys (85 MEDIA_PLAY_PAUSE, 126 PLAY, 127 PAUSE, 2055 HEADSETHOOK) are exclusively handled by AVSession
    if (kc === 2016 || kc === 66 || kc === 62) {
      if (this.activeTab === 0) {
        // In Discovery page: Enter/Play starts singing selected song and jumps to Stage
        this.switchTab(1); // Jump to Screen 2 Stage (Tab 1)
        const targetSong = this.store.selectedSong ?? (this.store.songs.length > 0 ? this.store.songs[0] : undefined);
        if (targetSong) {
          this.store.selectSongAndPlay(targetSong, PlaybackQueueSource.RECOMMEND_OR_SEARCH, this.store.songs).then(() => {
            this.refresh();
            this.requestInitialFocus();
          });
        }
        this.refresh();
      } else if (this.activeTab === 1) {
        // In Stage page: Double-press -> toggle favorite; Single-press -> toggle playback (260ms debounce)
        const now = Date.now();
        if (now - this.lastStageEnterTime < 300 && this.stageEnterTimerId !== -1) {
          clearTimeout(this.stageEnterTimerId);
          this.stageEnterTimerId = -1;
          this.lastStageEnterTime = 0;
          if (this.store.selectedSong) {
            this.store.toggleFavorite(this.store.selectedSong);
            this.refresh();
          }
        } else {
          this.lastStageEnterTime = now;
          if (this.stageEnterTimerId !== -1) {
            clearTimeout(this.stageEnterTimerId);
          }
          this.stageEnterTimerId = setTimeout(() => {
            this.store.togglePlayback().then(() => {
              this.refresh();
            });
            this.stageEnterTimerId = -1;
          }, 260);
        }
      } else {
        this.store.togglePlayback().then(() => {
          this.refresh();
        });
      }
    } else if (this.activeTab === 1 && (kc === 20 || kc === 2013)) {
      // Remote DPAD_DOWN in Stage -> play next song
      this.store.playNextSong(false).then(() => {
        this.refresh();
      });
    } else if (this.activeTab === 1 && (kc === 19 || kc === 2012)) {
      // Remote DPAD_UP in Stage -> play prev song
      this.store.playPrevSong().then(() => {
        this.refresh();
      });
    } else if (kc === 2071 || kc === 24) {
      // Volume Up
      const newVol = Math.min(1.0, this.store.accompanimentGain + 0.05);
      this.store.setAccompanimentGain(newVol);
      this.refresh();
    } else if (kc === 2072 || kc === 25) {
      // Volume Down
      const newVol = Math.max(0.0, this.store.accompanimentGain - 0.05);
      this.store.setAccompanimentGain(newVol);
      this.refresh();
    } else if (kc === 2067 || kc === 82) {
      // Menu -> toggle discovery / stage
      this.switchTab(this.activeTab === 0 ? 1 : 0);
    } else if (kc === 2 || kc === 4) {
      // Remote Back Key -> return to Stage (Tab 1) or Discovery (Tab 0)
      if (this.activeTab !== 0) {
        this.switchTab(0);
      }
    }
  }

  @Builder
  canvasBackdrop() {
    Stack() {
      // 1. Grape Soda Gradient Base（明快的葡萄蓝紫基底）
      Column()
        .width('100%')
        .height('100%')
        .linearGradient({
          angle: 160,
          colors: [
            [PivoTheme.backgroundGlow, 0.0],
            [PivoTheme.background, 0.55],
            [PivoTheme.backgroundDark, 1.0]
          ]
        })

      // 2. Aurora Layer 1: Top-Left Grape Purple
      Circle({ width: 560, height: 560 })
        .fill('rgba(255, 225, 215, 0.62)')
        .blur(140)
        .position({ x: '-15%', y: '-15%' })

      // 3. Aurora Layer 2: Top-Right Soda Cyan
      Circle({ width: 500, height: 500 })
        .fill('rgba(99, 190, 232, 0.20)')
        .blur(150)
        .position({ x: '55%', y: '10%' })

      // 4. Aurora Layer 3: Mid-Center Energy Pink
      Circle({ width: 440, height: 440 })
        .fill('rgba(255, 129, 151, 0.14)')
        .blur(160)
        .position({ x: '20%', y: '35%' })

      // 5. Aurora Layer 4: Bottom-Right Electric Gold Accent (右下微金绿流光)
      Circle({ width: 420, height: 420 })
        .fill('rgba(200, 240, 75, 0.18)')
        .blur(160)
        .position({ x: '40%', y: '65%' })
    }
    .width('100%')
    .height('100%')
    .hitTestBehavior(HitTestMode.None)
  }

  build() {
    Stack() {
      // 1. Atmospheric Ambient Glow Canvas
      this.canvasBackdrop()

      if (!this.store.isCloudLoggedIn) {
        // 强制登录与注册入口 (全屏演播级体验)
        AuthLoginPage({
          wide: this.isTvLayout,
          onLogin: async (username: string, password: string): Promise<boolean> => {
            const ok = await this.store.loginCloudAccount(username, password);
            this.refresh();
            return ok;
          },
          onRegister: async (username: string, password: string, nickname?: string): Promise<boolean> => {
            const ok = await this.store.registerCloudAccount(username, password, nickname);
            this.refresh();
            return ok;
          },
          onWeChatSuccess: (token: string, user?: UserInfo): void => {
            this.store.applyWeChatLogin(token, user);
            this.refresh();
          },
          onSuccess: (): void => {
            this.refresh();
          }
        })
      } else {
        // 2. Multi-device distinct root layout (已登录)
        if (this.isTvLayout) {
          // 电视端 / 16:9 大屏沉浸全屏布局 (100% 满屏无黑边，完全对标汽水音乐 TV 版)
          this.tvWidescreenLayout()
        } else {
          // 手机端 / 竖屏单手触控布局
          this.phonePortraitLayout()
        }
      }

      if (this.showServerConfigModal) {
        this.serverConfigModalBuilder()
      }
    }
    .width('100%').height('100%').backgroundColor(PivoTheme.background)
    .bindSheet($$this.showAccompanimentPanel, this.accompanimentPanelBuilder(), { height: '85%', showClose: false })
    .expandSafeArea([SafeAreaType.SYSTEM, SafeAreaType.CUTOUT], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM, SafeAreaEdge.START, SafeAreaEdge.END])
    .focusable(true)
    .onKeyEvent((event: KeyEvent) => {
      if (!this.showAccompanimentPanel) this.handleKeyEvent(event);
    })
    .onAreaChange((_oldArea: Area, newArea: Area) => {
      const w = Number(newArea.width);
      const h = Number(newArea.height);
      if (w > 0 && h > 0) {
        const oldLayout = this.isTvLayout;
        this.updateLayoutMode(w, h);
        if (oldLayout !== this.isTvLayout) {
          this.refresh();
        }
      }
    })
  }

  @Builder
  accompanimentPanelBuilder() {
    AccompanimentPanel({ store: this.store, onClose: (): void => { this.showAccompanimentPanel = false; } })
  }

  @Builder
  serverConfigModalBuilder() {
    Stack({ alignContent: Alignment.Center }) {
      // Backdrop
      Row()
        .width('100%')
        .height('100%')
        .backgroundColor('rgba(98, 98, 98, 0.32)')
        .onClick(() => {
          this.showServerConfigModal = false;
        })

      Column({ space: 14 }) {
        // Header
        Row() {
          Row({ space: 6 }) {
            Text('🎶')
              .fontSize(16)
            Text('音乐服务源与网络配置')
              .fontSize(16)
              .fontWeight(FontWeight.Bold)
              .fontColor(PivoTheme.text)
          }

          Blank()

          Button('✕')
            .height(28)
            .width(28)
            .fontSize(14)
            .fontColor(PivoTheme.textMuted)
            .backgroundColor(Color.Transparent)
            .onClick(() => {
              this.showServerConfigModal = false;
            })
        }
        .width('100%')

        Text('选择全网歌曲搜索与每日榜单的音乐服务提供者，或切换为离线本地模式。')
          .fontSize(12)
          .fontColor(PivoTheme.textSecondary)
          .lineHeight(18)
          .width('100%')

        // 双段式音源模式选择器
        Row({ space: 8 }) {
          Button('🌐 原生全网源 (推荐)')
            .layoutWeight(1.3)
            .height(34)
            .fontSize(12)
            .fontWeight(this.serverModalInputMode === MusicSourceMode.ONLINE ? FontWeight.Bold : FontWeight.Normal)
            .fontColor(this.serverModalInputMode === MusicSourceMode.ONLINE ? PivoTheme.primaryTextDark : PivoTheme.text)
            .backgroundColor(this.serverModalInputMode === MusicSourceMode.ONLINE ? PivoTheme.primary : PivoTheme.surface)
            .borderRadius(8)
            .border({ width: 0.8, color: this.serverModalInputMode === MusicSourceMode.ONLINE ? PivoTheme.primary : PivoTheme.border })
            .onClick(() => {
              this.serverModalInputMode = MusicSourceMode.ONLINE;
            })

          Button('📁 纯本地模式')
            .layoutWeight(1)
            .height(34)
            .fontSize(12)
            .fontWeight(this.serverModalInputMode === MusicSourceMode.LOCAL ? FontWeight.Bold : FontWeight.Normal)
            .fontColor(this.serverModalInputMode === MusicSourceMode.LOCAL ? PivoTheme.primaryTextDark : PivoTheme.text)
            .backgroundColor(this.serverModalInputMode === MusicSourceMode.LOCAL ? PivoTheme.primary : PivoTheme.surface)
            .borderRadius(8)
            .border({ width: 0.8, color: this.serverModalInputMode === MusicSourceMode.LOCAL ? PivoTheme.primary : PivoTheme.border })
            .onClick(() => {
              this.serverModalInputMode = MusicSourceMode.LOCAL;
            })
        }
        .width('100%')

        // 模式内容展示区
        if (this.serverModalInputMode === MusicSourceMode.ONLINE) {
          Column({ space: 10 }) {
            Column({ space: 4 }) {
              Row({ space: 6 }) {
                Text('✨')
                  .fontSize(12)
                Text('原生全网免签音源直连 (端侧多协议聚合)')
                  .fontSize(12)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(PivoTheme.text)
              }
              Text('免搭建免配置直连，集成酷我 320k 高音质 CDN、酷狗、QQ音乐官方榜单与逐字歌词，智能自动跨平台换源。')
                .fontSize(11)
                .fontColor(PivoTheme.textSecondary)
                .lineHeight(16)
            }
            .width('100%')
            .padding(10)
            .backgroundColor(PivoTheme.surfaceRaised)
            .borderRadius(8)

            // 原生引擎连通性测试
            Row({ space: 10 }) {
              Button(this.isTestingHuibqModal ? '正在测试连接…' : '🔍 测试原生引擎连通性')
                .height(32)
                .padding({ left: 12, right: 12 })
                .fontSize(11)
                .fontWeight(FontWeight.Medium)
                .fontColor(PivoTheme.text)
                .backgroundColor(PivoTheme.surface)
                .borderRadius(16)
                .border({ width: 0.8, color: PivoTheme.border })
                .enabled(!this.isTestingHuibqModal)
                .onClick(async () => {
                  this.isTestingHuibqModal = true;
                  this.huibqModalTestMsg = '正在检测连通性…';
                  const res = await this.store.testHuibqConnection();
                  this.isTestingHuibqModal = false;
                  this.huibqModalTestMsg = res.message;
                  this.huibqModalTestSuccess = res.success;
                })

              if (this.huibqModalTestMsg.length > 0) {
                Text(this.huibqModalTestMsg)
                  .fontSize(11)
                  .fontColor(this.huibqModalTestSuccess ? '#10B981' : '#EF4444')
                  .layoutWeight(1)
                  .maxLines(2)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
              }
            }
            .width('100%')
            .alignItems(VerticalAlign.Center)

            // 特性标签
            Row({ space: 6 }) {
              Text('酷我 320k')
                .fontSize(9)
                .fontColor(PivoTheme.textMuted)
                .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                .backgroundColor(PivoTheme.surfaceRaised)
                .borderRadius(4)
              Text('酷狗直连')
                .fontSize(9)
                .fontColor(PivoTheme.textMuted)
                .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                .backgroundColor(PivoTheme.surfaceRaised)
                .borderRadius(4)
              Text('QQ权威榜')
                .fontSize(9)
                .fontColor(PivoTheme.textMuted)
                .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                .backgroundColor(PivoTheme.surfaceRaised)
                .borderRadius(4)
              Text('网易云')
                .fontSize(9)
                .fontColor(PivoTheme.textMuted)
                .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                .backgroundColor(PivoTheme.surfaceRaised)
                .borderRadius(4)
              Text('汽水音乐')
                .fontSize(9)
                .fontColor(PivoTheme.textMuted)
                .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                .backgroundColor(PivoTheme.surfaceRaised)
                .borderRadius(4)
            }
            .width('100%')
          }
          .width('100%')
        } else {
          Column({ space: 8 }) {
            Row({ space: 6 }) {
              Text('📁')
                .fontSize(14)
              Text('纯本地音乐模式')
                .fontSize(12)
                .fontWeight(FontWeight.Bold)
                .fontColor(PivoTheme.text)
            }
            Text('停用所有在线榜单推荐与全网搜索，仅扫描和播放设备本地存储中的音乐。适合在完全无网、弱网或注重纯离线隐私的场景使用。')
              .fontSize(11)
              .fontColor(PivoTheme.textSecondary)
              .lineHeight(16)
          }
          .width('100%')
          .padding(12)
          .backgroundColor(PivoTheme.surfaceRaised)
          .borderRadius(8)
        }

        // Action Buttons
        Row({ space: 8 }) {
          Button('取消')
            .layoutWeight(1)
            .height(36)
            .fontSize(12)
            .fontColor(PivoTheme.textMuted)
            .backgroundColor(PivoTheme.surface)
            .borderRadius(18)
            .onClick(() => {
              this.showServerConfigModal = false;
            })

          Button('恢复默认')
            .layoutWeight(1)
            .height(36)
            .fontSize(12)
            .fontColor(PivoTheme.textMuted)
            .backgroundColor(PivoTheme.surface)
            .borderRadius(18)
            .onClick(async () => {
              this.serverModalInputMode = MusicSourceMode.ONLINE;
              await this.store.updateMusicSourceMode(MusicSourceMode.ONLINE);
              this.showServerConfigModal = false;
              promptAction.showToast({ message: '已恢复默认原生全网源' });
              this.refresh();
            })

          Button('保存生效')
            .layoutWeight(1.2)
            .height(36)
            .fontSize(13)
            .fontWeight(FontWeight.Bold)
            .fontColor(PivoTheme.primaryTextDark)
            .backgroundColor(PivoTheme.primary)
            .borderRadius(18)
            .onClick(async () => {
              await this.store.updateMusicSourceMode(this.serverModalInputMode);
              this.showServerConfigModal = false;
              const modeText = this.serverModalInputMode === MusicSourceMode.ONLINE ? '原生全网源' : '纯本地模式';
              promptAction.showToast({ message: `音乐源已配置为：${modeText}` });
              this.refresh();
            })
        }
        .width('100%')
        .padding({ top: 6 })
      }
      .width(this.isTvLayout ? 440 : '90%')
      .padding(20)
      .backgroundColor(PivoTheme.surface)
      .borderRadius(16)
      .shadow({ radius: 24, color: 'rgba(0, 0, 0, 0.45)', offsetX: 0, offsetY: 8 })
      .border({ width: 1, color: PivoTheme.border })
    }
    .width('100%')
    .height('100%')
    .position({ x: 0, y: 0 })
    .zIndex(999)
  }
}
