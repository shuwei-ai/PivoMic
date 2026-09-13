import accompanimentRepositoryTest from './AccompanimentRepository.test';
import separationTest from './Separation.test';
import abilityTest from './Ability.test';
import karaokeEngineTest from './KaraokeEngine.test';

export default function testsuite() {
  separationTest();
  accompanimentRepositoryTest();
  abilityTest();
  karaokeEngineTest();
}
