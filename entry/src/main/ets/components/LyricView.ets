import { LyricLine, LyricWord, PlaybackState } from '../domain/MusicModels';
import { PivoTheme } from '../theme/PivoTheme';

@Component({ freezeWhenInactive: true })
export struct LyricView {
  @Prop @Watch('onLinesChanged') lines: LyricLine[] = [];
  @Prop @Watch('onActiveIndexChanged') activeIndex: number = -1;
  @Prop positionMs: number = 0;
  @Prop microphonePeak: number = 0;
  @Prop state: PlaybackState = PlaybackState.IDLE;
  @Prop largeDisplay: boolean = false;
  onSeek: (timeMs: number) => void = (_timeMs: number): void => {};

  private scroller: Scroller = new Scroller();

  // User manual scroll interaction detection
  private isUserInteracting: boolean = false;
  private autoScrollResumeTimer: number = -1;

  // Harmonic weights for 18-band spectrum bars
  private readonly spectrumWeights: number[] = [
    0.45, 0.70, 0.95, 1.15, 1.35, 1.50, 1.40, 1.25, 1.10, 1.20, 1.45, 1.30, 1.05, 0.85, 0.65, 0.50, 0.40, 0.35
  ];

  aboutToAppear(): void {
    if (this.activeIndex >= 0 && this.lines.length > 0) {
      setTimeout(() => {
        this.scrollToActive(false);
      }, 150);
    }
  }

  aboutToDisappear(): void {
    if (this.autoScrollResumeTimer >= 0) {
      clearTimeout(this.autoScrollResumeTimer);
      this.autoScrollResumeTimer = -1;
    }
  }

  onActiveIndexChanged(): void {
    // If the user is currently scrolling/browsing, do not interrupt their touch!
    if (!this.isUserInteracting) {
      this.scrollToActive(true);
    }
  }

  onLinesChanged(): void {
    if (this.lines.length > 0) {
      setTimeout(() => {
        this.scrollToActive(false);
      }, 150);
    }
  }

  private scrollToActive(smooth: boolean): void {
    if (this.activeIndex >= 0 && this.activeIndex < this.lines.length) {
      this.scroller.scrollToIndex(this.activeIndex, smooth, ScrollAlign.CENTER);
    }
  }

  private markUserInteraction(): void {
    this.isUserInteracting = true;
    if (this.autoScrollResumeTimer >= 0) {
      clearTimeout(this.autoScrollResumeTimer);
    }
    // After 3 seconds of user inactivity, resume auto-scrolling to active lyric
    this.autoScrollResumeTimer = setTimeout(() => {
      this.isUserInteracting = false;
      this.scrollToActive(true);
    }, 3000);
  }

  private barHeight(index: number): number {
    const isPlaying = this.state === PlaybackState.PLAYING;
    if (!isPlaying) {
      return 4;
    }
    const weight = this.spectrumWeights[index % this.spectrumWeights.length];
    const wave = Math.sin((this.positionMs / 180) + (index * 0.45)) * 0.4 + 0.6;
    const peakBoost = Math.min(1.0, this.microphonePeak * 3.2);
    const dynamicVal = 6 + (peakBoost * 30 * weight) + (wave * 10 * weight);
    const maxH = this.largeDisplay ? 56 : 42;
    return Math.max(4, Math.min(maxH, dynamicVal));
  }

  private barColor(index: number): string {
    const ratio = index / 18;
    if (ratio < 0.35) return PivoTheme.primary;
    if (ratio < 0.70) return PivoTheme.accent;
    return PivoTheme.rose;
  }

  @Builder
  spectrumVisualizer() {
    Row({ space: this.largeDisplay ? 6 : 4 }) {
      ForEach(this.spectrumWeights, (_weight: number, index: number) => {
        Row()
          .width(this.largeDisplay ? 5 : 3.5)
          .height(this.barHeight(index))
          .borderRadius(2)
          .backgroundColor(this.barColor(index))
      })
    }
    .width('100%')
    .height(this.largeDisplay ? 58 : 44)
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Bottom)
    .padding({ bottom: 4 })
    .opacity(this.state === PlaybackState.PLAYING ? 0.85 : 0.25)
  }

  @Builder
  ambientGlow() {
    Stack() {
      Row()
        .width(this.largeDisplay ? 360 : 240)
        .height(this.largeDisplay ? 360 : 240)
        .borderRadius(this.largeDisplay ? 180 : 120)
        .backgroundColor(PivoTheme.atmospherePurpleGlow)
        .position({ x: -30, y: 10 })

      Row()
        .width(this.largeDisplay ? 360 : 240)
        .height(this.largeDisplay ? 360 : 240)
        .borderRadius(this.largeDisplay ? 180 : 120)
        .backgroundColor(PivoTheme.accentGlow)
        .position({ x: '55%', y: '35%' })
    }
    .width('100%')
    .height('100%')
    .hitTestBehavior(HitTestMode.None)
  }

  private activeFontSize(): number {
    return this.largeDisplay ? 30 : 22;
  }

  private adjacentFontSize(distance: number): number {
    if (this.largeDisplay) {
      return distance === 1 ? 20 : (distance === 2 ? 16 : 14);
    }
    return distance === 1 ? 16 : (distance === 2 ? 14 : 13);
  }

  @Builder
  enhancedLine(line: LyricLine, active: boolean, distance: number) {
    Row() {
      ForEach(line.words, (word: LyricWord) => {
        Text(word.text)
          .fontSize(active ? this.activeFontSize() : this.adjacentFontSize(distance))
          .fontWeight(active ? FontWeight.Bolder : (distance <= 1 ? FontWeight.Medium : FontWeight.Normal))
          .fontColor(active && this.positionMs >= word.timeMs ? PivoTheme.primary : (active ? PivoTheme.text : (distance === 1 ? PivoTheme.textSecondary : (distance === 2 ? PivoTheme.textMuted : PivoTheme.textFaint))))
          .opacity(active ? 1.0 : (distance === 1 ? 0.85 : (distance === 2 ? 0.60 : 0.35)))
      })
    }
    .justifyContent(FlexAlign.Center)
    .width('100%')
    .padding({
      top: active ? (this.largeDisplay ? 12 : 8) : (distance === 1 ? 6 : 4),
      bottom: active ? (this.largeDisplay ? 12 : 8) : (distance === 1 ? 6 : 4),
      left: 16,
      right: 16
    })
    .scale(active ? { x: 1.04, y: 1.04 } : { x: 1.0, y: 1.0 })
  }

  private hasLyrics(): boolean {
    return this.lines.length > 0 && this.lines.some((line: LyricLine) => line.text.trim().length > 0 || line.words.length > 0);
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      // 1. Audio-reactive ambient aurora glow
      this.ambientGlow()

      // 2. Main Lyrics View or Ambient Visualization
      Column({ space: 4 }) {
        if (!this.hasLyrics()) {
          // Pure ambient visualization stage when no lyrics are available
          Column({ space: 16 }) {
            Stack({ alignContent: Alignment.Center }) {
              Row()
                .width(this.largeDisplay ? 120 : 90)
                .height(this.largeDisplay ? 120 : 90)
                .borderRadius(this.largeDisplay ? 60 : 45)
                .backgroundColor(PivoTheme.atmospherePurpleGlow)
                .border({ width: 2, color: PivoTheme.accentGlow })
                .shadow({ radius: 30, color: PivoTheme.primaryGlow })

              Text(this.state === PlaybackState.PLAYING ? '🎵' : '🎤')
                .fontSize(this.largeDisplay ? 46 : 36)
            }

            Text(this.state === PlaybackState.PLAYING ? '伴奏演奏中 · 随心唱' : '等待演唱 / 伴奏就绪')
              .fontSize(this.largeDisplay ? 22 : 17)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.state === PlaybackState.PLAYING ? PivoTheme.accent : PivoTheme.text)
              .letterSpacing(0.5)

            if (this.state !== PlaybackState.PLAYING) {
              Text('歌词将随伴奏播放自动置中多行滚动')
                .fontSize(this.largeDisplay ? 14 : 13)
                .fontColor(PivoTheme.textMuted)
            }
          }
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else {
          List({ space: this.largeDisplay ? 10 : 7, scroller: this.scroller }) {
            ForEach(this.lines, (line: LyricLine, index: number) => {
              if (line.text.trim().length > 0 || line.words.length > 0) {
                ListItem() {
                  Column() {
                    if (line.words.length > 0) {
                      this.enhancedLine(line, index === this.activeIndex, Math.abs(index - this.activeIndex))
                    } else {
                      Row() {
                        Text(line.text)
                          .width('100%')
                          .textAlign(TextAlign.Center)
                          .fontSize(index === this.activeIndex ? this.activeFontSize() : this.adjacentFontSize(Math.abs(index - this.activeIndex)))
                          .fontWeight(index === this.activeIndex ? FontWeight.Bold : (Math.abs(index - this.activeIndex) <= 1 ? FontWeight.Medium : FontWeight.Normal))
                          .fontColor(index === this.activeIndex ? PivoTheme.primary : (Math.abs(index - this.activeIndex) === 1 ? PivoTheme.textSecondary : (Math.abs(index - this.activeIndex) === 2 ? PivoTheme.textMuted : PivoTheme.textFaint)))
                          .opacity(index === this.activeIndex ? 1.0 : (Math.abs(index - this.activeIndex) === 1 ? 0.85 : (Math.abs(index - this.activeIndex) === 2 ? 0.60 : 0.35)))
                      }
                      .padding({
                        top: index === this.activeIndex ? (this.largeDisplay ? 12 : 8) : (Math.abs(index - this.activeIndex) === 1 ? 6 : 4),
                        bottom: index === this.activeIndex ? (this.largeDisplay ? 12 : 8) : (Math.abs(index - this.activeIndex) === 1 ? 6 : 4),
                        left: 16,
                        right: 16
                      })
                      .scale(index === this.activeIndex ? { x: 1.04, y: 1.04 } : { x: 1.0, y: 1.0 })
                    }
                  }
                  .width('100%')
                  .onClick(() => {
                    this.isUserInteracting = false;
                    this.onSeek(line.timeMs);
                    this.scrollToActive(true);
                  })
                }
                .clip(true)
              }
            }, (line: LyricLine, index: number) => `${this.lines.length}_${line.timeMs}_${index}`)
          }
          .layoutWeight(1)
          .width('100%')
          .padding({ top: this.largeDisplay ? 52 : 40, bottom: this.largeDisplay ? 52 : 40, left: 8, right: 8 })
          .scrollBar(BarState.Off)
          .edgeEffect(EdgeEffect.Spring)
          .clip(true)
          .onScrollStart(() => {
            this.markUserInteraction();
          })
          .onScrollStop(() => {
            this.markUserInteraction();
          })
          .onTouch((event: TouchEvent) => {
            if (event.type === TouchType.Down || event.type === TouchType.Move) {
              this.markUserInteraction();
            }
          })
        }

        // 3. Audio Spectrum Equalizer Wave at bottom
        this.spectrumVisualizer()
      }
      .width('100%')
      .height('100%')
      .padding({ left: 14, right: 14, top: 10, bottom: 4 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(PivoTheme.surfaceSolid)
    .borderRadius(26)
    .border({ width: 1, color: PivoTheme.border })
    .clip(true)
  }
}
