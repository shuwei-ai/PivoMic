import { backgroundTaskManager } from '@kit.BackgroundTasksKit';
import { wantAgent, WantAgent } from '@kit.AbilityKit';
import { avSession } from '@kit.AVSessionKit';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { runningLock } from '@kit.BasicServicesKit';

const DOMAIN = 0x0000;
const TAG = 'PivoMicBgTask';

export interface AVSessionControlListener {
  onPlay?: () => void;
  onPause?: () => void;
  onPlayNext?: () => void;
  onPlayPrevious?: () => void;
  onSeek?: (positionMs: number) => void;
  onToggleFavorite?: (assetId?: string) => void;
}

export class BackgroundTaskService {
  private static instance?: BackgroundTaskService;
  private isRunning: boolean = false;
  private currentContext?: common.UIAbilityContext;
  private session?: avSession.AVSession;
  private lastReportedSongId: string = '';
  private lastReportedState: number = -1;
  private lastReportedCover: string = '';
  private lastReportedDurationMs: number = 0;
  private lastReportedPositionMs: number = -1;
  private lastReportedFavorite: boolean = false;
  private lastPlaybackStateUpdateTime: number = 0;
  private controlListener?: AVSessionControlListener;
  private runningLockObj?: runningLock.RunningLock;

  private constructor() {}

  static getInstance(): BackgroundTaskService {
    if (!BackgroundTaskService.instance) {
      BackgroundTaskService.instance = new BackgroundTaskService();
    }
    return BackgroundTaskService.instance;
  }

  setContext(context: common.UIAbilityContext): void {
    this.currentContext = context;
  }

  setControlListener(listener: AVSessionControlListener): void {
    this.controlListener = listener;
  }


  private async getAbilityWantAgent(ctx: common.UIAbilityContext): Promise<WantAgent> {
    const bundleName = ctx.abilityInfo?.bundleName || 'com.shuwei.pivomic';
    const abilityName = ctx.abilityInfo?.name || 'EntryAbility';
    const wantAgentInfo: wantAgent.WantAgentInfo = {
      wants: [
        {
          bundleName: bundleName,
          abilityName: abilityName
        }
      ],
      actionType: wantAgent.OperationType.START_ABILITY,
      requestCode: 1001,
      wantAgentFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG]
    };
    return wantAgent.getWantAgent(wantAgentInfo);
  }

  private async ensureSession(ctx: common.UIAbilityContext): Promise<avSession.AVSession | undefined> {
    if (!this.session) {
      try {
        this.session = await avSession.createAVSession(ctx, 'PivoMicAudio', 'audio');
        this.bindSessionControls(this.session);
        await this.session.activate();

        try {
          const agent = await this.getAbilityWantAgent(ctx);
          await this.session.setLaunchAbility(agent);
        } catch (agentErr) {
          hilog.warn(DOMAIN, TAG, 'Failed to set launch ability: %{public}s', JSON.stringify(agentErr));
        }

        hilog.info(DOMAIN, TAG, 'AVSession created, activated and launch ability set successfully');
      } catch (err) {
        hilog.warn(DOMAIN, TAG, 'Failed to create AVSession: %{public}s', JSON.stringify(err));
      }
    }
    return this.session;
  }

  private bindSessionControls(session: avSession.AVSession): void {
    try {
      session.on('play', () => {
        hilog.info(DOMAIN, TAG, 'AVSession onPlay received from system/lockscreen');
        if (this.controlListener?.onPlay) {
          this.controlListener.onPlay();
        }
      });
      session.on('pause', () => {
        hilog.info(DOMAIN, TAG, 'AVSession onPause received from system/lockscreen');
        if (this.controlListener?.onPause) {
          this.controlListener.onPause();
        }
      });
      session.on('playNext', () => {
        hilog.info(DOMAIN, TAG, 'AVSession onPlayNext received from system/lockscreen');
        if (this.controlListener?.onPlayNext) {
          this.controlListener.onPlayNext();
        }
      });
      session.on('playPrevious', () => {
        hilog.info(DOMAIN, TAG, 'AVSession onPlayPrevious received from system/lockscreen');
        if (this.controlListener?.onPlayPrevious) {
          this.controlListener.onPlayPrevious();
        }
      });
      session.on('seek', (position: number) => {
        hilog.info(DOMAIN, TAG, 'AVSession onSeek received: %{public}d', position);
        if (this.controlListener?.onSeek) {
          this.controlListener.onSeek(position);
        }
      });
      session.on('toggleFavorite', (assetId: string) => {
        hilog.info(DOMAIN, TAG, 'AVSession onToggleFavorite received from system/lockscreen: %{public}s', assetId);
        if (this.controlListener?.onToggleFavorite) {
          this.controlListener.onToggleFavorite(assetId);
        }
      });
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'Failed to bind AVSession controls: %{public}s', JSON.stringify(e));
    }
  }

  async updatePlaybackState(
    isPlaying: boolean,
    songTitle: string = 'PivoMic 音乐',
    artist: string = '',
    durationMs: number = 0,
    positionMs: number = 0,
    coverUrl?: string,
    context?: common.UIAbilityContext,
    isFavorite: boolean = false
  ): Promise<boolean> {
    const ctx = context ?? this.currentContext;
    if (!ctx) {
      hilog.warn(DOMAIN, TAG, 'updatePlaybackState skipped: context is undefined');
      return false;
    }

    // 1. Create and update AVSession for System Media Controller & Lockscreen Widget
    try {
      const session = await this.ensureSession(ctx);
      if (session) {
        const validDuration = durationMs > 0 ? Math.floor(durationMs) : undefined;
        const durationChanged = validDuration !== undefined && (this.lastReportedDurationMs <= 0 || Math.abs(this.lastReportedDurationMs - validDuration) > 1000);
        const songChanged = this.lastReportedSongId !== songTitle || this.lastReportedCover !== (coverUrl ?? '');

        if (songChanged || durationChanged) {
          this.lastReportedSongId = songTitle;
          this.lastReportedCover = coverUrl ?? '';
          if (validDuration !== undefined) {
            this.lastReportedDurationMs = validDuration;
          }
          const metadata: avSession.AVMetadata = {
            assetId: songTitle,
            title: songTitle,
            artist: artist || 'PivoMic',
            duration: validDuration,
            mediaImage: coverUrl && coverUrl.length > 0 ? coverUrl : undefined
          };
          await session.setAVMetadata(metadata);
        }

        const targetState = isPlaying ? avSession.PlaybackState.PLAYBACK_STATE_PLAY : avSession.PlaybackState.PLAYBACK_STATE_PAUSE;
        if (this.lastReportedState === avSession.PlaybackState.PLAYBACK_STATE_STOP || this.lastReportedState === -1) {
          await session.activate();
        }

        const validPos = Math.max(0, Math.floor(Number.isFinite(positionMs) ? positionMs : 0));
        const nowMs = Math.floor(new Date().getTime());
        const stateChanged = this.lastReportedState !== targetState;
        const favChanged = this.lastReportedFavorite !== isFavorite;
        const isSeekOrDrift = Math.abs(validPos - this.lastReportedPositionMs) > 2000;
        const isThrottleElapsed = (nowMs - this.lastPlaybackStateUpdateTime) >= 2000;

        // 状态变更（如播放->暂停）、切歌（换歌）、跳转（Seek）、收藏状态变化或常规播放达到2秒节流周期时同步 AVSession
        if (songChanged || stateChanged || favChanged || isSeekOrDrift || isThrottleElapsed) {
          const currentSpeed = 1.0;
          const playbackState: avSession.AVPlaybackState = {
            state: targetState,
            speed: currentSpeed,
            position: {
              elapsedTime: validPos,
              updateTime: nowMs
            },
            isFavorite: isFavorite
          };
          hilog.info(DOMAIN, TAG, 'Updating AVSession playbackState: isPlaying=%{public}s, state=%{public}d, pos=%{public}d, speed=%{public}s, isFavorite=%{public}s',
            String(isPlaying), targetState, validPos, String(currentSpeed), String(isFavorite));
          await session.setAVPlaybackState(playbackState);
          this.lastReportedState = targetState;
          this.lastReportedPositionMs = validPos;
          this.lastReportedFavorite = isFavorite;
          this.lastPlaybackStateUpdateTime = nowMs;
          hilog.info(DOMAIN, TAG, 'AVSession setAVPlaybackState succeeded');
        }
      }
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'AVSession update warning: %{public}s', JSON.stringify(e));
    }

    if (this.isRunning) {
      return true;
    }

    try {
      const agent: WantAgent = await this.getAbilityWantAgent(ctx);
      await backgroundTaskManager.startBackgroundRunning(
        ctx,
        backgroundTaskManager.BackgroundMode.AUDIO_PLAYBACK,
        agent
      );
      this.isRunning = true;
      this.currentContext = ctx;
      this.acquireRunningLock();
      hilog.info(DOMAIN, TAG, 'Succeeded in starting background continuous audio task for: %{public}s - %{public}s', songTitle, artist);
      return true;
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'Failed to start background continuous audio task: %{public}s', JSON.stringify(err));
      return false;
    }
  }

  async updateFavoriteStatus(isFavorite: boolean): Promise<boolean> {
    this.lastReportedFavorite = isFavorite;
    if (!this.session) {
      return false;
    }
    try {
      const nowMs = Math.floor(new Date().getTime());
      const stateToReport = this.lastReportedState >= 0 ? this.lastReportedState : avSession.PlaybackState.PLAYBACK_STATE_PLAY;
      const posToReport = Math.max(0, this.lastReportedPositionMs >= 0 ? this.lastReportedPositionMs : 0);
      const playbackState: avSession.AVPlaybackState = {
        state: stateToReport,
        speed: 1.0,
        position: {
          elapsedTime: posToReport,
          updateTime: nowMs
        },
        isFavorite: isFavorite
      };
      await this.session.setAVPlaybackState(playbackState);
      hilog.info(DOMAIN, TAG, 'AVSession favorite status updated immediately: isFavorite=%{public}s', String(isFavorite));
      return true;
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'Failed to update AVSession favorite status: %{public}s', JSON.stringify(e));
      return false;
    }
  }

  async startContinuousAudioTask(
    context?: common.UIAbilityContext,
    songTitle: string = 'PivoMic 音乐播放中',
    artist: string = '',
    durationMs: number = 0,
    positionMs: number = 0,
    coverUrl?: string,
    isFavorite: boolean = false
  ): Promise<boolean> {
    return this.updatePlaybackState(true, songTitle, artist, durationMs, positionMs, coverUrl, context, isFavorite);
  }

  private async acquireRunningLock(): Promise<void> {
    if (this.runningLockObj) return;
    try {
      if (runningLock.isSupported(runningLock.RunningLockType.BACKGROUND)) {
        this.runningLockObj = await runningLock.create('PivoMicAudioRunningLock', runningLock.RunningLockType.BACKGROUND);
        if (this.runningLockObj) {
          this.runningLockObj.hold(0);
          hilog.info(DOMAIN, TAG, 'RunningLock.BACKGROUND held successfully');
        }
      }
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'Failed to hold RunningLock: %{public}s', JSON.stringify(err));
    }
  }

  private releaseRunningLock(): void {
    if (this.runningLockObj) {
      try {
        if (this.runningLockObj.isHolding()) {
          this.runningLockObj.unhold();
        }
        hilog.info(DOMAIN, TAG, 'RunningLock.BACKGROUND released');
      } catch (err) {
        hilog.warn(DOMAIN, TAG, 'Failed to unhold RunningLock: %{public}s', JSON.stringify(err));
      }
      this.runningLockObj = undefined;
    }
  }

  async stopContinuousAudioTask(context?: common.UIAbilityContext): Promise<void> {
    const ctx = context ?? this.currentContext;

    if (this.session && this.lastReportedState !== avSession.PlaybackState.PLAYBACK_STATE_STOP) {
      this.lastReportedState = avSession.PlaybackState.PLAYBACK_STATE_STOP;
      this.lastReportedPositionMs = -1;
      this.lastPlaybackStateUpdateTime = 0;
      try {
        await this.session.setAVPlaybackState({
          state: avSession.PlaybackState.PLAYBACK_STATE_STOP,
          speed: 1.0
        });
        await this.session.deactivate();
      } catch (e) {
        hilog.warn(DOMAIN, TAG, 'AVSession deactivate warning: %{public}s', JSON.stringify(e));
      }
    }

    this.releaseRunningLock();

    if (!ctx || !this.isRunning) {
      return;
    }

    try {
      await backgroundTaskManager.stopBackgroundRunning(ctx);
      this.isRunning = false;
      hilog.info(DOMAIN, TAG, 'Succeeded in stopping background continuous audio task');
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'Failed to stop background continuous audio task: %{public}s', JSON.stringify(err));
    }
  }

  async releaseSession(): Promise<void> {
    this.releaseRunningLock();
    if (this.session) {
      try {
        await this.session.destroy();
      } catch (_) {}
      this.session = undefined;
      this.lastReportedSongId = '';
      this.lastReportedCover = '';
      this.lastReportedDurationMs = 0;
      this.lastReportedPositionMs = -1;
      this.lastReportedFavorite = false;
      this.lastPlaybackStateUpdateTime = 0;
      this.lastReportedState = -1;
    }
  }

  isContinuousTaskRunning(): boolean {
    return this.isRunning;
  }
}

