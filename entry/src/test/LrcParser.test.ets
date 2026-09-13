import { describe, it, expect } from '@ohos/hypium';
import { findActiveLyricIndex, parseLrc } from '../main/ets/services/LrcParser';

export default function lrcParserTest() {
  describe('lrcParser', () => {
    it('parsesMetadataOffsetAndDuplicateTimestamps', 0, () => {
      const result = parseLrc('[ti:Demo]\r\n[ar:PivoMic]\r\n[offset:100]\r\n[00:01.00][00:02.000]Hello');
      expect(result.title).assertEqual('Demo');
      expect(result.artist).assertEqual('PivoMic');
      expect(result.lines.length).assertEqual(2);
      expect(result.lines[0].timeMs).assertEqual(1100);
      expect(result.lines[1].timeMs).assertEqual(2100);
      expect(result.lines[0].text).assertEqual('Hello');
    });

    it('parsesEnhancedWordTimestamps', 0, () => {
      const result = parseLrc('[00:01.00]<00:01.00>Hel<00:01.40>lo');
      expect(result.lines[0].text).assertEqual('Hello');
      expect(result.lines[0].words.length).assertEqual(2);
      expect(result.lines[0].words[0].timeMs).assertEqual(1000);
      expect(result.lines[0].words[1].timeMs).assertEqual(1400);
    });

    it('ignoresInvalidLinesAndFindsActiveLine', 0, () => {
      const result = parseLrc('plain text\n[bad]ignored\n[00:01.00]One\n[00:03.00]Three');
      expect(result.lines.length).assertEqual(2);
      expect(findActiveLyricIndex(result.lines, 999)).assertEqual(-1);
      expect(findActiveLyricIndex(result.lines, 2000)).assertEqual(0);
      expect(findActiveLyricIndex(result.lines, 5000)).assertEqual(1);
    });
  });
}
