import nativeAudio from 'libpivomic_audio.so';
import { KaraokeAudioEngine, NativeKaraokePort } from './KaraokeAudioEngine';
const systemPort: NativeKaraokePort = nativeAudio;
let systemEngine: KaraokeAudioEngine | null = null;
export function getSystemKaraokeAudioEngine(): KaraokeAudioEngine {
  if (systemEngine === null) { systemEngine = new KaraokeAudioEngine(systemPort, () => { systemEngine = null; }); }
  return systemEngine;
}
