import { describe, it, expect } from '@ohos/hypium';
import { Song, MusicSourceKind, PlaybackState } from '../main/ets/domain/MusicModels';
import { MockAudioEngine } from '../main/ets/audio/MockAudioEngine';

export default function mockAudioEngineTest() {
  describe('mockAudioEngine', () => {
    it('supportsPlaybackControlsAndClampsValues', 0, () => {
      const song: Song = {
        id: 'song', title: 'Demo', artist: 'PivoMic', uri: 'demo://song',
        durationMs: 10000, format: 'MP3', source: MusicSourceKind.DEMO
      };
      const engine = new MockAudioEngine();
      engine.load(song);
      expect(engine.getSnapshot().state).assertEqual(PlaybackState.READY);
      engine.play();
      engine.tick(2500);
      expect(engine.getSnapshot().positionMs).assertEqual(2500);
      engine.seek(20000);
      expect(engine.getSnapshot().positionMs).assertEqual(10000);
      engine.setVolume(2);
      expect(engine.getSnapshot().volume).assertEqual(1);
      engine.setPitch(-10);
      expect(engine.getSnapshot().pitchSemitones).assertEqual(-6);
      engine.unload();
      expect(engine.getSnapshot().state).assertEqual(PlaybackState.IDLE);
    });
  });
}
