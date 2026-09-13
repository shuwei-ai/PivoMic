import { media } from '@kit.MediaKit';
import { audio } from '@kit.AudioKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { fileIo } from '@kit.CoreFileKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { MusicSourceKind, PlaybackSnapshot, PlaybackState, Song } from '../domain/MusicModels';

const DOMAIN = 0x0000;
const TAG = 'PivoMicPlayer';

export class AVPlayerEngine {
  private player?: media.AVPlayer;
  private currentFileFd?: number;
  private snapshot: PlaybackSnapshot = {
    state: PlaybackState.IDLE, positionMs: 0, durationMs: 0,
    bufferedPositionMs: 0,
    volume: 0.8, pitchSemitones: 0, errorMessage: ''
  };
  private shouldAutoPlay: boolean = false;
  private initialSeekMs: number = 0;
  private generation: number = 0;
  private wasPlayingBeforeInterrupt: boolean = false;
  private interruptTimestamp: number = 0;
  private originalVolumeBeforeDuck: number = -1;

  async load(song: Song, autoPlay: boolean = false, initialSeekMs: number = 0): Promise<void> {
    const generation = ++this.generation;
    this.wasPlayingBeforeInterrupt = false;
    this.interruptTimestamp = 0;
    this.originalVolumeBeforeDuck = -1;
    if (this.currentFileFd !== undefined) {
      try { fileIo.closeSync(this.currentFileFd); } catch (_) {}
      this.currentFileFd = undefined;
    }
    this.shouldAutoPlay = autoPlay;
    this.initialSeekMs = initialSeekMs;
    const isLocal = song.source === MusicSourceKind.LOCAL || song.uri.startsWith('/') || song.uri.startsWith('file://');
    this.snapshot = {
      state: PlaybackState.IDLE, positionMs: initialSeekMs, durationMs: song.durationMs,
      bufferedPositionMs: isLocal ? song.durationMs : 0,
      volume: this.snapshot.volume, pitchSemitones: 0, errorMessage: ''
    };
    try {
      let player = this.player;
      if (player !== undefined) {
        try {
          if (player.state !== 'idle') {
            await player.reset();
          }
        } catch (resetErr) {
          hilog.warn(DOMAIN, TAG, 'Player reset failed, recreating instance: %{public}s', JSON.stringify(resetErr));
          try { await player.release(); } catch (_) {}
          this.player = undefined;
          player = undefined;
        }
      }

      if (player === undefined) {
        player = await media.createAVPlayer();
        if (generation !== this.generation) { try { await player.release(); } catch (_) {} return; }
        this.player = player;
        this.bindEvents(player);
      }

      if (generation !== this.generation) return;
      if (isLocal) {
        const filePath = song.uri.startsWith('file://') ? song.uri.substring(7) : song.uri;
        const file = fileIo.openSync(filePath, fileIo.OpenMode.READ_ONLY);
        const stat = fileIo.statSync(file.fd);
        this.currentFileFd = file.fd;
        hilog.info(DOMAIN, TAG, 'Loading local file via fdSrc: %{public}s, fd: %{public}d, size: %{public}d', filePath, file.fd, stat.size);
        player.fdSrc = { fd: file.fd, offset: 0, length: stat.size };
        this.snapshot.bufferedPositionMs = song.durationMs > 0 ? song.durationMs : this.snapshot.durationMs;
      } else {
        hilog.info(DOMAIN, TAG, 'Loading remote URL: %{public}s', song.uri);
        player.url = song.uri;
      }
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'Failed to prepare AVPlayer: %{public}s', JSON.stringify(err));
      if (generation === this.generation) { this.snapshot.state = PlaybackState.ERROR; this.snapshot.errorMessage = '播放器初始化失败'; }
    }
  }

  onStateChanged?: (state: PlaybackState, snapshot: PlaybackSnapshot) => void;
  onTimeUpdated?: (positionMs: number) => void;

  private bindEvents(player: media.AVPlayer): void {
    player.on('stateChange', (state: media.AVPlayerState) => {
      if (this.player !== player) return;
      if (state === 'initialized') {
        try {
          player.audioRendererInfo = {
            content: audio.ContentType.CONTENT_TYPE_MUSIC,
            usage: audio.StreamUsage.STREAM_USAGE_MUSIC,
            rendererFlags: 0
          };
        } catch (e) {
          hilog.warn(DOMAIN, TAG, 'Failed to set audioRendererInfo: %{public}s', JSON.stringify(e));
        }
        player.prepare().catch(() => {
          if (this.player !== player) return;
          this.snapshot.state = PlaybackState.ERROR;
          this.snapshot.errorMessage = '音频准备失败';
          if (this.onStateChanged) this.onStateChanged(this.snapshot.state, this.snapshot);
        });
      } else if (state === 'prepared') {
        this.snapshot.durationMs = player.duration > 0 ? player.duration : this.snapshot.durationMs;
        if (this.snapshot.bufferedPositionMs <= 0 && this.currentFileFd !== undefined) {
          this.snapshot.bufferedPositionMs = this.snapshot.durationMs;
        }
        player.setVolume(this.snapshot.volume);
        if (this.initialSeekMs > 0) {
          const target = this.initialSeekMs;
          this.initialSeekMs = 0;
          try {
            player.seek(target, media.SeekMode.SEEK_CLOSEST);
            this.snapshot.positionMs = target;
          } catch (_) {}
        }
        if (this.shouldAutoPlay) {
          this.shouldAutoPlay = false;
          this.snapshot.state = PlaybackState.PLAYING;
          if (this.onStateChanged) this.onStateChanged(this.snapshot.state, this.snapshot);
          player.play().catch(() => {
            if (this.player !== player) return;
            this.snapshot.state = PlaybackState.ERROR;
            this.snapshot.errorMessage = '音频播放失败';
            if (this.onStateChanged) this.onStateChanged(this.snapshot.state, this.snapshot);
          });
        } else {
          this.snapshot.state = PlaybackState.READY;
          if (this.onStateChanged) this.onStateChanged(this.snapshot.state, this.snapshot);
        }
      } else if (state === 'playing') {
        this.snapshot.state = PlaybackState.PLAYING;
        if (this.onStateChanged) this.onStateChanged(this.snapshot.state, this.snapshot);
      } else if (state === 'paused') {
        this.snapshot.state = PlaybackState.PAUSED;
        if (this.onStateChanged) this.onStateChanged(this.snapshot.state, this.snapshot);
      } else if (state === 'completed') {
        this.snapshot.state = PlaybackState.COMPLETED;
        this.snapshot.positionMs = this.snapshot.durationMs;
        this.snapshot.bufferedPositionMs = this.snapshot.durationMs;
        if (this.onStateChanged) this.onStateChanged(this.snapshot.state, this.snapshot);
      } else if (state === 'error') {
        this.snapshot.state = PlaybackState.ERROR;
        this.snapshot.errorMessage = '当前音源无法播放，请尝试其他来源';
        if (this.onStateChanged) this.onStateChanged(this.snapshot.state, this.snapshot);
      }
    });
    player.on('bufferingUpdate', (infoType: media.BufferingInfoType, value: number) => {
      if (this.player !== player) return;
      if (infoType === media.BufferingInfoType.CACHED_DURATION) {
        this.snapshot.bufferedPositionMs = Math.max(this.snapshot.bufferedPositionMs, value);
      } else if (infoType === media.BufferingInfoType.BUFFERING_PERCENT) {
        const dur = this.snapshot.durationMs > 0 ? this.snapshot.durationMs : (this.player?.duration ?? 0);
        if (dur > 0) {
          this.snapshot.bufferedPositionMs = Math.max(this.snapshot.bufferedPositionMs, Math.round(dur * (value / 100)));
        }
      }
    });
    player.on('timeUpdate', (timeMs: number) => {
      if (this.player !== player) return;
      this.snapshot.positionMs = timeMs;
      this.snapshot.bufferedPositionMs = Math.max(this.snapshot.bufferedPositionMs, timeMs);
      if (this.onTimeUpdated) {
        this.onTimeUpdated(timeMs);
      }
    });
    player.on('durationUpdate', (durationMs: number) => {
      if (this.player !== player) return;
      this.snapshot.durationMs = durationMs;
    });
    player.on('error', (_error: BusinessError) => {
      if (this.player !== player) return;
      this.snapshot.state = PlaybackState.ERROR;
      this.snapshot.errorMessage = '播放出错，请换一个来源重试';
      if (this.onStateChanged) this.onStateChanged(this.snapshot.state, this.snapshot);
    });
    player.on('audioInterrupt', (interruptEvent: audio.InterruptEvent) => {
      if (this.player !== player) return;
      hilog.info(DOMAIN, TAG, 'AVPlayer audioInterrupt: eventType=%{public}d, forceType=%{public}d, hintType=%{public}d',
        interruptEvent.eventType, interruptEvent.forceType, interruptEvent.hintType);

      if (interruptEvent.hintType === audio.InterruptHint.INTERRUPT_HINT_PAUSE) {
        const isCurrentlyPlaying = this.snapshot.state === PlaybackState.PLAYING || player.state === 'playing';
        if (isCurrentlyPlaying) {
          this.wasPlayingBeforeInterrupt = true;
          this.interruptTimestamp = Date.now();
        }
        this.snapshot.state = PlaybackState.PAUSED;
        if (this.onStateChanged) this.onStateChanged(this.snapshot.state, this.snapshot);
      } else if (interruptEvent.hintType === audio.InterruptHint.INTERRUPT_HINT_RESUME) {
        const elapsedMs = Date.now() - this.interruptTimestamp;
        const maxTimeoutMs = 30 * 60 * 1000;
        if (this.wasPlayingBeforeInterrupt && (this.interruptTimestamp === 0 || elapsedMs <= maxTimeoutMs)) {
          this.wasPlayingBeforeInterrupt = false;
          this.interruptTimestamp = 0;
          hilog.info(DOMAIN, TAG, 'AVPlayer auto-resuming playback after audio interruption (elapsed: %{public}d ms)', elapsedMs);
          this.play().catch((err: BusinessError) => {
            hilog.warn(DOMAIN, TAG, 'Failed to resume AVPlayer after interrupt: %{public}s', JSON.stringify(err));
          });
        }
      } else if (interruptEvent.hintType === audio.InterruptHint.INTERRUPT_HINT_STOP) {
        this.wasPlayingBeforeInterrupt = false;
        this.interruptTimestamp = 0;
        this.snapshot.state = PlaybackState.PAUSED;
        if (this.onStateChanged) this.onStateChanged(this.snapshot.state, this.snapshot);
      } else if (interruptEvent.hintType === audio.InterruptHint.INTERRUPT_HINT_DUCK) {
        if (this.originalVolumeBeforeDuck < 0) {
          this.originalVolumeBeforeDuck = this.snapshot.volume;
        }
        const duckedVolume = Math.max(0.05, this.originalVolumeBeforeDuck * 0.2);
        player.setVolume(duckedVolume);
      } else if (interruptEvent.hintType === audio.InterruptHint.INTERRUPT_HINT_UNDUCK) {
        if (this.originalVolumeBeforeDuck >= 0) {
          player.setVolume(this.originalVolumeBeforeDuck);
          this.originalVolumeBeforeDuck = -1;
        }
      }
    });
  }

  async play(): Promise<void> {
    if (this.player === undefined) return;
    if (this.snapshot.state === PlaybackState.READY || this.snapshot.state === PlaybackState.PAUSED ||
      this.snapshot.state === PlaybackState.COMPLETED || this.player.state === 'prepared' || this.player.state === 'paused') {
      this.snapshot.state = PlaybackState.PLAYING;
      if (this.onStateChanged) {
        this.onStateChanged(this.snapshot.state, this.snapshot);
      }
      try {
        await this.player.play();
      } catch (_) {
        this.snapshot.state = PlaybackState.ERROR;
        this.snapshot.errorMessage = '无法开始播放';
        if (this.onStateChanged) {
          this.onStateChanged(this.snapshot.state, this.snapshot);
        }
      }
    } else if (this.player.state === 'initialized') {
      this.shouldAutoPlay = true;
    }
  }

  async pause(): Promise<void> {
    this.wasPlayingBeforeInterrupt = false;
    this.interruptTimestamp = 0;
    if (this.player !== undefined && (this.snapshot.state === PlaybackState.PLAYING || this.player.state === 'playing')) {
      this.snapshot.state = PlaybackState.PAUSED;
      if (this.onStateChanged) {
        this.onStateChanged(this.snapshot.state, this.snapshot);
      }
      try { await this.player.pause(); } catch (_) {}
    }
  }

  seek(positionMs: number): void {
    if (this.player === undefined || this.player.state === 'idle' || this.player.state === 'initialized') {
      this.initialSeekMs = positionMs;
      this.snapshot.positionMs = positionMs;
      if (this.onTimeUpdated) {
        this.onTimeUpdated(positionMs);
      }
      return;
    }
    const duration = this.snapshot.durationMs > 0 ? this.snapshot.durationMs : (this.player.duration > 0 ? this.player.duration : 0);
    const maxAllowed = duration > 0 ? duration : positionMs;
    const clamped = Math.min(maxAllowed, Math.max(0, positionMs));
    try {
      this.player.seek(clamped, media.SeekMode.SEEK_CLOSEST);
      this.snapshot.positionMs = clamped;
      if (this.onTimeUpdated) {
        this.onTimeUpdated(clamped);
      }
    } catch (_) {}
  }

  setVolume(volume: number): void {
    this.snapshot.volume = Math.min(1, Math.max(0, volume));
    if (this.originalVolumeBeforeDuck >= 0) {
      this.originalVolumeBeforeDuck = this.snapshot.volume;
    } else if (this.player !== undefined && this.player.state !== 'idle' && this.player.state !== 'released') {
      this.player.setVolume(this.snapshot.volume);
    }
  }

  getSnapshot(): PlaybackSnapshot {
    return {
      state: this.snapshot.state, positionMs: this.snapshot.positionMs, durationMs: this.snapshot.durationMs,
      bufferedPositionMs: this.snapshot.bufferedPositionMs,
      volume: this.snapshot.volume, pitchSemitones: 0, errorMessage: this.snapshot.errorMessage
    };
  }

  async release(): Promise<void> {
    this.generation++;
    this.shouldAutoPlay = false;
    this.wasPlayingBeforeInterrupt = false;
    this.interruptTimestamp = 0;
    this.originalVolumeBeforeDuck = -1;
    if (this.currentFileFd !== undefined) {
      try { fileIo.closeSync(this.currentFileFd); } catch (_) {}
      this.currentFileFd = undefined;
    }
    if (this.player !== undefined) {
      const player = this.player;
      this.player = undefined;
      try { await player.release(); } catch (_) {}
    }
  }
}
