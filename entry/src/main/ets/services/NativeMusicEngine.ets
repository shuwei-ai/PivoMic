import { http } from '@kit.NetworkKit';
import { buffer } from '@kit.ArkTS';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { Song, MusicSourceKind, RecommendPlaylist } from '../domain/MusicModels';

const DOMAIN = 0x0000;
const TAG = 'NativeMusicEngine';

export interface NativeSearchResult {
  songs: Song[];
  message: string;
}

export interface EngineTestResult {
  success: boolean;
  message: string;
  statusCode?: number;
  kuwoLatencyMs?: number;
  kugouLatencyMs?: number;
  qqLatencyMs?: number;
}

export interface PlayUrlResult {
  url?: string;
  cover?: string;
}

export interface EngineProbeResult {
  ok: boolean;
  ms: number;
}

function responseText(result: string | Object | ArrayBuffer | Uint8Array): string {
  if (typeof result === 'string') return result;
  try {
    if (result instanceof Uint8Array) return buffer.from(result).toString('utf8');
    return buffer.from(result as ArrayBuffer).toString('utf8');
  } catch (_) {
    return '';
  }
}

function parseKuwoJson(raw: string): Record<string, Object> | undefined {
  if (!raw || raw.length === 0) return undefined;
  try {
    return JSON.parse(raw) as Record<string, Object>;
  } catch (_) {
    try {
      const fixed = raw.replace(/'/g, '"');
      return JSON.parse(fixed) as Record<string, Object>;
    } catch (_) {
      return undefined;
    }
  }
}

/**
 * 全新原生多平台音乐引擎 (NativeMusicEngine)
 * 参考 lx-music-source/server.py 原生协议
 * 覆盖：酷我音乐(主力320k)、酷狗音乐、QQ音乐、网易云音乐、汽水音乐
 * 零第三方中继、零 Render.com 免费节点依赖、端侧直连
 */
export class NativeMusicEngine {
  private static instance?: NativeMusicEngine;

  private constructor() {}

  static getInstance(): NativeMusicEngine {
    if (!NativeMusicEngine.instance) {
      NativeMusicEngine.instance = new NativeMusicEngine();
    }
    return NativeMusicEngine.instance;
  }

  // ===========================================================================
  // 1. 酷我音乐 (Kuwo) - 车载端免签直连，主力音源，支持 320k/128k/FLAC
  // ===========================================================================

  async searchKuwo(keyword: string, page: number = 1, pageSize: number = 20): Promise<Song[]> {
    const fetchCount = pageSize * 2;
    const request = http.createHttp();
    const pn = Math.max(0, page - 1);
    const url = `http://search.kuwo.cn/r.s?client=kt&all=${encodeURIComponent(keyword)}&pn=${pn}&rn=${fetchCount}&vipver=1&ft=music&encoding=utf8&rformat=json&mobi=1`;
    hilog.info(DOMAIN, TAG, 'searchKuwo start, keyword: %{public}s, pn: %{public}d, rn: %{public}d', keyword, pn, fetchCount);

    try {
      const response = await request.request(url, {
        method: http.RequestMethod.GET,
        connectTimeout: 8000,
        readTimeout: 12000,
        header: {
          'User-Agent': 'okhttp/3.10.0',
          'Accept': '*/*'
        }
      });

      hilog.info(DOMAIN, TAG, 'searchKuwo HTTP status: %{public}d for keyword: %{public}s', response.responseCode, keyword);

      if (response.responseCode < 200 || response.responseCode >= 300) {
        hilog.warn(DOMAIN, TAG, 'searchKuwo HTTP error: %{public}d', response.responseCode);
        return [];
      }
      const text = responseText(response.result);
      if (!text) {
        hilog.warn(DOMAIN, TAG, 'searchKuwo response body empty');
        return [];
      }

      const data = parseKuwoJson(text);
      if (!data) {
        hilog.warn(DOMAIN, TAG, 'searchKuwo failed to parse JSON, text length: %{public}d', text.length);
        return [];
      }

      const abslist = Array.isArray(data.abslist) ? data.abslist as Array<Record<string, Object>> : [];
      hilog.info(DOMAIN, TAG, 'searchKuwo abslist count: %{public}d', abslist.length);
      const songs: Song[] = [];

      for (let i = 0; i < abslist.length; i++) {
        const item = abslist[i];
        const rawRid = `${item.DC_TARGETID ?? item.MUSICRID ?? ''}`;
        const rid = rawRid.replace(/^MUSIC_/, '');
        const name = `${item.SONGNAME ?? ''}`;
        if (!rid || !name) continue;

        const artist = `${item.ARTIST ?? '未知歌手'}`;
        const album = `${item.ALBUM ?? ''}`;
        const duration = Number(item.DURATION ?? 0);

        let cover: string | undefined = undefined;
        const albumpic = `${item.web_albumpic_short ?? ''}`;
        const artistpic = `${item.web_artistpic_short ?? ''}`;
        const htsPic = `${item.hts_MVPIC ?? ''}`;
        const mvPic = `${item.MVPIC ?? ''}`;
        if (albumpic.length > 0) {
          const short = albumpic.replace(/^\d+\//, '300/');
          cover = `https://img1.kuwo.cn/star/albumcover/${short}`;
        } else if (artistpic.length > 0) {
          const short = artistpic.replace(/^\d+\//, '300/');
          cover = `https://img1.kuwo.cn/star/starheads/${short}`;
        } else if (htsPic.length > 0) {
          cover = htsPic.replace(/^http:\/\//, 'https://');
        } else if (mvPic.length > 0) {
          cover = `https://img1.kuwo.cn/wmvpic/${mvPic}`;
        }

        const song: Song = {
          id: `online-kw-${rid}`,
          title: name,
          artist: artist,
          uri: '',
          durationMs: duration > 0 ? duration * 1000 : 0,
          format: 'KW',
          source: MusicSourceKind.ONLINE,
          provider: 'kw',
          remoteId: rid,
          album: album.length > 0 ? album : undefined,
          coverUrl: cover,
          extra: JSON.stringify({ rid: rid })
        };
        songs.push(song);
        if (songs.length >= pageSize) break;
      }

      hilog.info(DOMAIN, TAG, 'searchKuwo finished for keyword: %{public}s, parsed playable songs: %{public}d', keyword, songs.length);
      return songs;
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'searchKuwo exception: %{public}s', JSON.stringify(err));
      return [];
    } finally {
      request.destroy();
    }
  }

  async resolveKuwoPlayUrl(rid: string, quality: string = '320k'): Promise<string | undefined> {
    const qualitiesToTry = quality === '320k' ? ['320kmp3', '128kmp3'] : [quality === 'flac' ? 'flac' : '128kmp3'];
    for (let i = 0; i < qualitiesToTry.length; i++) {
      const q = qualitiesToTry[i];
      const request = http.createHttp();
      try {
        const ts = Date.now();
        const randSuffix = Math.floor(Math.random() * 9000 + 1000);
        const user = `C_APK_guanwang_${ts}${randSuffix}`;
        const url = `https://mobi.kuwo.cn/mobi.s?f=web&source=kwplayercar_ar_6.0.0.9_B_jiakong_vh.apk&from=PC&type=convert_url_with_sign&br=${q}&rid=${encodeURIComponent(rid)}&user=${user}`;

        const response = await request.request(url, {
          method: http.RequestMethod.GET,
          connectTimeout: 7000,
          readTimeout: 10000,
          header: {
            'User-Agent': 'okhttp/3.10.0',
            'Accept': '*/*'
          }
        });

        if (response.responseCode >= 200 && response.responseCode < 300) {
          const text = responseText(response.result);
          if (text) {
            const json = JSON.parse(text) as Record<string, Object>;
            if (json.code === 200 && json.data && typeof json.data === 'object') {
              const dataObj = json.data as Record<string, Object>;
              const playUrl = `${dataObj.url ?? ''}`;
              if (playUrl.startsWith('http')) {
                hilog.info(DOMAIN, TAG, 'Kuwo resolved %{public}s -> %{public}s (%{public}s)', rid, playUrl, q);
                return playUrl;
              }
            }
          }
        }
      } catch (err) {
        hilog.warn(DOMAIN, TAG, 'resolveKuwoPlayUrl error for rid=%{public}s (%{public}s): %{public}s', rid, q, JSON.stringify(err));
      } finally {
        request.destroy();
      }
    }
    return undefined;
  }

  async fetchKuwoLyric(rid: string): Promise<string> {
    const request = http.createHttp();
    try {
      const url = `http://m.kuwo.cn/newh5/singles/songinfoandlrc?musicId=${encodeURIComponent(rid)}&httpsStatus=1`;
      const response = await request.request(url, {
        method: http.RequestMethod.GET,
        connectTimeout: 8000,
        readTimeout: 10000,
        header: { 'User-Agent': 'Mozilla/5.0' }
      });

      if (response.responseCode >= 200 && response.responseCode < 300) {
        const text = responseText(response.result);
        if (text) {
          const json = JSON.parse(text) as Record<string, Object>;
          const data = (json.data && typeof json.data === 'object') ? json.data as Record<string, Object> : undefined;
          const lrclist = (data && Array.isArray(data.lrclist)) ? data.lrclist as Array<Record<string, Object>> : [];
          if (lrclist.length > 0) {
            const lines: string[] = [];
            for (let i = 0; i < lrclist.length; i++) {
              const item = lrclist[i];
              const timeVal = Number(item.time || 0);
              const m = Math.floor(timeVal / 60);
              const s = (timeVal % 60).toFixed(2);
              const mStr = m < 10 ? `0${m}` : `${m}`;
              const sNum = Number(s);
              const sStr = sNum < 10 ? `0${s}` : `${s}`;
              lines.push(`[${mStr}:${sStr}]${item.lineLyric || ''}`);
            }
            return lines.join('\n');
          }
        }
      }
      return '';
    } catch (_) {
      return '';
    } finally {
      request.destroy();
    }
  }

  // ===========================================================================
  // 2. 酷狗音乐 (Kugou) - 移动端免签直连，返回 MP3 及封面
  // ===========================================================================

  async searchKugou(keyword: string, page: number = 1, pageSize: number = 20): Promise<Song[]> {
    const request = http.createHttp();
    try {
      const url = `http://songsearch.kugou.com/song_search_v2?keyword=${encodeURIComponent(keyword)}&platform=WebFilter&format=json&page=${page}&pagesize=${pageSize * 2}`;
      const response = await request.request(url, {
        method: http.RequestMethod.GET,
        connectTimeout: 8000,
        readTimeout: 12000,
        header: {
          'Referer': 'http://m.kugou.com',
          'User-Agent': 'Mozilla/5.0 (iPhone; CPU iPhone OS 14_0 like Mac OS X) AppleWebKit/605.1.15'
        }
      });

      if (response.responseCode < 200 || response.responseCode >= 300) return [];
      const text = responseText(response.result);
      if (!text) return [];

      const json = JSON.parse(text) as Record<string, Object>;
      const data = (json.data && typeof json.data === 'object') ? json.data as Record<string, Object> : undefined;
      const lists = (data && Array.isArray(data.lists)) ? data.lists as Array<Record<string, Object>> : [];
      const songs: Song[] = [];

      for (let i = 0; i < lists.length; i++) {
        const item = lists[i];
        const priv = Number(item.Privilege || 0);
        if (priv !== 0) continue; // 过滤 VIP

        const hash = `${item.FileHash || ''}`;
        const name = `${item.SongName || ''}`;
        if (!hash || !name) continue;

        const artist = `${item.SingerName || '未知歌手'}`;
        const album = `${item.AlbumName || ''}`;
        const duration = Number(item.Duration || 0);
        const albumId = `${item.AlbumID || ''}`;

        const song: Song = {
          id: `online-kg-${hash}`,
          title: name,
          artist: artist,
          uri: '',
          durationMs: duration > 0 ? duration * 1000 : 0,
          format: 'KG',
          source: MusicSourceKind.ONLINE,
          provider: 'kg',
          remoteId: hash,
          album: album.length > 0 ? album : undefined,
          extra: JSON.stringify({ hash: hash, album_id: albumId })
        };
        songs.push(song);
        if (songs.length >= pageSize) break;
      }
      return songs;
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'searchKugou failed: %{public}s', JSON.stringify(err));
      return [];
    } finally {
      request.destroy();
    }
  }

  async resolveKugouPlayUrl(hash: string): Promise<PlayUrlResult> {
    const request = http.createHttp();
    try {
      const url = `http://m.kugou.com/app/i/getSongInfo.php?cmd=playInfo&hash=${encodeURIComponent(hash)}`;
      const response = await request.request(url, {
        method: http.RequestMethod.GET,
        connectTimeout: 8000,
        readTimeout: 10000,
        header: {
          'Referer': 'http://m.kugou.com',
          'User-Agent': 'Mozilla/5.0 (iPhone; CPU iPhone OS 14_0 like Mac OS X) AppleWebKit/605.1.15'
        }
      });

      if (response.responseCode >= 200 && response.responseCode < 300) {
        const text = responseText(response.result);
        if (text) {
          const json = JSON.parse(text) as Record<string, Object>;
          if (json.status === 1 && json.url) {
            const playUrl = `${json.url}`;
            let coverUrl = `${json.imgUrl || ''}`;
            if (coverUrl.includes('{size}')) {
              coverUrl = coverUrl.replace('{size}', '400');
            }
            if (coverUrl.startsWith('http://')) {
              coverUrl = coverUrl.replace(/^http:\/\//, 'https://');
            }
            const res: PlayUrlResult = { url: playUrl, cover: coverUrl.length > 0 ? coverUrl : undefined };
            return res;
          }
        }
      }
    } catch (_) {}
    finally {
      request.destroy();
    }
    const emptyRes: PlayUrlResult = {};
    return emptyRes;
  }

  // ===========================================================================
  // 3. QQ 音乐 (QQ) - UrlGetVkey 直连 + 官方权威榜单 + 逐字歌词
  // ===========================================================================

  async searchQQ(keyword: string, page: number = 1, pageSize: number = 20): Promise<Song[]> {
    const request = http.createHttp();
    try {
      const url = `http://c.y.qq.com/soso/fcgi-bin/search_for_qq_cp?w=${encodeURIComponent(keyword)}&format=json&p=${page}&n=${pageSize * 2}`;
      const response = await request.request(url, {
        method: http.RequestMethod.GET,
        connectTimeout: 8000,
        readTimeout: 12000,
        header: {
          'Referer': 'http://m.y.qq.com',
          'User-Agent': 'Mozilla/5.0'
        }
      });

      if (response.responseCode < 200 || response.responseCode >= 300) return [];
      const text = responseText(response.result);
      if (!text) return [];

      const json = JSON.parse(text) as Record<string, Object>;
      const data = (json.data && typeof json.data === 'object') ? json.data as Record<string, Object> : undefined;
      const songObj = (data && typeof data.song === 'object') ? data.song as Record<string, Object> : undefined;
      const list = (songObj && Array.isArray(songObj.list)) ? songObj.list as Array<Record<string, Object>> : [];
      const songs: Song[] = [];

      for (let i = 0; i < list.length; i++) {
        const item = list[i];
        const payObj = (item.pay && typeof item.pay === 'object') ? item.pay as Record<string, Object> : undefined;
        const payplay = Number(payObj?.payplay || 0);
        if (payplay !== 0) continue; // 过滤 VIP

        const songmid = `${item.songmid || ''}`;
        const songname = `${item.songname || ''}`;
        if (!songmid || !songname) continue;

        const singerList = Array.isArray(item.singer) ? item.singer as Array<Record<string, Object>> : [];
        const artist = singerList.map((s) => `${s.name || ''}`).filter((s) => s.length > 0).join(' / ') || '未知歌手';
        const albumname = `${item.albumname || ''}`;
        const albummid = `${item.albummid || ''}`;
        const interval = Number(item.interval || 0);
        const cover = albummid.length > 0 ? `https://y.gtimg.cn/music/photo_new/T002R300x300M000${albummid}.jpg` : undefined;

        const song: Song = {
          id: `online-tx-${songmid}`,
          title: songname,
          artist: artist,
          uri: '',
          durationMs: interval > 0 ? interval * 1000 : 0,
          format: 'TX',
          source: MusicSourceKind.ONLINE,
          provider: 'tx',
          remoteId: songmid,
          album: albumname.length > 0 ? albumname : undefined,
          coverUrl: cover,
          extra: JSON.stringify({ songmid: songmid })
        };
        songs.push(song);
        if (songs.length >= pageSize) break;
      }
      return songs;
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'searchQQ failed: %{public}s', JSON.stringify(err));
      return [];
    } finally {
      request.destroy();
    }
  }

  async resolveQQPlayUrl(songmid: string, quality: string = '320k'): Promise<string | undefined> {
    const guid = `${Math.floor(Math.random() * 9000000000 + 1000000000)}`;
    const prefix = quality === '320k' ? 'M800' : 'M500';
    const filename = `${prefix}${songmid}${songmid}.mp3`;

    const postPayload = `{"comm":{"cv":4747474,"ct":24,"format":"json","inCharset":"utf-8","outCharset":"utf-8","notice":0,"platform":"yqq.json","needNewCode":1,"uin":0},"req_1":{"module":"music.vkey.GetVkey","method":"UrlGetVkey","param":{"guid":"${guid}","songmid":["${songmid}"],"songtype":[0],"uin":"0","loginflag":1,"platform":"20","filename":["${filename}"]}}}`;

    const request = http.createHttp();
    try {
      const response = await request.request('https://u.y.qq.com/cgi-bin/musicu.fcg', {
        method: http.RequestMethod.POST,
        connectTimeout: 8000,
        readTimeout: 12000,
        header: {
          'Content-Type': 'application/json',
          'Referer': 'http://y.qq.com',
          'User-Agent': 'Mozilla/5.0'
        },
        extraData: postPayload
      });

      if (response.responseCode >= 200 && response.responseCode < 300) {
        const text = responseText(response.result);
        if (text) {
          const json = JSON.parse(text) as Record<string, Object>;
          const req1 = (json.req_1 && typeof json.req_1 === 'object') ? json.req_1 as Record<string, Object> : undefined;
          const data = (req1 && typeof req1.data === 'object') ? req1.data as Record<string, Object> : undefined;
          const midurlinfo = (data && Array.isArray(data.midurlinfo)) ? data.midurlinfo as Array<Record<string, Object>> : [];
          if (midurlinfo.length > 0) {
            const purl = `${midurlinfo[0].purl || ''}`;
            if (purl.length > 0) {
              const fullUrl = `https://ws.stream.qqmusic.qq.com/${purl}`;
              hilog.info(DOMAIN, TAG, 'QQ resolved %{public}s -> %{public}s', songmid, fullUrl);
              return fullUrl;
            }
          }
        }
      }
    } catch (_) {}
    finally {
      request.destroy();
    }
    return undefined;
  }

  async fetchQQLyric(songmid: string): Promise<string> {
    const request = http.createHttp();
    try {
      const url = `https://c.y.qq.com/lyric/fcgi-bin/fcg_query_lyric_new.fcg?songmid=${encodeURIComponent(songmid)}&format=json&nobase64=1`;
      const response = await request.request(url, {
        method: http.RequestMethod.GET,
        connectTimeout: 8000,
        readTimeout: 10000,
        header: {
          'Referer': 'https://y.qq.com',
          'User-Agent': 'Mozilla/5.0'
        }
      });

      if (response.responseCode >= 200 && response.responseCode < 300) {
        const text = responseText(response.result);
        if (text) {
          const json = JSON.parse(text) as Record<string, Object>;
          if (typeof json.lyric === 'string') {
            return json.lyric;
          }
        }
      }
      return '';
    } catch (_) {
      return '';
    } finally {
      request.destroy();
    }
  }

  // ===========================================================================
  // 4. 汽水音乐 / 抖音 (Soda)
  // ===========================================================================

  async searchSoda(keyword: string, page: number = 1, pageSize: number = 20): Promise<Song[]> {
    const request = http.createHttp();
    const fetchCount = Math.max(pageSize * 2, 40);
    const cursor = Math.max(0, page - 1) * pageSize;
    const nowMs = `${Date.now()}`;
    const params: string[] = [
      'device_platform=android',
      'os=android',
      'ssmix=a',
      'cdid=46556f98-1720-4248-83da-62b74b60b46a',
      'channel=xiaomi_8478_64',
      'aid=386088',
      'app_name=luna',
      'version_code=100198030',
      'version_name=19.8.0',
      'package=com.luna.music',
      'iid=2204957404569386',
      'device_id=2204957404565290',
      `_rticket=${nowMs}`,
      `q=${encodeURIComponent(keyword)}`,
      `cursor=${cursor}`,
      `count=${fetchCount}`
    ];
    const url = `https://api.qishui.com/luna/search/track?${params.join('&')}`;

    hilog.info(DOMAIN, TAG, 'searchSoda start, keyword: %{public}s, cursor: %{public}d, count: %{public}d', keyword, cursor, fetchCount);

    try {
      const response = await request.request(url, {
        method: http.RequestMethod.GET,
        connectTimeout: 8000,
        readTimeout: 12000,
        header: {
          'User-Agent': 'com.luna.music/100198030 (Linux; U; Android 15; zh_CN_#Hans; ABR-AL80; Build/V417IR;tt-ok/3.12.13.19)',
          'Content-Type': 'application/json; charset=UTF-8'
        }
      });

      hilog.info(DOMAIN, TAG, 'searchSoda HTTP status: %{public}d for keyword: %{public}s', response.responseCode, keyword);

      if (response.responseCode < 200 || response.responseCode >= 300) {
        hilog.warn(DOMAIN, TAG, 'searchSoda HTTP error: %{public}d', response.responseCode);
        return [];
      }
      const text = responseText(response.result);
      if (!text) {
        hilog.warn(DOMAIN, TAG, 'searchSoda response body empty');
        return [];
      }

      const json = JSON.parse(text) as Record<string, Object>;
      const extra = (json.extra && typeof json.extra === 'object') ? json.extra as Record<string, Object> : undefined;
      if (extra && extra.empty_search === 1) {
        hilog.warn(DOMAIN, TAG, 'searchSoda API returned empty_search=1 for keyword: %{public}s', keyword);
      }

      const groups = Array.isArray(json.result_groups) ? json.result_groups as Array<Record<string, Object>> : [];
      hilog.info(DOMAIN, TAG, 'searchSoda groups count: %{public}d', groups.length);
      const songs: Song[] = [];

      for (let g = 0; g < groups.length; g++) {
        const group = groups[g];
        const dataList = Array.isArray(group.data) ? group.data as Array<Record<string, Object>> : [];
        for (let i = 0; i < dataList.length; i++) {
          const item = dataList[i];
          const entity = (item.entity && typeof item.entity === 'object') ? item.entity as Record<string, Object> : undefined;
          const track = (entity && typeof entity.track === 'object') ? entity.track as Record<string, Object> : undefined;
          if (!track || !track.id) continue;

          // 仅返回非 VIP 试听可播曲目
          const labelInfo = (track.label_info && typeof track.label_info === 'object') ? track.label_info as Record<string, Object> : undefined;
          const qmap = (labelInfo?.quality_map && typeof labelInfo.quality_map === 'object') ? labelInfo.quality_map as Record<string, Object> : undefined;
          const higherObj = (qmap?.higher && typeof qmap.higher === 'object') ? qmap.higher as Record<string, Object> : undefined;
          const higherPlay = (higherObj?.play_detail && typeof higherObj.play_detail === 'object') ? higherObj.play_detail as Record<string, Object> : undefined;
          const mediumObj = (qmap?.medium && typeof qmap.medium === 'object') ? qmap.medium as Record<string, Object> : undefined;
          const mediumPlay = (mediumObj?.play_detail && typeof mediumObj.play_detail === 'object') ? mediumObj.play_detail as Record<string, Object> : undefined;

          const isHigherVip = Boolean(higherPlay?.need_vip || higherPlay?.need_purchase);
          const isMediumVip = Boolean(!higherPlay && mediumPlay?.need_vip);
          if (isHigherVip || isMediumVip) {
            continue;
          }

          const trackId = `${track.id}`;
          const name = `${track.name || ''}`;
          const artistsList = Array.isArray(track.artists) ? track.artists as Array<Record<string, Object>> : [];
          const artist = artistsList.map((a) => `${a.name || ''}`).filter((s) => s.length > 0).join(' / ') || '未知歌手';
          const albumObj = (track.album && typeof track.album === 'object') ? track.album as Record<string, Object> : undefined;
          const albumName = `${albumObj?.name || ''}`;
          const duration = Number(track.duration || 0);

          // 提取汽水音乐火山引擎 TOS 官方封面规则
          const trackCover = (track.url_cover && typeof track.url_cover === 'object') ? track.url_cover as Record<string, Object> : undefined;
          const albumCover = (albumObj?.url_cover && typeof albumObj.url_cover === 'object') ? albumObj.url_cover as Record<string, Object> : undefined;
          const firstArtist = artistsList.length > 0 ? artistsList[0] : undefined;
          const artistAvatar = (firstArtist?.url_avatar && typeof firstArtist.url_avatar === 'object') ? firstArtist.url_avatar as Record<string, Object> : undefined;
          const coverObj = trackCover || albumCover || artistAvatar;

          let coverUrl: string | undefined = undefined;
          if (coverObj) {
            const uri = `${coverObj.uri || ''}`;
            if (uri.length > 0) {
              const urls = (Array.isArray(coverObj.urls) && (coverObj.urls as Array<Object>).length > 0)
                ? `${(coverObj.urls as Array<Object>)[0] || ''}`
                : 'https://p3-luna.douyinpic.com/img/';
              const tpl = `${coverObj.template_prefix || 'tplv-b829550vbb'}`;
              coverUrl = `${urls}${uri}~${tpl}-image.jpeg`;
            }
          }

          const song: Song = {
            id: `online-sd-${trackId}`,
            title: name,
            artist: artist,
            uri: '',
            durationMs: duration > 0 ? duration * 1000 : 0,
            format: 'SD',
            source: MusicSourceKind.ONLINE,
            provider: 'sd',
            remoteId: trackId,
            album: albumName.length > 0 ? albumName : undefined,
            coverUrl: coverUrl,
            extra: JSON.stringify({ track_id: trackId })
          };
          songs.push(song);
          if (songs.length >= pageSize) break;
        }
        if (songs.length >= pageSize) break;
      }

      hilog.info(DOMAIN, TAG, 'searchSoda finished for keyword: %{public}s, parsed playable songs: %{public}d', keyword, songs.length);
      return songs;
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'searchSoda exception: %{public}s', JSON.stringify(err));
      return [];
    } finally {
      request.destroy();
    }
  }

  async resolveSodaPlayUrl(trackId: string, song?: Song): Promise<string | undefined> {
    const request = http.createHttp();
    hilog.info(DOMAIN, TAG, 'resolveSodaPlayUrl start, trackId: %{public}s', trackId);
    try {
      const url = `https://beta-luna.douyin.com/luna/h5/seo_track?track_id=${encodeURIComponent(trackId)}&device_platform=web`;
      const response = await request.request(url, {
        method: http.RequestMethod.GET,
        connectTimeout: 8000,
        readTimeout: 10000,
        header: { 'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36' }
      });

      if (response.responseCode >= 200 && response.responseCode < 300) {
        const text = responseText(response.result);
        if (text) {
          const json = JSON.parse(text) as Record<string, Object>;
          const player = (json.track_player && typeof json.track_player === 'object') ? json.track_player as Record<string, Object> : undefined;
          const vmodelRaw = `${player?.video_model || ''}`;
          if (vmodelRaw.length > 0) {
            const vmodel = JSON.parse(vmodelRaw) as Record<string, Object>;
            const vlist = Array.isArray(vmodel.video_list) ? vmodel.video_list as Array<Record<string, Object>> : [];
            if (vlist.length > 0) {
              const playUrl = `${vlist[0].main_url || ''}`;
              if (playUrl.startsWith('http')) {
                // 动态补全封面（若当前歌曲未提供）
                if (song && !song.coverUrl) {
                  const seoTrack = (json.seo_track && typeof json.seo_track === 'object') ? json.seo_track as Record<string, Object> : undefined;
                  const seoTrackObj = (seoTrack?.track && typeof seoTrack.track === 'object') ? seoTrack.track as Record<string, Object> : undefined;
                  const seoAlbum = (seoTrackObj?.album && typeof seoTrackObj.album === 'object') ? seoTrackObj.album as Record<string, Object> : undefined;
                  const coverObj = (seoAlbum?.url_cover && typeof seoAlbum.url_cover === 'object') ? seoAlbum.url_cover as Record<string, Object> : undefined;
                  if (coverObj) {
                    const uri = `${coverObj.uri || ''}`;
                    if (uri.length > 0) {
                      const urls = (Array.isArray(coverObj.urls) && (coverObj.urls as Array<Object>).length > 0)
                        ? `${(coverObj.urls as Array<Object>)[0] || ''}`
                        : 'https://p3-luna.douyinpic.com/img/';
                      const tpl = `${coverObj.template_prefix || 'tplv-b829550vbb'}`;
                      song.coverUrl = `${urls}${uri}~${tpl}-image.jpeg`;
                    }
                  }
                }
                hilog.info(DOMAIN, TAG, 'resolveSodaPlayUrl success for trackId: %{public}s, url: %{public}s', trackId, playUrl.substring(0, 60));
                return playUrl;
              }
            }
          }
        }
      }
      hilog.warn(DOMAIN, TAG, 'resolveSodaPlayUrl failed or empty stream for trackId: %{public}s, code: %{public}d', trackId, response.responseCode);
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'resolveSodaPlayUrl exception for trackId: %{public}s, error: %{public}s', trackId, JSON.stringify(err));
    } finally {
      request.destroy();
    }
    return undefined;
  }

  // ===========================================================================
  // 5. 网易云音乐 (Netease)
  // ===========================================================================

  async searchNetease(keyword: string, page: number = 1, pageSize: number = 20): Promise<Song[]> {
    const request = http.createHttp();
    try {
      const offset = Math.max(0, page - 1) * pageSize;
      const url = `https://music.163.com/api/cloudsearch/pc?s=${encodeURIComponent(keyword)}&type=1&offset=${offset}&limit=${pageSize * 2}`;
      const response = await request.request(url, {
        method: http.RequestMethod.GET,
        connectTimeout: 8000,
        readTimeout: 12000,
        header: { 'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)' }
      });

      if (response.responseCode < 200 || response.responseCode >= 300) return [];
      const text = responseText(response.result);
      if (!text) return [];

      const json = JSON.parse(text) as Record<string, Object>;
      const resultObj = (json.result && typeof json.result === 'object') ? json.result as Record<string, Object> : undefined;
      const songsList = (resultObj && Array.isArray(resultObj.songs)) ? resultObj.songs as Array<Record<string, Object>> : [];
      const songs: Song[] = [];

      for (let i = 0; i < songsList.length; i++) {
        const item = songsList[i];
        const fee = Number(item.fee || 0);
        if (fee !== 0) continue; // 过滤 VIP

        const id = `${item.id || ''}`;
        const name = `${item.name || ''}`;
        if (!id || !name) continue;

        const artists = Array.isArray(item.ar) ? item.ar as Array<Record<string, Object>> : [];
        const artist = artists.map((a) => `${a.name || ''}`).filter((s) => s.length > 0).join(' / ') || '未知歌手';
        const al = (item.al && typeof item.al === 'object') ? item.al as Record<string, Object> : undefined;
        const album = `${al?.name || ''}`;
        let cover = `${al?.picUrl || ''}`;
        if (cover.startsWith('http://')) {
          cover = cover.replace(/^http:\/\//, 'https://');
        }
        if (cover.length > 0 && !cover.includes('?')) {
          cover = `${cover}?param=300y300`;
        }
        const duration = Number(item.dt || 0);

        const song: Song = {
          id: `online-wy-${id}`,
          title: name,
          artist: artist,
          uri: '',
          durationMs: duration > 0 ? duration : 0,
          format: 'WY',
          source: MusicSourceKind.ONLINE,
          provider: 'wy',
          remoteId: id,
          album: album.length > 0 ? album : undefined,
          coverUrl: cover.length > 0 ? cover : undefined,
          extra: JSON.stringify({ id: id })
        };
        songs.push(song);
        if (songs.length >= pageSize) break;
      }
      return songs;
    } catch (_) {
      return [];
    } finally {
      request.destroy();
    }
  }

  async fetchNeteaseLyric(id: string): Promise<string> {
    const request = http.createHttp();
    try {
      const url = `https://music.163.com/api/song/lyric?id=${encodeURIComponent(id)}&lv=1`;
      const response = await request.request(url, {
        method: http.RequestMethod.GET,
        connectTimeout: 8000,
        readTimeout: 10000,
        header: { 'User-Agent': 'Mozilla/5.0' }
      });

      if (response.responseCode >= 200 && response.responseCode < 300) {
        const text = responseText(response.result);
        if (text) {
          const json = JSON.parse(text) as Record<string, Object>;
          const lrc = (json.lrc && typeof json.lrc === 'object') ? json.lrc as Record<string, Object> : undefined;
          if (typeof lrc?.lyric === 'string') {
            return lrc.lyric;
          }
        }
      }
      return '';
    } catch (_) {
      return '';
    } finally {
      request.destroy();
    }
  }

  // ===========================================================================
  // 6. 统一搜索入口 (聚合全网 / 分平台)
  // ===========================================================================

  async search(keyword: string, page: number = 1, sources?: string[]): Promise<NativeSearchResult> {
    const trimmed = keyword.trim();
    if (!trimmed) {
      return { songs: [], message: '请输入歌曲或歌手名称' };
    }

    const wantAll = !sources || sources.length === 0 || sources.includes('all');
    const selected = sources && sources.length > 0 ? sources[0] : 'all';

    if (!wantAll) {
      if (selected === 'kw' || selected === 'kuwo') {
        const kwSongs = await this.searchKuwo(trimmed, page);
        return { songs: kwSongs, message: kwSongs.length > 0 ? `酷我找到 ${kwSongs.length} 首歌曲` : '未找到匹配歌曲' };
      }
      if (selected === 'kg' || selected === 'kugou') {
        const kgSongs = await this.searchKugou(trimmed, page);
        return { songs: kgSongs, message: kgSongs.length > 0 ? `酷狗找到 ${kgSongs.length} 首歌曲` : '未找到匹配歌曲' };
      }
      if (selected === 'tx' || selected === 'qq') {
        const qqSongs = await this.searchQQ(trimmed, page);
        return { songs: qqSongs, message: qqSongs.length > 0 ? `QQ音乐找到 ${qqSongs.length} 首歌曲` : '未找到匹配歌曲' };
      }
      if (selected === 'sd' || selected === 'soda') {
        const sdSongs = await this.searchSoda(trimmed, page);
        return { songs: sdSongs, message: sdSongs.length > 0 ? `汽水找到 ${sdSongs.length} 首歌曲` : '未找到匹配歌曲' };
      }
      if (selected === 'wy' || selected === 'netease') {
        const wySongs = await this.searchNetease(trimmed, page);
        return { songs: wySongs, message: wySongs.length > 0 ? `网易云找到 ${wySongs.length} 首歌曲` : '未找到匹配歌曲' };
      }
    }

    // 聚合搜索：酷我(主力320k) + QQ音乐 + 酷狗并发检索
    try {
      const results = await Promise.all([
        this.searchKuwo(trimmed, page, 15),
        this.searchQQ(trimmed, page, 10),
        this.searchKugou(trimmed, page, 10)
      ]);

      const merged: Song[] = [];
      const seenTitles = new Set<string>();

      // 交叉合并，酷我优先排在前面以便秒出 320k 直链
      const maxLen = Math.max(results[0].length, results[1].length, results[2].length);
      for (let i = 0; i < maxLen; i++) {
        for (let p = 0; p < 3; p++) {
          const list = results[p];
          if (i < list.length) {
            const s = list[i];
            const key = `${s.title.toLowerCase()}::${s.artist.toLowerCase()}`;
            if (!seenTitles.has(key)) {
              seenTitles.add(key);
              merged.push(s);
            }
          }
        }
      }

      return {
        songs: merged,
        message: merged.length > 0 ? `全网聚合找到 ${merged.length} 首歌曲` : '没有找到匹配歌曲'
      };
    } catch (e) {
      // 若并发异常，降级单一检索酷我
      const kwSongs = await this.searchKuwo(trimmed, page);
      return { songs: kwSongs, message: kwSongs.length > 0 ? `找到 ${kwSongs.length} 首歌曲` : '检索失败' };
    }
  }

  // ===========================================================================
  // 7. 核心直链换取与智能自动降级换源 (Switch Source Fallback)
  // ===========================================================================

  async resolvePlayUrl(song: Song, quality: string = '320k'): Promise<string | undefined> {
    const provider = (song.provider || '').toLowerCase();
    const songId = song.remoteId || '';

    // 1. 根据当前歌曲提供商直接解析
    if (provider === 'kw' || provider === 'kuwo') {
      const url = await this.resolveKuwoPlayUrl(songId, quality);
      if (url) return url;
    } else if (provider === 'kg' || provider === 'kugou') {
      const res = await this.resolveKugouPlayUrl(songId);
      if (res.url) {
        if (res.cover && !song.coverUrl) song.coverUrl = res.cover;
        return res.url;
      }
    } else if (provider === 'tx' || provider === 'qq') {
      const url = await this.resolveQQPlayUrl(songId, quality);
      if (url) return url;
    } else if (provider === 'sd' || provider === 'soda') {
      const url = await this.resolveSodaPlayUrl(songId, song);
      if (url) return url;
    }

    // 2. 当前平台无法获取直链，触发全网智能换源：在酷我/酷狗/QQ中无缝匹配并播放
    const swapped = await this.switchSource(song);
    if (swapped && swapped.streamUrl) {
      song.streamUrl = swapped.streamUrl;
      song.uri = swapped.streamUrl;
      if (swapped.coverUrl && !song.coverUrl) song.coverUrl = swapped.coverUrl;
      return swapped.streamUrl;
    }

    return undefined;
  }

  async switchSource(song: Song, targetSource?: string, excludeSources: string[] = []): Promise<Song | undefined> {
    const currentProvider = (song.provider || 'kw').toLowerCase();
    const keyword = `${song.title} ${song.artist}`.trim();

    // 依次尝试候选平台：酷我 -> 酷狗 -> QQ音乐 -> 汽水
    const candidates = ['kw', 'kg', 'tx', 'sd'];
    for (let i = 0; i < candidates.length; i++) {
      const src = candidates[i];
      if (src === currentProvider || excludeSources.includes(src)) continue;
      if (targetSource && src !== targetSource) continue;

      let matchedSongs: Song[] = [];
      if (src === 'kw') matchedSongs = await this.searchKuwo(keyword, 1, 3);
      else if (src === 'kg') matchedSongs = await this.searchKugou(keyword, 1, 3);
      else if (src === 'tx') matchedSongs = await this.searchQQ(keyword, 1, 3);
      else if (src === 'sd') matchedSongs = await this.searchSoda(keyword, 1, 3);

      if (matchedSongs.length > 0) {
        const candidate = matchedSongs[0];
        let playUrl: string | undefined = undefined;

        if (src === 'kw') {
          playUrl = await this.resolveKuwoPlayUrl(candidate.remoteId || '', '320k');
        } else if (src === 'kg') {
          const res = await this.resolveKugouPlayUrl(candidate.remoteId || '');
          playUrl = res.url;
          if (res.cover) candidate.coverUrl = res.cover;
        } else if (src === 'tx') {
          playUrl = await this.resolveQQPlayUrl(candidate.remoteId || '', '320k');
        } else if (src === 'sd') {
          playUrl = await this.resolveSodaPlayUrl(candidate.remoteId || '', candidate);
        }

        if (playUrl) {
          candidate.streamUrl = playUrl;
          candidate.uri = playUrl;
          hilog.info(DOMAIN, TAG, 'Auto switchSource successful: %{public}s (%{public}s -> %{public}s)', song.title, currentProvider, src);
          return candidate;
        }
      }
    }
    return undefined;
  }

  // ===========================================================================
  // 8. 歌词获取 (逐字/标准 LRC)
  // ===========================================================================

  async fetchLyrics(song: Song): Promise<string> {
    const provider = (song.provider || '').toLowerCase();
    const songId = song.remoteId || '';

    if (provider === 'kw' || provider === 'kuwo') {
      const lrc = await this.fetchKuwoLyric(songId);
      if (lrc) return lrc;
    } else if (provider === 'tx' || provider === 'qq') {
      const lrc = await this.fetchQQLyric(songId);
      if (lrc) return lrc;
    } else if (provider === 'wy' || provider === 'netease') {
      const lrc = await this.fetchNeteaseLyric(songId);
      if (lrc) return lrc;
    }

    // 跨源歌词兜底：在酷我/QQ上按曲名+歌手匹配
    const keyword = `${song.title} ${song.artist}`.trim();
    const qqMatch = await this.searchQQ(keyword, 1, 1);
    if (qqMatch.length > 0 && qqMatch[0].remoteId) {
      const lrc = await this.fetchQQLyric(qqMatch[0].remoteId);
      if (lrc) return lrc;
    }

    const kwMatch = await this.searchKuwo(keyword, 1, 1);
    if (kwMatch.length > 0 && kwMatch[0].remoteId) {
      const lrc = await this.fetchKuwoLyric(kwMatch[0].remoteId);
      if (lrc) return lrc;
    }

    return '';
  }

  // ===========================================================================
  // 9. 官方权威榜单与推荐
  // ===========================================================================

  async fetchToplists(): Promise<RecommendPlaylist[]> {
    return [
      {
        id: '26',
        source: 'tx',
        name: 'QQ音乐热歌榜',
        creator: '官方权威每日更新',
        coverUrl: 'https://y.gtimg.cn/music/photo_new/T003R300x300M000003bviTG4L3WzF.jpg',
        trackCount: 300
      },
      {
        id: '27',
        source: 'tx',
        name: 'QQ音乐新歌榜',
        creator: '流行风向标',
        coverUrl: 'https://y.gtimg.cn/music/photo_new/T003R300x300M000001Z9eKq4f4X0T.jpg',
        trackCount: 100
      },
      {
        id: '62',
        source: 'tx',
        name: 'QQ音乐飙升榜',
        creator: '全网热搜曲目',
        coverUrl: 'https://y.gtimg.cn/music/photo_new/T003R300x300M000004bcT632W5WqW.jpg',
        trackCount: 100
      },
      {
        id: '4',
        source: 'tx',
        name: 'QQ音乐流行指数榜',
        creator: '热播金曲聚集地',
        coverUrl: 'https://y.gtimg.cn/music/photo_new/T003R300x300M000002M4Z1T3a8M5d.jpg',
        trackCount: 100
      }
    ];
  }

  async fetchToplistSongs(playlist: RecommendPlaylist): Promise<Song[]> {
    const topId = playlist.id || '26';
    const request = http.createHttp();
    try {
      const url = `https://c.y.qq.com/v8/fcg-bin/fcg_v8_toplist_cp.fcg?topid=${encodeURIComponent(topId)}&format=json&n=35&page=detail`;
      const response = await request.request(url, {
        method: http.RequestMethod.GET,
        connectTimeout: 8000,
        readTimeout: 12000,
        header: { 'User-Agent': 'Mozilla/5.0' }
      });

      if (response.responseCode < 200 || response.responseCode >= 300) return [];
      const text = responseText(response.result);
      if (!text) return [];

      const json = JSON.parse(text) as Record<string, Object>;
      const songlist = Array.isArray(json.songlist) ? json.songlist as Array<Record<string, Object>> : [];
      const songs: Song[] = [];

      for (let i = 0; i < songlist.length; i++) {
        const item = songlist[i];
        const data = (item.data && typeof item.data === 'object') ? item.data as Record<string, Object> : undefined;
        if (!data) continue;

        const songmid = `${data.songmid || ''}`;
        const songname = `${data.songname || ''}`;
        if (!songmid || !songname) continue;

        const singerList = Array.isArray(data.singer) ? data.singer as Array<Record<string, Object>> : [];
        const artist = singerList.map((s) => `${s.name || ''}`).filter((s) => s.length > 0).join(' / ') || '未知歌手';
        const albumname = `${data.albumname || ''}`;
        const albummid = `${data.albummid || ''}`;
        const interval = Number(data.interval || 0);
        const cover = albummid.length > 0 ? `https://y.gtimg.cn/music/photo_new/T002R300x300M000${albummid}.jpg` : undefined;

        const song: Song = {
          id: `online-tx-${songmid}`,
          title: songname,
          artist: artist,
          uri: '',
          durationMs: interval > 0 ? interval * 1000 : 0,
          format: 'TX',
          source: MusicSourceKind.ONLINE,
          provider: 'tx',
          remoteId: songmid,
          album: albumname.length > 0 ? albumname : undefined,
          coverUrl: cover,
          extra: JSON.stringify({ songmid: songmid })
        };
        songs.push(song);
      }
      return songs;
    } catch (_) {
      return [];
    } finally {
      request.destroy();
    }
  }

  // ===========================================================================
  // 10. 综合连通测速 (并发测试各平台延迟)
  // ===========================================================================

  async testEngine(): Promise<EngineTestResult> {
    let kwLatency = -1;
    let kgLatency = -1;
    let qqLatency = -1;

    try {
      const probes = await Promise.all([
        (async (): Promise<EngineProbeResult> => {
          const t0 = Date.now();
          const r = await this.searchKuwo('周杰伦', 1, 1);
          const probe: EngineProbeResult = { ok: r.length > 0, ms: Date.now() - t0 };
          return probe;
        })(),
        (async (): Promise<EngineProbeResult> => {
          const t0 = Date.now();
          const r = await this.searchKugou('周杰伦', 1, 1);
          const probe: EngineProbeResult = { ok: r.length > 0, ms: Date.now() - t0 };
          return probe;
        })(),
        (async (): Promise<EngineProbeResult> => {
          const t0 = Date.now();
          const r = await this.searchQQ('周杰伦', 1, 1);
          const probe: EngineProbeResult = { ok: r.length > 0, ms: Date.now() - t0 };
          return probe;
        })()
      ]);

      const kwRes = probes[0];
      const kgRes = probes[1];
      const qqRes = probes[2];

      if (kwRes.ok) kwLatency = kwRes.ms;
      if (kgRes.ok) kgLatency = kgRes.ms;
      if (qqRes.ok) qqLatency = qqRes.ms;

      const anyOk = kwRes.ok || kgRes.ok || qqRes.ok;
      if (anyOk) {
        const msgs: string[] = [];
        if (kwLatency > 0) msgs.push(`酷我 ${kwLatency}ms`);
        if (qqLatency > 0) msgs.push(`QQ ${qqLatency}ms`);
        if (kgLatency > 0) msgs.push(`酷狗 ${kgLatency}ms`);

        const result: EngineTestResult = {
          success: true,
          message: `原生多源引擎就绪 (${msgs.join(' · ')})`,
          kuwoLatencyMs: kwLatency,
          kugouLatencyMs: kgLatency,
          qqLatencyMs: qqLatency
        };
        return result;
      }

      const failResult: EngineTestResult = {
        success: false,
        message: '各大音源接口暂时无响应，请检查设备网络'
      };
      return failResult;
    } catch (e) {
      const errResult: EngineTestResult = {
        success: false,
        message: '测速异常，请检查网络连接'
      };
      return errResult;
    }
  }
}
