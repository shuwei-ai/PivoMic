import { PlaybackState } from '../domain/MusicModels';
import { PivoTheme } from '../theme/PivoTheme';

@Component({ freezeWhenInactive: true })
export struct PlaybackControls {
  @Prop state: PlaybackState = PlaybackState.IDLE;
  @Prop positionMs: number = 0;
  @Prop durationMs: number = 0;
  @Prop bufferedPositionMs: number = 0;
  @Prop @Watch('onVolumePropChanged') volume: number = 0.8;
  @Prop actionEnabled: boolean = false;
  @Prop seekEnabled: boolean = false;
  @Prop stopEnabled: boolean = false;
  @State isDragging: boolean = false;
  @State dragPositionMs: number = 0;
  @State localVolume: number = 0.8;

  aboutToAppear(): void {
    this.localVolume = this.volume;
  }

  onVolumePropChanged(): void {
    this.localVolume = this.volume;
  }
  onToggle: () => void = (): void => {};
  onStop: () => void = (): void => {};
  onPreview: () => void = (): void => {};
  onSeek: (value: number) => void = (_value: number): void => {};
  onVolume: (value: number) => void = (_value: number): void => {};

  private timeLabel(milliseconds: number): string {
    const seconds = Math.max(0, Math.floor(milliseconds / 1000));
    return `${Math.floor(seconds / 60)}:${(seconds % 60).toString().padStart(2, '0')}`;
  }

  private maxSeekLimit(): number {
    return this.seekEnabled ? Math.max(1, this.durationMs) : 0;
  }

  private currentDisplayPosition(): number {
    return this.isDragging ? this.dragPositionMs : this.positionMs;
  }

  build() {
    Column({ space: 12 }) {
      // 1. Progress Bar & Time
      Column({ space: 4 }) {
        Row() {
          Text(this.timeLabel(this.currentDisplayPosition()))
            .fontSize(12)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.isDragging ? PivoTheme.warning : PivoTheme.accent)
          Blank()
          if (this.bufferedPositionMs > 0 && this.durationMs > 0 && this.bufferedPositionMs < this.durationMs) {
            Text(`已缓存 ${this.timeLabel(this.bufferedPositionMs)} / ${this.timeLabel(this.durationMs)}`)
              .fontSize(11)
              .fontColor(PivoTheme.textMuted)
          } else {
            Text(this.timeLabel(this.durationMs))
              .fontSize(12)
              .fontColor(PivoTheme.textMuted)
          }
        }
        .width('100%')

        Slider({
          value: this.currentDisplayPosition(),
          min: 0,
          max: Math.max(1, this.durationMs),
          step: 100
        })
          .enabled(this.seekEnabled && this.maxSeekLimit() > 0)
          .selectedColor(this.isDragging ? PivoTheme.warning : PivoTheme.accent)
          .trackColor(PivoTheme.surfaceRaised)
          .onChange((value: number, mode: SliderChangeMode) => {
            const limit = this.maxSeekLimit();
            if (limit <= 0) return;
            const clamped = Math.min(value, limit);
            if (mode === SliderChangeMode.Begin || mode === SliderChangeMode.Moving) {
              this.isDragging = true;
              this.dragPositionMs = clamped;
            } else if (mode === SliderChangeMode.End || mode === SliderChangeMode.Click) {
              this.isDragging = false;
              this.dragPositionMs = clamped;
              this.onSeek(clamped);
            }
          })
      }
      .width('100%')



      // 2. Main Control Console (Car-Grade Large Touch Targets >= 52vp)
      Row({ space: 10 }) {
        // Main Action Button (Glow + Gradient + High Visibility)
        Button(this.state === PlaybackState.PLAYING ? '⏸ 暂停演唱' : (this.state === PlaybackState.PAUSED ? '▶ 继续演唱' : '🎤 开始演唱'))
          .height(PivoTheme.carLargeButtonHeight)
          .layoutWeight(1)
          .fontSize(17)
          .fontWeight(FontWeight.Bold)
          .fontColor('#FFFFFF')
          .backgroundColor(this.state === PlaybackState.PLAYING ? PivoTheme.rose : PivoTheme.primary)
          .borderRadius(28)
          .shadow({
            radius: 16,
            color: this.state === PlaybackState.PLAYING ? PivoTheme.roseGlow : PivoTheme.primaryGlow,
            offsetY: 4
          })
          .focusable(true)
          .enabled(this.actionEnabled)
          .onClick(() => this.onToggle())

        // Stop Button (Car Touch Target >= 52vp)
        Button('⏹ 停止')
          .width(96)
          .height(PivoTheme.carLargeButtonHeight)
          .backgroundColor(PivoTheme.surfaceRaised)
          .fontColor(this.stopEnabled ? PivoTheme.text : PivoTheme.textFaint)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .borderRadius(28)
          .border({ width: 1, color: this.stopEnabled ? PivoTheme.borderHighlight : PivoTheme.border })
          .focusable(true)
          .enabled(this.stopEnabled)
          .onClick(() => this.onStop())
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      // 3. Preview Only Button (Car Touch Target >= 40vp)
      Button('♪ 仅试听伴奏（不开启麦克风）')
        .width('100%')
        .height(40)
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontColor(PivoTheme.textMuted)
        .backgroundColor('rgba(255, 255, 255, 0.04)')
        .borderRadius(14)
        .border({ width: 1, color: PivoTheme.border })
        .focusable(true)
        .enabled(this.actionEnabled)
        .onClick(() => this.onPreview())

      // 4. Output Volume Row
      Row({ space: 10 }) {
        Text('🔊 车载外放')
          .fontSize(12)
          .fontWeight(FontWeight.Medium)
          .fontColor(PivoTheme.textMuted)
          .width(68)

        Slider({ value: this.localVolume, min: 0, max: 1, step: 0.05 })
          .layoutWeight(1)
          .selectedColor(PivoTheme.accent)
          .trackColor(PivoTheme.surfaceRaised)
          .onChange((value: number) => {
            this.localVolume = value;
            this.onVolume(value);
          })

        Text(`${Math.round(this.localVolume * 100)}%`)
          .fontSize(12)
          .fontWeight(FontWeight.Bold)
          .fontColor(PivoTheme.text)
          .width(38)
          .textAlign(TextAlign.End)
      }
      .width('100%')
      .padding({ left: 10, right: 10, top: 4, bottom: 4 })
      .backgroundColor(PivoTheme.surfaceRaised)
      .borderRadius(14)
      .border({ width: 1, color: PivoTheme.border })
    }
    .width('100%')
  }
}

