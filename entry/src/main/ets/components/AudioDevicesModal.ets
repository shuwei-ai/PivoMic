import { FormattedAudioDevice, audioDeviceService } from '../domain/AudioDeviceService';
import { PivoTheme } from '../theme/PivoTheme';

@Component({ freezeWhenInactive: true })
export struct AudioDevicesModal {
  @Prop visible: boolean = false;
  @State inputDevices: FormattedAudioDevice[] = [];
  @State outputDevices: FormattedAudioDevice[] = [];
  @State selectedCategory: number = 0; // 0: 全部, 1: 仅本地设备, 2: 仅分布式远程设备, 3: 仅输入设备, 4: 仅输出设备
  onClose: () => void = (): void => {};

  aboutToAppear(): void {
    this.refreshDevices();
  }

  private async refreshDevices(): Promise<void> {
    const inputs = await audioDeviceService.getInputDevices();
    const outputs = await audioDeviceService.getOutputDevices();
    this.inputDevices = inputs;
    this.outputDevices = outputs;
  }

  private countLocalDevices(): number {
    return this.inputDevices.filter(d => !d.isRemote).length + this.outputDevices.filter(d => !d.isRemote).length;
  }

  private countRemoteDevices(): number {
    return this.inputDevices.filter(d => d.isRemote).length + this.outputDevices.filter(d => d.isRemote).length;
  }

  private shouldShowDevice(dev: FormattedAudioDevice): boolean {
    if (this.selectedCategory === 0) return true; // 全部
    if (this.selectedCategory === 1) return !dev.isRemote; // 仅本地
    if (this.selectedCategory === 2) return dev.isRemote; // 仅分布式远程
    if (this.selectedCategory === 3) return dev.deviceRole === 1; // 仅输入
    if (this.selectedCategory === 4) return dev.deviceRole === 2; // 仅输出
    return true;
  }

  @Builder
  categoryPill(title: string, index: number, count: number, activeColor: string) {
    Button(`${title} (${count})`)
      .fontSize(11)
      .fontWeight(this.selectedCategory === index ? FontWeight.Bold : FontWeight.Normal)
      .fontColor(this.selectedCategory === index ? PivoTheme.primaryTextDark : PivoTheme.textMuted)
      .backgroundColor(this.selectedCategory === index ? activeColor : PivoTheme.surfaceRaised)
      .height(26)
      .padding({ left: 10, right: 10 })
      .borderRadius(13)
      .border({
        width: 1,
        color: this.selectedCategory === index ? activeColor : PivoTheme.border
      })
      .shadow(this.selectedCategory === index ? { radius: 8, color: `${activeColor}40` } : undefined)
      .onClick(() => {
        this.selectedCategory = index;
      })
  }

  @Builder
  deviceCard(dev: FormattedAudioDevice, idx: number, isInput: boolean) {
    Column({ space: 6 }) {
      // 第一层：序号与设备名 + 本地/分布式标签 + 右侧当前激活标签/选择按钮
      Row() {
        Row({ space: 6 }) {
          Text(`${idx + 1}. ${dev.name}`)
            .fontSize(13)
            .fontWeight(FontWeight.Bold)
            .fontColor(PivoTheme.text)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .constraintSize({ maxWidth: 140 })

          // 本地 / 分布式标识
          Text(dev.isRemote ? '🌐 分布式' : '🏠 本地')
            .fontSize(9)
            .fontWeight(FontWeight.Medium)
            .fontColor(PivoTheme.text)
            .backgroundColor(dev.isRemote ? '#FFE1D7' : '#DDEFFD')
            .padding({ left: 5, right: 5, top: 1, bottom: 1 })
            .borderRadius(4)
        }
        .layoutWeight(1)
        .alignItems(VerticalAlign.Center)

        // 状态标识或选择按钮
        if (dev.isActive) {
          Row({ space: 4 }) {
            Text('●')
              .fontSize(7)
              .fontColor(isInput ? PivoTheme.primary : PivoTheme.accent)
            Text(isInput ? '当前采集' : '当前播放')
              .fontSize(10)
              .fontWeight(FontWeight.Bold)
              .fontColor(isInput ? PivoTheme.primary : PivoTheme.accent)
          }
          .padding({ left: 8, right: 8, top: 3, bottom: 3 })
          .backgroundColor(isInput ? PivoTheme.surfaceSelected : PivoTheme.accentGlow)
          .borderRadius(10)
          .border({ width: 1, color: isInput ? PivoTheme.primary : PivoTheme.accent })
        } else {
          Button(isInput ? '选择采集' : '选择播放')
            .fontSize(10)
            .fontWeight(FontWeight.Medium)
            .fontColor(PivoTheme.textSecondary)
            .backgroundColor(PivoTheme.surfaceRaised)
            .height(24)
            .padding({ left: 8, right: 8 })
            .borderRadius(12)
            .border({ width: 1, color: PivoTheme.border })
            .onClick(async () => {
              if (isInput) {
                await audioDeviceService.selectInputDevice(dev);
              } else {
                await audioDeviceService.selectOutputDevice(dev);
              }
              this.refreshDevices();
            })
        }
      }
      .width('100%')
      .justifyContent(FlexAlign.SpaceBetween)

      // 第二层：设备类型说明徽章 (独立行，杜绝与按钮挤压)
      Row({ space: 6 }) {
        Text(dev.deviceTypeName)
          .fontSize(10)
          .fontColor(PivoTheme.text)
          .backgroundColor(isInput ? '#DDF5E7' : '#DDEFFD')
          .padding({ left: 6, right: 6, top: 2, bottom: 2 })
          .borderRadius(4)
          .border({ width: 1, color: isInput ? 'rgba(16, 185, 129, 0.30)' : 'rgba(59, 130, 246, 0.30)' })
      }
      .width('100%')

      // 第三层：元数据详情徽章 (ID / 节点 / 采样率)
      Row({ space: 6 }) {
        Text(`ID: ${dev.id}`)
          .fontSize(9)
          .fontColor(PivoTheme.textMuted)
          .backgroundColor(PivoTheme.surfaceRaised)
          .padding({ left: 4, right: 4, top: 1, bottom: 1 })
          .borderRadius(3)

        Text(`地址: ${dev.address}`)
          .fontSize(9)
          .fontColor(PivoTheme.textMuted)
          .backgroundColor(PivoTheme.surfaceRaised)
          .padding({ left: 4, right: 4, top: 1, bottom: 1 })
          .borderRadius(3)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)

        Text(`采样率: ${dev.sampleRates}`)
          .fontSize(9)
          .fontColor(PivoTheme.textMuted)
          .backgroundColor(PivoTheme.surfaceRaised)
          .padding({ left: 4, right: 4, top: 1, bottom: 1 })
          .borderRadius(3)
      }
      .width('100%')
    }
    .width('100%')
    .padding(10)
    .backgroundColor(dev.isActive ? (isInput ? PivoTheme.surfaceSelectedSubtle : PivoTheme.accentGlow) : (dev.isRemote ? PivoTheme.atmospherePurpleGlow : PivoTheme.surfaceRaised))
    .borderRadius(10)
    .border({
      width: dev.isActive ? 1.5 : 1,
      color: dev.isActive ? (isInput ? PivoTheme.primaryDark : PivoTheme.accent) : PivoTheme.border
    })
    .shadow(dev.isActive ? { radius: 10, color: isInput ? PivoTheme.primaryGlow : PivoTheme.accentGlow } : undefined)
  }

  build() {
    if (this.visible) {
      Stack({ alignContent: Alignment.Center }) {
        // 半透明暗色背景遮罩
        Rect()
          .width('100%')
          .height('100%')
          .fill('rgba(98, 98, 98, 0.32)')
          .onClick(() => {
            this.onClose();
          })

        // 居中高级玻璃拟态卡片
        Column({ space: 12 }) {
          // 1. 顶部标题栏与紧凑操作区 (确保弹性约束，永不溢出)
          Row() {
            Row({ space: 8 }) {
              Text('🎙️')
                .fontSize(20)
              Column({ space: 2 }) {
                Text('系统音频与设备诊断')
                  .fontSize(15)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(PivoTheme.text)
                Text(`本地 ${this.countLocalDevices()} 个 · 分布式协同 ${this.countRemoteDevices()} 个`)
                  .fontSize(10)
                  .fontColor(PivoTheme.textMuted)
              }
              .alignItems(HorizontalAlign.Start)
            }
            .layoutWeight(1)

            // 右侧紧凑工具按钮
            Row({ space: 6 }) {
              Button({ type: ButtonType.Normal }) {
                Row({ space: 3 }) {
                  Text('🔄')
                    .fontSize(10)
                  Text('刷新')
                    .fontSize(11)
                    .fontColor(PivoTheme.textSecondary)
                }
              }
              .height(28)
              .padding({ left: 8, right: 8 })
              .borderRadius(14)
              .backgroundColor(PivoTheme.surfaceRaised)
              .onClick(() => {
                this.refreshDevices();
              })

              Button({ type: ButtonType.Circle }) {
                Text('✕')
                  .fontSize(12)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(PivoTheme.textMuted)
              }
              .width(28)
              .height(28)
              .backgroundColor(PivoTheme.surfaceRaised)
              .onClick(() => {
                this.onClose();
              })
            }
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)

          // 2. 核心功能操作区：等宽复制输入设备与全部清单
          Row({ space: 8 }) {
            Button('📋 复制输入设备')
              .fontSize(11)
              .fontWeight(FontWeight.Bold)
              .fontColor(PivoTheme.primaryTextDark)
              .backgroundColor(PivoTheme.primary)
              .height(32)
              .layoutWeight(1)
              .borderRadius(16)
              .shadow({ radius: 8, color: PivoTheme.primaryGlow })
              .onClick(() => {
                audioDeviceService.copyAllInputDeviceNames();
              })

            Button('📑 复制全部设备')
              .fontSize(11)
              .fontWeight(FontWeight.Medium)
              .fontColor(PivoTheme.textSecondary)
              .backgroundColor(PivoTheme.surfaceRaised)
              .border({ width: 1, color: PivoTheme.border })
              .height(32)
              .layoutWeight(1)
              .borderRadius(16)
              .onClick(() => {
                audioDeviceService.copyAllDeviceNames();
              })
          }
          .width('100%')

          // 3. 多维分类切换 Tab (全部 / 本地 / 分布式 / 输入采集 / 输出播放)
          Scroll() {
            Row({ space: 6 }) {
              this.categoryPill('全部', 0, this.inputDevices.length + this.outputDevices.length, PivoTheme.primary)
              this.categoryPill('🏠 本地', 1, this.countLocalDevices(), '#0284C7')
              this.categoryPill('🌐 分布式', 2, this.countRemoteDevices(), '#8B5CF6')
              this.categoryPill('🎤 采集', 3, this.inputDevices.length, '#10B981')
              this.categoryPill('🔊 播放', 4, this.outputDevices.length, '#3B82F6')
            }
            .padding({ left: 2, right: 2 })
          }
          .width('100%')
          .scrollable(ScrollDirection.Horizontal)
          .scrollBar(BarState.Off)

          // 4. 滚动设备卡片列表
          Scroll() {
            Column({ space: 12 }) {
              // 4.1 输入采集设备板块
              if (this.selectedCategory !== 4) {
                Column({ space: 6 }) {
                  Row({ space: 6 }) {
                    Text('🎤 人声采集设备 (Inputs)')
                      .fontSize(12)
                      .fontWeight(FontWeight.Bold)
                      .fontColor(PivoTheme.primary)
                    Text(`(${this.inputDevices.filter(d => this.shouldShowDevice(d)).length})`)
                      .fontSize(11)
                      .fontColor(PivoTheme.textMuted)
                  }
                  .width('100%')

                  if (this.inputDevices.filter(d => this.shouldShowDevice(d)).length === 0) {
                    Text('当前筛选分类下无输入设备')
                      .fontSize(11)
                      .fontColor(PivoTheme.textMuted)
                      .padding(8)
                  } else {
                    ForEach(this.inputDevices.filter(d => this.shouldShowDevice(d)), (dev: FormattedAudioDevice, idx: number) => {
                      this.deviceCard(dev, idx, true)
                    }, (dev: FormattedAudioDevice) => `in_${dev.id}_${dev.name}_${dev.isActive}`)
                  }
                }
                .width('100%')
                .alignItems(HorizontalAlign.Start)
              }

              // 4.2 输出播放设备板块
              if (this.selectedCategory !== 3) {
                Column({ space: 6 }) {
                  Row({ space: 6 }) {
                    Text('🔊 音频播放设备 (Outputs)')
                      .fontSize(12)
                      .fontWeight(FontWeight.Bold)
                      .fontColor(PivoTheme.accent)
                    Text(`(${this.outputDevices.filter(d => this.shouldShowDevice(d)).length})`)
                      .fontSize(11)
                      .fontColor(PivoTheme.textMuted)
                  }
                  .width('100%')

                  if (this.outputDevices.filter(d => this.shouldShowDevice(d)).length === 0) {
                    Text('当前筛选分类下无播放设备')
                      .fontSize(11)
                      .fontColor(PivoTheme.textMuted)
                      .padding(8)
                  } else {
                    ForEach(this.outputDevices.filter(d => this.shouldShowDevice(d)), (dev: FormattedAudioDevice, idx: number) => {
                      this.deviceCard(dev, idx, false)
                    }, (dev: FormattedAudioDevice) => `out_${dev.id}_${dev.name}_${dev.isActive}`)
                  }
                }
                .width('100%')
                .alignItems(HorizontalAlign.Start)
              }
            }
            .width('100%')
          }
          .width('100%')
          .constraintSize({ maxHeight: 360 })
          .scrollBar(BarState.Auto)
        }
        .width('90%')
        .constraintSize({ maxWidth: 440 })
        .padding(16)
        .backgroundColor(PivoTheme.surfaceGlassHeavy)
        .borderRadius(20)
        .border({ width: 1, color: PivoTheme.borderSubtle })
        .shadow({ radius: 24, color: 'rgba(120, 105, 85, 0.18)', offsetX: 0, offsetY: 10 })
      }
      .width('100%')
      .height('100%')
      .position({ x: 0, y: 0 })
      .zIndex(999)
    }
  }
}
