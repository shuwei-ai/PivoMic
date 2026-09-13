import { abilityDelegatorRegistry } from '@kit.TestKit';
import { describe, it, expect } from '@ohos/hypium';
import { fileIo } from '@kit.CoreFileKit';
import nativeSeparation from 'libpivomic_separation.so';
import { SeparationService } from '../../../main/ets/services/SeparationService';
import { MusicSourceKind, Song } from '../../../main/ets/domain/MusicModels';

export default function separationTest(): void {
  describe('SeparationDevice', (): void => {
    it('generates_verified_instrumental_and_rejects_corrupt_model', 0, async (): Promise<void> => {
      const delegator = abilityDelegatorRegistry.getAbilityDelegator();
      await delegator.startAbility({ bundleName: 'com.shuwei.pivomic', abilityName: 'EntryAbility' });
      await new Promise<void>((resolve: () => void): void => { setTimeout(resolve, 1500); });
      const ctx = (await delegator.getCurrentTopAbility()).context;
      delegator.printSync(`SEPARATION_CONTEXT:${ctx.filesDir}\n`);
      const service = new SeparationService(nativeSeparation); service.init(ctx.filesDir, ctx.cacheDir, ctx.resourceManager);
      const resources = ctx.createModuleContext('entry_test').resourceManager;
      for (const name of ['separation-fixture.wav']) {
        const path = `${ctx.filesDir}/${name}`;
        const raw = await resources.getRawFd(name);
        const out = fileIo.openSync(path, fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC);
        try {
          const buffer = new ArrayBuffer(262144); let copied = 0;
          while (copied < raw.length) {
            const length = Math.min(buffer.byteLength, raw.length - copied);
            const count = fileIo.readSync(raw.fd, buffer, { offset: raw.offset + copied, length: length });
            if (!count) throw new Error('Fixture read failed');
            fileIo.writeSync(out.fd, buffer, { length: count }); copied += count;
          }
        } finally { fileIo.closeSync(out.fd); await resources.closeRawFd(name); }
      }
      const song: Song = { id: 'uvr-official-fixture', title: 'UVR 测试片段', artist: '官方测试资源',
        uri: `${ctx.filesDir}/separation-fixture.wav`,
        durationMs: 26102, format: 'WAV', source: MusicSourceKind.LOCAL, provider: 'fixture', remoteId: 'qi-feng-le-zh' };
      let lastPhase = '';
      service.subscribe((snapshot): void => {
        if (snapshot.job.phase !== lastPhase) {
          lastPhase = snapshot.job.phase;
          abilityDelegatorRegistry.getAbilityDelegator().printSync(`SEPARATION_PHASE:${lastPhase}:timeMs=${Date.now()}:${snapshot.job.errorMessage}\n`);
        }
      });
      const start = Date.now(); await service.generate(song);
      const snap = service.getSnapshot();
      abilityDelegatorRegistry.getAbilityDelegator().printSync(`SEPARATION_RESULT:${snap.job.phase};elapsedMs=${Date.now()-start};error=${snap.job.errorMessage}\n`);
      expect(snap.job.phase).assertEqual('completed');
      const asset = service.resolveAsset(song); expect(asset !== undefined).assertTrue();
      if (!asset) return;
      expect(fileIo.statSync(asset.path).size).assertEqual(asset.frameCount * 4 + 44);
      expect(asset.sampleRate).assertEqual(44100);
      const pin = service.pinAsset(asset.id); let protectedFile = false;
      try { service.deleteAsset(asset.id); } catch (_) { protectedFile = true; }
      expect(protectedFile).assertTrue(); pin();
      abilityDelegatorRegistry.getAbilityDelegator().printSync(`SEPARATION_ASSET:${asset.path}\n`);
      const badPath = `${ctx.cacheDir}/bad-model.onnx`;
      const bad = fileIo.openSync(badPath, fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC);
      fileIo.writeSync(bad.fd, 'broken'); fileIo.closeSync(bad.fd);
      const input = fileIo.openSync(asset.path, fileIo.OpenMode.READ_ONLY);
      const job = nativeSeparation.startJob(input.fd,0,fileIo.statSync(input.fd).size,badPath,`${ctx.cacheDir}/bad-output.wav`);
      let result = nativeSeparation.getJobSnapshot(job);
      while(result.phase !== 'failed' && result.phase !== 'ready') {
        await new Promise<void>((resolve: () => void): void => { setTimeout(resolve,100); });
        result = nativeSeparation.getJobSnapshot(job);
      }
      expect(result.phase).assertEqual('failed'); nativeSeparation.releaseJob(job); fileIo.closeSync(input.fd);
      fileIo.unlinkSync(badPath);
      abilityDelegatorRegistry.getAbilityDelegator().printSync('SEPARATION_DEVICE_PASS\n');
    });
  });
}
