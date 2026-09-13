import { Song } from '../domain/MusicModels';
import { AccompanimentAsset, copyAccompanimentSong } from '../domain/AccompanimentModels';
import { validAccompanimentWav } from '../services/AccompanimentRepository';

export function resolvePlaybackSong(song: Song, asset?: AccompanimentAsset): Song {
  if (!asset) return song;
  if (!validAccompanimentWav(asset.path)) throw new Error('AI 伴奏文件不可用，请重新生成或选择原曲');
  const result = copyAccompanimentSong(song);
  result.uri = asset.path; result.streamUrl = undefined; result.format = 'WAV';
  result.durationMs = Math.round(asset.frameCount * 1000 / asset.sampleRate);
  return result;
}
