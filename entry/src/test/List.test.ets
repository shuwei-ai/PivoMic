import accompanimentModelsTest from './AccompanimentModels.test';
import localUnitTest from './LocalUnit.test';
import lrcParserTest from './LrcParser.test';
import musicSourceTest from './MusicSource.test';
import mockAudioEngineTest from './MockAudioEngine.test';
import onlineMusicSourceTest from './OnlineMusicSource.test';
import karaokeAudioEngineTest from './KaraokeAudioEngine.test';
import karaokePlatformServicesTest from './KaraokePlatformServices.test';
import pivoMicStoreTest from './PivoMicStore.test';

export default function testsuite() {
  accompanimentModelsTest();
  localUnitTest();
  lrcParserTest();
  musicSourceTest();
  mockAudioEngineTest();
  onlineMusicSourceTest();
  karaokeAudioEngineTest();
  karaokePlatformServicesTest();
  pivoMicStoreTest();
}
