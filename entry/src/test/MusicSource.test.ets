import { describe, it, expect } from '@ohos/hypium';
import { isSupportedAudioFile, songsFromUris } from '../main/ets/services/LocalMusicSource';

export default function musicSourceTest() {
  describe('musicSource', () => {
    it('filtersSupportedAudioExtensions', 0, () => {
      expect(isSupportedAudioFile('file:///Music/a.MP3')).assertTrue();
      expect(isSupportedAudioFile('file:///Music/a.flac')).assertTrue();
      expect(isSupportedAudioFile('file:///Music/a.wav')).assertTrue();
      expect(isSupportedAudioFile('file:///Music/cover.jpg')).assertFalse();
    });

    it('mapsUrisAndReportsRejectedFiles', 0, () => {
      const result = songsFromUris(['file:///Music/My%20Song.mp3', 'file:///Music/readme.txt']);
      expect(result.songs.length).assertEqual(1);
      expect(result.rejectedCount).assertEqual(1);
      expect(result.songs[0].title).assertEqual('My Song');
      expect(result.songs[0].format).assertEqual('MP3');
    });
  });
}
