import { PivoTheme } from '../theme/PivoTheme';

@Component({ freezeWhenInactive: true })
export struct StatusBanner {
  @Prop message: string = '';
  @Prop warning: boolean = false;

  build() {
    if (this.message && this.message.length > 0) {
      Row({ space: 12 }) {
        // Left accent indicator dot
        Row()
          .width(3)
          .height(24)
          .borderRadius(1.5)
          .backgroundColor(this.warning ? PivoTheme.warning : PivoTheme.accent)
          .shadow({ radius: 8, color: this.warning ? PivoTheme.warningGlow : PivoTheme.accentGlow })

        // Status Icon Pill
        Row() {
          Text(this.warning ? '!' : '✓')
            .fontSize(12)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.warning ? PivoTheme.warning : PivoTheme.accent)
        }
        .width(24)
        .height(24)
        .borderRadius(12)
        .justifyContent(FlexAlign.Center)
        .backgroundColor(this.warning ? '#FFF0AD' : '#DDF5E7')

        Text(this.message)
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor(PivoTheme.text)
          .layoutWeight(1)
          .maxLines(2)
      }
      .width('100%')
      .padding({ left: 14, right: 16, top: 10, bottom: 10 })
      .borderRadius(16)
      .backgroundColor(this.warning ? '#FFF9EE' : '#F7FBF5')
      .border({ width: 1, color: this.warning ? PivoTheme.warning : PivoTheme.success })
      .shadow({ radius: 14, color: this.warning ? PivoTheme.warningGlow : PivoTheme.accentGlow, offsetY: 2 })
    }
  }
}
