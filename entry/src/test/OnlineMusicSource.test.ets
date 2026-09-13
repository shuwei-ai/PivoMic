import { describe, it, expect } from '@ohos/hypium';
import { responseText, SEARCH_SOURCE_OPTIONS, ALL_SEARCH_SOURCES, OnlineMusicSource } from '../main/ets/services/OnlineMusicSource';
import { NativeMusicEngine } from '../main/ets/services/NativeMusicEngine';

export default function onlineMusicSourceTest() {
  describe('onlineMusicSource', () => {
    it('decodesBinaryLyricResponseAsUtf8', 0, () => {
      const bytes = new Uint8Array([91, 48, 48, 58, 48, 49, 46, 48, 48, 48, 93, 72, 101, 108, 108, 111]);
      expect(responseText(bytes)).assertEqual('[00:01.000]Hello');
    });

    it('containsAllExpectedSearchSourcesWithOptions', 0, () => {
      expect(SEARCH_SOURCE_OPTIONS.length).assertEqual(6);
      expect(SEARCH_SOURCE_OPTIONS[0].id).assertEqual('all');
      expect(ALL_SEARCH_SOURCES.length).assertEqual(5);
      expect(ALL_SEARCH_SOURCES.includes('kuwo')).assertTrue();
      expect(ALL_SEARCH_SOURCES.includes('qq')).assertTrue();
      expect(ALL_SEARCH_SOURCES.includes('kugou')).assertTrue();
      expect(ALL_SEARCH_SOURCES.includes('netease')).assertTrue();
      expect(ALL_SEARCH_SOURCES.includes('soda')).assertTrue();
    });

    it('providesNativeMusicEngineSingleton', 0, () => {
      const engine1 = NativeMusicEngine.getInstance();
      const engine2 = NativeMusicEngine.getInstance();
      expect(engine1 !== undefined).assertTrue();
      expect(engine1 === engine2).assertTrue();
    });

    it('instantiatesOnlineMusicSourceFacade', 0, () => {
      const source = new OnlineMusicSource();
      expect(source !== undefined).assertTrue();
    });
  });
}
