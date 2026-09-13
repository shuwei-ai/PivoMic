import { ImportResult, MusicSource, MusicSourceResult, MusicSourceStatus } from './MusicSource';

export interface WebDavConfiguration {
  endpoint: string;
  username: string;
  cacheDirectory: string;
}

export class WebDavMusicSource implements MusicSource {
  private configuration?: WebDavConfiguration;

  configure(configuration: WebDavConfiguration): void {
    this.configuration = configuration;
  }

  listSongs(): Promise<MusicSourceResult> {
    if (this.configuration === undefined) {
      return Promise.resolve({ status: MusicSourceStatus.NOT_CONFIGURED, songs: [], message: 'WebDAV 尚未配置' });
    }
    return Promise.resolve({ status: MusicSourceStatus.NOT_CONFIGURED, songs: [], message: 'WebDAV 连接器将在后续版本启用' });
  }

  importUris(_uris: string[]): Promise<ImportResult> {
    return Promise.resolve({ songs: [], rejectedCount: 0, message: 'WebDAV 不支持本地 URI 导入' });
  }
}

