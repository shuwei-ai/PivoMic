// Public-domain test signal generated at runtime: 3 seconds, 8 kHz, mono S16 WAV.
// Keeping the synthesis here makes the fixture small, deterministic and licence-free.
export function buildKaraokeWavFixture(): ArrayBuffer {
  const sampleRate: number = 8000;
  const sampleCount: number = sampleRate * 3;
  const dataBytes: number = sampleCount * 2;
  const bytes = new Uint8Array(44 + dataBytes);
  writeAscii(bytes, 0, 'RIFF'); writeU32(bytes, 4, 36 + dataBytes); writeAscii(bytes, 8, 'WAVE');
  writeAscii(bytes, 12, 'fmt '); writeU32(bytes, 16, 16); writeU16(bytes, 20, 1); writeU16(bytes, 22, 1);
  writeU32(bytes, 24, sampleRate); writeU32(bytes, 28, sampleRate * 2); writeU16(bytes, 32, 2); writeU16(bytes, 34, 16);
  writeAscii(bytes, 36, 'data'); writeU32(bytes, 40, dataBytes);
  for (let index: number = 0; index < sampleCount; index++) {
    const value: number = Math.round(Math.sin(2 * Math.PI * 440 * index / sampleRate) * 4096);
    writeU16(bytes, 44 + index * 2, value & 0xffff);
  }
  return bytes.buffer;
}

function writeAscii(target: Uint8Array, offset: number, value: string): void {
  for (let index: number = 0; index < value.length; index++) target[offset + index] = value.charCodeAt(index);
}
function writeU16(target: Uint8Array, offset: number, value: number): void {
  target[offset] = value & 0xff; target[offset + 1] = (value >>> 8) & 0xff;
}
function writeU32(target: Uint8Array, offset: number, value: number): void {
  writeU16(target, offset, value & 0xffff); writeU16(target, offset + 2, (value >>> 16) & 0xffff);
}
