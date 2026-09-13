import { resourceManager } from '@kit.LocalizationKit';
import { fileIo } from '@kit.CoreFileKit';
import { http } from '@kit.NetworkKit';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { SeparationModelSnapshot } from '../domain/AccompanimentModels';
import { ensureSeparationDirectory, removeSeparationFile, writeSeparationBytes } from './AccompanimentRepository';

const MODEL_BYTES: number = 52787034;
const MODEL_HASH: string = '628d621d64a06237949de109571cad488c977ab1b34f53d852428d44e492f198';
export class SeparationCancellation {
  cancelled: boolean = false;
  request?: http.HttpRequest;
  onCancel?: () => void;
  cancel(): void { this.cancelled = true; if (this.onCancel) this.onCancel(); if (this.request) this.request.destroy(); }
  check(): void { if (this.cancelled) throw new Error('已取消生成'); }
}
export async function hashSeparationFile(path: string, token: SeparationCancellation): Promise<string> {
  const md = cryptoFramework.createMd('SHA256');
  const file = fileIo.openSync(path, fileIo.OpenMode.READ_ONLY);
  try {
    const buffer = new ArrayBuffer(256 * 1024);
    while (true) {
      token.check();
      const count = fileIo.readSync(file.fd, buffer);
      if (count === 0) break;
      await md.update({ data: new Uint8Array(buffer.slice(0, count)) });
    }
    const digest = await md.digest();
    let result: string = '';
    for (let i: number = 0; i < digest.data.length; i++) result += digest.data[i].toString(16).padStart(2, '0');
    return result;
  } finally { fileIo.closeSync(file.fd); }
}
export async function downloadSeparationFile(url: string, path: string, maxBytes: number,
  token: SeparationCancellation, progress: (bytes: number) => void): Promise<void> {
  token.check();
  const file = fileIo.openSync(path, fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC);
  const request = http.createHttp();
  token.request = request;
  let received: number = 0;
  let streamError: string = '';
  let failStream: ((error: Error) => void) | undefined;
  try {
    request.on('dataReceive', (data: ArrayBuffer): void => {
      if (streamError.length > 0 || token.cancelled) return;
      try {
        received += data.byteLength;
        if (received > maxBytes) throw new Error('文件超过处理大小限制');
        writeSeparationBytes(file.fd, new Uint8Array(data));
        progress(received);
      } catch (error) { streamError = (error as Error).message; if (failStream) failStream(new Error(streamError)); request.destroy(); }
    });
    const status = await new Promise<number>((resolve: (status: number) => void, reject: (error: Error) => void): void => {
      failStream = reject;
      let ended: boolean = false;
      let responseStatus: number = -1;
      token.onCancel = (): void => { reject(new Error('已取消生成')); };
      request.on('dataEnd', (): void => {
        ended = true;
        if (responseStatus >= 0) resolve(responseStatus);
      });
      request.requestInStream(url, { method: http.RequestMethod.GET, connectTimeout: 30000, readTimeout: 120000, header: { 'Accept': 'application/octet-stream' } })
        .then((code: number): void => { responseStatus = code; if (ended) resolve(code); })
        .catch((error: Error): void => { reject(error); });
    });
    token.check();
    if (streamError.length > 0) throw new Error(streamError);
    if (status !== 200 || received === 0) throw new Error(`下载失败 (HTTP ${status})`);
    fileIo.fsyncSync(file.fd);
  } finally {
    token.onCancel = undefined;
    token.request = undefined;
    request.destroy();
    fileIo.closeSync(file.fd);
  }
}
export class SeparationModelService {
  path: string = '';
  private resources?: resourceManager.ResourceManager;
  snapshot: SeparationModelSnapshot = { phase: 'missing', progress: 0, errorMessage: '' };
  init(filesDir: string, resources: resourceManager.ResourceManager): void {
    this.resources = resources;
    const dir = `${filesDir}/separation-models`;
    ensureSeparationDirectory(dir);
    this.path = `${dir}/Inst_Main.onnx`;
    removeSeparationFile(`${this.path}.tmp`);
    this.snapshot = { phase: fileIo.accessSync(this.path) ? 'ready' : 'missing', progress: 0, errorMessage: '' };
  }
  async ensure(token: SeparationCancellation, changed: () => void): Promise<string> {
    try {
      if (!fileIo.accessSync(this.path)) {
        if (!this.resources) throw new Error('包内伴奏资源尚未初始化');
        this.snapshot = { phase: 'extracting', progress: 0, errorMessage: '' }; changed();
        const raw = await this.resources.getRawFd('uvr-inst-main.onnx');
        const out = fileIo.openSync(`${this.path}.tmp`, fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC);
        try {
          if (raw.length !== MODEL_BYTES) throw new Error('包内模型大小不匹配');
          const buffer = new ArrayBuffer(262144); let copied: number = 0;
          while (copied < raw.length) {
            token.check();
            const count = fileIo.readSync(raw.fd, buffer, { offset: raw.offset + copied, length: Math.min(buffer.byteLength, raw.length - copied) });
            if (count <= 0) throw new Error('包内模型读取失败');
            writeSeparationBytes(out.fd, new Uint8Array(buffer.slice(0, count))); copied += count;
            this.snapshot.progress = copied / raw.length; changed();
            await new Promise<void>((resolve: () => void): void => { setTimeout(resolve, 0); });
          }
          fileIo.fsyncSync(out.fd);
        } finally { fileIo.closeSync(out.fd); await this.resources.closeRawFd('uvr-inst-main.onnx'); }
      }
      const candidate = fileIo.accessSync(this.path) ? this.path : `${this.path}.tmp`;
      this.snapshot = { phase: 'verifying', progress: 1, errorMessage: '' }; changed();
      if (fileIo.statSync(candidate).size !== MODEL_BYTES || await hashSeparationFile(candidate, token) !== MODEL_HASH) {
        removeSeparationFile(candidate);
        throw new Error('模型校验失败，请重试初始化');
      }
      token.check();
      if (candidate !== this.path) fileIo.renameSync(candidate, this.path);
      this.snapshot = { phase: 'ready', progress: 1, errorMessage: '' }; changed();
      return this.path;
    } catch (error) {
      removeSeparationFile(`${this.path}.tmp`);
      this.snapshot = { phase: token.cancelled ? 'missing' : 'error', progress: 0, errorMessage: (error as Error).message };
      changed(); throw new Error((error as Error).message);
    }
  }
}
