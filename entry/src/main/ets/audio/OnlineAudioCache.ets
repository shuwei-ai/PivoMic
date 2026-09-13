import { fileIo } from '@kit.CoreFileKit';
import { http } from '@kit.NetworkKit';
import { util } from '@kit.ArkTS';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { MusicSourceKind, Song } from '../domain/MusicModels';

const DOMAIN = 0x0000;
const TAG = 'PivoMicCache';
const MAX_CACHE_FILE_NAME_LENGTH: number = 80;
const PROCESS_TEMP_TAG: string = util.generateRandomUUID();
let nextTemporaryId: number = 0;

export interface CacheNetworkResponse { statusCode: number; data: Uint8Array; }
export interface CacheDownloadOperation { result: Promise<CacheNetworkResponse>; cancel(): void; }
export interface CacheNetworkClient { startDownload(url: string): CacheDownloadOperation; }
export interface CachedAudioFile { fd: number; offset: number; size: number; close: () => void; }
export interface CacheFileStore {
  isValid(path: string): boolean;
  writeTemporary(path: string, data: Uint8Array): void;
  publishTemporary(tempPath: string, finalPath: string): Promise<void>;
  remove(path: string): void;
  openReadOnly(path: string): CachedAudioFile;
  listFiles?(dirPath: string): string[];
  getFileStat?(path: string): CacheFileStat | undefined;
}

export interface CacheByteWriter { write(data: Uint8Array): number; }

export function writeAllBytes(data: Uint8Array, writer: CacheByteWriter): void {
  let offset = 0;
  while (offset < data.byteLength) {
    const remaining = data.subarray(offset);
    const written = writer.write(remaining);
    if (written <= 0 || written > remaining.byteLength) {
      throw new Error('Unable to write the complete accompaniment cache file');
    }
    offset += written;
  }
}

export interface CachePlatformFile { fd: number; }
export interface CacheFileStat { size: number; isFile: boolean; mtime?: number; }
export interface CacheFileOperations {
  stat(pathOrFd: string | number): CacheFileStat;
  openWrite(path: string): CachePlatformFile;
  openReadOnly(path: string): CachePlatformFile;
  write(fd: number, data: Uint8Array): number;
  close(file: CachePlatformFile): void;
  rename(tempPath: string, finalPath: string): Promise<void>;
  remove(path: string): void;
  listFiles?(dirPath: string): string[];
}

function safeSegment(value: string): string {
  const normalized = value.trim().toLowerCase().replace(/[^a-z0-9_.-]+/g, '_').replace(/^_+|_+$/g, '');
  return normalized.length > 0 ? normalized : 'unknown';
}

function stableHash(value: string): string {
  let hash = 2166136261;
  for (let index = 0; index < value.length; index++) {
    hash ^= value.charCodeAt(index);
    hash = Math.imul(hash, 16777619);
  }
  return (hash >>> 0).toString(16).padStart(8, '0');
}

export function buildCacheKey(provider: string, trackId: string): string {
  const identity = `${provider.trim().toLowerCase()}\n${trackId.trim()}`;
  return `${safeSegment(provider)}_${safeSegment(trackId)}_${stableHash(identity)}`;
}

export function buildCacheFileName(provider: string, trackId: string): string {
  const key = buildCacheKey(provider, trackId);
  const extension = '.audio';
  if (key.length + extension.length <= MAX_CACHE_FILE_NAME_LENGTH) return `${key}${extension}`;
  const suffix = `_${stableHash(`${provider}\n${trackId}`)}${extension}`;
  return `${key.substring(0, MAX_CACHE_FILE_NAME_LENGTH - suffix.length)}${suffix}`;
}

export function buildDemoWav(durationMs: number): Uint8Array {
  const sampleRate: number = 48000;
  const boundedDurationMs: number = Math.max(250, Math.min(30000, Math.round(durationMs)));
  const sampleCount: number = Math.floor(sampleRate * boundedDurationMs / 1000);
  const dataBytes: number = sampleCount * 2;
  const bytes = new Uint8Array(44 + dataBytes);
  writeAscii(bytes, 0, 'RIFF'); writeU32(bytes, 4, 36 + dataBytes); writeAscii(bytes, 8, 'WAVE');
  writeAscii(bytes, 12, 'fmt '); writeU32(bytes, 16, 16); writeU16(bytes, 20, 1); writeU16(bytes, 22, 1);
  writeU32(bytes, 24, sampleRate); writeU32(bytes, 28, sampleRate * 2); writeU16(bytes, 32, 2); writeU16(bytes, 34, 16);
  writeAscii(bytes, 36, 'data'); writeU32(bytes, 40, dataBytes);
  for (let index: number = 0; index < sampleCount; index++) {
    const envelope: number = Math.min(1, index / 1200, (sampleCount - index) / 1200);
    const value: number = Math.round(Math.sin(2 * Math.PI * 440 * index / sampleRate) * 4096 * envelope);
    writeU16(bytes, 44 + index * 2, value & 0xffff);
  }
  return bytes;
}

function writeAscii(target: Uint8Array, offset: number, value: string): void {
  for (let index: number = 0; index < value.length; index++) target[offset + index] = value.charCodeAt(index);
}

function writeU16(target: Uint8Array, offset: number, value: number): void {
  target[offset] = value & 0xff; target[offset + 1] = (value >>> 8) & 0xff;
}

function writeU32(target: Uint8Array, offset: number, value: number): void {
  writeU16(target, offset, value & 0xffff); writeU16(target, offset + 2, (value >>> 16) & 0xffff);
}

class SystemCacheDownloadOperation implements CacheDownloadOperation {
  result: Promise<CacheNetworkResponse>;
  private request: http.HttpRequest;
  private finished: boolean = false;
  private destroyed: boolean = false;

  constructor(url: string) {
    this.request = http.createHttp();
    this.result = this.run(url);
  }

  private async run(url: string): Promise<CacheNetworkResponse> {
    try {
      const response = await this.request.request(url, {
        method: http.RequestMethod.GET, connectTimeout: 15000, readTimeout: 120000,
        expectDataType: http.HttpDataType.ARRAY_BUFFER,
        header: { 'Accept': 'audio/*,application/octet-stream', 'User-Agent': 'PivoMic/1.0 HarmonyOS' }
      });
      if (!(response.result instanceof ArrayBuffer)) {
        return { statusCode: response.responseCode, data: new Uint8Array() };
      }
      return { statusCode: response.responseCode, data: new Uint8Array(response.result) };
    } finally {
      this.finished = true;
      this.destroyRequest();
    }
  }

  cancel(): void {
    if (this.finished) return;
    this.destroyRequest();
  }

  private destroyRequest(): void {
    if (this.destroyed) return;
    this.destroyed = true;
    try { this.request.destroy(); } catch (_) {}
  }
}

export class SystemCacheNetworkClient implements CacheNetworkClient {
  startDownload(url: string): CacheDownloadOperation { return new SystemCacheDownloadOperation(url); }
}

export function shouldRetryDownload(statusCode: number): boolean {
  return statusCode === 404 || statusCode === 408 || statusCode === 429 || statusCode >= 500;
}

class HarmonyCacheFileOperations implements CacheFileOperations {
  stat(pathOrFd: string | number): CacheFileStat {
    const stat = fileIo.statSync(pathOrFd);
    return { size: stat.size, isFile: stat.isFile(), mtime: stat.mtime };
  }

  openWrite(path: string): CachePlatformFile {
    return fileIo.openSync(path, fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC);
  }

  openReadOnly(path: string): CachePlatformFile { return fileIo.openSync(path, fileIo.OpenMode.READ_ONLY); }

  write(fd: number, data: Uint8Array): number {
    const exact = data.buffer.slice(data.byteOffset, data.byteOffset + data.byteLength);
    return fileIo.writeSync(fd, exact);
  }

  close(file: CachePlatformFile): void { fileIo.closeSync(file.fd); }
  rename(tempPath: string, finalPath: string): Promise<void> { return fileIo.rename(tempPath, finalPath); }
  remove(path: string): void { fileIo.unlinkSync(path); }

  listFiles(dirPath: string): string[] {
    try {
      return fileIo.listFileSync(dirPath);
    } catch (_) {
      return [];
    }
  }
}

class PlatformByteWriter implements CacheByteWriter {
  private operations: CacheFileOperations;
  private fd: number;
  constructor(operations: CacheFileOperations, fd: number) { this.operations = operations; this.fd = fd; }
  write(data: Uint8Array): number { return this.operations.write(this.fd, data); }
}

export class SystemCacheFileStore implements CacheFileStore {
  private operations: CacheFileOperations;
  constructor(operations: CacheFileOperations = new HarmonyCacheFileOperations()) { this.operations = operations; }

  isValid(path: string): boolean {
    try {
      const stat = this.operations.stat(path);
      return stat.isFile && stat.size > 0;
    } catch (_) { return false; }
  }

  writeTemporary(path: string, data: Uint8Array): void {
    const file = this.operations.openWrite(path);
    try { writeAllBytes(data, new PlatformByteWriter(this.operations, file.fd)); }
    finally { this.operations.close(file); }
  }

  publishTemporary(tempPath: string, finalPath: string): Promise<void> {
    return this.operations.rename(tempPath, finalPath);
  }

  remove(path: string): void { try { this.operations.remove(path); } catch (_) {} }

  listFiles(dirPath: string): string[] {
    return this.operations.listFiles ? this.operations.listFiles(dirPath) : [];
  }

  getFileStat(path: string): CacheFileStat | undefined {
    try {
      return this.operations.stat(path);
    } catch (_) {
      return undefined;
    }
  }

  openReadOnly(path: string): CachedAudioFile {
    const rawPath = path.startsWith('file://') ? path.substring(7) : path;
    const file = this.operations.openReadOnly(rawPath);
    let size = 0;
    try {
      const stat = this.operations.stat(file.fd);
      if (!stat.isFile || stat.size <= 0) throw new Error('Cached accompaniment is not a valid file');
      size = stat.size;
    } catch (_) {
      this.operations.close(file);
      throw new Error('Unable to validate cached accompaniment file');
    }
    let closed = false;
    return {
      fd: file.fd, offset: 0, size: size,
      close: (): void => {
        if (!closed) { closed = true; this.operations.close(file); }
      }
    };
  }
}

function nextTempPath(finalPath: string): string {
  nextTemporaryId += 1;
  return `${finalPath}.${PROCESS_TEMP_TAG}.${nextTemporaryId}.tmp`;
}

interface InFlightPreload {
  finalPath: string;
  tempPath: string;
  download: CacheDownloadOperation;
  promise: Promise<boolean>;
}

const MAX_CONCURRENT_PRELOADS: number = 2;

export class OnlineAudioCache {
  private cacheDirectory: string;
  private network: CacheNetworkClient;
  private files: CacheFileStore;
  private generation: number = 0;
  private activeDownload?: CacheDownloadOperation;
  private activePreloads: Map<string, InFlightPreload> = new Map<string, InFlightPreload>();

  constructor(cacheDirectory: string, network: CacheNetworkClient, files: CacheFileStore) {
    this.cacheDirectory = cacheDirectory.replace(/\/$/, '');
    this.network = network;
    this.files = files;
  }

  cancelPending(): void {
    this.generation += 1;
    if (this.activeDownload !== undefined) {
      this.activeDownload.cancel();
      this.activeDownload = undefined;
    }
    this.cancelAllPreloads();
  }

  cancelAllPreloads(): void {
    if (this.activePreloads.size === 0) return;
    hilog.info(DOMAIN, TAG, '[Preload] Cancelling %{public}d active preload(s)', this.activePreloads.size);
    const keys: string[] = [];
    this.activePreloads.forEach((_val: InFlightPreload, key: string) => {
      keys.push(key);
    });
    for (let i = 0; i < keys.length; i++) {
      const inFlight = this.activePreloads.get(keys[i]);
      if (inFlight) {
        try {
          inFlight.download.cancel();
          this.files.remove(inFlight.tempPath);
        } catch (_) {}
      }
    }
    this.activePreloads.clear();
  }

  private cancelOtherPreloads(keepFinalPath: string): void {
    const toCancel: string[] = [];
    this.activePreloads.forEach((_val: InFlightPreload, key: string) => {
      if (key !== keepFinalPath) {
        toCancel.push(key);
      }
    });
    for (let i = 0; i < toCancel.length; i++) {
      const key = toCancel[i];
      const inFlight = this.activePreloads.get(key);
      if (inFlight) {
        try {
          inFlight.download.cancel();
          this.files.remove(inFlight.tempPath);
        } catch (_) {}
        this.activePreloads.delete(key);
      }
    }
  }

  getCachedFilePath(song: Song): string | undefined {
    if (song.source === MusicSourceKind.LOCAL || (song.uri && (song.uri.startsWith('/') || song.uri.startsWith('file://')))) return song.uri;
    const provider = song.provider ?? '';
    const remoteId = song.remoteId ?? '';
    if (provider.length === 0 || remoteId.length === 0) return undefined;
    const finalPath = `${this.cacheDirectory}/${buildCacheFileName(provider, remoteId)}`;
    if (this.files.isValid(finalPath)) {
      return finalPath;
    }
    return undefined;
  }

  async prepare(song: Song): Promise<CachedAudioFile> {
    if (song.source === MusicSourceKind.LOCAL || (song.uri && (song.uri.startsWith('/') || song.uri.startsWith('file://')))) {
      this.cancelPending();
      if (song.uri.length === 0) throw new Error('Local song is missing its file URI');
      return this.files.openReadOnly(song.uri);
    }
    if (song.source === MusicSourceKind.DEMO) return this.prepareDemo(song);
    const provider = song.provider ?? '';
    const remoteId = song.remoteId ?? '';
    const rawUrl = song.streamUrl ?? song.uri;
    if (provider.length === 0 || remoteId.length === 0 || rawUrl.length === 0) {
      throw new Error('Online song is missing provider, track id, or stream URL');
    }
    let downloadUrl = rawUrl;
    if (downloadUrl.includes('/music/download') && !downloadUrl.includes('stream=1')) {
      downloadUrl += downloadUrl.includes('?') ? '&stream=1' : '?stream=1';
    }

    const finalPath = `${this.cacheDirectory}/${buildCacheFileName(provider, remoteId)}`;
    if (this.files.isValid(finalPath)) {
      this.cancelPending();
      hilog.info(DOMAIN, TAG, 'Cache HIT for track %{public}s (%{public}s): %{public}s', song.title, remoteId, finalPath);
      return this.files.openReadOnly(finalPath);
    }

    // Check if in-flight preload matches this target song!
    const inFlight = this.activePreloads.get(finalPath);
    if (inFlight !== undefined) {
      hilog.info(DOMAIN, TAG, '[Preload] HIT in-flight download for: %{public}s, awaiting completion...', song.title);
      this.cancelOtherPreloads(finalPath);
      const success = await inFlight.promise;
      if (success && this.files.isValid(finalPath)) {
        hilog.info(DOMAIN, TAG, '[Preload] In-flight download succeeded for: %{public}s', song.title);
        return this.files.openReadOnly(finalPath);
      }
      hilog.warn(DOMAIN, TAG, '[Preload] In-flight download did not produce valid file, falling back to foreground download: %{public}s', song.title);
    }

    // Miss: Cancel all pending preloads and foreground downloads to dedicate 100% bandwidth to foreground playback
    this.cancelPending();
    const requestGeneration = this.generation;
    hilog.info(DOMAIN, TAG, 'Cache MISS for track %{public}s (%{public}s), downloading from: %{public}s', song.title, remoteId, downloadUrl);

    const tempPath = nextTempPath(finalPath);
    let response: CacheNetworkResponse = { statusCode: 0, data: new Uint8Array() };
    for (let attempt: number = 0; attempt < 2; attempt++) {
      const download = this.network.startDownload(downloadUrl);
      this.activeDownload = download;
      try { response = await download.result; }
      catch (_) {
        if (this.activeDownload === download) this.activeDownload = undefined;
        if (requestGeneration !== this.generation) throw new Error('Stale accompaniment download ignored');
        if (attempt === 0) continue;
        throw new Error('Unable to download accompaniment');
      }
      if (this.activeDownload === download) this.activeDownload = undefined;
      if (requestGeneration !== this.generation) throw new Error('Stale accompaniment download ignored');
      if (attempt === 0 && shouldRetryDownload(response.statusCode)) continue;
      break;
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw new Error(`Accompaniment download failed with HTTP ${response.statusCode}`);
    }
    if (response.data.byteLength === 0) throw new Error('Accompaniment download returned an empty body');

    try {
      this.files.writeTemporary(tempPath, response.data);
      if (requestGeneration !== this.generation) throw new Error('Stale accompaniment download ignored');
      await this.files.publishTemporary(tempPath, finalPath);
      this.trimCacheToLimit(30, 200 * 1024 * 1024, finalPath);
    } catch (_) {
      this.files.remove(tempPath);
      if (requestGeneration !== this.generation) throw new Error('Stale accompaniment download ignored');
      if (this.files.isValid(finalPath)) return this.files.openReadOnly(finalPath);
      throw new Error('Unable to publish accompaniment cache file');
    }
    if (requestGeneration !== this.generation) throw new Error('Stale accompaniment download ignored');
    return this.files.openReadOnly(finalPath);
  }

  async preload(song: Song, protectedPaths?: string[] | string): Promise<boolean> {
    if (song.source === MusicSourceKind.LOCAL || (song.uri && (song.uri.startsWith('/') || song.uri.startsWith('file://'))) || song.source === MusicSourceKind.DEMO) return true;
    const provider = song.provider ?? '';
    const remoteId = song.remoteId ?? '';
    const rawUrl = song.streamUrl ?? song.uri;
    if (provider.length === 0 || remoteId.length === 0 || rawUrl.length === 0) {
      return false;
    }
    const finalPath = `${this.cacheDirectory}/${buildCacheFileName(provider, remoteId)}`;
    if (this.files.isValid(finalPath)) {
      hilog.info(DOMAIN, TAG, '[Preload] Already cached: %{public}s (%{public}s)', song.title, remoteId);
      return true;
    }

    const existingInFlight = this.activePreloads.get(finalPath);
    if (existingInFlight !== undefined) {
      hilog.info(DOMAIN, TAG, '[Preload] Already in flight: %{public}s', song.title);
      return existingInFlight.promise;
    }

    if (this.activeDownload !== undefined) {
      hilog.info(DOMAIN, TAG, '[Preload] Skipped: active foreground download busy (%{public}s)', song.title);
      return false;
    }

    if (this.activePreloads.size >= MAX_CONCURRENT_PRELOADS) {
      hilog.info(DOMAIN, TAG, '[Preload] Skipped: preload pool full (%{public}d/%{public}d) for %{public}s',
        this.activePreloads.size, MAX_CONCURRENT_PRELOADS, song.title);
      return false;
    }

    let downloadUrl = rawUrl;
    if (!downloadUrl.includes('stream=1')) {
      downloadUrl += downloadUrl.includes('?') ? '&stream=1' : '?stream=1';
    }

    const currentGeneration = this.generation;
    const tempPath = nextTempPath(finalPath);
    hilog.info(DOMAIN, TAG, '[Preload] Starting download (%{public}d/%{public}d) for: %{public}s (%{public}s)',
      this.activePreloads.size + 1, MAX_CONCURRENT_PRELOADS, song.title, downloadUrl);

    let downloadOp: CacheDownloadOperation;
    try {
      downloadOp = this.network.startDownload(downloadUrl);
    } catch (startErr) {
      hilog.warn(DOMAIN, TAG, '[Preload] Failed to start download for %{public}s: %{public}s', song.title, JSON.stringify(startErr));
      return false;
    }

    const preloadPromise = (async (): Promise<boolean> => {
      try {
        let response: CacheNetworkResponse;
        try {
          response = await downloadOp.result;
        } finally {
          this.activePreloads.delete(finalPath);
        }

        if (currentGeneration !== this.generation) {
          this.files.remove(tempPath);
          return false;
        }
        if (response.statusCode < 200 || response.statusCode >= 300 || response.data.byteLength === 0) {
          this.files.remove(tempPath);
          return false;
        }

        this.files.writeTemporary(tempPath, response.data);
        if (currentGeneration !== this.generation) {
          this.files.remove(tempPath);
          return false;
        }
        await this.files.publishTemporary(tempPath, finalPath);
        hilog.info(DOMAIN, TAG, '[Preload] Successfully cached: %{public}s -> %{public}s', song.title, finalPath);
        let protectList: string[];
        if (typeof protectedPaths === 'string') {
          protectList = [protectedPaths, finalPath];
        } else if (protectedPaths && protectedPaths.length > 0) {
          protectList = [...protectedPaths, finalPath];
        } else {
          protectList = [finalPath];
        }
        this.trimCacheToLimit(30, 200 * 1024 * 1024, protectList);
        return true;
      } catch (err) {
        this.activePreloads.delete(finalPath);
        this.files.remove(tempPath);
        hilog.warn(DOMAIN, TAG, '[Preload] Download failed for %{public}s: %{public}s', song.title, JSON.stringify(err));
        return false;
      }
    })();

    const inFlight: InFlightPreload = {
      finalPath: finalPath,
      tempPath: tempPath,
      download: downloadOp,
      promise: preloadPromise
    };
    this.activePreloads.set(finalPath, inFlight);

    return preloadPromise;
  }

  trimCacheToLimit(maxCount: number = 30, maxBytes: number = 200 * 1024 * 1024, protectedPaths?: string[] | string): void {
    if (!this.files.listFiles || !this.files.getFileStat) return;
    try {
      const names = this.files.listFiles(this.cacheDirectory);
      interface CacheItemInfo {
        path: string;
        size: number;
        mtime: number;
      }
      const items: CacheItemInfo[] = [];
      let totalSize = 0;
      const protectSet = new Set<string>();
      if (protectedPaths) {
        if (typeof protectedPaths === 'string') {
          protectSet.add(protectedPaths);
        } else {
          for (let i = 0; i < protectedPaths.length; i++) {
            const p = protectedPaths[i];
            if (p && p.length > 0) protectSet.add(p);
          }
        }
      }
      this.activePreloads.forEach((_val: InFlightPreload, key: string) => {
        protectSet.add(key);
      });

      for (let i = 0; i < names.length; i++) {
        const name = names[i];
        if (!name.endsWith('.audio')) continue;
        const filePath = `${this.cacheDirectory}/${name}`;
        if (protectSet.has(filePath)) continue;
        const stat = this.files.getFileStat(filePath);
        if (stat !== undefined && stat.isFile && stat.size > 0) {
          items.push({ path: filePath, size: stat.size, mtime: stat.mtime ?? 0 });
          totalSize += stat.size;
        }
      }
      if (items.length <= maxCount && totalSize <= maxBytes) {
        return;
      }
      items.sort((a: CacheItemInfo, b: CacheItemInfo): number => a.mtime - b.mtime);
      let remainingCount = items.length;
      let remainingBytes = totalSize;
      for (let i = 0; i < items.length; i++) {
        if (remainingCount <= maxCount && remainingBytes <= maxBytes) {
          break;
        }
        const item = items[i];
        this.files.remove(item.path);
        remainingCount -= 1;
        remainingBytes -= item.size;
        hilog.info(DOMAIN, TAG, '[LRU] Evicted old audio cache: %{public}s (%{public}d bytes)', item.path, item.size);
      }
    } catch (e) {
      hilog.warn(DOMAIN, TAG, '[LRU] Trim cache failed: %{public}s', JSON.stringify(e));
    }
  }

  private async prepareDemo(song: Song): Promise<CachedAudioFile> {
    this.cancelPending();
    const requestGeneration: number = this.generation;
    const finalPath: string = `${this.cacheDirectory}/${buildCacheFileName('demo', song.id)}`;
    if (this.files.isValid(finalPath)) return this.files.openReadOnly(finalPath);
    const tempPath: string = nextTempPath(finalPath);
    try {
      this.files.writeTemporary(tempPath, buildDemoWav(song.durationMs));
      if (requestGeneration !== this.generation) throw new Error('Stale demo accompaniment ignored');
      await this.files.publishTemporary(tempPath, finalPath);
    } catch (_) {
      this.files.remove(tempPath);
      if (requestGeneration !== this.generation) throw new Error('Stale demo accompaniment ignored');
      if (!this.files.isValid(finalPath)) throw new Error('Unable to publish demo accompaniment');
    }
    if (requestGeneration !== this.generation) throw new Error('Stale demo accompaniment ignored');
    return this.files.openReadOnly(finalPath);
  }
}
