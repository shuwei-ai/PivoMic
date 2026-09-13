import { PivoTheme } from '../theme/PivoTheme';

@Component({ freezeWhenInactive: true })
export struct MicrophoneMeter {
  @Prop peak: number = 0;

  private getMeterColor(): string {
    if (this.peak >= 0.85) return PivoTheme.danger;
    if (this.peak >= 0.65) return PivoTheme.warning;
    return PivoTheme.accent;
  }

  build() {
    Row({ space: 12 }) {
      Row({ space: 6 }) {
        Row()
          .width(6)
          .height(6)
          .borderRadius(3)
          .backgroundColor(this.peak > 0.05 ? this.getMeterColor() : PivoTheme.textFaint)
          .shadow(this.peak > 0.05 ? { radius: 6, color: this.getMeterColor() } : undefined)

        Text('麦克风拾音')
          .fontSize(12)
          .fontWeight(FontWeight.Medium)
          .fontColor(PivoTheme.textSecondary)
      }
      .width(82)

      Progress({ value: Math.max(0, Math.min(1, this.peak)) * 100, total: 100, type: ProgressType.Linear })
        .color(this.getMeterColor())
        .backgroundColor(PivoTheme.surfaceRaised)
        .layoutWeight(1)
        .height(8)
        .borderRadius(4)
        .shadow(this.peak > 0.1 ? { radius: 8, color: this.getMeterColor(), offsetY: 1 } : undefined)

      Text(`${Math.round(Math.max(0, Math.min(1, this.peak)) * 100)}%`)
        .fontSize(12)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.getMeterColor())
        .width(42)
        .textAlign(TextAlign.End)
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 8, bottom: 8 })
    .backgroundColor(PivoTheme.surfaceRaised)
    .borderRadius(12)
    .border({ width: 1, color: PivoTheme.border })
  }
}
