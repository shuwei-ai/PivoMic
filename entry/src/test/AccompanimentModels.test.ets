import { describe, it, expect } from '@ohos/hypium';
import { Song, MusicSourceKind } from '../main/ets/domain/MusicModels';
import { AccompanimentAsset, accompanimentSourceIdentity, accompanimentMatches,
  SEPARATION_MODEL_ID, SEPARATION_PIPELINE_VERSION } from '../main/ets/domain/AccompanimentModels';

function song(id: string, provider: string): Song {
  return { id: id, title: '同名歌曲', artist: '歌手', uri: 'https://example.com/audio',
    durationMs: 1000, format: 'mp3', source: MusicSourceKind.ONLINE, provider: provider, remoteId: id };
}
function asset(source: Song): AccompanimentAsset {
  return { id: 'asset', song: source, sourceIdentity: accompanimentSourceIdentity(source), sourceHash: 'hash',
    modelId: SEPARATION_MODEL_ID, pipelineVersion: SEPARATION_PIPELINE_VERSION, path: '/asset.wav',
    createdAt: 1, sampleRate: 44100, frameCount: 44100 };
}
export default function accompanimentModelsTest(): void {
  describe('AccompanimentIdentity', (): void => {
    it('does_not_reuse_same_title_across_provider_or_track', 0, (): void => {
      const original = song('42', 'qq');
      expect(accompanimentMatches(asset(original), song('42', 'netease'))).assertFalse();
      expect(accompanimentMatches(asset(original), song('43', 'qq'))).assertFalse();
    });
    it('ignores_expiring_online_url_but_rejects_old_pipeline', 0, (): void => {
      const original = song('42', 'qq');
      const cached = asset(original);
      original.streamUrl = 'https://example.com/new-token';
      expect(accompanimentMatches(cached, original)).assertTrue();
      cached.pipelineVersion = 'old';
      expect(accompanimentMatches(cached, original)).assertFalse();
    });
    it('keeps_local_uri_identity_distinct', 0, (): void => {
      const original = song('42', ''); original.source = MusicSourceKind.LOCAL; original.uri = '/a.mp3';
      const cached = asset(original); cached.sourceIdentity += ':123:999';
      expect(accompanimentMatches(cached, original)).assertTrue();
      original.uri = '/b.mp3';
      expect(accompanimentMatches(cached, original)).assertFalse();
    });
  });
}
