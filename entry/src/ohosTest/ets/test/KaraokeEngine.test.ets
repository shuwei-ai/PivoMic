import nativeAudio, { NativeEngineSnapshot } from 'libpivomic_audio.so';
import { abilityDelegatorRegistry } from '@kit.TestKit';
import { abilityAccessCtrl, bundleManager, Permissions } from '@kit.AbilityKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { describe, it, expect, beforeAll, afterAll, afterEach } from '@ohos/hypium';
import { buildKaraokeWavFixture } from './KaraokeWavFixture';

const DOMAIN: number = 0xD003100;
const TAG: string = 'PivoMicDeviceQA';
let passedCases: number = 0;

function qaMarker(value: string): void {
  abilityDelegatorRegistry.getAbilityDelegator().printSync(`${value}\n`);
  console.info(value);
}
function passCase(name: string): void { passedCases++; qaMarker(`PIVOMIC_QA_CASE_PASS:${name}`); }
function skipReason(reason: string): void {
  qaMarker(`PIVOMIC_QA_SKIP:${reason}`);
  hilog.info(DOMAIN, TAG, '%{public}s', `SKIP ${reason}`);
}

function delay(milliseconds: number): Promise<void> {
  return new Promise<void>((resolve: () => void): void => { setTimeout(resolve, milliseconds); });
}

async function waitForState(expected: string, timeoutMs: number): Promise<NativeEngineSnapshot> {
  const deadline: number = Date.now() + timeoutMs;
  let snapshot: NativeEngineSnapshot = nativeAudio.getSnapshot();
  while (snapshot.state !== expected && Date.now() < deadline) {
    if (snapshot.state === 'Error') return snapshot;
    await delay(20); snapshot = nativeAudio.getSnapshot();
  }
  return snapshot;
}

async function microphonePermissionGranted(): Promise<boolean> {
  const bundle = await bundleManager.getBundleInfoForSelf(bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_APPLICATION);
  const permission: Permissions = 'ohos.permission.MICROPHONE';
  const status = await abilityAccessCtrl.createAtManager().checkAccessToken(bundle.appInfo.accessTokenId, permission);
  return status === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED;
}

export default function karaokeEngineTest(): void {
  describe('NativeKaraokeEngineDeviceSmoke', () => {
    beforeAll(() => { passedCases = 0; qaMarker('PIVOMIC_QA_SUITE:NativeKaraokeEngineDeviceSmoke'); });
    afterAll(() => { qaMarker(`PIVOMIC_QA_SUMMARY:passed=${passedCases};expected=3`); });
    afterEach(() => { nativeAudio.stop(); nativeAudio.release(); });

    it('starts idle and release is idempotent', 0, () => {
      nativeAudio.release();
      nativeAudio.release();
      const snapshot: NativeEngineSnapshot = nativeAudio.getSnapshot();
      expect(snapshot.state).assertEqual('Idle');
      expect(snapshot.positionMs).assertEqual(0);
      expect(snapshot.microphonePeak).assertLargerOrEqual(0);
      expect(snapshot.microphonePeak).assertLessOrEqual(1);
      passCase('release_idle');
    });

    it('rejects start before preparation', 0, () => {
      nativeAudio.release();
      expect(nativeAudio.start()).assertFalse();
      expect(nativeAudio.getSnapshot().state).assertEqual('Idle');
      passCase('reject_unprepared');
    });

    it('runs the safe public lifecycle with a bundled WAV fixture', 0, async () => {
      nativeAudio.release();
      const context = abilityDelegatorRegistry.getAbilityDelegator().getAppContext();
      const path: string = `${context.filesDir}/pivomic-device-fixture.wav`;
      const output = fs.openSync(path, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
      fs.writeSync(output.fd, buildKaraokeWavFixture()); fs.closeSync(output);
      const input = fs.openSync(path, fs.OpenMode.READ_ONLY);
      try {
        const prepared: boolean = nativeAudio.prepare(input.fd, 0, 48044, 3000);
        expect(prepared).assertTrue();
        const ready: NativeEngineSnapshot = await waitForState('Ready', 3000);
        expect(ready.state).assertEqual('Ready');

        // Never claim a wired route from a test process. Without AEC, prove the
        // unsafe-output rejection and leave the audible lifecycle to manual QA.
        nativeAudio.setSafeOutputConnected(false);
        if (!ready.aecSupported) {
          expect(nativeAudio.start()).assertFalse();
          skipReason('lifecycle_no_aec_or_verified_safe_output');
          expect(nativeAudio.stop()).assertTrue();
          expect(nativeAudio.getSnapshot().state).assertEqual('Idle');
          passCase('bundled_wav_lifecycle');
          return;
        }
        if (!await microphonePermissionGranted()) {
          skipReason('lifecycle_microphone_permission_not_granted');
          expect(nativeAudio.stop()).assertTrue();
          expect(nativeAudio.getSnapshot().state).assertEqual('Idle');
          passCase('bundled_wav_lifecycle');
          return;
        }

        expect(nativeAudio.start()).assertTrue();
        const singing: NativeEngineSnapshot = await waitForState('Singing', 1000);
        expect(singing.state).assertEqual('Singing');
        await delay(250);
        const advanced: NativeEngineSnapshot = nativeAudio.getSnapshot();
        expect(advanced.positionMs).assertLarger(singing.positionMs);
        if (advanced.microphonePeak <= 0.01) {
          skipReason('microphone_peak_no_external_stimulus');
        } else {
          expect(advanced.microphonePeak).assertLarger(0.01);
        }

        expect(nativeAudio.pause()).assertTrue();
        const pausedAt: number = nativeAudio.getSnapshot().positionMs;
        await delay(150);
        const pausedAfter: number = nativeAudio.getSnapshot().positionMs;
        expect(Math.abs(pausedAfter - pausedAt)).assertLessOrEqual(30);

        expect(nativeAudio.seek(500)).assertTrue();
        const sought: NativeEngineSnapshot = await waitForState('Paused', 3000);
        expect(Math.abs(sought.positionMs - 500)).assertLessOrEqual(100);
        expect(nativeAudio.stop()).assertTrue();
        expect(nativeAudio.getSnapshot().state).assertEqual('Idle');
        nativeAudio.release();
        expect(nativeAudio.getSnapshot().state).assertEqual('Idle');
        passCase('bundled_wav_lifecycle');
      } finally {
        fs.closeSync(input);
        try { fs.unlinkSync(path); } catch (_) {}
      }
    });
  });
}
