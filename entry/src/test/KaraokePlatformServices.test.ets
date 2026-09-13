import { describe, it, expect } from '@ohos/hypium';
import {
  MicrophonePermissionService,
  MicrophonePermissionStatus,
  PermissionRequester
} from '../main/ets/audio/MicrophonePermissionService';
import {
  AudioOutputRoute,
  canStartMonitoring,
  classifyPreferredOutput
} from '../main/ets/audio/KaraokeSafetyPolicy';
import {
  CacheByteWriter,
  CacheDownloadOperation,
  CacheFileStore,
  CacheFileOperations,
  CacheFileStat,
  CacheNetworkClient,
  CacheNetworkResponse,
  CachePlatformFile,
  CachedAudioFile,
  OnlineAudioCache,
  SystemCacheFileStore,
  buildDemoWav,
  buildCacheFileName,
  buildCacheKey,
  shouldRetryDownload,
  writeAllBytes
} from '../main/ets/audio/OnlineAudioCache';
import { MusicSourceKind, Song } from '../main/ets/domain/MusicModels';

class FakePermissionRequester implements PermissionRequester {
  calls: number = 0;
  result: MicrophonePermissionStatus;

  constructor(result: MicrophonePermissionStatus) {
    this.result = result;
  }

  async requestMicrophone(): Promise<MicrophonePermissionStatus> {
    this.calls += 1;
    return this.result;
  }
}

class FakeNetworkClient implements CacheNetworkClient {
  calls: number = 0;
  cancellations: number = 0;
  response: CacheNetworkResponse = { statusCode: 200, data: new Uint8Array([1, 2, 3]) };
  pendingOperations: FakeDownloadOperation[] = [];

  startDownload(url: string): CacheDownloadOperation {
    this.calls += 1;
    if (url === 'pending') {
      const operation = new FakeDownloadOperation((): void => { this.cancellations += 1; });
      this.pendingOperations.push(operation);
      return operation;
    }
    return new ImmediateDownloadOperation(this.response);
  }
}

class ImmediateDownloadOperation implements CacheDownloadOperation {
  result: Promise<CacheNetworkResponse>;

  constructor(response: CacheNetworkResponse) {
    this.result = Promise.resolve(response);
  }

  cancel(): void {
  }
}

class FakeDownloadOperation implements CacheDownloadOperation {
  result: Promise<CacheNetworkResponse>;
  resolver?: (response: CacheNetworkResponse) => void;
  onCancel: () => void;

  constructor(onCancel: () => void) {
    this.onCancel = onCancel;
    this.result = new Promise<CacheNetworkResponse>((resolve) => { this.resolver = resolve; });
  }

  cancel(): void {
    this.onCancel();
  }

  resolve(response: CacheNetworkResponse): void {
    if (this.resolver !== undefined) this.resolver(response);
  }
}

class PartialByteWriter implements CacheByteWriter {
  bytes: number[] = [];

  write(data: Uint8Array): number {
    const count = Math.min(2, data.byteLength);
    for (let index = 0; index < count; index++) this.bytes.push(data[index]);
    return count;
  }
}

class FailingStatFileOperations implements CacheFileOperations {
  closed: number[] = [];

  stat(pathOrFd: string | number): CacheFileStat {
    if (typeof pathOrFd === 'number') throw new Error('stat failed');
    return { size: 0, isFile: false };
  }

  openWrite(path: string): CachePlatformFile { return { fd: 10 }; }
  openReadOnly(path: string): CachePlatformFile { return { fd: 11 }; }
  write(fd: number, data: Uint8Array): number { return data.byteLength; }
  close(file: CachePlatformFile): void { this.closed.push(file.fd); }
  async rename(tempPath: string, finalPath: string): Promise<void> {}
  remove(path: string): void {}
}

class FakeFileStore implements CacheFileStore {
  validPaths: Set<string> = new Set<string>();
  writes: string[] = [];
  publications: string[] = [];
  removals: string[] = [];
  opened: string[] = [];
  temporaryPaths: Set<string> = new Set<string>();
  lastWrite?: Uint8Array;

  isValid(path: string): boolean {
    return this.validPaths.has(path);
  }

  writeTemporary(path: string, data: Uint8Array): void {
    this.writes.push(`${path}:${data.length}`);
    this.lastWrite = new Uint8Array(data);
    this.temporaryPaths.add(path);
  }

  async publishTemporary(tempPath: string, finalPath: string): Promise<void> {
    this.publications.push(`${tempPath}>${finalPath}`);
    if (this.validPaths.has(finalPath)) throw new Error('already published');
    this.temporaryPaths.delete(tempPath);
    this.validPaths.add(finalPath);
  }

  remove(path: string): void {
    this.removals.push(path);
    this.temporaryPaths.delete(path);
  }

  openReadOnly(path: string): CachedAudioFile {
    this.opened.push(path);
    return { fd: 7, offset: 0, size: 3, close: (): void => {} };
  }
}

function onlineSong(provider: string, remoteId: string, streamUrl: string): Song {
  return {
    id: `online-${provider}-${remoteId}`,
    title: 'Song', artist: 'Artist', uri: streamUrl, durationMs: 1000,
    format: 'MP3', source: MusicSourceKind.ONLINE,
    provider: provider, remoteId: remoteId, streamUrl: streamUrl
  };
}

export default function karaokePlatformServicesTest() {
  describe('karaokePlatformServices', () => {
    it('doesNotPromptUntilKaraokeStart', 0, async () => {
      const requester = new FakePermissionRequester(MicrophonePermissionStatus.GRANTED);
      const service = new MicrophonePermissionService(requester);
      expect(requester.calls).assertEqual(0);
      expect(await service.requestForKaraokeStart()).assertEqual(MicrophonePermissionStatus.GRANTED);
      expect(requester.calls).assertEqual(1);
    });

    it('reportsDeniedMicrophonePermission', 0, async () => {
      const requester = new FakePermissionRequester(MicrophonePermissionStatus.DENIED);
      const service = new MicrophonePermissionService(requester);
      expect(await service.requestForKaraokeStart()).assertEqual(MicrophonePermissionStatus.DENIED);
    });

    it('opensImportedLocalAudioWithoutNetworkDownload', 0, async () => {
      const network = new FakeNetworkClient(); const files = new FakeFileStore();
      const cache = new OnlineAudioCache('/cache', network, files);
      const local: Song = { id: 'local-song', title: 'Local', artist: 'Singer',
        uri: 'file://media/Audio/local.mp3', durationMs: 1000, format: 'MP3', source: MusicSourceKind.LOCAL };
      await cache.prepare(local);
      expect(network.calls).assertEqual(0);
      expect(files.opened[0]).assertEqual(local.uri);
    });

    it('generatesPlayableDemoWavWithoutNetworkDownload', 0, async () => {
      const network = new FakeNetworkClient(); const files = new FakeFileStore();
      const cache = new OnlineAudioCache('/cache', network, files);
      const demo: Song = { id: 'demo-tone', title: 'Demo', artist: 'PivoMic', uri: 'demo://tone',
        durationMs: 1000, format: 'WAV', source: MusicSourceKind.DEMO };
      await cache.prepare(demo);
      expect(network.calls).assertEqual(0);
      expect(files.lastWrite?.byteLength).assertEqual(96044);
      const wav = buildDemoWav(1000);
      expect(String.fromCharCode(wav[0], wav[1], wav[2], wav[3])).assertEqual('RIFF');
      expect(String.fromCharCode(wav[8], wav[9], wav[10], wav[11])).assertEqual('WAVE');
    });

    it('allowsAllAecMonitoringCombinations', 0, () => {
      const safe = canStartMonitoring({
        aecSupported: true, safeOutputConnected: false, outputRoute: AudioOutputRoute.SPEAKER
      });
      const wired = canStartMonitoring({
        aecSupported: true, safeOutputConnected: true, outputRoute: AudioOutputRoute.WIRED
      });
      expect(safe.allowed).assertTrue();
      expect(wired.allowed).assertTrue();
    });

    it('allowsSafePhysicalOutputsWithoutAec', 0, () => {
      expect(canStartMonitoring({
        aecSupported: false, safeOutputConnected: true, outputRoute: AudioOutputRoute.WIRED
      }).allowed).assertTrue();
      expect(canStartMonitoring({
        aecSupported: false, safeOutputConnected: true, outputRoute: AudioOutputRoute.USB
      }).allowed).assertTrue();
      expect(canStartMonitoring({
        aecSupported: false, safeOutputConnected: true, outputRoute: AudioOutputRoute.BLUETOOTH_LOW_LATENCY
      }).allowed)
        .assertTrue();
    });

    it('allowsKnownRoutesAndRejectsUnknownOutput', 0, () => {
      const speaker = canStartMonitoring({
        aecSupported: false, safeOutputConnected: false, outputRoute: AudioOutputRoute.SPEAKER
      });
      const bluetooth = canStartMonitoring({
        aecSupported: false, safeOutputConnected: false, outputRoute: AudioOutputRoute.BLUETOOTH_UNVERIFIED
      });
      expect(speaker.allowed).assertTrue();
      expect(bluetooth.allowed).assertTrue();
      expect(canStartMonitoring({
        aecSupported: false,
        safeOutputConnected: true,
        outputRoute: AudioOutputRoute.BLUETOOTH_UNVERIFIED
      }).allowed).assertTrue();
      expect(canStartMonitoring({
        aecSupported: false,
        safeOutputConnected: true,
        outputRoute: AudioOutputRoute.SPEAKER
      }).allowed).assertTrue();
      expect(canStartMonitoring({
        aecSupported: false,
        safeOutputConnected: true,
        outputRoute: AudioOutputRoute.UNKNOWN
      }).allowed).assertFalse();
    });

    it('derivesSafeOutputFromVerifiedRouteDespiteContradictoryHint', 0, () => {
      expect(canStartMonitoring({
        aecSupported: false,
        safeOutputConnected: false,
        outputRoute: AudioOutputRoute.WIRED
      }).allowed).assertTrue();
      expect(canStartMonitoring({
        aecSupported: false,
        safeOutputConnected: false,
        outputRoute: AudioOutputRoute.USB
      }).allowed).assertTrue();
      expect(canStartMonitoring({
        aecSupported: false,
        safeOutputConnected: false,
        outputRoute: AudioOutputRoute.BLUETOOTH_LOW_LATENCY
      }).allowed).assertTrue();
    });

    it('onlyTrustsOnePreferredActiveOutputRegardlessOfOrdering', 0, () => {
      expect(classifyPreferredOutput([AudioOutputRoute.WIRED])).assertEqual(AudioOutputRoute.WIRED);
      expect(classifyPreferredOutput([AudioOutputRoute.USB])).assertEqual(AudioOutputRoute.USB);
      expect(classifyPreferredOutput([AudioOutputRoute.WIRED, AudioOutputRoute.SPEAKER])).assertEqual(AudioOutputRoute.UNKNOWN);
      expect(classifyPreferredOutput([AudioOutputRoute.SPEAKER, AudioOutputRoute.WIRED])).assertEqual(AudioOutputRoute.UNKNOWN);
      expect(canStartMonitoring({ aecSupported: false, safeOutputConnected: true,
        outputRoute: classifyPreferredOutput([AudioOutputRoute.WIRED, AudioOutputRoute.SPEAKER]) }).allowed).assertFalse();
    });

    it('buildsStableBoundedSafeCacheNames', 0, () => {
      const first = buildCacheKey('KuWo', '141/494 937');
      expect(first).assertEqual(buildCacheKey('KuWo', '141/494 937'));
      expect(first).assertContain('kuwo_141_494_937_');
      expect(buildCacheKey('??', 'a') !== buildCacheKey('!!', 'a')).assertTrue();
      const fileName = buildCacheFileName('very-long-provider', 'x'.repeat(200));
      expect(fileName.length <= 80).assertTrue();
      expect(/^[a-z0-9_.-]+$/.test(fileName)).assertTrue();
    });

    it('reusesValidPublishedCacheEntry', 0, async () => {
      const network = new FakeNetworkClient();
      const files = new FakeFileStore();
      const path = `/cache/${buildCacheFileName('kuwo', '1')}`;
      files.validPaths.add(path);
      const cache = new OnlineAudioCache('/cache', network, files);
      const result = await cache.prepare(onlineSong('kuwo', '1', 'url'));
      expect(result.fd).assertEqual(7);
      expect(network.calls).assertEqual(0);
      expect(files.opened[0]).assertEqual(path);
    });

    it('validatesStatusAndPublishesAtomically', 0, async () => {
      const network = new FakeNetworkClient();
      const files = new FakeFileStore();
      const cache = new OnlineAudioCache('/cache', network, files);
      await cache.prepare(onlineSong('kuwo', '2', 'url'));
      expect(files.writes.length).assertEqual(1);
      expect(files.publications[0]).assertContain('.tmp>');
      expect(files.opened[0]).assertEqual(`/cache/${buildCacheFileName('kuwo', '2')}`);
      network.response = { statusCode: 503, data: new Uint8Array([9]) };
      let rejected = false;
      try {
        await cache.prepare(onlineSong('kuwo', '3', 'url'));
      } catch (_) {
        rejected = true;
      }
      expect(rejected).assertTrue();
      expect(files.publications.length).assertEqual(1);
      expect(network.calls).assertEqual(3);
    });

    it('retriesTransientResolverResponses', 0, () => {
      expect(shouldRetryDownload(404)).assertTrue();
      expect(shouldRetryDownload(429)).assertTrue();
      expect(shouldRetryDownload(503)).assertTrue();
      expect(shouldRetryDownload(403)).assertFalse();
      expect(shouldRetryDownload(200)).assertFalse();
    });

    it('writesNonzeroOffsetViewsCompletelyAcrossPartialWrites', 0, () => {
      const source = new Uint8Array([90, 91, 1, 2, 3, 4, 92]);
      const writer = new PartialByteWriter();
      writeAllBytes(source.subarray(2, 6), writer);
      expect(writer.bytes.length).assertEqual(4);
      expect(writer.bytes[0]).assertEqual(1);
      expect(writer.bytes[1]).assertEqual(2);
      expect(writer.bytes[2]).assertEqual(3);
      expect(writer.bytes[3]).assertEqual(4);
    });

    it('closesOpenedDescriptorWhenPostOpenStatFails', 0, () => {
      const operations = new FailingStatFileOperations();
      const store = new SystemCacheFileStore(operations);
      let rejected = false;
      try {
        store.openReadOnly('/cache/file.audio');
      } catch (_) {
        rejected = true;
      }
      expect(rejected).assertTrue();
      expect(operations.closed.length).assertEqual(1);
      expect(operations.closed[0]).assertEqual(11);
    });

    it('doesNotPublishStaleSongDownload', 0, async () => {
      const network = new FakeNetworkClient();
      const files = new FakeFileStore();
      const cache = new OnlineAudioCache('/cache', network, files);
      const stale = cache.prepare(onlineSong('kuwo', 'old', 'pending'));
      const current = cache.prepare(onlineSong('kuwo', 'new', 'url'));
      await current;
      expect(network.cancellations).assertEqual(1);
      network.pendingOperations[0].resolve({ statusCode: 200, data: new Uint8Array([1]) });
      let rejected = false;
      try {
        await stale;
      } catch (_) {
        rejected = true;
      }
      expect(rejected).assertTrue();
      expect(files.publications.length).assertEqual(1);
      expect(files.publications[0]).assertContain('kuwo_new');
      expect(files.writes.length).assertEqual(1);
      expect(files.opened.length).assertEqual(1);
    });

    it('cancelsPendingDownloadWithoutWritingOrOpening', 0, async () => {
      const network = new FakeNetworkClient();
      const files = new FakeFileStore();
      const cache = new OnlineAudioCache('/cache', network, files);
      const pending = cache.prepare(onlineSong('kuwo', 'cancelled', 'pending'));
      cache.cancelPending();
      expect(network.cancellations).assertEqual(1);
      network.pendingOperations[0].resolve({ statusCode: 200, data: new Uint8Array([1]) });
      let rejected = false;
      try {
        await pending;
      } catch (_) {
        rejected = true;
      }
      expect(rejected).assertTrue();
      expect(files.writes.length).assertEqual(0);
      expect(files.publications.length).assertEqual(0);
      expect(files.opened.length).assertEqual(0);
    });

    it('usesUniqueTempsAndAcceptsConcurrentPublishedFinal', 0, async () => {
      const network = new FakeNetworkClient();
      const files = new FakeFileStore();
      const firstCache = new OnlineAudioCache('/cache', network, files);
      const secondCache = new OnlineAudioCache('/cache', network, files);
      const first = firstCache.prepare(onlineSong('kuwo', 'race', 'pending'));
      const second = secondCache.prepare(onlineSong('kuwo', 'race', 'pending'));
      network.pendingOperations[0].resolve({ statusCode: 200, data: new Uint8Array([1, 2]) });
      network.pendingOperations[1].resolve({ statusCode: 200, data: new Uint8Array([1, 2]) });
      await first;
      await second;
      expect(files.writes.length).assertEqual(2);
      expect(files.writes[0] !== files.writes[1]).assertTrue();
      expect(files.temporaryPaths.size).assertEqual(0);
      expect(files.opened.length).assertEqual(2);
    });
  });
}
