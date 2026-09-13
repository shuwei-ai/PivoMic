import { fileIo } from '@kit.CoreFileKit';
import { AccompanimentAsset, accompanimentMatches } from '../domain/AccompanimentModels';
import { Song } from '../domain/MusicModels';

export function removeSeparationFile(path: string): void {
  try { fileIo.unlinkSync(path); } catch (_) {}
}
export function ensureSeparationDirectory(path: string): void {
  if (!fileIo.accessSync(path)) fileIo.mkdirSync(path, true);
}
export function writeSeparationBytes(fd: number, bytes: Uint8Array): void {
  let offset: number = 0;
  while (offset < bytes.byteLength) {
    const written = fileIo.writeSync(fd, bytes.buffer.slice(bytes.byteOffset + offset, bytes.byteOffset + bytes.byteLength));
    if (written <= 0) throw new Error('文件写入失败，请检查剩余存储空间');
    offset += written;
  }
}
export function validAccompanimentWav(path: string): boolean {
  let fd: number = -1;
  try {
    const stat = fileIo.statSync(path);
    if (!stat.isFile() || stat.size <= 44) return false;
    fd = fileIo.openSync(path, fileIo.OpenMode.READ_ONLY).fd;
    const header = new ArrayBuffer(44);
    if (fileIo.readSync(fd, header) !== 44) return false;
    const bytes = new Uint8Array(header);
    const view = new DataView(header);
    if (view.getUint16(20, true) !== 1 || view.getUint16(22, true) !== 2 || view.getUint32(24, true) !== 44100 || view.getUint16(34, true) !== 16 || view.getUint32(40, true) + 44 !== stat.size) return false;
    return bytes[0] === 82 && bytes[1] === 73 && bytes[2] === 70 && bytes[3] === 70 &&
      bytes[8] === 87 && bytes[9] === 65 && bytes[10] === 86 && bytes[11] === 69;
  } catch (_) { return false; }
  finally { if (fd >= 0) fileIo.closeSync(fd); }
}
export class AccompanimentRepository {
  directory: string = '';
  private assets: AccompanimentAsset[] = [];
  init(filesDir: string): void {
    this.directory = `${filesDir}/accompaniments`;
    ensureSeparationDirectory(this.directory);
    let indexValid: boolean = false;
    try {
      const indexed = JSON.parse(fileIo.readTextSync(`${this.directory}/index.json`)) as AccompanimentAsset[];
      if (Array.isArray(indexed)) {
        this.assets = indexed.filter((asset: AccompanimentAsset): boolean => this.validAsset(asset));
        indexValid = true;
        for (const asset of this.assets) {
          const record = `${this.directory}/${asset.id}.asset.json`;
          if (!fileIo.accessSync(record)) this.writeJson(record, JSON.stringify(asset));
        }
      }
    } catch (_) {}
    if (!indexValid) {
      this.assets = [];
      const records = fileIo.listFileSync(this.directory);
      for (const name of records) {
        if (!/^[a-zA-Z0-9-]+\.asset\.json$/.test(name)) continue;
        try {
          const asset = JSON.parse(fileIo.readTextSync(`${this.directory}/${name}`)) as AccompanimentAsset;
          if (this.validAsset(asset) && name === `${asset.id}.asset.json`) this.assets.push(asset);
        } catch (_) {}
      }
      this.assets.sort((a: AccompanimentAsset, b: AccompanimentAsset): number => b.createdAt - a.createdAt);
      this.persist(this.assets);
    }
    const names = fileIo.listFileSync(this.directory);
    for (let i: number = 0; i < names.length; i++) {
      const path = `${this.directory}/${names[i]}`;
      if (names[i].endsWith('.tmp') || names[i].endsWith('.tmp.pcm')) removeSeparationFile(path);
    }
  }
  list(): AccompanimentAsset[] { return this.assets.slice(); }
  resolve(song: Song): AccompanimentAsset | undefined {
    return this.assets.find((asset: AccompanimentAsset): boolean => accompanimentMatches(asset, song) && validAccompanimentWav(asset.path));
  }
  publish(asset: AccompanimentAsset, temporaryPath: string): void {
    if (!validAccompanimentWav(temporaryPath)) throw new Error('生成的伴奏文件无效');
    fileIo.renameSync(temporaryPath, asset.path);
    const next = [asset].concat(this.assets.filter((item: AccompanimentAsset): boolean => item.id !== asset.id));
    const record = `${this.directory}/${asset.id}.asset.json`;
    try { this.writeJson(record, JSON.stringify(asset)); this.persist(next); }
    catch (error) { removeSeparationFile(asset.path); removeSeparationFile(record); throw new Error((error as Error).message); }
    this.assets = next;
  }
  delete(id: string): void {
    const asset = this.assets.find((item: AccompanimentAsset): boolean => item.id === id);
    if (!asset) return;
    const next = this.assets.filter((item: AccompanimentAsset): boolean => item.id !== id);
    this.persist(next);
    this.assets = next;
    removeSeparationFile(asset.path);
    removeSeparationFile(`${this.directory}/${asset.id}.asset.json`);
  }
  private validAsset(asset: AccompanimentAsset): boolean {
    return asset !== null && typeof asset === 'object' && typeof asset.id === 'string' &&
      /^[a-zA-Z0-9-]+$/.test(asset.id) && asset.path === `${this.directory}/${asset.id}.wav` &&
      asset.song !== null && typeof asset.song === 'object' && typeof asset.song.id === 'string' &&
      typeof asset.song.title === 'string' && typeof asset.song.uri === 'string' &&
      typeof asset.sourceIdentity === 'string' && typeof asset.sourceHash === 'string' &&
      typeof asset.modelId === 'string' && typeof asset.pipelineVersion === 'string' &&
      Number.isFinite(asset.createdAt) && asset.sampleRate === 44100 &&
      Number.isSafeInteger(asset.frameCount) && asset.frameCount > 0 &&
      validAccompanimentWav(asset.path) && fileIo.statSync(asset.path).size === asset.frameCount * 4 + 44;
  }
  private persist(assets: AccompanimentAsset[]): void {
    this.writeJson(`${this.directory}/index.json`, JSON.stringify(assets));
  }
  private writeJson(path: string, text: string): void {
    const file = fileIo.openSync(`${path}.tmp`, fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC);
    try { fileIo.writeSync(file.fd, text); fileIo.fsyncSync(file.fd); }
    finally { fileIo.closeSync(file.fd); }
    fileIo.renameSync(`${path}.tmp`, path);
  }
}
