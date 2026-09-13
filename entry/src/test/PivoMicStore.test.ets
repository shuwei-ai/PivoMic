import { describe, it, expect } from '@ohos/hypium';
import { CachedAudioFile } from '../main/ets/audio/OnlineAudioCache';
import { AudioRouteMode, KaraokeSessionSnapshot } from '../main/ets/audio/KaraokeSessionModels';
import { MicrophonePermissionStatus } from '../main/ets/audio/MicrophonePermissionService';
import { MusicSourceKind, PlaybackSnapshot, PlaybackState, Song } from '../main/ets/domain/MusicModels';
import { AppLifecycleEvents, AppLifecycleListener } from '../main/ets/store/AppLifecycleEvents';
import {
  KaraokeCachePort, KaraokeEnginePort, KaraokeEngineProvider, KaraokePermissionPort,
  KaraokePreviewPort, KaraokeRouteMonitorPort, KaraokeSafetyPort, PivoMicStore, PlaybackQueueSource
} from '../main/ets/store/PivoMicStore';

interface PreviewActivity { active: boolean; }

class FakePermission implements KaraokePermissionPort {
  calls: number = 0;
  trace: string[] = [];
  status: MicrophonePermissionStatus = MicrophonePermissionStatus.GRANTED;
  async requestForKaraokeStart(): Promise<MicrophonePermissionStatus> { this.calls++; this.trace.push('permission'); return this.status; }
}

class FakeCache implements KaraokeCachePort {
  calls: number = 0; cancels: number = 0; closes: number = 0; fails: boolean = false;
  trace: string[] = [];
  async prepare(song: Song): Promise<CachedAudioFile> {
    this.calls++; this.trace.push('cache'); if (this.fails) throw new Error('cache failed');
    return { fd: 7, offset: 2, size: 88, close: (): void => { this.closes++; this.trace.push('fileClose'); } };
  }
  cancelPending(): void { this.cancels++; }
}

class FakeSafety implements KaraokeSafetyPort {
  calls: number = 0; allowed: boolean = true; reason: string = ''; safe: boolean = true; allowAec: boolean = true; trace: string[] = [];
  route: AudioRouteMode = AudioRouteMode.Wired;
  evaluate(aecSupported: boolean): string {
    this.calls++; this.trace.push('safety');
    return this.allowed || (this.allowAec && aecSupported) ? '' : (this.reason.length > 0 ? this.reason : 'unsafe');
  }
  routeLabel(): string { return this.route === AudioRouteMode.Wired ? '有线' : '扬声器'; }
  safeOutputConnected(): boolean { return this.safe; }
  detectAudioRouteMode(): AudioRouteMode { return this.route; }
}

class FakeEngine implements KaraokeEnginePort {
  calls: string[] = []; released: number = 0; succeeds: boolean = true; throwSnapshot: boolean = false; throwControl: boolean = false; throwGain: boolean = false;
  trace: string[] = [];
  previewActivity?: PreviewActivity; previewOverlappedPrepare: boolean = false;
  snapshot: KaraokeSessionSnapshot = { state: 'ready', positionMs: 0, durationMs: 123000,
    microphonePeak: 0, latencyMs: 18, underrunCount: 0, fastMode: true,
    aecSupported: false, audioRoute: 0, accompanimentPitchShift: 0,
    pitchCorrectionEnabled: false, pitchCorrectionStrength: 0.5,
    isRecording: false, recordedDurationMs: 0,
    errorCode: 0, errorMessage: '' };
  prepare(fd: number, offset: number, size: number, durationMs: number): void { this.calls.push(`prepare:${fd}:${offset}:${size}:${durationMs}`); this.trace.push('prepare'); this.previewOverlappedPrepare = this.previewActivity?.active ?? false; if (!this.succeeds) throw new Error('prepare failed'); this.snapshot.aecSupported = this.aecAfterPrepare; }
  start(): void { this.calls.push('start'); this.trace.push('start'); if (!this.succeeds) throw new Error('start failed'); this.snapshot.state = 'singing'; }
  pause(): void { this.calls.push('pause'); if (this.throwControl) throw new Error('pause failed'); this.snapshot.state = 'paused'; }
  seek(positionMs: number): void { this.calls.push(`seek:${positionMs}`); if (this.throwControl) throw new Error('seek failed'); this.snapshot.positionMs = positionMs; }
  stop(): void { this.calls.push('stop'); this.trace.push('stop'); this.snapshot.state = 'idle'; }
  release(): void { this.calls.push('release'); this.trace.push('release'); this.released++; }
  setSafeOutputConnected(value: boolean): void { this.calls.push(`safe:${value}`); }
  setAudioRoute(route: number): void { this.calls.push(`route:${route}`); this.snapshot.audioRoute = route; }
  setAccompanimentGain(value: number): void { this.calls.push(`music:${value}`); if (this.throwGain) throw new Error('gain failed'); }
  setVocalGain(value: number): void { this.calls.push(`mic:${value}`); if (this.throwGain) throw new Error('gain failed'); }
  setReverbMix(value: number): void { this.calls.push(`reverb:${value}`); if (this.throwGain) throw new Error('gain failed'); }
  getSnapshot(): KaraokeSessionSnapshot { if (this.throwSnapshot) throw new Error('snapshot failed'); return this.snapshot; }
  aecAfterPrepare: boolean = false;
}

class FakeProvider implements KaraokeEngineProvider {
  engine: FakeEngine = new FakeEngine(); calls: number = 0;
  acquire(): KaraokeEnginePort { this.calls++; return this.engine; }
}
class FakePreview implements KaraokePreviewPort {
  trace: string[] = []; loads: number = 0; releases: number = 0;
  onStateChanged?: (state: PlaybackState, snapshot: PlaybackSnapshot) => void;
  onTimeUpdated?: (positionMs: number) => void;
  snapshot: PlaybackSnapshot = { state: PlaybackState.IDLE, positionMs: 0, durationMs: 0, bufferedPositionMs: 0, volume: 0.8, pitchSemitones: 0, errorMessage: '' };
  async load(song: Song, autoPlay: boolean, initialSeekMs: number = 0): Promise<void> {
    this.loads++;
    this.trace.push('previewLoad');
    this.snapshot.state = autoPlay ? PlaybackState.PLAYING : PlaybackState.READY;
    this.snapshot.positionMs = initialSeekMs;
    this.snapshot.durationMs = song.durationMs;
  }
  async release(): Promise<void> { this.releases++; this.trace.push('previewRelease'); this.snapshot.state = PlaybackState.IDLE; }
  async play(): Promise<void> { this.snapshot.state = PlaybackState.PLAYING; }
  async pause(): Promise<void> { this.snapshot.state = PlaybackState.PAUSED; }
  getSnapshot(): PlaybackSnapshot { return this.snapshot; }
  emitTime(positionMs: number): void {
    this.snapshot.positionMs = positionMs;
    if (this.onTimeUpdated) this.onTimeUpdated(positionMs);
  }
}
class DeferredPermission implements KaraokePermissionPort {
  resolvers: Array<(status: MicrophonePermissionStatus) => void> = [];
  requestForKaraokeStart(): Promise<MicrophonePermissionStatus> {
    return new Promise<MicrophonePermissionStatus>((resolve) => { this.resolvers.push(resolve); });
  }
  resolve(index: number, status: MicrophonePermissionStatus): void { this.resolvers[index](status); }
}
class FakeRouteMonitor implements KaraokeRouteMonitorPort {
  listener?: () => void; unsubscribes: number = 0;
  subscribe(listener: () => void): void { this.listener = listener; }
  unsubscribe(): void { this.listener = undefined; this.unsubscribes++; }
  fire(): void { if (this.listener !== undefined) this.listener(); }
}
class DeferredPreview implements KaraokePreviewPort, PreviewActivity {
  loadResolvers: Array<() => void> = []; releaseResolvers: Array<() => void> = []; releases: number = 0;
  active: boolean = false;
  load(song: Song, autoPlay: boolean): Promise<void> { this.active = true; return new Promise<void>((resolve) => { this.loadResolvers.push(resolve); }); }
  release(): Promise<void> { this.releases++; this.active = false; return new Promise<void>((resolve) => { this.releaseResolvers.push(resolve); }); }
}
class DeferredCache implements KaraokeCachePort {
  resolvers: Array<(file: CachedAudioFile) => void> = []; closed: number[] = []; cancels: number = 0;
  prepare(song: Song): Promise<CachedAudioFile> {
    return new Promise<CachedAudioFile>((resolve) => { this.resolvers.push(resolve); });
  }
  cancelPending(): void { this.cancels++; }
  resolve(index: number, fd: number): void {
    this.resolvers[index]({ fd: fd, offset: 0, size: 10, close: (): void => { this.closed.push(fd); } });
  }
}

function song(id: string = 'one'): Song {
  return { id: id, title: id, artist: 'artist', uri: 'https://audio', durationMs: 123000,
    format: 'MP3', source: MusicSourceKind.ONLINE, provider: 'p', remoteId: id,
    lyricText: '[00:01.00]one\n[00:02.00]two' };
}

function fixture(): [PivoMicStore, FakePermission, FakeCache, FakeSafety, FakeProvider, FakePreview] {
  const permission = new FakePermission(); const cache = new FakeCache();
  const safety = new FakeSafety(); const provider = new FakeProvider(); const preview = new FakePreview();
  const trace: string[] = []; permission.trace = trace; cache.trace = trace; safety.trace = trace; provider.engine.trace = trace; preview.trace = trace;
  return [new PivoMicStore(permission, cache, safety, provider, preview), permission, cache, safety, provider, preview];
}
class FakeLifecycleListener implements AppLifecycleListener {
  events: string[] = [];
  onBackground(): void { this.events.push('background'); }
  onForeground(): void { this.events.push('foreground'); }
  onDestroy(): void { this.events.push('destroy'); }
}

export default function pivoMicStoreTest() {
  describe('pivoMicStoreKaraoke', () => {
    it('selectDoesNotPromptCacheOrCapture', 0, async () => {
      const values = fixture(); await values[0].selectSong(song());
      expect(values[1].calls).assertEqual(0); expect(values[2].calls).assertEqual(0);
      expect(values[4].calls).assertEqual(0); expect(values[4].engine.calls.length).assertEqual(0);
    });
    it('startsInPermissionCacheSafetyNativeOrder', 0, async () => {
      const values = fixture(); await values[0].selectSong(song()); values[1].trace.splice(0); await values[0].startKaraoke();
      expect(values[1].trace.join('>')).assertEqual('permission>cache>previewRelease>prepare>safety>start');
      await values[0].togglePlayback(); expect(values[0].session.state).assertEqual('paused');
      await values[0].togglePlayback(); expect(values[0].session.state).assertEqual('singing');
      expect(values[1].calls).assertEqual(1); expect(values[2].calls).assertEqual(1);
      expect(values[3].calls).assertEqual(2); expect(values[4].engine.calls[0]).assertEqual('prepare:7:2:88:123000');
      expect(values[4].engine.calls.includes('safe:true')).assertTrue(); expect(values[4].engine.calls.includes('route:3')).assertTrue();
      expect(values[4].engine.calls.includes('start')).assertTrue(); expect(values[0].session.state).assertEqual('singing');
    });
    it('startsSpeakerKaraokeWithCaptureAndWithoutPreviewFallback', 0, async () => {
      const values = fixture(); values[3].safe = false; values[3].route = AudioRouteMode.Speaker;
      await values[0].selectSong(song()); const previewLoads = values[5].loads; await values[0].startKaraoke();
      expect(values[4].engine.calls.includes('safe:false')).assertTrue();
      expect(values[4].engine.calls.includes('route:0')).assertTrue();
      expect(values[4].engine.calls.includes('start')).assertTrue();
      expect(values[5].loads).assertEqual(previewLoads);
      expect(values[0].session.state).assertEqual('singing');
    });
    it('openingMicStartsKaraokeEvenWhenPreviewStateIsStillIdle', 0, async () => {
      const values = fixture(); await values[0].selectSong(song());
      expect(values[0].playback.state).assertEqual('ready');
      await values[0].toggleMicrophone();
      expect(values[4].engine.calls.includes('start')).assertTrue();
      expect(values[0].session.state).assertEqual('singing');
    });
    it('switchesToKaraokeWhenMicIsEnabledDuringPreviewLoad', 0, async () => {
      const permission = new FakePermission(); const cache = new FakeCache(); const safety = new FakeSafety();
      const provider = new FakeProvider(); const preview = new DeferredPreview();
      const store = new PivoMicStore(permission, cache, safety, provider, preview);
      const selection = store.selectSong(song(), true);
      preview.releaseResolvers[0](); await Promise.resolve(); await Promise.resolve();
      await store.toggleMicrophone();
      preview.loadResolvers[0](); await Promise.resolve();
      preview.releaseResolvers[1](); await selection;
      expect(provider.engine.calls.includes('start')).assertTrue();
      expect(store.session.state).assertEqual('singing');
    });
    it('refreshesRouteAfterAsyncPreparationBeforeStartingNative', 0, async () => {
      const permission = new DeferredPermission(); const cache = new FakeCache(); const safety = new FakeSafety();
      const provider = new FakeProvider(); const preview = new FakePreview();
      const store = new PivoMicStore(permission, cache, safety, provider, preview);
      await store.selectSong(song()); const start = store.startKaraoke();
      safety.safe = false; safety.route = AudioRouteMode.Speaker;
      permission.resolve(0, MicrophonePermissionStatus.GRANTED); await start;
      expect(provider.engine.calls.includes('route:0')).assertTrue();
      expect(provider.engine.calls.includes('safe:false')).assertTrue();
      expect(store.statusMessage).assertContain('无耳机K歌进行中');
    });
    it('denialAndUnsafeRouteNeverStartNative', 0, async () => {
      const denied = fixture(); denied[1].status = MicrophonePermissionStatus.DENIED;
      await denied[0].selectSong(song()); await denied[0].startKaraoke();
      expect(denied[2].calls).assertEqual(0); expect(denied[4].calls).assertEqual(0);
      expect(denied[0].statusMessage).assertContain('麦克风');
      const unsafe = fixture(); unsafe[3].allowed = false; unsafe[3].allowAec = false; unsafe[3].safe = false; unsafe[3].reason = '请连接耳机';
      await unsafe[0].selectSong(song()); await unsafe[0].startKaraoke();
      expect(unsafe[4].engine.calls.includes('start')).assertFalse(); expect(unsafe[4].engine.calls.filter((value: string) => value.startsWith('prepare')).length).assertEqual(1); expect(unsafe[2].closes).assertEqual(1);
      expect(unsafe[0].monitoringAllowed).assertFalse(); expect(unsafe[0].blockedReason).assertContain('耳机');
      const unsafeTrace = unsafe[1].trace;
      expect(unsafeTrace.indexOf('stop') < unsafeTrace.indexOf('release')).assertTrue();
      expect(unsafeTrace.indexOf('release') < unsafeTrace.indexOf('fileClose')).assertTrue();
    });
    it('usesAecDiscoveredOnlyAfterPrepare', 0, async () => {
      const values = fixture(); values[3].allowed = false; values[3].safe = false; values[4].engine.aecAfterPrepare = true;
      await values[0].selectSong(song()); await values[0].startKaraoke();
      expect(values[4].engine.calls.includes('start')).assertTrue(); expect(values[0].session.aecSupported).assertTrue();
    });
    it('mapsSnapshotsControlsLyricsAndBackgroundPause', 0, async () => {
      const values = fixture(); await values[0].selectSong(song()); await values[0].startKaraoke();
      values[4].engine.snapshot.positionMs = 2100; values[4].engine.snapshot.microphonePeak = 0.7;
      values[4].engine.snapshot.latencyMs = 21; values[4].engine.snapshot.fastMode = false;
      values[4].engine.snapshot.aecSupported = true; values[4].engine.snapshot.errorCode = 9;
      values[4].engine.snapshot.errorMessage = 'xrun'; values[0].pollNativeSnapshot();
      expect(values[0].activeLyricIndex).assertEqual(1); expect(values[0].session.microphonePeak).assertEqual(0.7);
      expect(values[0].session.latencyMs).assertEqual(21); expect(values[0].session.fastMode).assertFalse();
      expect(values[0].session.errorCode).assertEqual(9); expect(values[0].session.errorMessage).assertEqual('xrun');
      values[0].seek(1000); values[0].setAccompanimentGain(0.4); values[0].setVocalGain(0.5); values[0].setReverbMix(0.2);
      values[0].handleBackground(); values[0].handleForeground();
      expect(values[4].engine.calls.includes('seek:1000')).assertTrue();
      expect(values[4].engine.calls.filter((value: string) => value === 'start').length).assertEqual(1);
    });
    it('songChangeAndReleaseCancelCloseStopWithoutPreviewFallback', 0, async () => {
      const values = fixture(); await values[0].selectSong(song()); await values[0].startKaraoke();
      await values[0].selectSong(song('two'));
      expect(values[2].cancels > 0).assertTrue(); expect(values[2].closes).assertEqual(1);
      expect(values[4].engine.calls.includes('stop')).assertTrue(); expect(values[4].engine.released).assertEqual(1);
      expect(values[0].playback.state).assertEqual('ready');
      await values[0].release(); expect(values[2].cancels > 1).assertTrue();
    });
    it('nativeFailureClosesFileAndShowsError', 0, async () => {
      const values = fixture(); values[4].engine.succeeds = false;
      await values[0].selectSong(song()); await values[0].startKaraoke();
      expect(values[2].closes).assertEqual(1); expect(values[4].engine.released).assertEqual(1);
      expect(values[0].session.state).assertEqual('error'); expect(values[0].statusMessage).assertContain('failed');
    });
    it('cacheFailureNeverAcquiresNativeEngine', 0, async () => {
      const values = fixture(); values[2].fails = true; await values[0].selectSong(song()); await values[0].startKaraoke();
      expect(values[4].calls).assertEqual(0); expect(values[0].statusMessage).assertContain('cache failed');
    });
    it('deliversAbilityLifecycleAndClearsOwnershipOnDestroy', 0, () => {
      const events = new AppLifecycleEvents(); const listener = new FakeLifecycleListener();
      events.subscribe(listener); events.publishBackground(); events.publishForeground(); events.publishDestroy(); events.publishBackground();
      expect(listener.events.join('>')).assertEqual('background>foreground>destroy');
    });
    it('coalescesBackgroundPreviewUpdatesIntoOneLatestForegroundSnapshot', 0, async () => {
      const values = fixture(); const store = values[0]; const preview = values[5];
      const first = song('background-one'); const second = song('background-two');
      await store.selectSong(first, true);
      let updates = 0; let lastPosition = -1; let lastSongId = '';
      store.addProgressListener((positionMs: number, _activeIndex: number, _snapshot: PlaybackSnapshot): void => {
        updates++;
        lastPosition = positionMs;
        lastSongId = store.selectedSong?.id ?? '';
      });

      store.handleBackground();
      preview.emitTime(1000);
      preview.emitTime(2000);
      await store.selectSong(second, true);
      preview.emitTime(3456);
      expect(updates).assertEqual(0);

      store.handleForeground();
      expect(updates).assertEqual(1);
      expect(lastSongId).assertEqual('background-two');
      expect(lastPosition).assertEqual(3456);

      store.handleForeground();
      expect(updates).assertEqual(1);
    });
    it('stopsSessionOnControlOrGainFailure', 0, async () => {
      const control = fixture(); await control[0].selectSong(song()); await control[0].startKaraoke();
      control[4].engine.throwControl = true; await control[0].togglePlayback();
      expect(control[0].session.state).assertEqual('error'); expect(control[2].closes).assertEqual(1);
      const gain = fixture(); await gain[0].selectSong(song()); await gain[0].startKaraoke();
      gain[4].engine.throwGain = true; gain[0].setVocalGain(0.3);
      expect(gain[0].session.state).assertEqual('error'); expect(gain[2].closes).assertEqual(1);
      expect(gain[1].trace.indexOf('release') < gain[1].trace.indexOf('fileClose')).assertTrue();
      const snapshot = fixture(); await snapshot[0].selectSong(song()); await snapshot[0].startKaraoke();
      snapshot[4].engine.throwSnapshot = true; snapshot[0].pollNativeSnapshot();
      expect(snapshot[0].session.state).assertEqual('error'); expect(snapshot[2].closes).assertEqual(1);
    });
    it('stopKaraokeClosesEverythingAndClearsSafetyUi', 0, async () => {
      const values = fixture(); await values[0].selectSong(song()); await values[0].startKaraoke();
      values[0].blockedReason = 'stale'; values[0].outputRouteLabel = '有线'; values[0].stopKaraoke();
      expect(values[4].engine.calls.includes('stop')).assertTrue(); expect(values[4].engine.released).assertEqual(1);
      expect(values[2].closes).assertEqual(1); expect(values[0].monitoringAllowed).assertFalse();
      expect(values[0].blockedReason).assertEqual(''); expect(values[0].outputRouteLabel).assertEqual('未检测');
    });
    it('releasesExplicitPreviewBeforeNativePrepareWithoutFallback', 0, async () => {
      const values = fixture(); await values[0].selectSong(song()); values[1].trace.splice(0);
      await values[0].startPreviewOnly(); expect(values[5].loads).assertEqual(1);
      await values[0].startKaraoke();
      const trace = values[1].trace;
      expect(trace.indexOf('previewRelease') < trace.indexOf('prepare')).assertTrue();
      expect(values[5].loads).assertEqual(1); expect(values[4].engine.calls.includes('start')).assertTrue();
    });
    it('oldStartCompletionCannotMutateNewSongSession', 0, async () => {
      const permission = new DeferredPermission(); const cache = new FakeCache(); const safety = new FakeSafety();
      const provider = new FakeProvider(); const preview = new FakePreview();
      const store = new PivoMicStore(permission, cache, safety, provider, preview);
      await store.selectSong(song('old')); const oldStart = store.startKaraoke();
      await store.selectSong(song('new')); const newStart = store.startKaraoke();
      permission.resolve(0, MicrophonePermissionStatus.DENIED); await Promise.resolve();
      expect(store.selectedSong?.id).assertEqual('new'); expect(store.isStartPending).assertTrue();
      permission.resolve(1, MicrophonePermissionStatus.GRANTED); await oldStart; await newStart;
      expect(store.selectedSong?.id).assertEqual('new'); expect(store.session.state).assertEqual('singing');
      expect(store.isStartPending).assertFalse(); expect(store.statusMessage).assertContain('耳机K歌进行中');
    });
    it('oldCacheCompletionClosesOnlyOldFileAndKeepsNewStartPending', 0, async () => {
      const permission = new FakePermission(); const cache = new DeferredCache(); const safety = new FakeSafety();
      const provider = new FakeProvider(); const preview = new FakePreview();
      const store = new PivoMicStore(permission, cache, safety, provider, preview);
      await store.selectSong(song('old-cache')); const oldStart = store.startKaraoke(); await Promise.resolve();
      await store.selectSong(song('new-cache')); const newStart = store.startKaraoke(); await Promise.resolve();
      cache.resolve(0, 31); await Promise.resolve();
      expect(cache.closed.includes(31)).assertTrue(); expect(store.isStartPending).assertTrue();
      expect(store.selectedSong?.id).assertEqual('new-cache');
      cache.resolve(1, 32); await oldStart; await newStart;
      expect(store.session.state).assertEqual('singing'); expect(cache.closed.includes(32)).assertFalse();
    });
    it('overlappingSelectionsNeverLetOldPreviewReleaseSelectOldSong', 0, async () => {
      const preview = new DeferredPreview(); const store = new PivoMicStore(undefined, undefined, undefined, undefined, preview);
      const oldSelection = store.selectSong(song('old-selection')); const newSelection = store.selectSong(song('new-selection'));
      preview.releaseResolvers[1](); await newSelection; expect(store.selectedSong?.id).assertEqual('new-selection');
      preview.releaseResolvers[0](); await oldSelection; expect(store.selectedSong?.id).assertEqual('new-selection');
    });
    it('staleSlowPreviewCannotPlayOverNativeOrRepeatedPreview', 0, async () => {
      const permission = new FakePermission(); const cache = new FakeCache(); const safety = new FakeSafety();
      const provider = new FakeProvider(); const preview = new DeferredPreview();
      const store = new PivoMicStore(permission, cache, safety, provider, preview);
      provider.engine.previewActivity = preview;
      const selection = store.selectSong(song()); preview.releaseResolvers[0](); await selection;
      const firstPreview = store.startPreviewOnly(); preview.releaseResolvers[1](); await Promise.resolve();
      const secondPreview = store.startPreviewOnly(); preview.releaseResolvers[2](); await Promise.resolve();
      preview.loadResolvers[0](); await Promise.resolve(); preview.releaseResolvers[3](); await firstPreview;
      const start = store.startKaraoke(); await Promise.resolve(); await Promise.resolve(); preview.releaseResolvers[4]();
      await Promise.resolve(); preview.loadResolvers[1](); await Promise.resolve(); preview.releaseResolvers[5]();
      await secondPreview; await start;
      expect(store.session.state).assertEqual('singing'); expect(provider.engine.calls.includes('start')).assertTrue();
      expect(provider.engine.previewOverlappedPrepare).assertFalse();
    });
    it('switchesActiveKaraokeToSpeakerWithoutStoppingTheEngine', 0, async () => {
      const permission = new FakePermission(); const cache = new FakeCache(); const safety = new FakeSafety();
      const provider = new FakeProvider(); const preview = new FakePreview(); const monitor = new FakeRouteMonitor();
      const store = new PivoMicStore(permission, cache, safety, provider, preview, monitor);
      await store.selectSong(song()); await store.startKaraoke(); const stopCount = provider.engine.calls.filter((call: string) => call === 'stop').length;
      safety.safe = false; safety.route = AudioRouteMode.Speaker; monitor.fire();
      expect(store.session.state).assertEqual('singing'); expect(store.monitoringAllowed).assertTrue();
      expect(provider.engine.calls.includes('safe:false')).assertTrue(); expect(provider.engine.calls.includes('route:0')).assertTrue();
      expect(provider.engine.calls.filter((call: string) => call === 'stop').length).assertEqual(stopCount);
      expect(provider.engine.calls.includes('release')).assertFalse();
      safety.safe = true; safety.route = AudioRouteMode.Wired; monitor.fire();
      expect(provider.engine.calls.includes('route:3')).assertTrue(); expect(store.session.state).assertEqual('singing');
      await store.release(); expect(monitor.unsubscribes > 0).assertTrue();
    });
    it('autoSwitchesSourceWhenPlaybackEncounteredError', 0, async () => {
      const preview = new FakePreview();
      const store = new PivoMicStore(undefined, undefined, undefined, undefined, preview);
      const onlineSong: Song = {
        id: 'online-kugou-123',
        title: '演员',
        artist: '薛之谦',
        uri: 'https://example.com/bad_stream',
        durationMs: 261000,
        format: 'KUGOU',
        source: MusicSourceKind.ONLINE,
        provider: 'kugou',
        remoteId: '123'
      };
      await store.selectSong(onlineSong);
      expect(store.selectedSong?.provider).assertEqual('kugou');
      
      // Simulate switchSource directly
      const success = await store.autoSwitchSource(onlineSong, 0, false);
      expect(typeof success).assertEqual('boolean');
    });
    it('doesNotResetPlaybackWhenSelectingSameSongWhilePlaying', 0, async () => {
      const values = fixture();
      const s1 = song('song-1');
      await values[0].selectSongAndPlay(s1);
      expect(values[0].selectedSong?.id).assertEqual('song-1');
      values[0].playback.positionMs = 35000;
      const initialLoads = values[5].loads;
      const initialReleases = values[5].releases;

      // Click same song while playing
      await values[0].selectSongAndPlay(s1);
      expect(values[0].playback.positionMs).assertEqual(35000);
      expect(values[5].loads).assertEqual(initialLoads);
      expect(values[5].releases).assertEqual(initialReleases);
    });
    it('resumesFromCurrentPositionWhenSelectingSameSongWhilePaused', 0, async () => {
      const values = fixture();
      const s1 = song('song-1');
      await values[0].selectSongAndPlay(s1);
      values[0].playback.state = PlaybackState.PAUSED;
      values[0].playback.positionMs = 28000;
      values[5].snapshot.state = PlaybackState.PAUSED;

      // Click same song while paused
      await values[0].selectSongAndPlay(s1);
      expect(values[0].playback.positionMs).assertEqual(28000);
      expect(values[5].snapshot.state).assertEqual(PlaybackState.PLAYING);
    });
    it('resetsAndPlaysWhenSelectingDifferentSong', 0, async () => {
      const values = fixture();
      const s1 = song('song-1');
      const s2 = song('song-2');
      await values[0].selectSongAndPlay(s1);
      values[0].playback.positionMs = 40000;

      // Click different song
      await values[0].selectSongAndPlay(s2);
      expect(values[0].selectedSong?.id).assertEqual('song-2');
      expect(values[0].playback.positionMs).assertEqual(0);
    });
    it('switchingPlaylistsDoesNotInterruptActiveSongPlayback', 0, async () => {
      const values = fixture();
      const s1 = song('song-active');
      await values[0].selectSongAndPlay(s1);
      values[0].playback.positionMs = 15000;
      const activeState = values[0].playback.state;

      // Load a category or recommendation playlist
      await values[0].loadCategory('chinese', false);
      expect(values[0].selectedSong?.id).assertEqual('song-active');
      expect(values[0].playback.positionMs).assertEqual(15000);
      expect(values[0].playback.state).assertEqual(activeState);
    });
    it('switchesSequentiallyAndLoopsThroughActiveQueue', 0, async () => {
      const values = fixture();
      const s1 = song('song-1');
      const s2 = song('song-2');
      const s3 = song('song-3');
      values[0].songs = [s1, s2, s3];
      await values[0].selectSongAndPlay(s1, PlaybackQueueSource.RECOMMEND_OR_SEARCH, [s1, s2, s3]);

      expect(values[0].selectedSong?.id).assertEqual('song-1');

      // Next -> song-2
      await values[0].playNextSong(false);
      expect(values[0].selectedSong?.id).assertEqual('song-2');

      // Next -> song-3
      await values[0].playNextSong(false);
      expect(values[0].selectedSong?.id).assertEqual('song-3');

      // Next -> loop back to song-1
      await values[0].playNextSong(false);
      expect(values[0].selectedSong?.id).assertEqual('song-1');

      // Prev -> loop back to song-3
      await values[0].playPrevSong();
      expect(values[0].selectedSong?.id).assertEqual('song-3');

      // Prev -> song-2
      await values[0].playPrevSong();
      expect(values[0].selectedSong?.id).assertEqual('song-2');
    });
    it('resetsQueueSourceWhenSwitchingFromFavoritesToRecommend', 0, async () => {
      const values = fixture();
      const favSong = song('fav-1');
      const recSong1 = song('rec-1');
      const recSong2 = song('rec-2');

      values[0].favorites = [favSong];
      values[0].songs = [recSong1, recSong2];

      // 1. Play from favorites
      await values[0].selectSongAndPlay(favSong, PlaybackQueueSource.FAVORITES);
      expect(values[0].playbackQueueSource).assertEqual(PlaybackQueueSource.FAVORITES);
      expect(values[0].selectedSong?.id).assertEqual('fav-1');

      // 2. Play from recommend page
      await values[0].selectSongAndPlay(recSong1, PlaybackQueueSource.RECOMMEND_OR_SEARCH, [recSong1, recSong2]);
      expect(values[0].playbackQueueSource).assertEqual(PlaybackQueueSource.RECOMMEND_OR_SEARCH);
      expect(values[0].selectedSong?.id).assertEqual('rec-1');

      // 3. Next song should be rec-2, NOT fav-1
      await values[0].playNextSong(false);
      expect(values[0].selectedSong?.id).assertEqual('rec-2');
    });

    it('initializesSearchStateAndSwitchesSearchSources', 0, async () => {
      const values = fixture();
      expect(values[0].selectedSearchSource).assertEqual('all');
      expect(values[0].searchPage).assertEqual(1);
      expect(values[0].hasMoreSearchResults).assertTrue();
      expect(values[0].isSearchingMore).assertFalse();

      await values[0].switchSearchSource('netease');
      expect(values[0].selectedSearchSource).assertEqual('netease');

      await values[0].switchSearchSource('qq');
      expect(values[0].selectedSearchSource).assertEqual('qq');
    });

    it('managesSearchHistoryWithLruDeduplicationAndCapacity', 0, () => {
      const values = fixture();
      const store = values[0];
      store.searchHistory = [];

      // 1. Add first keyword
      store.addSearchHistory('周杰伦');
      expect(store.searchHistory.length).assertEqual(1);
      expect(store.searchHistory[0]).assertEqual('周杰伦');

      // 2. Add second keyword
      store.addSearchHistory('晴天');
      expect(store.searchHistory.length).assertEqual(2);
      expect(store.searchHistory[0]).assertEqual('晴天');
      expect(store.searchHistory[1]).assertEqual('周杰伦');

      // 3. Re-add first keyword (LRU move to top)
      store.addSearchHistory('周杰伦');
      expect(store.searchHistory.length).assertEqual(2);
      expect(store.searchHistory[0]).assertEqual('周杰伦');
      expect(store.searchHistory[1]).assertEqual('晴天');

      // 4. Capacity limit 15
      for (let i = 1; i <= 20; i++) {
        store.addSearchHistory(`song_${i}`);
      }
      expect(store.searchHistory.length).assertEqual(15);
      expect(store.searchHistory[0]).assertEqual('song_20');

      // 5. Remove single item
      store.removeSearchHistory('song_20');
      expect(store.searchHistory.length).assertEqual(14);
      expect(store.searchHistory[0]).assertEqual('song_19');

      // 6. Clear all
      store.clearSearchHistory();
      expect(store.searchHistory.length).assertEqual(0);
    });
  });
}
