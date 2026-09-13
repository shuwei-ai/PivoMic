import { describe, it, expect } from '@ohos/hypium';
import { KaraokeAudioEngine, NativeKaraokePort } from '../main/ets/audio/KaraokeAudioEngine';
import { NativeEngineSnapshot } from '../main/ets/audio/KaraokeSessionModels';

class FakePort implements NativeKaraokePort {
  snapshot: NativeEngineSnapshot = { state: 'Singing', positionMs: 42, durationMs: 99,
    microphonePeak: 0.5, latencyMs: 12, underrunCount: 3, fastMode: true,
    aecSupported: true, audioRoute: 0, accompanimentPitchShift: 0,
    pitchCorrectionEnabled: false, pitchCorrectionStrength: 0.5,
    isRecording: false, recordedDurationMs: 0,
    errorCode: 0, errorMessage: '' };
  accompaniment: number = -1; vocal: number = -1; reverb: number = -1; releases: number = 0; calls: number = 0; succeeds: boolean = true;
  prepare(fd: number, offset: number, size: number, durationMs: number): boolean { this.calls++; return fd >= 0 && offset >= 0 && size > 0 && durationMs >= 0; }
  start(): boolean { this.calls++; return this.succeeds; } pause(): boolean { this.calls++; return this.succeeds; }
  seek(positionMs: number): boolean { this.calls++; return positionMs >= 0; } stop(): boolean { this.calls++; return true; }
  release(): void { this.calls++; this.releases++; }
  setSafeOutputConnected(value: boolean): void { this.calls++; }
  setAccompanimentGain(value: number): void { this.calls++; this.accompaniment = value; }
  setVocalGain(value: number): void { this.calls++; this.vocal = value; }
  setReverbMix(value: number): void { this.calls++; this.reverb = value; }
  getSnapshot(): NativeEngineSnapshot { this.calls++; return this.snapshot; }
}

export default function karaokeAudioEngineTest() {
  describe('karaokeAudioEngine', () => {
    it('mapsNativeSnapshotExactly', 0, () => {
      const engine = new KaraokeAudioEngine(new FakePort()); const value = engine.getSnapshot();
      expect(value.state).assertEqual('singing'); expect(value.positionMs).assertEqual(42);
      expect(value.microphonePeak).assertEqual(0.5); expect(value.latencyMs).assertEqual(12);
      expect(value.fastMode).assertTrue(); expect(value.aecSupported).assertTrue();
      expect(value.underrunCount).assertEqual(3); expect(value.errorMessage).assertEqual('');
      expect(value.durationMs).assertEqual(99); expect(value.errorCode).assertEqual(0);
    });
    it('clampsGainsAndReleasesOnce', 0, () => {
      const port = new FakePort(); const engine = new KaraokeAudioEngine(port);
      engine.setAccompanimentGain(-2); engine.setVocalGain(5); engine.setReverbMix(0.4); engine.release(); engine.release();
      expect(port.accompaniment).assertEqual(0); expect(port.vocal).assertEqual(2); expect(port.reverb).assertEqual(0.4); expect(port.releases).assertEqual(1);
    });
    it('throwsWhenNativeControlFails', 0, () => {
      const port = new FakePort(); port.succeeds = false; let threw: boolean = false;
      try { new KaraokeAudioEngine(port).start(); } catch (error) { threw = true; }
      expect(threw).assertTrue();
    });
    it('rejectsNonFiniteGainWithoutCallingNative', 0, () => {
      const port = new FakePort(); let threw: boolean = false;
      try { new KaraokeAudioEngine(port).setVocalGain(Number.NaN); } catch (error) { threw = true; }
      expect(threw).assertTrue(); expect(port.vocal).assertEqual(-1);
    });
    it('releaseAllowsFreshSystemLease', 0, () => {
      const port = new FakePort(); let current: KaraokeAudioEngine | null = null;
      const getEngine = (): KaraokeAudioEngine => { if (current === null) { current = new KaraokeAudioEngine(port, () => { current = null; }); } return current; };
      const first = getEngine(); expect(getEngine() === first).assertTrue(); first.release();
      expect(getEngine() === first).assertFalse(); expect(port.releases).assertEqual(1);
    });
    it('releasedLeaseCannotTouchSuccessorPort', 0, () => {
      const port = new FakePort(); let current: KaraokeAudioEngine | null = null;
      const getEngine = (): KaraokeAudioEngine => { if (current === null) { current = new KaraokeAudioEngine(port, () => { current = null; }); } return current; };
      const stale = getEngine(); stale.release(); const successor = getEngine(); const calls = port.calls;
      try { stale.prepare(1, 0, 1, 1); } catch (error) {} try { stale.start(); } catch (error) {}
      try { stale.pause(); } catch (error) {} try { stale.seek(0); } catch (error) {} try { stale.stop(); } catch (error) {}
      try { stale.setAccompanimentGain(0.5); } catch (error) {} try { stale.setVocalGain(0.5); } catch (error) {}
      try { stale.setReverbMix(0.5); } catch (error) {} try { stale.getSnapshot(); } catch (error) {}
      expect(port.calls).assertEqual(calls); expect(successor === stale).assertFalse();
    });
    it('mapsNativeFailureToError', 0, () => {
      const port = new FakePort(); port.snapshot.state = 'Error'; port.snapshot.errorCode = 4; port.snapshot.errorMessage = 'decoder';
      expect(new KaraokeAudioEngine(port).getSnapshot().state).assertEqual('error');
    });
    it('mapsInterruptFieldsCorrectly', 0, () => {
      const port = new FakePort();
      port.snapshot.resumeRequested = true;
      port.snapshot.isDucked = true;
      const engine = new KaraokeAudioEngine(port);
      const snap = engine.getSnapshot();
      expect(snap.resumeRequested).assertTrue();
      expect(snap.isDucked).assertTrue();
    });
  });
}
