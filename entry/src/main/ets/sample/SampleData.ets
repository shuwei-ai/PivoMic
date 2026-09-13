import { MusicSourceKind, Song } from '../domain/MusicModels';

const SUNRISE_LRC: string = `[ti:晨光练习曲]
[ar:PivoMic Demo]
[00:00.00]准备好，跟随节拍呼吸
[00:04.00]让清晨的光落在旋律里
[00:09.00]这一刻只为自己歌唱
[00:14.00]把每一句唱成喜欢的模样`;

const CITY_LRC: string = `[ti:城市夜航]
[ar:PivoMic Demo]
[00:00.00]<00:00.00>灯光<00:01.20>掠过<00:02.40>车窗
[00:04.00]<00:04.00>节拍<00:05.20>陪我<00:06.40>夜航
[00:08.00]<00:08.00>麦克风<00:09.60>点亮<00:10.80>心房
[00:12.00]<00:12.00>自由地<00:13.50>唱`;

export function demoSongs(): Song[] {
  return [
    {
      id: 'demo-sunrise', title: '晨光练习曲', artist: 'PivoMic Demo', uri: 'demo://sunrise',
      durationMs: 18000, format: 'WAV', source: MusicSourceKind.DEMO, lyricText: SUNRISE_LRC
    },
    {
      id: 'demo-city', title: '城市夜航', artist: 'PivoMic Demo', uri: 'demo://city',
      durationMs: 16000, format: 'WAV', source: MusicSourceKind.DEMO, lyricText: CITY_LRC
    },
    {
      id: 'demo-instrumental', title: '无词伴奏示例', artist: 'PivoMic Demo', uri: 'demo://instrumental',
      durationMs: 20000, format: 'WAV', source: MusicSourceKind.DEMO
    }
  ];
}
