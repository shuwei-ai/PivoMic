import { abilityDelegatorRegistry } from '@kit.TestKit';
import { describe, it, expect } from '@ohos/hypium';
import { fileIo } from '@kit.CoreFileKit';
import { AccompanimentRepository } from '../../../main/ets/services/AccompanimentRepository';
import { AccompanimentAsset, SEPARATION_MODEL_ID, SEPARATION_PIPELINE_VERSION } from '../../../main/ets/domain/AccompanimentModels';
import { MusicSourceKind } from '../../../main/ets/domain/MusicModels';

function write(path: string, data: string | ArrayBuffer): void {
  const file = fileIo.openSync(path, fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC);
  try { fileIo.writeSync(file.fd, data); } finally { fileIo.closeSync(file.fd); }
}
export default function accompanimentRepositoryTest(): void {
  describe('AccompanimentRepositoryDevice', (): void => {
    it('recovers_corrupt_index_and_does_not_resurrect_deleted_asset', 0, (): void => {
      const root = `${abilityDelegatorRegistry.getAbilityDelegator().getAppContext().cacheDir}/repository-test-${Date.now()}`;
      const repository = new AccompanimentRepository(); repository.init(root);
      const temporary = `${repository.directory}/fixture.wav.tmp`;
      const header = new Uint32Array([0x46464952, 40, 0x45564157, 0x20746d66, 16, 0x00020001, 44100, 176400, 0x00100004, 0x61746164, 4, 0]);
      write(temporary, header.buffer);
      const asset: AccompanimentAsset = { id: 'fixture', song: { id: 'fixture', title: '测试', artist: '测试', uri: '/fixture.wav',
        durationMs: 1, format: 'WAV', source: MusicSourceKind.LOCAL }, sourceIdentity: 'local:/fixture.wav:48:1',
        sourceHash: 'test', modelId: SEPARATION_MODEL_ID, pipelineVersion: SEPARATION_PIPELINE_VERSION,
        path: `${repository.directory}/fixture.wav`, createdAt: Date.now(), sampleRate: 44100, frameCount: 1 };
      repository.publish(asset, temporary);
      write(`${repository.directory}/index.json`, '{broken');
      const recovered = new AccompanimentRepository(); recovered.init(root);
      expect(recovered.list().length).assertEqual(1);
      expect(recovered.list()[0].id).assertEqual('fixture');
      recovered.delete('fixture');
      write(`${repository.directory}/index.json`, '{broken');
      const deleted = new AccompanimentRepository(); deleted.init(root);
      expect(deleted.list().length).assertEqual(0);
      write(`${repository.directory}/index.json`, '[null, {}, 7]');
      const malformed = new AccompanimentRepository(); malformed.init(root);
      expect(malformed.list().length).assertEqual(0);
      fileIo.rmdirSync(root);
    });
  });
}
