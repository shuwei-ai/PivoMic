import { promptAction } from '@kit.ArkUI';
import { AudioCapability, LyricDocument, LyricLine, LyricWord, MusicSourceKind, PlaybackState, Song, PlaybackSnapshot } from '../domain/MusicModels';
import { PivoTheme } from '../theme/PivoTheme';
import { KaraokeMixerControls } from './KaraokeMixerControls';
import { MicrophoneMeter } from './MicrophoneMeter';
import { CapabilityPanel } from './CapabilityPanel';
import { AudioDevicesModal } from './AudioDevicesModal';
import { ParticleStageBackground } from './ParticleStageBackground';
import { HeartBurstCanvas } from './HeartBurstCanvas';
import { findActiveLyricIndex } from '../services/LrcParser';
import { isValidArtist } from './MusicRecommendationPage';
import { PivoMicStore } from '../store/PivoMicStore';

function formatTime(ms: number): string {
  if (isNaN(ms) || ms < 0) return '00:00';
  const totalSec = Math.floor(ms / 1000);
  const m = Math.floor(totalSec / 60);
  const s = totalSec % 60;
  return `${m < 10 ? '0' : ''}${m}:${s < 10 ? '0' : ''}${s}`;
}

@Component({ freezeWhenInactive: true })
struct SongProgressBar {
  @Prop @Watch('onPositionPropChanged') positionMs: number = 0;
  @Prop durationMs: number = 0;
  accentColor: string = PivoTheme.primary;
  trackColor: string = PivoTheme.border;
  onSeek: (positionMs: number) => void = (_pos: number) => {};
  onDraggingChange?: (isDragging: boolean, currentPos: number) => void;

  @State isDragging: boolean = false;
  @State dragPositionMs: number = 0;
  private lastSeekTime: number = 0;

  aboutToAppear(): void {
    this.dragPositionMs = this.positionMs;
  }

  onPositionPropChanged(): void {
    const now = Date.now();
    // 保护期内（刚 seek 完 600ms 内）或拖拽中，不被旧的 positionMs 覆盖回弹
    if (!this.isDragging && (now - this.lastSeekTime > 600)) {
      this.dragPositionMs = this.positionMs;
    }
  }

  private currentDisplayPosition(): number {
    const now = Date.now();
    if (this.isDragging || (now - this.lastSeekTime <= 600)) {
      return Math.max(0, Math.min(this.dragPositionMs, this.durationMs));
    }
    return Math.max(0, Math.min(this.positionMs, this.durationMs));
  }

  private maxLimit(): number {
    return Math.max(1, this.durationMs);
  }

  build() {
    Column({ space: 2 }) {
      Slider({
        value: this.currentDisplayPosition(),
        min: 0,
        max: this.maxLimit(),
        step: 100
      })
        .width('100%')
        .selectedColor(this.isDragging ? PivoTheme.primary : this.accentColor)
        .trackColor(this.trackColor)
        .trackThickness(this.isDragging ? 4 : 2.5)
        .blockColor(this.isDragging ? PivoTheme.primaryDark : PivoTheme.textSecondary)
        .blockSize(this.isDragging ? { width: 12, height: 12 } : { width: 6, height: 6 })
        .focusable(true)
        .onKeyEvent((event?: KeyEvent) => {
          if (!event || event.type !== KeyType.Down) return;
          const current = this.currentDisplayPosition();
          if (event.keyCode === 2014 || event.keyCode === 21) {
            const next = Math.max(0, current - 5000);
            this.dragPositionMs = next;
            this.lastSeekTime = Date.now();
            this.onSeek(next);
          } else if (event.keyCode === 2015 || event.keyCode === 22) {
            const next = Math.min(this.durationMs, current + 5000);
            this.dragPositionMs = next;
            this.lastSeekTime = Date.now();
            this.onSeek(next);
          }
        })
        .onChange((value: number, mode: SliderChangeMode) => {
          const clamped = Math.max(0, Math.min(value, this.durationMs));
          if (mode === SliderChangeMode.Begin || mode === SliderChangeMode.Moving) {
            this.isDragging = true;
            this.dragPositionMs = clamped;
            if (this.onDraggingChange) {
              this.onDraggingChange(true, clamped);
            }
          } else if (mode === SliderChangeMode.End || mode === SliderChangeMode.Click) {
            this.isDragging = false;
            this.dragPositionMs = clamped;
            this.lastSeekTime = Date.now();
            if (this.onDraggingChange) {
              this.onDraggingChange(false, clamped);
            }
            this.onSeek(clamped);
          }
        })

      Row() {
        Text(formatTime(this.currentDisplayPosition()))
          .fontSize(10)
          .fontColor(this.isDragging ? PivoTheme.primaryDark : PivoTheme.textMuted)
          .fontWeight(this.isDragging ? FontWeight.Bold : FontWeight.Normal)
        Blank()
        Text(formatTime(this.durationMs))
          .fontSize(10)
          .fontColor(PivoTheme.textMuted)
      }
      .width('100%')
    }
    .width('100%')
  }
}

@Component
export struct KaraokeStage {
  @Prop activeAccompanimentId: string = '';
  @Prop separationBusy: boolean = false;
  @Prop trackSwitchPending: boolean = false;
  onAccompaniment: () => void = (): void => {};
  onOriginalTrack: () => void = (): void => {};
  store?: PivoMicStore = undefined;
  @Prop songId: string = '';
  @Prop @Watch('onSongPropChanged') title: string = '请选择歌曲';
  @Prop artist: string = '';
  @Prop coverUrl: string = '';
  @Prop @Watch('onLinesPropChanged') lines: LyricLine[] = [];
  @Prop @Watch('onActiveIndexPropChanged') activeIndex: number = -1;
  @Prop state: PlaybackState = PlaybackState.IDLE;
  @Prop positionMs: number = 0;
  @Prop durationMs: number = 0;
  @Prop bufferedPositionMs: number = 0;
  @Prop volume: number = 0.8;
  @Prop wide: boolean = false;
  @Prop @Watch('onVisibilityChanged') isVisible: boolean = true;
  @Prop isFavorite: boolean = false;
  @Prop upcomingSongs: Song[] = [];
  @Prop queue: Song[] = [];
  @Prop @Watch('onQueueIndexPropChanged') currentQueueIndex: number = 0;
  @Prop capability: AudioCapability = {
    simulated: true, microphoneAvailable: false, lowLatencyAvailable: false,
    aecAvailable: false, message: ''
  };
  @Prop microphonePeak: number = 0;
  @Prop latencyMs: number = 0;
  @Prop fastMode: boolean = false;
  @Prop aecSupported: boolean = false;
  @Prop monitoringAllowed: boolean = false;
  @Prop blockedReason: string = '';
  @Prop outputRoute: string = '未检测';
  @Prop startPending: boolean = false;
  @Prop accompanimentGain: number = 0.8;
  @Prop vocalGain: number = 0.8;
  @Prop reverbMix: number = 0.25;
  @Prop audioRoute: number = 0;
  @Prop pitchShiftSemitones: number = 0;
  @Prop autoTuneActive: boolean = false;
  @Prop autoTuneStrength: number = 0.5;
  @Prop isRecording: boolean = false;
  @Prop recordedDurationMs: number = 0;
  @Prop micEnabled: boolean = false;
  @Prop isHeadsetConnected: boolean = false;

  @State showMixerModal: boolean = false;
  @State showAudioDevicesModal: boolean = false;
  @State showExpandedLyrics: boolean = false;
  @State expandedFollowActive: boolean = true;
  @State dragOffsetY: number = 0;
  @State contentOpacity: number = 1.0;
  @State contentTranslateY: number = 0;
  @State isSwitchingSong: boolean = false;
  @State isDraggingProgress: boolean = false;
  @State dragPositionMs: number = 0;
  @State focusedTopBtn: string = '';
  @State focusedSideAction: string = '';
  @State focusedUpcomingId: string = '';
  @State focusedDownNext: boolean = false;
  @State focusedModalClose: boolean = false;
  @State showHeartBurst: boolean = false;
  @State heartBurstTrigger: number = 0;
  @State heartBurstIsFav: boolean = false;
  @State favButtonScale: number = 1.0;
  @State localPositionMs: number = 0;
  @State localDurationMs: number = 0;
  @State @Watch('onLocalActiveIndexChanged') localActiveIndex: number = -1;
  @State localLines: LyricLine[] = [];
  private lyricsScroller: Scroller = new Scroller();
  private expandedScroller: Scroller = new Scroller();
  private expandedTouchDownY: number = -1;
  private lyricsListener?: (lyrics: LyricDocument) => void;
  private progressListener?: (pos: number, activeIdx: number, snap: PlaybackSnapshot) => void;
  private heartBurstTimerId: number = -1;
  private lastPlayClickTime: number = 0;
  private playClickTimerId: number = -1;
  private songSwitchTimerId: number = -1;

  onLocalActiveIndexChanged(): void {
    if (this.showExpandedLyrics) {
      // 展开歌词层：仅在自动跟随开启时滚动
      if (this.expandedFollowActive) {
        this.scrollToActiveOn(this.expandedScroller, true);
      }
    } else {
      // 默认播放页：歌词始终自动跟随
      this.scrollToActive(true);
    }
  }

  onActiveIndexPropChanged(): void {
    if (!this.store) {
      this.localActiveIndex = this.activeIndex;
    }
  }

  onLinesPropChanged(): void {
    if (this.lines.length > 0) {
      this.localLines = this.lines;
      setTimeout(() => {
        this.scrollToActive(false);
      }, 100);
    }
  }

  private getEffectiveLines(): LyricLine[] {
    if (this.localLines.length > 0) {
      return this.localLines;
    }
    if (this.store && this.store.lyrics.lines.length > 0) {
      return this.store.lyrics.lines;
    }
    return this.lines;
  }

  private scrollToActiveOn(scroller: Scroller, smooth: boolean): void {
    const lines = this.getEffectiveLines();
    const active = this.currentActiveIndex();
    if (active >= 0 && active < lines.length) {
      try {
        scroller.scrollToIndex(active, smooth, ScrollAlign.CENTER);
      } catch (_) {}
    }
  }

  private scrollToActive(smooth: boolean): void {
    this.scrollToActiveOn(this.lyricsScroller, smooth);
  }

  private openExpandedLyrics(): void {
    this.showExpandedLyrics = true;
    this.expandedFollowActive = true;
    setTimeout(() => {
      this.scrollToActiveOn(this.expandedScroller, false);
    }, 120);
  }

  private closeExpandedLyrics(): void {
    this.showExpandedLyrics = false;
    this.expandedFollowActive = true;
    // 回到默认播放页后重新同步歌词位置
    setTimeout(() => {
      this.scrollToActive(false);
    }, 120);
  }

  private syncLocalProgress(): void {
    if (!this.store) return;
    this.localPositionMs = this.store.playback.positionMs;
    let dur = this.store.playback.durationMs > 0 ? this.store.playback.durationMs : (this.store.selectedSong?.durationMs ?? 0);
    if (dur <= 0 && this.store.lyrics.lines.length > 0) {
      const lastLine = this.store.lyrics.lines[this.store.lyrics.lines.length - 1];
      if (lastLine && lastLine.timeMs > 0) {
        dur = lastLine.timeMs + 5000;
      }
    }
    this.localDurationMs = dur;
    this.localActiveIndex = this.store.activeLyricIndex;
    if (this.store.lyrics.lines.length > 0) {
      this.localLines = this.store.lyrics.lines;
    } else if (this.lines.length > 0) {
      this.localLines = this.lines;
    }
  }

  private attachProgressListener(): void {
    if (!this.store || !this.isVisible || this.progressListener) return;
    this.syncLocalProgress();
    this.progressListener = (pos: number, activeIdx: number, snap: PlaybackSnapshot) => {
      this.localPositionMs = pos;
      this.localActiveIndex = activeIdx;
      if (snap) {
        let snapDur = snap.durationMs > 0 ? snap.durationMs : (this.store?.selectedSong?.durationMs ?? 0);
        if (snapDur <= 0 && this.store && this.store.lyrics.lines.length > 0) {
          const lastLine = this.store.lyrics.lines[this.store.lyrics.lines.length - 1];
          if (lastLine && lastLine.timeMs > 0) {
            snapDur = lastLine.timeMs + 5000;
          }
        }
        if (snapDur > 0 && snapDur !== this.localDurationMs) {
          this.localDurationMs = snapDur;
        }
      }
      if (this.store && this.store.lyrics.lines.length > 0 && this.localLines.length !== this.store.lyrics.lines.length) {
        this.localLines = this.store.lyrics.lines;
      }
    };
    this.store.addProgressListener(this.progressListener);

    if (!this.lyricsListener && this.store.addLyricsListener) {
      this.lyricsListener = (lyrics: LyricDocument) => {
        if (lyrics.lines.length > 0) {
          this.localLines = lyrics.lines;
          setTimeout(() => {
            this.scrollToActive(false);
          }, 100);
        }
      };
      this.store.addLyricsListener(this.lyricsListener);
    }
  }

  private detachProgressListener(): void {
    if (this.store && this.progressListener) {
      this.store.removeProgressListener(this.progressListener);
      this.progressListener = undefined;
    }
    if (this.store && this.lyricsListener && this.store.removeLyricsListener) {
      this.store.removeLyricsListener(this.lyricsListener);
      this.lyricsListener = undefined;
    }
  }

  aboutToAppear(): void {
    this.contentOpacity = 1.0;
    this.contentTranslateY = 0;
    this.dragOffsetY = 0;
    this.isSwitchingSong = false;
    if (this.store) {
      this.syncLocalProgress();
      this.attachProgressListener();
    } else {
      this.localPositionMs = this.positionMs;
      this.localDurationMs = this.durationMs;
      this.localActiveIndex = this.activeIndex;
      this.localLines = this.lines;
    }
    setTimeout(() => {
      this.scrollToActive(false);
    }, 200);
  }

  aboutToDisappear(): void {
    this.detachProgressListener();
    if (this.heartBurstTimerId !== -1) {
      clearTimeout(this.heartBurstTimerId);
      this.heartBurstTimerId = -1;
    }
    if (this.playClickTimerId !== -1) {
      clearTimeout(this.playClickTimerId);
      this.playClickTimerId = -1;
    }
    if (this.songSwitchTimerId !== -1) {
      clearTimeout(this.songSwitchTimerId);
      this.songSwitchTimerId = -1;
    }
    if (this.lyricClickTimerId !== -1) {
      clearTimeout(this.lyricClickTimerId);
      this.lyricClickTimerId = -1;
    }
    this.showHeartBurst = false;
    this.isSwitchingSong = false;
  }

  onQueueIndexPropChanged(): void {
    if (!this.isVisible) {
      this.isSwitchingSong = false;
      this.contentOpacity = 1.0;
      this.contentTranslateY = 0;
      this.dragOffsetY = 0;
    }
  }

  onSongPropChanged(): void {
    if (!this.isVisible || !this.isSwitchingSong) {
      this.isSwitchingSong = false;
      this.contentOpacity = 1.0;
      this.contentTranslateY = 0;
      this.dragOffsetY = 0;
    }
    this.syncLocalProgress();
    // 换歌后展开歌词层重新回到自动跟随
    if (this.showExpandedLyrics) {
      this.expandedFollowActive = true;
      setTimeout(() => {
        this.scrollToActiveOn(this.expandedScroller, false);
      }, 150);
    }
    setTimeout(() => {
      this.scrollToActive(false);
    }, 150);
  }

  onVisibilityChanged(): void {
    if (this.isVisible) {
      this.syncLocalProgress();
      this.attachProgressListener();
      setTimeout(() => {
        this.scrollToActive(false);
      }, 100);
    } else {
      this.detachProgressListener();
      if (this.heartBurstTimerId !== -1) {
        clearTimeout(this.heartBurstTimerId);
        this.heartBurstTimerId = -1;
      }
      if (this.playClickTimerId !== -1) {
        clearTimeout(this.playClickTimerId);
        this.playClickTimerId = -1;
      }
      this.showHeartBurst = false;
      this.isSwitchingSong = false;
    }
  }

  private triggerFavButtonPulse(): void {
    animateTo({ duration: 160, curve: Curve.EaseOut }, () => {
      this.favButtonScale = 1.22;
    });
    setTimeout(() => {
      animateTo({ duration: 200, curve: Curve.EaseIn }, () => {
        this.favButtonScale = 1.0;
      });
    }, 160);
  }

  private lastDoubleTapActionTime: number = 0;
  private lastStageClickTime: number = 0;
  private lastLyricClickTime: number = 0;
  private lyricClickTimerId: number = -1;

  private handleStageClick(): void {
    if (this.lyricClickTimerId !== -1) {
      clearTimeout(this.lyricClickTimerId);
      this.lyricClickTimerId = -1;
    }
    const now = Date.now();
    if (now - this.lastStageClickTime < 350) {
      this.lastStageClickTime = 0;
      this.triggerDoubleTapFavorite();
    } else {
      this.lastStageClickTime = now;
    }
  }

  private handleLyricClick(): void {
    const now = Date.now();
    if (now - this.lastLyricClickTime < 300 && this.lyricClickTimerId !== -1) {
      // 连续两次点击歌词 -> 判定为双击，取消单次展开歌词，立即执行双击收藏/取消收藏
      clearTimeout(this.lyricClickTimerId);
      this.lyricClickTimerId = -1;
      this.lastLyricClickTime = 0;
      this.triggerDoubleTapFavorite();
    } else {
      // 单击候选 -> 250ms 防抖倒计时，超时未连按则打开歌词详情界面
      this.lastLyricClickTime = now;
      if (this.lyricClickTimerId !== -1) {
        clearTimeout(this.lyricClickTimerId);
      }
      this.lyricClickTimerId = setTimeout(() => {
        if (this.getEffectiveLines().length > 0) {
          this.openExpandedLyrics();
        }
        this.lyricClickTimerId = -1;
      }, 250);
    }
  }

  private triggerDoubleTapFavorite(): void {
    if (this.lyricClickTimerId !== -1) {
      clearTimeout(this.lyricClickTimerId);
      this.lyricClickTimerId = -1;
    }
    const now = Date.now();
    if (now - this.lastDoubleTapActionTime < 400) {
      return;
    }
    this.lastDoubleTapActionTime = now;

    // 双击在“收藏”与“取消收藏”之间双向 Toggle 切换
    const nextFav = !this.isFavorite;
    this.isFavorite = nextFav; // 本地乐观即时翻转，防连续快速操作读取陈旧状态
    this.onToggleFavorite();
    this.heartBurstIsFav = nextFav;
    this.heartBurstTrigger = Date.now();
    this.showHeartBurst = true;
    if (this.heartBurstTimerId !== -1) {
      clearTimeout(this.heartBurstTimerId);
    }
    this.heartBurstTimerId = setTimeout(() => {
      this.showHeartBurst = false;
      this.heartBurstTimerId = -1;
    }, 700);

    // 右侧/底部收藏胶囊按钮弹性呼吸放大联动
    this.triggerFavButtonPulse();

    try {
      promptAction.showToast({
        message: nextFav ? '已加入收藏 ♥' : '已取消收藏',
        duration: 1200,
        bottom: 120
      });
    } catch (_) {}
  }

  private handlePlayButtonClick(): void {
    const now = Date.now();
    if (now - this.lastPlayClickTime < 300 && this.playClickTimerId !== -1) {
      // 连按两次（双击） -> 收藏 / 取消收藏
      clearTimeout(this.playClickTimerId);
      this.playClickTimerId = -1;
      this.lastPlayClickTime = 0;
      this.triggerDoubleTapFavorite();
    } else {
      // 单击候选 -> 260ms 防抖倒计时，超时未连按则执行播放/暂停
      this.lastPlayClickTime = now;
      if (this.playClickTimerId !== -1) {
        clearTimeout(this.playClickTimerId);
      }
      this.playClickTimerId = setTimeout(() => {
        this.onToggle();
        this.playClickTimerId = -1;
      }, 260);
    }
  }

  private currentActiveIndex(): number {
    const lines = this.getEffectiveLines();
    if (this.isDraggingProgress && lines.length > 0) {
      return findActiveLyricIndex(lines, this.dragPositionMs);
    }
    if (this.store) {
      return this.localActiveIndex >= 0 ? this.localActiveIndex : this.activeIndex;
    }
    return this.activeIndex;
  }

  private currentDisplayPosition(): number {
    if (this.isDraggingProgress) {
      return this.dragPositionMs;
    }
    if (this.store) {
      return this.localPositionMs;
    }
    return this.positionMs;
  }

  private effectiveQueue(): Song[] {
    if (this.queue && this.queue.length > 0) {
      return this.queue;
    }
    if (this.songId && this.songId.length > 0) {
      const fallbackSong: Song = {
        id: this.songId,
        title: this.title,
        artist: this.artist,
        coverUrl: this.coverUrl,
        durationMs: this.durationMs,
        uri: '',
        format: 'mp3',
        source: MusicSourceKind.ONLINE
      };
      return [fallbackSong];
    }
    return [];
  }

  onSelectSong: (song: Song) => void = (_song: Song): void => {};
  onSwipeChangeSong?: (song: Song, targetIndex: number) => void;
  onToggle: () => void = (): void => {};
  onStop: () => void = (): void => {};
  onPreview: () => void = (): void => {};
  onToggleMicrophone: () => void = (): void => {};
  onNextSong: () => Promise<void> | void = (): void => {};
  onPrevSong: () => Promise<void> | void = (): void => {};
  onSeek: (value: number) => void = (_value: number): void => {};
  onVolume: (value: number) => void = (_value: number): void => {};
  onVocalGain: (value: number) => void = (_value: number): void => {};
  onReverbMix: (value: number) => void = (_value: number): void => {};
  onRouteChange: (route: number) => void = (_route: number): void => {};
  onPitchShiftChange: (semitones: number) => void = (_semitones: number): void => {};
  onAutoTuneToggle: (active: boolean) => void = (_active: boolean): void => {};
  onAutoTuneStrengthChange: (strength: number) => void = (_strength: number): void => {};
  onRecordingToggle: () => void = (): void => {};
  onToggleFavorite: () => void = (): void => {};
  onOpenLibrary: () => void = (): void => {};
  onOpenProfile: () => void = (): void => {};
  onToggleOrientation: () => void = (): void => {};
  onSearchArtist?: (artist: string) => void = (_artist: string): void => {};

  private triggerSongSwitch(direction: number): void {
    if (this.isSwitchingSong) return;
    this.isSwitchingSong = true;

    // 1. 垂直平滑位移并淡出当前歌曲视图 (上滑 direction > 0: 向上滑出 -50px; 下滑 direction < 0: 向下滑出 +50px)
    animateTo({ duration: 180, curve: Curve.EaseOut }, () => {
      this.contentOpacity = 0.0;
      this.contentTranslateY = direction > 0 ? -50 : 50;
    });

    let completed = false;
    const completeSwitch = (): void => {
      if (completed) return;
      completed = true;
      if (this.songSwitchTimerId !== -1) {
        clearTimeout(this.songSwitchTimerId);
        this.songSwitchTimerId = -1;
      }
      this.contentTranslateY = direction > 0 ? 50 : -50;
      animateTo({ duration: 240, curve: Curve.FastOutSlowIn }, () => {
        this.contentOpacity = 1.0;
        this.contentTranslateY = 0;
      });
      this.isSwitchingSong = false;
    };

    // 8 秒超时保护兜底，防止极端异常下界面永远卡在淡出状态
    this.songSwitchTimerId = setTimeout(() => {
      completeSwitch();
    }, 8000);

    const switchResult = direction > 0 ? this.onNextSong() : this.onPrevSong();
    if (switchResult instanceof Promise) {
      switchResult.then(() => {
        completeSwitch();
      }).catch(() => {
        completeSwitch();
      });
    } else {
      setTimeout(() => {
        completeSwitch();
      }, 180);
    }
  }

  private getLyricLineText(index: number): string {
    const lines = this.getEffectiveLines();
    if (index >= 0 && index < lines.length) {
      return lines[index].text;
    }
    return '';
  }

  private getLyricLineTime(index: number): number {
    const lines = this.getEffectiveLines();
    if (index >= 0 && index < lines.length) {
      return lines[index].timeMs;
    }
    return 0;
  }

  @Builder
  micVectorIcon(fillColor: string, iconSize: number = 20) {
    Image($r('app.media.ic_microphone'))
      .width(iconSize)
      .height(iconSize)
      .fillColor(fillColor)
      .objectFit(ImageFit.Contain)
  }

  @Builder
  musicVectorIcon(fillColor: string, iconSize: number = 20) {
    Image($r('app.media.ic_music_note'))
      .width(iconSize)
      .height(iconSize)
      .fillColor(fillColor)
      .objectFit(ImageFit.Contain)
  }

  @Builder
  headphoneVectorIcon(fillColor: string, iconSize: number = 20) {
    Image($r('app.media.ic_headphone'))
      .width(iconSize)
      .height(iconSize)
      .fillColor(fillColor)
      .objectFit(ImageFit.Contain)
  }

  @Builder
  audioDeviceVectorIcon(fillColor: string, iconSize: number = 16) {
    Image($r('app.media.ic_microphone'))
      .width(iconSize)
      .height(iconSize)
      .fillColor(fillColor)
      .objectFit(ImageFit.Contain)
  }

  @Builder
  heartVectorIcon(iconSize: number = 20) {
    if (this.isFavorite) {
      Image($r('app.media.ic_heart_filled'))
        .width(iconSize)
        .height(iconSize)
        .fillColor('#FF2D55')
        .objectFit(ImageFit.Contain)
    } else {
      Image($r('app.media.ic_heart'))
        .width(iconSize)
        .height(iconSize)
        .fillColor(PivoTheme.text)
        .objectFit(ImageFit.Contain)
    }
  }

  @Builder
  playPauseVectorIcon(fillColor: string, iconSize: number = 18) {
    if (this.state === PlaybackState.PLAYING) {
      Image($r('app.media.ic_pause'))
        .width(iconSize)
        .height(iconSize)
        .fillColor(fillColor)
        .objectFit(ImageFit.Contain)
    } else {
      Image($r('app.media.ic_play'))
        .width(iconSize)
        .height(iconSize)
        .fillColor(fillColor)
        .objectFit(ImageFit.Contain)
        .margin({ left: 2 })
    }
  }

  @Builder
  lyricWordLine(line: LyricLine, active: boolean, distance: number, isCenter: boolean, isCompact: boolean = false) {
    Row() {
      ForEach(line.words, (word: LyricWord) => {
        Text(word.text)
          .fontSize(active ? (isCenter ? 21 : 22) : (distance === 1 ? 16 : (distance === 2 ? 14 : 13)))
          .fontWeight(active ? FontWeight.Bold : (distance <= 1 ? FontWeight.Medium : FontWeight.Normal))
          .fontColor(active && this.currentDisplayPosition() >= word.timeMs ? PivoTheme.primary : (active ? PivoTheme.text : (distance === 1 ? PivoTheme.textSecondary : (distance === 2 ? PivoTheme.textMuted : PivoTheme.textFaint))))
          .opacity(active ? 1.0 : (distance === 1 ? 0.80 : (distance === 2 ? 0.55 : 0.35)))
      })
    }
    .justifyContent(isCenter ? FlexAlign.Center : FlexAlign.Start)
    .width('100%')
    .padding({
      top: active ? 10 : (isCompact ? (distance === 1 ? 3 : 2) : (distance === 1 ? 6 : 4)),
      bottom: active ? 10 : (isCompact ? (distance === 1 ? 3 : 2) : (distance === 1 ? 6 : 4)),
      left: isCenter ? 12 : 4,
      right: isCenter ? 12 : 4
    })
    .scale(active ? { x: 1.04, y: 1.04 } : { x: 1.0, y: 1.0 })
    .animation({ duration: 200, curve: Curve.FastOutSlowIn })
  }

  @Builder
  lyricPlainLine(line: LyricLine, index: number, active: boolean, distance: number, isCenter: boolean, isCompact: boolean = false) {
    Row() {
      Text(line.text)
        .width('100%')
        .textAlign(isCenter ? TextAlign.Center : TextAlign.Start)
        .fontSize(active ? (isCenter ? 21 : 22) : (distance === 1 ? 16 : (distance === 2 ? 14 : 13)))
        .fontWeight(active ? FontWeight.Bold : (distance <= 1 ? FontWeight.Medium : FontWeight.Normal))
        .fontColor(active ? PivoTheme.text : (distance === 1 ? PivoTheme.textSecondary : (distance === 2 ? PivoTheme.textMuted : PivoTheme.textFaint)))
        .opacity(active ? 1.0 : (distance === 1 ? 0.80 : (distance === 2 ? 0.55 : 0.35)))
        .maxLines(active ? 2 : 1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .padding({
      top: active ? 10 : (isCompact ? (distance === 1 ? 3 : 2) : (distance === 1 ? 6 : 4)),
      bottom: active ? 10 : (isCompact ? (distance === 1 ? 3 : 2) : (distance === 1 ? 6 : 4)),
      left: isCenter ? 12 : 4,
      right: isCenter ? 12 : 4
    })
    .scale(active ? { x: 1.04, y: 1.04 } : { x: 1.0, y: 1.0 })
    .animation({ duration: 200, curve: Curve.FastOutSlowIn })
  }

  // Multi-line Dynamic Lyrics Stream with Smooth-Scrolling List + Scroller
  // interactive=false: 默认播放页，歌词仅自动跟随、不响应手动拖动（触摸穿透给父容器切歌手势）
  // interactive=true:  展开歌词层，可自由滚动，手动浏览后暂停自动跟随
  @Builder
  lyricStream(isCenterAligned: boolean, isCompact: boolean, interactive: boolean, scroller: Scroller) {
    if (this.getEffectiveLines().length === 0) {
      Column({ space: 10 }) {
        Row({ space: 8 }) {
          Text('♪')
            .fontSize(18)
            .fontColor(PivoTheme.primary)
          Text(this.state === PlaybackState.PLAYING ? '正在为您伴奏演唱' : (this.title.length > 0 && this.title !== '暂无歌曲播放' ? '轻触下方播放按钮开启演唱' : '请在推荐歌单或搜索中选择歌曲'))
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor(PivoTheme.text)
        }
        .justifyContent(FlexAlign.Center)

        Text('歌曲播放与实时低延迟耳返')
          .fontSize(12)
          .fontColor(PivoTheme.textMuted)
      }
      .width('100%')
      .alignItems(HorizontalAlign.Center)
      .padding({ top: 24, bottom: 24 })
      .backgroundColor(Color.Transparent)
      .priorityGesture(
        TapGesture({ count: 2 })
          .onAction(() => {
            this.triggerDoubleTapFavorite();
          })
      )
      .onClick(() => {
        this.handleLyricClick();
      })
      .id(`lyric_stream_empty_${this.songId || this.title}${interactive ? '_exp' : ''}`)
    } else {
      Stack({ alignContent: Alignment.Center }) {
        List({ space: isCompact ? 2 : (isCenterAligned ? 10 : 8), scroller: scroller }) {
          ForEach(this.getEffectiveLines(), (line: LyricLine, index: number) => {
            ListItem() {
              Column() {
                if (line.words.length > 0) {
                  this.lyricWordLine(
                    line,
                    index === this.currentActiveIndex(),
                    Math.abs(index - (this.currentActiveIndex() >= 0 ? this.currentActiveIndex() : 0)),
                    isCenterAligned,
                    isCompact
                  )
                } else {
                  this.lyricPlainLine(
                    line,
                    index,
                    index === this.currentActiveIndex(),
                    Math.abs(index - (this.currentActiveIndex() >= 0 ? this.currentActiveIndex() : 0)),
                    isCenterAligned,
                    isCompact
                  )
                }
              }
              .width('100%')
              .onClick(() => {
                // 仅展开歌词层支持点句跳唱；点击后恢复自动跟随
                if (interactive) {
                  this.onSeek(line.timeMs);
                  this.expandedFollowActive = true;
                  this.scrollToActiveOn(scroller, true);
                } else {
                  this.handleLyricClick();
                }
              })
            }
            .clip(true)
          }, (line: LyricLine, index: number) => `${this.songId || this.title}_lrc_${index}_${line.timeMs}_${index === this.currentActiveIndex() ? '1' : '0'}`)
        }
        .width('100%')
        .height('100%')
        .padding({
          top: isCompact ? 16 : (isCenterAligned ? 56 : 48),
          bottom: isCompact ? 24 : (isCenterAligned ? 56 : 48),
          left: isCenterAligned ? 12 : 4,
          right: isCenterAligned ? 12 : 4
        })
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)
        .clip(true)
        // 默认播放页：允许触摸事件传递，同时响应手势
        .hitTestBehavior(interactive ? HitTestMode.Default : HitTestMode.Transparent)
        .onTouch((event: TouchEvent) => {
          if (!interactive) return;
          if (event.type === TouchType.Down) {
            this.expandedTouchDownY = event.touches.length > 0 ? event.touches[0].y : -1;
          } else if (event.type === TouchType.Move) {
            // 手指实际拖动超过阈值才暂停自动跟随，避免轻点歌词误暂停
            if (this.expandedTouchDownY >= 0 && event.touches.length > 0 &&
              Math.abs(event.touches[0].y - this.expandedTouchDownY) > 8) {
              this.expandedFollowActive = false;
            }
          }
        })

        // Top Subtle Gradient Mask
        Row()
          .width('100%')
          .height(isCompact ? 20 : 36)
          .linearGradient({
            angle: 180,
            colors: [
              ['rgba(255, 249, 238, 0.95)', 0.0],
              ['rgba(255, 249, 238, 0.0)', 1.0]
            ]
          })
          .position({ x: 0, y: 0 })
          .hitTestBehavior(HitTestMode.None)

        // Bottom Subtle Gradient Mask
        Row()
          .width('100%')
          .height(isCompact ? 20 : 36)
          .linearGradient({
            angle: 0,
            colors: [
              ['rgba(255, 249, 238, 0.95)', 0.0],
              ['rgba(255, 249, 238, 0.0)', 1.0]
            ]
          })
          .position({ x: 0, y: '100%' })
          .markAnchor({ x: 0, y: isCompact ? 20 : 36 })
          .hitTestBehavior(HitTestMode.None)
      }
      .width('100%')
      .layoutWeight(1)
      .clip(true)
      .backgroundColor(Color.Transparent)
      .hitTestBehavior(HitTestMode.Default)
      .priorityGesture(
        TapGesture({ count: 2 })
          .onAction(() => {
            if (!interactive) {
              this.triggerDoubleTapFavorite();
            }
          })
      )
      .onClick(() => {
        if (!interactive) {
          this.handleLyricClick();
        }
      })
      .id(`lyric_stream_lines_${this.songId || this.title}${interactive ? '_exp' : ''}`)
    }
  }

  // Widescreen Layout (TV / 16:9 Landscape)
  @Builder
  widescreenLayout() {
    Column() {
      // 2.1 Top Header Bar: PivoMic Logo (Left) + Song Meta (Center) + Search (⌕) & Profile (○) Circles (Right)
      Row() {
        Text('PivoMic')
          .fontSize(28)
          .fontWeight(FontWeight.Bold)
          .fontColor(PivoTheme.text)
          .letterSpacing(0.5)

        Blank()

        // Center: Song Title & Artist with Album Art Badge (Figma Screen 2)
        Row({ space: 14 }) {
          if (this.coverUrl && this.coverUrl.length > 0) {
            Image(this.coverUrl)
              .width(42)
              .height(42)
              .borderRadius(10)
              .objectFit(ImageFit.Cover)
              .border({ width: 1.2, color: PivoTheme.border })
              .shadow({ radius: 10, color: 'rgba(120, 105, 85, 0.14)' })
          }

          Column({ space: 2 }) {
            Text(this.title.length > 0 ? this.title : '暂无歌曲播放')
              .fontSize(22)
              .fontWeight(FontWeight.Bold)
              .fontColor(PivoTheme.text)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })

            Row({ space: 8 }) {
              if (this.artist.length > 0) {
                Text(this.artist)
                  .fontSize(12)
                  .fontColor(PivoTheme.textMuted)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .padding({ left: 4, right: 4, top: 2, bottom: 2 })
                  .borderRadius(4)
                  .onClick(() => {
                    if (this.artist && isValidArtist(this.artist) && this.onSearchArtist) {
                      this.onSearchArtist(this.artist);
                    }
                  })
              }

              Text('48kHz 演播级无损')
                .fontSize(10)
                .fontColor(PivoTheme.accent)
                .padding({ left: 6, right: 6, top: 1, bottom: 1 })
                .backgroundColor(PivoTheme.accentGlow)
                .borderRadius(4)
            }
          }
          .alignItems(HorizontalAlign.Start)
        }
        .alignItems(VerticalAlign.Center)

        Blank()

        Row({ space: 14 }) {
          // Search Circle Button
          Row() {
            Text('⌕')
              .fontSize(20)
              .fontColor(this.focusedTopBtn === 'search' ? PivoTheme.primary : PivoTheme.text)
          }
          .width(44)
          .height(44)
          .borderRadius(22)
          .justifyContent(FlexAlign.Center)
          .backgroundColor(this.focusedTopBtn === 'search' ? PivoTheme.surfaceSelected : PivoTheme.surfaceCircleDark)
          .border({
            width: this.focusedTopBtn === 'search' ? 2.5 : 1,
            color: this.focusedTopBtn === 'search' ? PivoTheme.primary : PivoTheme.border
          })
          .shadow(this.focusedTopBtn === 'search' ? { radius: 14, color: PivoTheme.primaryGlow } : undefined)
          .scale({ x: this.focusedTopBtn === 'search' ? 1.08 : 1.0, y: this.focusedTopBtn === 'search' ? 1.08 : 1.0 })
          .focusable(true)
          .onFocus(() => {
            this.focusedTopBtn = 'search';
          })
          .onBlur(() => {
            if (this.focusedTopBtn === 'search') this.focusedTopBtn = '';
          })
          .onClick(() => this.onOpenLibrary())

          // Profile Circle Button
          Row() {
            Text('○')
              .fontSize(22)
              .fontColor(this.focusedTopBtn === 'profile' ? PivoTheme.primary : PivoTheme.text)
          }
          .width(44)
          .height(44)
          .borderRadius(22)
          .justifyContent(FlexAlign.Center)
          .backgroundColor(this.focusedTopBtn === 'profile' ? PivoTheme.surfaceSelected : PivoTheme.surfaceCircleDark)
          .border({
            width: this.focusedTopBtn === 'profile' ? 2.5 : 1,
            color: this.focusedTopBtn === 'profile' ? PivoTheme.primary : PivoTheme.border
          })
          .shadow(this.focusedTopBtn === 'profile' ? { radius: 14, color: PivoTheme.primaryGlow } : undefined)
          .scale({ x: this.focusedTopBtn === 'profile' ? 1.08 : 1.0, y: this.focusedTopBtn === 'profile' ? 1.08 : 1.0 })
          .focusable(true)
          .onFocus(() => {
            this.focusedTopBtn = 'profile';
          })
          .onBlur(() => {
            if (this.focusedTopBtn === 'profile') this.focusedTopBtn = '';
          })
          .onClick(() => this.onOpenProfile())

          // K歌模式切换 Circle Button（与竖屏底部左键功能一致）
          Row() {
            if (this.micEnabled) {
              this.micVectorIcon(
                this.focusedTopBtn === 'mic' ? PivoTheme.primary : PivoTheme.primaryDark, 18
              )
            } else {
              this.musicVectorIcon(
                this.focusedTopBtn === 'mic' ? PivoTheme.primary : PivoTheme.textSecondary, 18
              )
            }
          }
          .width(44)
          .height(44)
          .borderRadius(22)
          .justifyContent(FlexAlign.Center)
          .backgroundColor(
            this.focusedTopBtn === 'mic' ? PivoTheme.surfaceSelected :
            (this.micEnabled ? PivoTheme.primaryGlow : PivoTheme.surfaceCircleDark)
          )
          .border({
            width: (this.focusedTopBtn === 'mic' || this.micEnabled) ? 2.5 : 1,
            color: this.focusedTopBtn === 'mic' ? PivoTheme.primary :
              (this.micEnabled ? PivoTheme.primaryDark : PivoTheme.border)
          })
          .shadow(
            this.focusedTopBtn === 'mic' ? { radius: 14, color: PivoTheme.primaryGlow } :
            (this.micEnabled ? { radius: 10, color: PivoTheme.primaryGlow } : undefined)
          )
          .scale({ x: this.focusedTopBtn === 'mic' ? 1.08 : 1.0, y: this.focusedTopBtn === 'mic' ? 1.08 : 1.0 })
          .focusable(true)
          .onFocus(() => {
            this.focusedTopBtn = 'mic';
          })
          .onBlur(() => {
            if (this.focusedTopBtn === 'mic') this.focusedTopBtn = '';
          })
          .onClick(() => this.onToggleMicrophone())
        }
      }
      .width('100%')
      .padding({ left: 36, right: 36, top: 16, bottom: 8 })

      // 2.2 Middle Content Area: Left Song Stage + Center Atmospheric Wave + Right Action Stack
      Stack({ alignContent: Alignment.Center }) {
        // Center Flowing Atmospheric Wave Graphic
        Image($r('app.media.atmospheric_wave'))
          .width('85%')
          .height(95)
          .objectFit(ImageFit.Contain)
          .opacity(0.65)
          .hitTestBehavior(HitTestMode.None)
          .margin({ top: 30 })

        Row({ space: 24 }) {
          // Left Lyrics Presentation
          Column({ space: 6 }) {
            // Dynamic Real-time Lyric Display
            this.lyricStream(true, true, false, this.lyricsScroller)

            Blank()

            // Progress Bar
            this.accompanimentTrackControl()
        SongProgressBar({
              positionMs: this.store ? this.localPositionMs : this.positionMs,
              durationMs: this.store && this.localDurationMs > 0 ? this.localDurationMs : this.durationMs,
              accentColor: PivoTheme.primary,
              onSeek: (pos: number) => this.onSeek(pos),
              onDraggingChange: (isDragging: boolean, currentPos: number) => {
                this.isDraggingProgress = isDragging;
                this.dragPositionMs = currentPos;
              }
            })
            .width('80%')
          }
          .layoutWeight(1)
          .height('100%')
          .alignItems(HorizontalAlign.Start)
          .justifyContent(FlexAlign.Start)
          .backgroundColor(Color.Transparent)
          .priorityGesture(
            TapGesture({ count: 2 })
              .onAction(() => {
                this.triggerDoubleTapFavorite();
              })
          )
          .onClick(() => {
            this.handleLyricClick();
          })

          // Right Vertical Floating Action Buttons (Figma Screen 2)
          Column({ space: 16 }) {
            // 1. Primary Action: Circle (▶ / ❚❚) + "开始演唱" / "正在演唱"
            Row({ space: 12 }) {
              Row() {
                this.playPauseVectorIcon(
                  this.focusedSideAction === 'play' ? PivoTheme.primary :
                  (this.state === PlaybackState.PLAYING ? PivoTheme.primary : PivoTheme.text),
                  18
                )
              }
              .width(44)
              .height(44)
              .borderRadius(22)
              .justifyContent(FlexAlign.Center)
              .backgroundColor(this.focusedSideAction === 'play' ? PivoTheme.surfaceSelected :
                (this.state === PlaybackState.PLAYING ? 'rgba(88, 112, 0, 0.18)' : PivoTheme.surfaceCircle))
              .border({
                width: this.focusedSideAction === 'play' ? 2.5 : 1,
                color: this.focusedSideAction === 'play' ? PivoTheme.primary :
                  (this.state === PlaybackState.PLAYING ? 'rgba(88, 112, 0, 0.45)' : PivoTheme.border)
              })
              .shadow(this.focusedSideAction === 'play' ? { radius: 14, color: PivoTheme.primaryGlow } :
                (this.state === PlaybackState.PLAYING ? { radius: 12, color: PivoTheme.primaryGlow } : undefined))
              .scale({ x: this.focusedSideAction === 'play' ? 1.08 : 1.0, y: this.focusedSideAction === 'play' ? 1.08 : 1.0 })
              .focusable(true)
              .defaultFocus(true)
              .groupDefaultFocus(true)
              .id('tv_play_pause_btn')
              .onFocus(() => {
                this.focusedSideAction = 'play';
              })
              .onBlur(() => {
                if (this.focusedSideAction === 'play') this.focusedSideAction = '';
              })
              .onClick(() => this.handlePlayButtonClick())

              Text(this.state === PlaybackState.PLAYING ? '正在演唱' : '开始演唱')
                .fontSize(14)
                .fontWeight(this.state === PlaybackState.PLAYING ? FontWeight.Bold : FontWeight.Medium)
                .fontColor(this.focusedSideAction === 'play' ? PivoTheme.primary : (this.state === PlaybackState.PLAYING ? PivoTheme.primary : PivoTheme.text))
            }
            .alignItems(VerticalAlign.Center)

            // 2. Secondary Action: Circle (♡ / ♥) + "收藏"
            Row({ space: 12 }) {
              Row() {
                this.heartVectorIcon(20)
              }
              .width(44)
              .height(44)
              .borderRadius(22)
              .justifyContent(FlexAlign.Center)
              .backgroundColor(this.focusedSideAction === 'fav' ? PivoTheme.surfaceSelected :
                (this.isFavorite ? 'rgba(255, 45, 85, 0.18)' : PivoTheme.surfaceCircle))
              .border({
                width: this.focusedSideAction === 'fav' ? 2.5 : 1,
                color: this.focusedSideAction === 'fav' ? PivoTheme.primary :
                  (this.isFavorite ? 'rgba(255, 51, 102, 0.40)' : PivoTheme.border)
              })
              .shadow(this.focusedSideAction === 'fav' ? { radius: 14, color: PivoTheme.primaryGlow } :
                (this.isFavorite ? { radius: 12, color: 'rgba(255, 45, 85, 0.35)' } : undefined))
              .scale({
                x: this.favButtonScale * (this.focusedSideAction === 'fav' ? 1.08 : 1.0),
                y: this.favButtonScale * (this.focusedSideAction === 'fav' ? 1.08 : 1.0)
              })
              .focusable(true)
              .onFocus(() => {
                this.focusedSideAction = 'fav';
              })
              .onBlur(() => {
                if (this.focusedSideAction === 'fav') this.focusedSideAction = '';
              })
              .onClick(() => this.onToggleFavorite())

              Text(this.isFavorite ? '已收藏' : '收藏')
                .fontSize(14)
                .fontWeight(this.isFavorite ? FontWeight.Bold : FontWeight.Medium)
                .fontColor(this.focusedSideAction === 'fav' ? PivoTheme.primary : (this.isFavorite ? PivoTheme.rose : PivoTheme.text))
            }
            .alignItems(VerticalAlign.Center)

            // 3. More Action: Circle (•••) + "更多" (Opens Mixer & Sound Panel)
            Row({ space: 12 }) {
              Row() {
                Text('•••')
                  .fontSize(14)
                  .fontColor(this.focusedSideAction === 'more' ? PivoTheme.primary : PivoTheme.text)
              }
              .width(44)
              .height(44)
              .borderRadius(22)
              .justifyContent(FlexAlign.Center)
              .backgroundColor(this.focusedSideAction === 'more' ? PivoTheme.surfaceSelected : PivoTheme.surfaceCircle)
              .border({
                width: this.focusedSideAction === 'more' ? 2.5 : 1,
                color: this.focusedSideAction === 'more' ? PivoTheme.primary : PivoTheme.border
              })
              .shadow(this.focusedSideAction === 'more' ? { radius: 14, color: PivoTheme.primaryGlow } : undefined)
              .scale({ x: this.focusedSideAction === 'more' ? 1.08 : 1.0, y: this.focusedSideAction === 'more' ? 1.08 : 1.0 })
              .focusable(true)
              .onFocus(() => {
                this.focusedSideAction = 'more';
              })
              .onBlur(() => {
                if (this.focusedSideAction === 'more') this.focusedSideAction = '';
              })
              .onClick(() => {
                this.showMixerModal = true;
              })

              Text('更多')
                .fontSize(14)
                .fontWeight(FontWeight.Medium)
                .fontColor(this.focusedSideAction === 'more' ? PivoTheme.primary : PivoTheme.text)
            }
            .alignItems(VerticalAlign.Center)
          }
          .width(160)
          .height('100%')
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Start)
          .padding({ right: 16 })
        }
        .width('100%')
        .height('100%')
      }
      .layoutWeight(1)
      .width('100%')
      .padding({ left: 36, right: 20, top: 2, bottom: 4 })
      .opacity(this.contentOpacity)
      .translate({ y: this.contentTranslateY })
      .clip(true)
      .backgroundColor(Color.Transparent)
      .priorityGesture(
        TapGesture({ count: 2 })
          .onAction(() => {
            this.triggerDoubleTapFavorite();
          })
      )
      .onClick(() => {
        this.handleStageClick();
      })
      .gesture(
        PanGesture({ direction: PanDirection.Vertical, distance: 25 })
          .onActionEnd((event: GestureEvent) => {
            if (event.offsetY < -25) {
              // 向上滑动 -> 下一首
              this.triggerSongSwitch(1);
            } else if (event.offsetY > 25) {
              // 向下滑动 -> 上一首
              this.triggerSongSwitch(-1);
            }
          })
      )


    }
    .width('100%')
    .height('100%')
  }

  // Portrait Layout (Phone / Vertical Screen - Pure Immersive Lyric Stage)
  @Builder
  portraitLayout() {
    Column() {
      // 1. Sleek Glassmorphic Floating Top Bar (Back + Centered Song Title & Meta + Actions)
      Row() {
        // Left: Back to Discovery Glass Capsule
        Row({ space: 6 }) {
          Image($r('app.media.ic_chevron_left'))
            .width(16)
            .height(16)
            .fillColor(PivoTheme.text)
            .objectFit(ImageFit.Contain)

          Text('发现')
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor(PivoTheme.text)
        }
        .padding({ left: 10, right: 14, top: 7, bottom: 7 })
        .borderRadius(18)
        .backgroundColor(PivoTheme.surfaceGlass)
        .border({ width: 1, color: PivoTheme.border })
        .onClick(() => this.onOpenLibrary())

        Blank()

        // Center: Song Title & Artist + Acoustic Pill (顶部居中显示歌曲名称)
        Column({ space: 3 }) {
          Text(this.title.length > 0 ? this.title : '暂无歌曲播放')
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor(PivoTheme.text)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })

          Row({ space: 6 }) {
            if (this.artist.length > 0) {
              Text(this.artist)
                .fontSize(11)
                .fontColor(PivoTheme.textMuted)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .padding({ left: 4, right: 4, top: 2, bottom: 2 })
                .borderRadius(4)
                .onClick(() => {
                  if (this.artist && isValidArtist(this.artist) && this.onSearchArtist) {
                    this.onSearchArtist(this.artist);
                  }
                })
            }

            // Sleek acoustic capsule mini tag
            Row({ space: 4 }) {
              Circle({ width: 5, height: 5 })
                .fill(this.micEnabled ? PivoTheme.primaryDark : (this.isHeadsetConnected ? PivoTheme.accent : PivoTheme.text))
              Text(this.micEnabled ? (this.isHeadsetConnected ? '耳返K歌' : '外放K歌') :
                (this.isHeadsetConnected ? '高清纯音' : '伴奏'))
                .fontSize(10)
                .fontColor(PivoTheme.accent)
            }
            .padding({ left: 6, right: 6, top: 1, bottom: 1 })
            .borderRadius(8)
            .backgroundColor(PivoTheme.surfaceGlass)
            .onClick(() => {
              this.showMixerModal = true;
            })
          }
        }
        .alignItems(HorizontalAlign.Center)
        .layoutWeight(1)
        .padding({ left: 8, right: 8 })

        Blank()

        // Right: Favorite & Audio Devices Action Group
        Row({ space: 10 }) {
          // Favorite Button (Frosted Disc with SVG Heart)
          Row() {
            this.heartVectorIcon(19)
          }
          .width(36)
          .height(36)
          .borderRadius(18)
          .justifyContent(FlexAlign.Center)
          .backgroundColor(this.isFavorite ? PivoTheme.roseGlow : PivoTheme.surfaceGlass)
          .border({
            width: 1,
            color: this.isFavorite ? PivoTheme.rose : PivoTheme.border
          })
          .shadow(this.isFavorite ? { radius: 10, color: 'rgba(255, 45, 85, 0.35)' } : undefined)
          .scale({ x: this.favButtonScale, y: this.favButtonScale })
          .onClick(() => this.onToggleFavorite())
        }
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 12, bottom: 8 })
      .alignItems(VerticalAlign.Center)

      // 2. Middle Content Area: Active Song Card + Lyrics Stream (支持手势上下滑平滑切歌与双击点赞)
      Column() {
        if (this.coverUrl && this.coverUrl.trim().length > 0) {
          Stack({ alignContent: Alignment.Center }) {
            Image(this.coverUrl)
              .width(140)
              .height(140)
              .borderRadius(18)
              .objectFit(ImageFit.Cover)
              .shadow({ radius: 20, color: 'rgba(120, 105, 85, 0.16)', offsetY: 5 })
              .border({ width: 1.2, color: PivoTheme.border })
          }
          .margin({ top: 2, bottom: 6 })
          .priorityGesture(
            TapGesture({ count: 2 })
              .onAction(() => {
                this.triggerDoubleTapFavorite();
              })
          )
          .onClick(() => {
            this.handleStageClick();
          })
          .gesture(
            PanGesture({ direction: PanDirection.Vertical, distance: 25 })
              .onActionEnd((event: GestureEvent) => {
                if (event.offsetY < -25) {
                  // 向上滑动 -> 下一首
                  this.triggerSongSwitch(1);
                } else if (event.offsetY > 25) {
                  // 向下滑动 -> 上一首
                  this.triggerSongSwitch(-1);
                }
              })
          )
        }

        // 默认播放页歌词：单击打开歌词详情界面，双击收藏与取消收藏
        this.lyricStream(true, false, false, this.lyricsScroller)
      }
      .layoutWeight(1)
      .width('100%')
      .padding({ left: 20, right: 20, top: 2, bottom: 2 })
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      .opacity(this.contentOpacity)
      .translate({ y: this.contentTranslateY })
      .clip(true)
      .backgroundColor(Color.Transparent)
      .priorityGesture(
        TapGesture({ count: 2 })
          .onAction(() => {
            this.triggerDoubleTapFavorite();
          })
      )
      .onClick(() => {
        this.handleStageClick();
      })
      .gesture(
        PanGesture({ direction: PanDirection.Vertical, distance: 25 })
          .onActionEnd((event: GestureEvent) => {
            if (event.offsetY < -25) {
              // 向上滑动 -> 下一首
              this.triggerSongSwitch(1);
            } else if (event.offsetY > 25) {
              // 向下滑动 -> 上一首
              this.triggerSongSwitch(-1);
            }
          })
      )

      // 3. Minimalist Soda Music Playback Controls
      Column({ space: 14 }) {
        // Progress Slider
        this.accompanimentTrackControl()
        SongProgressBar({
          positionMs: this.store ? this.localPositionMs : this.positionMs,
          durationMs: this.store && this.localDurationMs > 0 ? this.localDurationMs : this.durationMs,
          accentColor: PivoTheme.text,
          onSeek: (pos: number) => this.onSeek(pos),
          onDraggingChange: (isDragging: boolean, currentPos: number) => {
            this.isDraggingProgress = isDragging;
            this.dragPositionMs = currentPos;
          }
        })
        .width('100%')

        // 3-Button Minimalist Control Row (伴奏/K歌, 播放/暂停, 耳返/调音 - 三键同规格纯白线框圆环)
        Row({ space: 36 }) {
          // 1. K-Song / Accompaniment Switch Button (纯白线框圆环)
          Row() {
            if (this.micEnabled) {
              this.micVectorIcon(PivoTheme.text, 20)
            } else {
              this.musicVectorIcon(PivoTheme.text, 20)
            }
          }
          .width(48)
          .height(48)
          .borderRadius(24)
          .justifyContent(FlexAlign.Center)
          .backgroundColor(PivoTheme.surfaceGlass)
          .border({ width: 1.8, color: PivoTheme.text })
          .onClick(() => this.onToggleMicrophone())

          // 2. Pure White Line-Ring Play / Pause Button (同规格纯白线框圆环)
          Row() {
            if (this.state === PlaybackState.PLAYING) {
              Row({ space: 4 }) {
                Row()
                  .width(3)
                  .height(14)
                  .borderRadius(1.5)
                  .backgroundColor(PivoTheme.text)
                Row()
                  .width(3)
                  .height(14)
                  .borderRadius(1.5)
                  .backgroundColor(PivoTheme.text)
              }
              .justifyContent(FlexAlign.Center)
              .alignItems(VerticalAlign.Center)
            } else {
              Image($r('app.media.ic_play'))
                .width(18)
                .height(18)
                .fillColor(PivoTheme.text)
                .objectFit(ImageFit.Contain)
                .margin({ left: 2.5 })
            }
          }
          .width(48)
          .height(48)
          .borderRadius(24)
          .justifyContent(FlexAlign.Center)
          .backgroundColor(PivoTheme.surfaceGlass)
          .border({ width: 1.8, color: PivoTheme.text })
          .onClick(() => this.handlePlayButtonClick())

          // 3. Audio Route / Ear Return / Mixer (纯白线框圆环)
          Row() {
            this.headphoneVectorIcon(PivoTheme.text, 20)
          }
          .width(48)
          .height(48)
          .borderRadius(24)
          .justifyContent(FlexAlign.Center)
          .backgroundColor(PivoTheme.surfaceGlass)
          .border({ width: 1.8, color: PivoTheme.text })
          .onClick(() => {
            this.showMixerModal = true;
          })
        }
        .width('100%')
        .justifyContent(FlexAlign.Center)
        .alignItems(VerticalAlign.Center)
      }
      .width('100%')
      .padding({ left: 24, right: 24, bottom: 20 })
    }
    .width('100%')
    .height('100%')
  }

  // 展开歌词层：接近全屏，上下滑动只浏览歌词；手动浏览后暂停自动跟随，可一键回到当前句
  @Builder
  expandedLyricsView() {
    Column() {
      // 顶部：歌名/歌手 + 收起按钮
      Row() {
        Column({ space: 3 }) {
          Text(this.title.length > 0 ? this.title : '暂无歌曲播放')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor(PivoTheme.text)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          if (this.artist.length > 0) {
            Text(this.artist)
              .fontSize(12)
              .fontColor(PivoTheme.textMuted)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        .padding({ right: 12 })

        Row() {
          Image($r('app.media.ic_chevron_left'))
            .width(18)
            .height(18)
            .fillColor(PivoTheme.text)
            .objectFit(ImageFit.Contain)
            .rotate({ angle: -90 })
        }
        .width(38)
        .height(38)
        .borderRadius(19)
        .justifyContent(FlexAlign.Center)
        .backgroundColor(PivoTheme.surfaceGlass)
        .border({ width: 1, color: PivoTheme.border })
        .onClick(() => this.closeExpandedLyrics())
      }
      .width('100%')
      .padding({ left: 20, right: 20, top: 14, bottom: 10 })
      .alignItems(VerticalAlign.Center)
      .gesture(
        PanGesture({ direction: PanDirection.Down, distance: 20 })
          .onActionEnd(() => {
            this.closeExpandedLyrics();
          })
      )

      // 中部：可自由滚动的歌词（点句可跳唱）
      Column() {
        this.lyricStream(false, false, true, this.expandedScroller)
      }
      .layoutWeight(1)
      .width('100%')
      .padding({ left: 16, right: 16 })
      .priorityGesture(
        TapGesture({ count: 2 })
          .onAction(() => {
            this.triggerDoubleTapFavorite();
          })
      )

      // 底部：手动浏览后暂停自动跟随，显示“回到当前句”
      if (!this.expandedFollowActive) {
        Row({ space: 6 }) {
          Image($r('app.media.ic_refresh'))
            .width(14)
            .height(14)
            .fillColor(PivoTheme.primary)
            .objectFit(ImageFit.Contain)
          Text('回到当前句')
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor(PivoTheme.primary)
        }
        .padding({ left: 18, right: 18, top: 9, bottom: 9 })
        .borderRadius(20)
        .backgroundColor(PivoTheme.surfaceGlass)
        .border({ width: 1, color: PivoTheme.primary })
        .margin({ bottom: 18 })
        .onClick(() => {
          this.expandedFollowActive = true;
          this.scrollToActiveOn(this.expandedScroller, true);
        })
      } else {
        // 占位，保持歌词区域高度稳定
        Row()
          .height(46)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(PivoTheme.background)
    .transition(TransitionEffect.asymmetric(
      TransitionEffect.OPACITY.animation({ duration: 200, curve: Curve.FastOutSlowIn })
        .combine(TransitionEffect.translate({ y: 48 }).animation({ duration: 240, curve: Curve.FastOutSlowIn })),
      TransitionEffect.OPACITY.animation({ duration: 180, curve: Curve.EaseIn })
    ))
  }

  @Builder
  accompanimentTrackControl() {
    Row({ space: 8 }) {
      Button('原曲').height(36).fontSize(13)
        .backgroundColor(this.activeAccompanimentId ? PivoTheme.textSecondary : PivoTheme.primary)
        .enabled(!this.isRecording && !this.trackSwitchPending)
        .onClick(() => this.onOriginalTrack())
      Button(this.separationBusy ? 'AI 伴奏 · 生成中' : (this.activeAccompanimentId ? 'AI 伴奏 ✓' : 'AI 伴奏'))
        .height(36).fontSize(13).backgroundColor(this.activeAccompanimentId ? PivoTheme.primary : PivoTheme.textSecondary)
        .onClick(() => this.onAccompaniment())
    }.width('100%').justifyContent(FlexAlign.Center).padding({ bottom: 6 })
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      // 1. Luminous Deep Space Studio Stage Gradient (Pure, High Contrast, Non-Muddy)
      Row()
        .width('100%')
        .height('100%')
        .radialGradient({
          center: ['50%', '35%'],
          radius: '90%',
          colors: [
            [PivoTheme.backgroundGlow, 0.0],
            [PivoTheme.background, 0.52],
            [PivoTheme.backgroundDark, 1.0]
          ]
        })
        .hitTestBehavior(HitTestMode.None)

      // 2. Dynamic Aurora Particles & Soundwave Beat Ripple Background
      if (this.isVisible) {
        ParticleStageBackground({
          isVisible: true,
          state: this.state,
          microphonePeak: this.microphonePeak
        })
          .width('100%')
          .height('100%')
          .opacity(this.state === PlaybackState.PLAYING ? 0.90 : 0.60)
          .hitTestBehavior(HitTestMode.None)
      }

      // 3. Subtle Studio Rim Lighting Glow (Cyan & Lime Stage Lighting)
      Row()
        .width('100%')
        .height('100%')
        .linearGradient({
          angle: 180,
          colors: [
            ['rgba(99, 190, 232, 0.16)', 0.0],
            ['rgba(255, 255, 255, 0.0)', 0.35],
            ['rgba(255, 225, 215, 0.18)', 0.72],
            ['rgba(200, 240, 75, 0.14)', 1.0]
          ]
        })
        .hitTestBehavior(HitTestMode.None)

      // 2. Main Stage Surface
      Column() {
        if (this.wide) {
          this.widescreenLayout()
        } else {
          this.portraitLayout()
        }
      }
      .width('100%')
      .height('100%')
      .opacity(this.contentOpacity)
      .clip(true)

      // 3. Expanded Full-Screen Lyrics Layer (展开歌词层，覆盖主界面，上下滑只翻歌词)
      if (this.showExpandedLyrics) {
        this.expandedLyricsView()
      }

      // 3. Floating Studio-Grade Canvas Double-Tap Heart Burst Animation
      if (this.showHeartBurst) {
        HeartBurstCanvas({
          isFavorite: this.heartBurstIsFav,
          trigger: this.heartBurstTrigger
        })
          .hitTestBehavior(HitTestMode.None)
      }

      // 4. Mixer & Audio Settings Dialog Modal ("更多" Panel with Focus Scope)
      if (this.showMixerModal) {
        Stack({ alignContent: Alignment.Center }) {
          Row()
            .width('100%')
            .height('100%')
            .backgroundColor('rgba(98, 98, 98, 0.32)')
            .onClick(() => {
              this.showMixerModal = false;
            })

          Column({ space: 18 }) {
            Row() {
              Text('专业调音与声学设置')
                .fontSize(this.wide ? 20 : 17)
                .fontWeight(FontWeight.Bold)
                .fontColor(PivoTheme.text)

              Blank()

              Text('✕')
                .fontSize(18)
                .fontColor(this.focusedModalClose ? PivoTheme.primary : PivoTheme.textMuted)
                .padding(8)
                .borderRadius(6)
                .border({
                  width: this.focusedModalClose ? 2 : 0,
                  color: PivoTheme.primary
                })
                .focusable(true)
                .onFocus(() => {
                  this.focusedModalClose = true;
                })
                .onBlur(() => {
                  this.focusedModalClose = false;
                })
                .onClick(() => {
                  this.showMixerModal = false;
                })
            }
            .width('100%')

            KaraokeMixerControls({
              accompanimentGain: this.accompanimentGain,
              vocalGain: this.vocalGain,
              reverbMix: this.reverbMix,
              audioRoute: this.audioRoute,
              pitchShiftSemitones: this.pitchShiftSemitones,
              autoTuneActive: this.autoTuneActive,
              autoTuneStrength: this.autoTuneStrength,
              isRecording: this.isRecording,
              recordedDurationMs: this.recordedDurationMs,
              isHeadsetConnected: this.isHeadsetConnected,
              onAccompaniment: (val: number) => {
                this.accompanimentGain = val;
                this.onVolume(val);
              },
              onVocal: (val: number) => {
                this.vocalGain = val;
                this.onVocalGain(val);
              },
              onReverb: (val: number) => {
                this.reverbMix = val;
                this.onReverbMix(val);
              },
              onRouteChange: (val: number) => this.onRouteChange(val),
              onPitchShiftChange: (val: number) => this.onPitchShiftChange(val),
              onAutoTuneToggle: (val: boolean) => this.onAutoTuneToggle(val),
              onAutoTuneStrengthChange: (val: number) => this.onAutoTuneStrengthChange(val),
              onRecordingToggle: () => this.onRecordingToggle()
            })
          }
          .width(this.wide ? 520 : '92%')
          .padding(this.wide ? 24 : 16)
          .borderRadius(24)
          .backgroundColor(PivoTheme.surfaceRaised)
          .border({ width: 1, color: PivoTheme.borderMuted })
          .shadow({ radius: 32, color: 'rgba(120, 105, 85, 0.18)' })
          .focusScopeId('mixerModal', true)
          .onKeyEvent((event?: KeyEvent) => {
            if (!event || event.type !== KeyType.Down) return;
            if (event.keyCode === 2 || event.keyCode === 4) {
              this.showMixerModal = false;
            }
          })
        }
        .width('100%')
        .height('100%')
      }

      // 音频输入/输出设备诊断与一键复制弹窗
      AudioDevicesModal({
        visible: this.showAudioDevicesModal,
        onClose: () => {
          this.showAudioDevicesModal = false;
        }
      })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(PivoTheme.background)
  }
}
