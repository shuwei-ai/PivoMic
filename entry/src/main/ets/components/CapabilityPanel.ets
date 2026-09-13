import { AudioCapability } from '../domain/MusicModels';
import { PivoTheme } from '../theme/PivoTheme';

@Component({ freezeWhenInactive: true })
export struct CapabilityPanel {
  @Prop capability: AudioCapability = {
    simulated: true, microphoneAvailable: false, lowLatencyAvailable: false,
    aecAvailable: false, message: ''
  };
  @Prop latencyMs: number = 0;
  @Prop fastMode: boolean = false;
  @Prop aecSupported: boolean = false;
  @Prop monitoringAllowed: boolean = false;
  @Prop outputRoute: string = '未检测';
  @Prop blockedReason: string = '';

  @Builder
  badge(label: string, active: boolean, highlightColor: string = PivoTheme.accent) {
    Row({ space: 5 }) {
      Row()
        .width(5)
        .height(5)
        .borderRadius(2.5)
        .backgroundColor(active ? highlightColor : PivoTheme.textFaint)
        .shadow(active ? { radius: 6, color: highlightColor } : undefined)

      Text(label)
        .fontSize(11)
        .fontWeight(active ? FontWeight.Bold : FontWeight.Normal)
        .fontColor(active ? PivoTheme.text : PivoTheme.textMuted)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .layoutWeight(1)
    .height(26)
    .justifyContent(FlexAlign.Center)
    .padding({ left: 6, right: 6 })
    .backgroundColor(active ? PivoTheme.surfaceActive : PivoTheme.surfaceRaised)
    .borderRadius(8)
    .border({ width: 1, color: active ? PivoTheme.primaryDark : PivoTheme.border })
  }

  build() {
    Column({ space: 8 }) {
      Row({ space: 6 }) {
        this.badge(`${this.latencyMs > 0 ? this.latencyMs : 25}ms 低时延`, this.latencyMs > 0, PivoTheme.primary)
        this.badge(this.fastMode ? 'FAST 直通' : '标准音频流', this.fastMode, PivoTheme.accent)
      }
      .width('100%')

      Row({ space: 6 }) {
        this.badge('防啸叫 +4Hz', true, PivoTheme.accent)
        this.badge(this.outputRoute, this.monitoringAllowed, this.monitoringAllowed ? PivoTheme.accent : PivoTheme.warning)
      }
      .width('100%')

      Row({ space: 8 }) {
        Row()
          .width(3)
          .height(14)
          .borderRadius(1.5)
          .backgroundColor(this.blockedReason.length > 0 ? PivoTheme.warning : PivoTheme.accent)

        Text(this.blockedReason.length > 0 ? this.blockedReason : (this.monitoringAllowed ? 'K歌音频路由已就绪' : '音频输出安全检查中...'))
          .fontSize(11)
          .fontColor(this.blockedReason.length > 0 ? PivoTheme.warning : PivoTheme.textMuted)
          .layoutWeight(1)
          .maxLines(2)
      }
      .width('100%')
      .margin({ top: 2 })
    }
    .width('100%')
    .padding(12)
    .backgroundColor(PivoTheme.surfaceGlass)
    .borderRadius(14)
    .border({ width: 1, color: PivoTheme.border })
  }
}
