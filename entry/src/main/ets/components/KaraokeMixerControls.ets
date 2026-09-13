import { PivoTheme } from '../theme/PivoTheme';
import { AudioRouteMode } from '../audio/KaraokeSessionModels';

interface ReverbPreset {
  name: string;
  mix: number;
  icon: string;
}

@Component({ freezeWhenInactive: true })
struct GainSliderRow {
  icon: string = '';
  label: string = '';
  @Prop @Watch('onValuePropChanged') value: number = 0;
  accentColor: string = '';
  maxValue: number = 1.0;
  onChangeValue: (value: number) => void = (_value: number) => {};

  @State currentValue: number = 0;

  aboutToAppear(): void {
    this.currentValue = this.value;
  }

  onValuePropChanged(): void {
    this.currentValue = this.value;
  }

  build() {
    Row({ space: 10 }) {
      Row({ space: 5 }) {
        Text(this.icon).fontSize(13).fontColor(this.accentColor)
        Text(this.label).fontSize(12).fontWeight(FontWeight.Medium).fontColor(PivoTheme.textSecondary)
      }
      .width(58)

      Slider({ value: this.currentValue, min: 0, max: this.maxValue, step: 0.05 })
        .layoutWeight(1)
        .selectedColor(this.accentColor)
        .trackColor(PivoTheme.surfaceRaised)
        .focusable(true)
        .onKeyEvent((event?: KeyEvent) => {
          if (!event || event.type !== KeyType.Down) return;
          if (event.keyCode === 2014 || event.keyCode === 21) {
            const next = Math.max(0, this.currentValue - 0.05);
            this.currentValue = next;
            this.onChangeValue(next);
          } else if (event.keyCode === 2015 || event.keyCode === 22) {
            const next = Math.min(this.maxValue, this.currentValue + 0.05);
            this.currentValue = next;
            this.onChangeValue(next);
          }
        })
        .onChange((val: number, _mode: SliderChangeMode) => {
          this.currentValue = val;
          this.onChangeValue(val);
        })

      Text(`${Math.round(this.currentValue * 100)}%`)
        .fontSize(12)
        .fontWeight(FontWeight.Bold)
        .fontColor(PivoTheme.text)
        .width(42)
        .textAlign(TextAlign.End)
    }
    .width('100%')
    .padding({ left: 10, right: 10, top: 2, bottom: 2 })
  }
}

@Component({ freezeWhenInactive: true })
export struct KaraokeMixerControls {
  @Prop accompanimentGain: number = 0.8;
  @Prop vocalGain: number = 0.8;
  @Prop reverbMix: number = 0.25;
  @Prop audioRoute: number = AudioRouteMode.Speaker;
  @Prop pitchShiftSemitones: number = 0;
  @Prop autoTuneActive: boolean = false;
  @Prop autoTuneStrength: number = 0.5;
  @Prop antiHowlingActive: boolean = true;
  @Prop aecActive: boolean = true;
  @Prop isRecording: boolean = false;
  @Prop recordedDurationMs: number = 0;
  @Prop isHeadsetConnected: boolean = false;

  onRouteChange: (route: number) => void = (_route: number): void => {};
  onAccompaniment: (value: number) => void = (_value: number): void => {};
  onVocal: (value: number) => void = (_value: number): void => {};
  onReverb: (value: number) => void = (_value: number): void => {};
  onPitchShiftChange: (semitones: number) => void = (_semitones: number): void => {};
  onAutoTuneToggle: (active: boolean) => void = (_active: boolean): void => {};
  onAutoTuneStrengthChange: (strength: number) => void = (_strength: number): void => {};
  onRecordingToggle: () => void = (): void => {};

  @State focusedRoute: number = -1;
  @State focusedRecord: boolean = false;
  @State focusedPitchBtn: string = '';
  @State focusedPreset: string = '';
  @State focusedAutoTune: boolean = false;

  private readonly carPresets: ReverbPreset[] = [
    { name: '原声', mix: 0.0, icon: '🎙️' },
    { name: '录音棚', mix: 0.15, icon: '🎧' },
    { name: '座舱全景', mix: 0.28, icon: '🚗' },
    { name: 'KTV包房', mix: 0.45, icon: '✨' }
  ];



  @Builder
  dspBadge(label: string, icon: string, active: boolean, color: string) {
    Row({ space: 5 }) {
      Text(icon).fontSize(11).fontColor(active ? color : PivoTheme.textMuted)
      Text(label).fontSize(11).fontWeight(FontWeight.Medium).fontColor(active ? color : PivoTheme.textMuted)
    }
    .layoutWeight(1)
    .height(28)
    .justifyContent(FlexAlign.Center)
    .backgroundColor(active ? PivoTheme.surfaceActive : PivoTheme.surface)
    .borderRadius(8)
    .border({ width: 1, color: active ? color : PivoTheme.border })
  }

  private formatDuration(ms: number): string {
    const totalSec = Math.floor(ms / 1000);
    const min = Math.floor(totalSec / 60);
    const sec = totalSec % 60;
    return `${min.toString().padStart(2, '0')}:${sec.toString().padStart(2, '0')}`;
  }

  private getRouteHelpText(): string {
    if (this.audioRoute === AudioRouteMode.Speaker) {
      return '📱 手机外放伴奏，耳返自动静音防啸叫；唱完可导出完整混响人声';
    }
    if (this.audioRoute === AudioRouteMode.SpeakerWithEarReturn) {
      return '📢 外放实时耳返：扬声器输出人声+混响，AEC与4Hz频移防啸叫运行中';
    }
    if (this.audioRoute === AudioRouteMode.Bluetooth) {
      return '🎧 蓝牙K歌模式：48kHz 高清耳返与混响已开启，手机麦克风高清拾音（若需 <20ms 极致零延迟可使用有线耳机）';
    }
    return '🔌 有线耳机模式：<20ms 超低延时实时耳返，实时监听空间混响与修音';
  }

  build() {
    Column({ space: 14 }) {
      // Headset Status Notice
      Row({ space: 8 }) {
        Text(this.isHeadsetConnected ? '🎧' : '📱')
          .fontSize(13)
        Text(this.isHeadsetConnected ? '已连接耳机：48kHz 麦克风高清耳返、混响与双轨录音已就绪' : '扬声器K歌：伴奏与处理后人声实时外放，双轨录音已就绪')
          .fontSize(11)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.isHeadsetConnected ? PivoTheme.primary : PivoTheme.warning)
          .layoutWeight(1)
          .maxLines(2)
      }
      .width('100%')
      .padding({ left: 10, right: 10, top: 6, bottom: 6 })
      .backgroundColor(this.isHeadsetConnected ? PivoTheme.surfaceSelectedSubtle : 'rgba(255, 179, 0, 0.10)')
      .borderRadius(10)
      .border({ width: 1, color: this.isHeadsetConnected ? PivoTheme.borderGlow : 'rgba(255, 179, 0, 0.30)' })

      // Top Recording Action Bar
      Row() {
        Row({ space: 6 }) {
          Text('🎙️')
            .fontSize(14)
          Text('实时双轨录音')
            .fontSize(13)
            .fontWeight(FontWeight.Bold)
            .fontColor(PivoTheme.text)
        }

        Blank()

        // Recording button
        Button(this.isRecording ? `🔴 ${this.formatDuration(this.recordedDurationMs)} (点击停止)` : '⏺ 录制干音/伴奏')
          .fontSize(12)
          .height(32)
          .padding({ left: 14, right: 14 })
          .fontWeight(FontWeight.Bold)
          .fontColor(this.isRecording ? '#FFFFFF' : PivoTheme.rose)
          .backgroundColor(this.isRecording ? '#E53935' : PivoTheme.surface)
          .border({
            width: this.focusedRecord ? 2 : 1,
            color: this.focusedRecord ? PivoTheme.primary : (this.isRecording ? '#FF5252' : PivoTheme.rose)
          })
          .shadow(this.focusedRecord ? { radius: 10, color: PivoTheme.primaryGlow } : undefined)
          .scale({ x: this.focusedRecord ? 1.05 : 1.0, y: this.focusedRecord ? 1.05 : 1.0 })
          .borderRadius(16)
          .focusable(true)
          .onFocus(() => {
            this.focusedRecord = true;
          })
          .onBlur(() => {
            this.focusedRecord = false;
          })
          .onClick(() => this.onRecordingToggle())
      }
      .width('100%')
      .padding({ left: 4, right: 4, bottom: 4 })

      // Core Audio Mixing Sliders
      Column({ space: 10 }) {
        GainSliderRow({
          icon: '♫',
          label: '音乐',
          value: this.accompanimentGain,
          accentColor: PivoTheme.primary,
          maxValue: 1.0,
          onChangeValue: (val: number) => {
            this.accompanimentGain = val;
            this.onAccompaniment(val);
          }
        })
        GainSliderRow({
          icon: '🎤',
          label: '麦克风',
          value: this.vocalGain,
          accentColor: PivoTheme.accent,
          maxValue: 2.0,
          onChangeValue: (val: number) => {
            this.vocalGain = val;
            this.onVocal(val);
          }
        })
        GainSliderRow({
          icon: '✨',
          label: '混响',
          value: this.reverbMix,
          accentColor: PivoTheme.rose,
          maxValue: 1.0,
          onChangeValue: (val: number) => {
            this.reverbMix = val;
            this.onReverb(val);
          }
        })
      }
      .width('100%')
    }
    .width('100%')
    .padding(16)
    .backgroundColor(PivoTheme.surfaceRaised)
    .borderRadius(16)
    .border({ width: 1, color: PivoTheme.border })
  }
}
