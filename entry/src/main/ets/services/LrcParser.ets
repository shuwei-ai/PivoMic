import { LyricDocument, LyricLine, LyricWord } from '../domain/MusicModels';

function timestampToMs(value: string): number {
  const parts = value.split(':');
  if (parts.length !== 2) {
    return -1;
  }
  const minutes = Number(parts[0]);
  const seconds = Number(parts[1]);
  if (!Number.isFinite(minutes) || !Number.isFinite(seconds)) {
    return -1;
  }
  return Math.round((minutes * 60 + seconds) * 1000);
}

function parseWords(content: string, offsetMs: number): LyricWord[] {
  const words: LyricWord[] = [];
  const matcher = /<([0-9]{1,3}:[0-9]{2}(?:\.[0-9]{1,3})?)>([^<]*)/g;
  let match: RegExpExecArray | null = matcher.exec(content);
  while (match !== null) {
    const timeMs = timestampToMs(match[1]);
    if (timeMs >= 0 && match[2].length > 0) {
      words.push({ timeMs: Math.max(0, timeMs + offsetMs), text: match[2] });
    }
    match = matcher.exec(content);
  }
  return words;
}

export function parseLrc(input: string): LyricDocument {
  const document: LyricDocument = {
    title: '', artist: '', album: '', by: '', offsetMs: 0, lines: []
  };
  const rows = input.replace(/\r\n/g, '\n').replace(/\r/g, '\n').split('\n');
  for (let index = 0; index < rows.length; index++) {
    const row = rows[index].trim();
    const metadata = /^\[(ti|ar|al|by|offset):([^\]]*)\]$/i.exec(row);
    if (metadata !== null) {
      const key = metadata[1].toLowerCase();
      const value = metadata[2].trim();
      if (key === 'ti') document.title = value;
      if (key === 'ar') document.artist = value;
      if (key === 'al') document.album = value;
      if (key === 'by') document.by = value;
      if (key === 'offset') {
        const parsedOffset = Number(value);
        document.offsetMs = Number.isFinite(parsedOffset) ? parsedOffset : 0;
      }
    }
  }

  for (let index = 0; index < rows.length; index++) {
    const row = rows[index].trim();
    const lineMatcher = /\[([0-9]{1,3}:[0-9]{2}(?:\.[0-9]{1,3})?)\]/g;
    const timestamps: number[] = [];
    let timeMatch: RegExpExecArray | null = lineMatcher.exec(row);
    let contentStart = 0;
    while (timeMatch !== null) {
      const timeMs = timestampToMs(timeMatch[1]);
      if (timeMs >= 0) timestamps.push(timeMs);
      contentStart = lineMatcher.lastIndex;
      timeMatch = lineMatcher.exec(row);
    }
    if (timestamps.length === 0) continue;
    const content = row.substring(contentStart);
    const words = parseWords(content, document.offsetMs);
    let text = '';
    if (words.length > 0) {
      for (let wordIndex = 0; wordIndex < words.length; wordIndex++) text += words[wordIndex].text;
    } else {
      text = content;
    }
    if (text.trim().length === 0 && words.length === 0) continue;
    for (let timestampIndex = 0; timestampIndex < timestamps.length; timestampIndex++) {
      const copiedWords: LyricWord[] = [];
      for (let wordIndex = 0; wordIndex < words.length; wordIndex++) {
        copiedWords.push({ timeMs: words[wordIndex].timeMs, text: words[wordIndex].text });
      }
      document.lines.push({
        timeMs: Math.max(0, timestamps[timestampIndex] + document.offsetMs), text: text, words: copiedWords
      });
    }
  }
  document.lines.sort((left: LyricLine, right: LyricLine): number => left.timeMs - right.timeMs);
  return document;
}

export function findActiveLyricIndex(lines: LyricLine[], positionMs: number): number {
  let low = 0;
  let high = lines.length - 1;
  let answer = -1;
  while (low <= high) {
    const middle = Math.floor((low + high) / 2);
    if (lines[middle].timeMs <= positionMs) {
      answer = middle;
      low = middle + 1;
    } else {
      high = middle - 1;
    }
  }
  return answer;
}

