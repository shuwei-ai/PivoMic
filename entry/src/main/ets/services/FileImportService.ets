import picker from '@ohos.file.picker';
import { fileIo } from '@kit.CoreFileKit';
import { Song } from '../domain/MusicModels';
import { LocalMusicSource } from './LocalMusicSource';

export interface FileImportOutcome {
  songs: Song[];
  message: string;
  cancelled: boolean;
}

export class FileImportService {
  private source: LocalMusicSource = new LocalMusicSource();

  async pickAudioFiles(): Promise<FileImportOutcome> {
    try {
      const audioPicker = new picker.AudioViewPicker();
      const options = new picker.AudioSelectOptions();
      options.maxSelectNumber = 100;
      const uris = await audioPicker.select(options);
      if (uris.length === 0) return { songs: [], message: '未选择文件', cancelled: true };
      const result = await this.source.importUris(uris);
      return { songs: result.songs, message: result.message, cancelled: false };
    } catch (_) {
      return { songs: [], message: '已取消导入或文件选择器暂不可用', cancelled: true };
    }
  }

  async pickSaveDirectory(): Promise<string | undefined> {
    try {
      const audioPicker = new picker.AudioViewPicker();
      const options = new picker.AudioSelectOptions();
      options.maxSelectNumber = 1;
      const uris = await audioPicker.select(options);
      if (uris && uris.length > 0 && uris[0].length > 0) {
        const fullUri = uris[0];
        const lastSlash = fullUri.lastIndexOf('/');
        return lastSlash > 0 ? fullUri.substring(0, lastSlash) : fullUri;
      }
    } catch (_) {
      try {
        const documentPicker = new picker.DocumentViewPicker();
        const options = new picker.DocumentSelectOptions();
        options.maxSelectNumber = 1;
        const uris = await documentPicker.select(options);
        if (uris && uris.length > 0 && uris[0].length > 0) {
          const fullUri = uris[0];
          const lastSlash = fullUri.lastIndexOf('/');
          return lastSlash > 0 ? fullUri.substring(0, lastSlash) : fullUri;
        }
      } catch (_) {}
    }
    return undefined;
  }
}

