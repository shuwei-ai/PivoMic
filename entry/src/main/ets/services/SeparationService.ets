import { resourceManager } from '@kit.LocalizationKit';
import { fileIo } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { Song, MusicSourceKind } from '../domain/MusicModels';
import { AccompanimentAsset, NativeSeparationPort, NativeSeparationSnapshot, SeparationJobSnapshot,
  SeparationSnapshot, accompanimentSourceIdentity, copyAccompanimentSong, SEPARATION_MODEL_ID, SEPARATION_PIPELINE_VERSION } from '../domain/AccompanimentModels';
import { AccompanimentRepository, ensureSeparationDirectory, removeSeparationFile, writeSeparationBytes } from './AccompanimentRepository';
import { SeparationModelService, SeparationCancellation, downloadSeparationFile, hashSeparationFile } from './SeparationModelService';

const MAX_SOURCE_BYTES: number = 300 * 1024 * 1024;
export class SeparationService {
  private native: NativeSeparationPort;
  private repository: AccompanimentRepository = new AccompanimentRepository();
  private model: SeparationModelService = new SeparationModelService();
  private cacheDirectory: string = '';
  private token?: SeparationCancellation;
  private nativeJob: number = -1;
  private listeners: ((snapshot: SeparationSnapshot) => void)[] = [];
  private pinned: Map<string, number> = new Map<string, number>();
  private job: SeparationJobSnapshot = { phase: 'idle', progress: 0, errorMessage: '', songId: '' };
  constructor(nativePort: NativeSeparationPort) { this.native = nativePort; }
  init(filesDir: string, cacheDir: string, resources: resourceManager.ResourceManager): void {
    this.repository.init(filesDir); this.model.init(filesDir, resources);
    this.cacheDirectory = `${cacheDir}/separation`;
    ensureSeparationDirectory(this.cacheDirectory);
    const names = fileIo.listFileSync(this.cacheDirectory);
    for (let i: number = 0; i < names.length; i++) removeSeparationFile(`${this.cacheDirectory}/${names[i]}`);
    this.emit();
  }
  subscribe(listener: (snapshot: SeparationSnapshot) => void): () => void {
    this.listeners.push(listener); listener(this.getSnapshot());
    return (): void => { this.listeners = this.listeners.filter((item: (snapshot: SeparationSnapshot) => void): boolean => item !== listener); };
  }
  getSnapshot(): SeparationSnapshot {
    return { assets: this.repository.list(), model: this.model.snapshot, job: this.job, busy: this.token !== undefined };
  }
  resolveAsset(song: Song): AccompanimentAsset | undefined {
    const asset = this.repository.resolve(song);
    if (!asset || song.source !== MusicSourceKind.LOCAL) return asset;
    try { return asset.sourceIdentity === this.sourceIdentity(song) ? asset : undefined; } catch (_) { return undefined; }
  }
  getAsset(id: string): AccompanimentAsset | undefined {
    return this.repository.list().find((asset: AccompanimentAsset): boolean => asset.id === id);
  }
  pinAsset(id: string): () => void {
    this.pinned.set(id, (this.pinned.get(id) ?? 0) + 1);
    let released: boolean = false;
    return (): void => {
      if (released) return;
      released = true;
      this.pinned.set(id, Math.max(0, (this.pinned.get(id) ?? 0) - 1));
    };
  }
  deleteAsset(id: string): void {
    if ((this.pinned.get(id) ?? 0) > 0) throw new Error('请先停止播放此伴奏');
    this.repository.delete(id); this.emit();
  }
  cancel(): void {
    if (!this.token) return;
    this.token.cancel();
    this.job.errorMessage = '正在取消，等待当前计算结束…'; this.emit();
    if (this.nativeJob >= 0) this.native.cancelJob(this.nativeJob);
  }
  private sourceIdentity(song: Song): string {
    const base = accompanimentSourceIdentity(song);
    if (song.source !== MusicSourceKind.LOCAL) return base;
    const file = fileIo.openSync(song.uri, fileIo.OpenMode.READ_ONLY);
    try { const stat = fileIo.statSync(file.fd); return `${base}:${stat.size}:${stat.mtime}`; }
    finally { fileIo.closeSync(file.fd); }
  }
  async generate(song: Song): Promise<void> {
    if (this.token) throw new Error('已有生成任务正在运行');
    if (!this.cacheDirectory) throw new Error('伴奏服务尚未初始化');
    const token = new SeparationCancellation(); this.token = token;
    const id = util.generateRandomUUID();
    const sourcePath = `${this.cacheDirectory}/${id}.source.tmp`;
    const outputPath = `${this.repository.directory}/${id}.wav.tmp`;
    let inputFd: number = -1;
    this.job = { phase: 'preparing', progress: 0, errorMessage: '', songId: song.id }; this.emit();
    try {
      const modelPath = await this.model.ensure(token, (): void => {
        this.job.phase = this.model.snapshot.phase === 'extracting' ? 'preparingModel' : 'verifyingModel';
        this.job.progress = this.model.snapshot.progress; this.emit();
      });
      token.check(); this.update('preparing', 0);
      const sourceIdentity = this.sourceIdentity(song);
      const url = song.streamUrl ?? song.uri;
      if (/^https?:\/\//.test(url)) {
        await downloadSeparationFile(url, sourcePath, MAX_SOURCE_BYTES, token, (_bytes: number): void => {});
      } else {
        const source = fileIo.openSync(song.uri, fileIo.OpenMode.READ_ONLY);
        const target = fileIo.openSync(sourcePath, fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC);
        try {
          const size = fileIo.statSync(source.fd).size;
          if (size <= 0 || size > MAX_SOURCE_BYTES) throw new Error('源音频为空或超过 300 MB');
          const buffer = new ArrayBuffer(256 * 1024); let copied: number = 0;
          while (copied < size) {
            token.check();
            const count = fileIo.readSync(source.fd, buffer);
            if (count === 0) throw new Error('源音频读取不完整');
            writeSeparationBytes(target.fd, new Uint8Array(buffer.slice(0, count)));
            copied += count;
            await new Promise<void>((resolve: () => void): void => { setTimeout(resolve, 0); });
          }
        } finally { fileIo.closeSync(source.fd); fileIo.closeSync(target.fd); }
      }
      const hash = await hashSeparationFile(sourcePath, token); token.check();
      if (sourceIdentity !== this.sourceIdentity(song)) throw new Error('源音频已变化，请重新生成');
      inputFd = fileIo.openSync(sourcePath, fileIo.OpenMode.READ_ONLY).fd;
      this.nativeJob = this.native.startJob(inputFd, 0, fileIo.statSync(inputFd).size, modelPath, outputPath);
      if (this.nativeJob < 0) throw new Error('无法启动本地分离引擎');
      let result: NativeSeparationSnapshot;
      while (true) {
        result = this.native.getJobSnapshot(this.nativeJob);
        if (result.phase === 'ready' || result.phase === 'completed') break;
        if (result.phase === 'failed' || result.phase === 'error') throw new Error(result.errorMessage || '本地分离失败');
        if (result.phase === 'cancelled') throw new Error('已取消生成');
        this.update(result.phase === 'saving' ? 'writing' : (result.phase === 'preparing' ? 'preparing' : 'separating'), result.progress);
        await new Promise<void>((resolve: () => void): void => { setTimeout(resolve, 150); });
      }
      token.check();
      const asset: AccompanimentAsset = { id: id, song: copyAccompanimentSong(song), sourceIdentity: sourceIdentity,
        sourceHash: hash, modelId: SEPARATION_MODEL_ID, pipelineVersion: SEPARATION_PIPELINE_VERSION,
        path: `${this.repository.directory}/${id}.wav`, createdAt: Date.now(), sampleRate: result.sampleRate, frameCount: result.frameCount };
      if (asset.sampleRate <= 0 || asset.frameCount <= 0) throw new Error('生成的音频信息无效');
      this.repository.publish(asset, outputPath); this.update('completed', 1);
    } catch (error) {
      this.job = { phase: token.cancelled ? 'cancelled' : 'error', progress: 0,
        errorMessage: (error as Error).message || '伴奏生成失败', songId: song.id };
    } finally {
      if (this.nativeJob >= 0) { try { this.native.releaseJob(this.nativeJob); } catch (_) {} this.nativeJob = -1; }
      if (inputFd >= 0) fileIo.closeSync(inputFd);
      removeSeparationFile(sourcePath); removeSeparationFile(outputPath);
      this.token = undefined; this.emit();
    }
  }
  private update(phase: string, progress: number): void {
    this.job = { phase: phase, progress: progress, errorMessage: '', songId: this.job.songId }; this.emit();
  }
  private emit(): void {
    const snapshot = this.getSnapshot();
    this.listeners.forEach((listener: (snapshot: SeparationSnapshot) => void): void => { try { listener(snapshot); } catch (_) {} });
  }
}
