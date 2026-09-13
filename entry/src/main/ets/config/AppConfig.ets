/**
 * Application Global Configuration
 */
export class AppConfig {
  /**
   * PivoMic Cloud Service API Base URL (Auth & Favorites)
   */
  static readonly CLOUD_API_BASE_URL: string = 'https://guangyingzhimeng.dpdns.org/pivomic/api';

  /**
   * Default Online Music Service Origin (Empty by default for store compliance)
   */
  static readonly DEFAULT_ONLINE_MUSIC_SERVICE_ORIGIN: string = '';

  /**
   * Runtime dynamic music service origin configured by the user
   */
  private static dynamicMusicServiceOrigin: string = '';

  /**
   * Runtime dynamic QQ Music API Key configured by the user
   */
  private static dynamicQQMusicApiKey: string = 'qmk-882f0cc6-8297-438a-972b-fe11382921b0';

  /**
   * Get the current active online music service origin
   */
  static getOnlineMusicServiceOrigin(): string {
    return AppConfig.dynamicMusicServiceOrigin.trim();
  }

  /**
   * Set or update the online music service origin
   */
  static setOnlineMusicServiceOrigin(origin: string): void {
    let clean = origin.trim();
    if (clean.endsWith('/')) {
      clean = clean.substring(0, clean.length - 1);
    }
    AppConfig.dynamicMusicServiceOrigin = clean;
  }

  /**
   * Get the current active QQ Music Skill API Key
   */
  static getQQMusicApiKey(): string {
    return AppConfig.dynamicQQMusicApiKey.trim();
  }

  /**
   * Set or update the QQ Music Skill API Key
   */
  static setQQMusicApiKey(key: string): void {
    AppConfig.dynamicQQMusicApiKey = key.trim();
  }

  /**
   * Network Timeouts Configuration (milliseconds)
   */
  static readonly TIMEOUT_SHORT_CONNECT: number = 8000;
  static readonly TIMEOUT_SHORT_READ: number = 10000;
  static readonly TIMEOUT_DEFAULT_CONNECT: number = 10000;
  static readonly TIMEOUT_DEFAULT_READ: number = 15000;
  static readonly TIMEOUT_LONG_CONNECT: number = 15000;
  static readonly TIMEOUT_LONG_READ: number = 20000;
}

