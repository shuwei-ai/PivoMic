import { promptAction } from '@kit.ArkUI';
import { MusicSourceMode } from '../domain/MusicModels';
import { PivoTheme } from '../theme/PivoTheme';
import { MusicServerTestResult } from '../services/OnlineMusicSource';

const DEFAULT_SERVER_TEST_FAIL: MusicServerTestResult = { success: false, message: '' };

@Component
export struct AppSettingsModal {
  @Prop visible: boolean = false;
  @Prop expanded: boolean = false;
  @Prop musicSourceMode: MusicSourceMode = MusicSourceMode.ONLINE;
  @Prop customMusicServerUrl: string = '';
  @Prop qqMusicApiKey: string = '';
  @Prop recordingDir: string = '';
  @Prop latencyMs: number = 25;
  @Prop fastMode: boolean = false;
  @Prop isCloudLoggedIn: boolean = false;
  @Prop currentUserNickname: string = '';
  @Prop currentUserUsername: string = '';
  @Prop isSyncingCloud: boolean = false;
  @Prop cloudSyncStatusText: string = '';

  onClose: () => void = (): void => {};
  onUpdateMusicSourceMode: (mode: MusicSourceMode) => Promise<void> = async () => {};
  onTestEngineConnection: () => Promise<MusicServerTestResult> = async () => DEFAULT_SERVER_TEST_FAIL;
  onTestHuibqConnection: () => Promise<MusicServerTestResult> = async () => DEFAULT_SERVER_TEST_FAIL;
  onUpdateCustomMusicServerUrl: (url: string) => Promise<boolean> = async () => false;
  onClearCustomMusicServerUrl: () => Promise<void> = async () => {};
  onTestCustomMusicServerUrl: (url: string) => Promise<MusicServerTestResult> = async () => DEFAULT_SERVER_TEST_FAIL;
  onUpdateQQMusicApiKey: (key: string) => Promise<boolean> = async () => false;
  onClearQQMusicApiKey: () => Promise<void> = async () => {};
  onUpdateRecordingDir: (path: string) => void = (_path: string): void => {};
  onResetRecordingDir: () => void = (): void => {};
  onOpenAudioDevicesModal: () => void = (): void => {};
  onOpenAuthModal: () => void = (): void => {};
  onLogoutCloud: () => void = (): void => {};
  onSyncCloud: () => void = (): void => {};

  @State private inputServerUrl: string = '';
  @State private inputQQApiKey: string = '';
  @State private inputRecordingDir: string = '';
  @State private isTestingEngine: boolean = false;
  @State private isTestingServer: boolean = false;
  @State private serverTestMsg: string = '';
  @State private serverTestSuccess: boolean = false;
  @State private engineTestMsg: string = '';
  @State private showPathEditDialog: boolean = false;

  aboutToAppear(): void {
    this.inputServerUrl = this.customMusicServerUrl;
    this.inputQQApiKey = this.qqMusicApiKey;
    this.inputRecordingDir = this.recordingDir;
  }

  build() {
    if (this.visible) {
      Stack({ alignContent: Alignment.Center }) {
        // 背景遮罩
        Row()
          .width('100%')
          .height('100%')
          .backgroundColor('rgba(0, 0, 0, 0.45)')
          .onClick(() => this.onClose())

        // 设置内容面板
        Column({ space: 0 }) {
          // 顶部标题栏
          Row() {
            Row({ space: 8 }) {
              Text('⚙️')
                .fontSize(20)
              Column({ space: 2 }) {
                Text('系统与服务设置')
                  .fontSize(17)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(PivoTheme.text)
                Text('个性化音源、硬件偏好与数据存储管理')
                  .fontSize(11)
                  .fontColor(PivoTheme.textMuted)
              }
              .alignItems(HorizontalAlign.Start)
            }

            Blank()

            Button('✕')
              .height(32)
              .width(32)
              .fontSize(16)
              .fontColor(PivoTheme.textMuted)
              .backgroundColor(Color.Transparent)
              .onClick(() => this.onClose())
          }
          .width('100%')
          .padding({ left: 20, right: 20, top: 18, bottom: 14 })
          .border({ width: { bottom: 1 }, color: PivoTheme.border })

          // 可滚动设置内容区
          Scroll() {
            Column({ space: 16 }) {
              // ==================== 1. 音乐服务源 ====================
              Column({ space: 10 }) {
                Row() {
                  Row({ space: 6 }) {
                    Text('🌐')
                      .fontSize(14)
                    Text('在线音乐服务源')
                      .fontSize(14)
                      .fontWeight(FontWeight.Bold)
                      .fontColor(PivoTheme.text)
                  }

                  Blank()

                  if (this.musicSourceMode === MusicSourceMode.ONLINE) {
                    Text('● 原生全网源')
                      .fontSize(10)
                      .fontWeight(FontWeight.Bold)
                      .fontColor('#10B981')
                      .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                      .backgroundColor('rgba(16, 185, 129, 0.12)')
                      .borderRadius(4)
                  } else {
                    Text('○ 纯本地模式')
                      .fontSize(10)
                      .fontWeight(FontWeight.Medium)
                      .fontColor(PivoTheme.textMuted)
                      .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                      .backgroundColor(PivoTheme.surface)
                      .borderRadius(4)
                  }
                }
                .width('100%')

                // 2段切换按钮
                Row({ space: 8 }) {
                  Button('🌐 原生全网源 (推荐)')
                    .layoutWeight(1.3)
                    .height(34)
                    .fontSize(12)
                    .fontWeight(this.musicSourceMode === MusicSourceMode.ONLINE ? FontWeight.Bold : FontWeight.Normal)
                    .fontColor(this.musicSourceMode === MusicSourceMode.ONLINE ? PivoTheme.primaryTextDark : PivoTheme.text)
                    .backgroundColor(this.musicSourceMode === MusicSourceMode.ONLINE ? PivoTheme.primary : PivoTheme.surface)
                    .borderRadius(8)
                    .border({ width: 0.8, color: this.musicSourceMode === MusicSourceMode.ONLINE ? PivoTheme.primary : PivoTheme.border })
                    .onClick(async () => {
                      await this.onUpdateMusicSourceMode(MusicSourceMode.ONLINE);
                      promptAction.showToast({ message: '已切换为原生全网源 (5大平台直连 · 320k 智能换源)' });
                    })

                  Button('📁 纯本地模式')
                    .layoutWeight(1)
                    .height(34)
                    .fontSize(12)
                    .fontWeight(this.musicSourceMode === MusicSourceMode.LOCAL ? FontWeight.Bold : FontWeight.Normal)
                    .fontColor(this.musicSourceMode === MusicSourceMode.LOCAL ? PivoTheme.primaryTextDark : PivoTheme.text)
                    .backgroundColor(this.musicSourceMode === MusicSourceMode.LOCAL ? PivoTheme.primary : PivoTheme.surface)
                    .borderRadius(8)
                    .border({ width: 0.8, color: this.musicSourceMode === MusicSourceMode.LOCAL ? PivoTheme.primary : PivoTheme.border })
                    .onClick(async () => {
                      await this.onUpdateMusicSourceMode(MusicSourceMode.LOCAL);
                      promptAction.showToast({ message: '已切换为纯本地模式' });
                    })
                }
                .width('100%')

                // 详情行
                if (this.musicSourceMode === MusicSourceMode.ONLINE) {
                  Column({ space: 8 }) {
                    // 平台徽章
                    Row({ space: 4 }) {
                      Text('酷我 320k')
                        .fontSize(9)
                        .fontColor('#F5A623')
                        .padding({ left: 5, right: 5, top: 2, bottom: 2 })
                        .backgroundColor('rgba(245, 166, 35, 0.12)')
                        .borderRadius(4)
                      Text('酷狗直连')
                        .fontSize(9)
                        .fontColor('#00A9F0')
                        .padding({ left: 5, right: 5, top: 2, bottom: 2 })
                        .backgroundColor('rgba(0, 169, 240, 0.12)')
                        .borderRadius(4)
                      Text('QQ权威榜')
                        .fontSize(9)
                        .fontColor('#1DB954')
                        .padding({ left: 5, right: 5, top: 2, bottom: 2 })
                        .backgroundColor('rgba(29, 185, 84, 0.12)')
                        .borderRadius(4)
                      Text('网易云')
                        .fontSize(9)
                        .fontColor('#E60026')
                        .padding({ left: 5, right: 5, top: 2, bottom: 2 })
                        .backgroundColor('rgba(230, 0, 38, 0.12)')
                        .borderRadius(4)
                      Text('汽水抖音')
                        .fontSize(9)
                        .fontColor('#10B981')
                        .padding({ left: 5, right: 5, top: 2, bottom: 2 })
                        .backgroundColor('rgba(16, 185, 129, 0.12)')
                        .borderRadius(4)
                    }
                    .width('100%')

                    Row({ space: 8 }) {
                      Text('内置原生免签引擎 · 320k 智能无缝换源')
                        .fontSize(11)
                        .fontColor(PivoTheme.textSecondary)
                        .layoutWeight(1)

                      Button(this.isTestingEngine ? '测速中…' : '⚡ 引擎连通测速')
                        .height(28)
                        .padding({ left: 10, right: 10 })
                        .fontSize(11)
                        .fontWeight(FontWeight.Medium)
                        .fontColor(PivoTheme.primary)
                        .backgroundColor(PivoTheme.surface)
                        .borderRadius(14)
                        .border({ width: 0.8, color: PivoTheme.primary })
                        .enabled(!this.isTestingEngine)
                        .onClick(async () => {
                          this.isTestingEngine = true;
                          const res = await this.onTestEngineConnection();
                          this.isTestingEngine = false;
                          this.engineTestMsg = res.message;
                          promptAction.showToast({ message: res.message, duration: 2500 });
                        })
                    }
                    .width('100%')

                    if (this.engineTestMsg.length > 0) {
                      Text(this.engineTestMsg)
                        .fontSize(11)
                        .fontColor('#10B981')
                        .width('100%')
                    }
                  }
                  .width('100%')
                  .padding(10)
                  .backgroundColor(PivoTheme.surface)
                  .borderRadius(8)
                } else {
                  Row() {
                    Text('仅使用本地导入音乐与伴奏录音，停用所有外网在线音频请求')
                      .fontSize(11)
                      .fontColor(PivoTheme.textMuted)
                      .layoutWeight(1)
                  }
                  .width('100%')
                  .padding(10)
                  .backgroundColor(PivoTheme.surface)
                  .borderRadius(8)
                }
              }
              .width('100%')
              .padding(14)
              .backgroundColor(PivoTheme.surfaceRaised)
              .borderRadius(14)
              .border({ width: 1, color: PivoTheme.border })

              // ==================== 2. QQ 音乐 Skill ====================
              Column({ space: 10 }) {
                Row() {
                  Row({ space: 6 }) {
                    Text('🎵')
                      .fontSize(14)
                    Text('QQ 音乐 Skill (Agent Gateway)')
                      .fontSize(14)
                      .fontWeight(FontWeight.Bold)
                      .fontColor(PivoTheme.text)
                  }

                  Blank()

                  if (this.qqMusicApiKey.length > 0) {
                    Text('● 已授权')
                      .fontSize(10)
                      .fontWeight(FontWeight.Bold)
                      .fontColor('#10B981')
                      .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                      .backgroundColor('rgba(16, 185, 129, 0.12)')
                      .borderRadius(4)
                  } else {
                    Text('○ 未配置')
                      .fontSize(10)
                      .fontWeight(FontWeight.Medium)
                      .fontColor(PivoTheme.textMuted)
                      .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                      .backgroundColor(PivoTheme.surface)
                      .borderRadius(4)
                  }
                }
                .width('100%')

                Text('直连 QQ 音乐官方 Agent 接口，激活每日推荐、AI歌单与热歌榜单')
                  .fontSize(11)
                  .fontColor(PivoTheme.textSecondary)
                  .width('100%')

                Row({ space: 6 }) {
                  TextInput({ placeholder: '请输入 API Key (格式形如 qmk-xxxxxxxx)', text: this.inputQQApiKey })
                    .height(36)
                    .fontSize(12)
                    .fontColor(PivoTheme.text)
                    .placeholderColor(PivoTheme.textMuted)
                    .backgroundColor(PivoTheme.surface)
                    .borderRadius(8)
                    .border({ width: 1, color: PivoTheme.border })
                    .layoutWeight(1)
                    .onChange((val: string) => {
                      this.inputQQApiKey = val;
                    })

                  Button('保存生效')
                    .height(36)
                    .padding({ left: 12, right: 12 })
                    .fontSize(11)
                    .fontWeight(FontWeight.Bold)
                    .fontColor(PivoTheme.primaryTextDark)
                    .backgroundColor(PivoTheme.primary)
                    .borderRadius(8)
                    .onClick(async () => {
                      const trimmed = this.inputQQApiKey.trim();
                      await this.onUpdateQQMusicApiKey(trimmed);
                      promptAction.showToast({
                        message: trimmed.length > 0 ? 'QQ 音乐 API Key 已保存' : '已清空 API Key'
                      });
                    })

                  if (this.qqMusicApiKey.length > 0) {
                    Button('清空')
                      .height(36)
                      .padding({ left: 10, right: 10 })
                      .fontSize(11)
                      .fontColor(PivoTheme.textMuted)
                      .backgroundColor(PivoTheme.surface)
                      .borderRadius(8)
                      .border({ width: 1, color: PivoTheme.border })
                      .onClick(async () => {
                        this.inputQQApiKey = '';
                        await this.onClearQQMusicApiKey();
                        promptAction.showToast({ message: '已清空 QQ 音乐 API Key' });
                      })
                  }
                }
                .width('100%')
              }
              .width('100%')
              .padding(14)
              .backgroundColor(PivoTheme.surfaceRaised)
              .borderRadius(14)
              .border({ width: 1, color: this.qqMusicApiKey.length > 0 ? 'rgba(16, 185, 129, 0.3)' : PivoTheme.border })

              // ==================== 3. 录音保存目录 ====================
              Column({ space: 10 }) {
                Row() {
                  Row({ space: 6 }) {
                    Text('🎙️')
                      .fontSize(14)
                    Text('录音与作品存储目录')
                      .fontSize(14)
                      .fontWeight(FontWeight.Bold)
                      .fontColor(PivoTheme.text)
                  }

                  Blank()

                  Row({ space: 6 }) {
                    Button('📁 更改')
                      .height(26)
                      .padding({ left: 10, right: 10 })
                      .fontSize(11)
                      .fontWeight(FontWeight.Bold)
                      .fontColor(PivoTheme.primaryTextDark)
                      .backgroundColor(PivoTheme.primary)
                      .borderRadius(13)
                      .onClick(() => {
                        this.inputRecordingDir = this.recordingDir;
                        this.showPathEditDialog = true;
                      })

                    Button('🔄 恢复默认')
                      .height(26)
                      .padding({ left: 8, right: 8 })
                      .fontSize(11)
                      .fontColor(PivoTheme.textMuted)
                      .backgroundColor(PivoTheme.surface)
                      .borderRadius(13)
                      .onClick(() => {
                        this.onResetRecordingDir();
                        promptAction.showToast({ message: '已恢复默认录音目录' });
                      })
                  }
                }
                .width('100%')

                Row() {
                  Text(this.recordingDir.length > 0 ? this.recordingDir : '默认沙箱目录 (/recordings)')
                    .fontSize(11)
                    .fontColor(PivoTheme.textSecondary)
                    .fontFamily('monospace')
                    .maxLines(2)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                    .layoutWeight(1)
                }
                .width('100%')
                .padding(8)
                .backgroundColor(PivoTheme.surface)
                .borderRadius(8)

                if (this.showPathEditDialog) {
                  Column({ space: 8 }) {
                    Text('请输入合法的绝对路径：')
                      .fontSize(11)
                      .fontColor(PivoTheme.textMuted)
                      .width('100%')

                    Row({ space: 6 }) {
                      TextInput({ placeholder: '如 /data/storage/el2/base/haps/entry/files/recordings', text: this.inputRecordingDir })
                        .height(36)
                        .fontSize(12)
                        .fontColor(PivoTheme.text)
                        .backgroundColor(PivoTheme.surface)
                        .borderRadius(8)
                        .border({ width: 1, color: PivoTheme.border })
                        .layoutWeight(1)
                        .onChange((val: string) => {
                          this.inputRecordingDir = val;
                        })

                      Button('确定')
                        .height(36)
                        .padding({ left: 12, right: 12 })
                        .fontSize(11)
                        .fontWeight(FontWeight.Bold)
                        .fontColor(PivoTheme.primaryTextDark)
                        .backgroundColor(PivoTheme.primary)
                        .borderRadius(8)
                        .onClick(() => {
                          if (this.inputRecordingDir.trim().length > 0) {
                            this.onUpdateRecordingDir(this.inputRecordingDir.trim());
                            this.showPathEditDialog = false;
                            promptAction.showToast({ message: '录音目录已更新' });
                          }
                        })

                      Button('取消')
                        .height(36)
                        .padding({ left: 10, right: 10 })
                        .fontSize(11)
                        .fontColor(PivoTheme.textMuted)
                        .backgroundColor(PivoTheme.surface)
                        .borderRadius(8)
                        .onClick(() => {
                          this.showPathEditDialog = false;
                        })
                    }
                    .width('100%')
                  }
                  .width('100%')
                  .padding(8)
                  .backgroundColor(PivoTheme.surface)
                  .borderRadius(8)
                }
              }
              .width('100%')
              .padding(14)
              .backgroundColor(PivoTheme.surfaceRaised)
              .borderRadius(14)
              .border({ width: 1, color: PivoTheme.border })

              // ==================== 4. 音频设备与延迟偏好 ====================
              Column({ space: 10 }) {
                Row() {
                  Row({ space: 6 }) {
                    Text('🎧')
                      .fontSize(14)
                    Text('音频设备与硬件偏好')
                      .fontSize(14)
                      .fontWeight(FontWeight.Bold)
                      .fontColor(PivoTheme.text)
                  }

                  Blank()

                  Button('🛠️ 诊断与切换设备')
                    .height(26)
                    .padding({ left: 10, right: 10 })
                    .fontSize(11)
                    .fontWeight(FontWeight.Medium)
                    .fontColor(PivoTheme.primary)
                    .backgroundColor(PivoTheme.surface)
                    .borderRadius(13)
                    .border({ width: 0.8, color: PivoTheme.primary })
                    .onClick(() => {
                      this.onOpenAudioDevicesModal();
                    })
                }
                .width('100%')

                Row({ space: 12 }) {
                  Row({ space: 4 }) {
                    Text('底层耳返延迟:')
                      .fontSize(11)
                      .fontColor(PivoTheme.textMuted)
                    Text(`${this.latencyMs}ms`)
                      .fontSize(11)
                      .fontWeight(FontWeight.Bold)
                      .fontColor(this.latencyMs < 35 ? '#10B981' : '#F59E0B')
                  }

                  Row({ space: 4 }) {
                    Text('快速处理模式:')
                      .fontSize(11)
                      .fontColor(PivoTheme.textMuted)
                    Text(this.fastMode ? '已激活' : '标准')
                      .fontSize(11)
                      .fontWeight(FontWeight.Bold)
                      .fontColor(this.fastMode ? '#10B981' : PivoTheme.textSecondary)
                  }
                }
                .width('100%')
                .padding(8)
                .backgroundColor(PivoTheme.surface)
                .borderRadius(8)
              }
              .width('100%')
              .padding(14)
              .backgroundColor(PivoTheme.surfaceRaised)
              .borderRadius(14)
              .border({ width: 1, color: PivoTheme.border })

              // ==================== 5. 账号与数据同步 ====================
              Column({ space: 10 }) {
                Row() {
                  Row({ space: 6 }) {
                    Text('☁️')
                      .fontSize(14)
                    Text('账号与云端同步')
                      .fontSize(14)
                      .fontWeight(FontWeight.Bold)
                      .fontColor(PivoTheme.text)
                  }

                  Blank()

                  if (this.isCloudLoggedIn) {
                    Row({ space: 6 }) {
                      Button(this.isSyncingCloud ? '同步中…' : '🔄 立即同步')
                        .height(26)
                        .padding({ left: 8, right: 8 })
                        .fontSize(10)
                        .fontWeight(FontWeight.Medium)
                        .fontColor(PivoTheme.primary)
                        .backgroundColor(PivoTheme.surface)
                        .borderRadius(13)
                        .border({ width: 0.8, color: PivoTheme.primary })
                        .enabled(!this.isSyncingCloud)
                        .onClick(() => {
                          this.onSyncCloud();
                        })

                      Button('退出')
                        .height(26)
                        .padding({ left: 8, right: 8 })
                        .fontSize(10)
                        .fontColor(PivoTheme.danger)
                        .backgroundColor(PivoTheme.surface)
                        .borderRadius(13)
                        .border({ width: 0.8, color: PivoTheme.danger })
                        .onClick(() => {
                          this.onLogoutCloud();
                          promptAction.showToast({ message: '已退出账号' });
                        })
                    }
                  } else {
                    Button('登录 / 注册')
                      .height(26)
                      .padding({ left: 10, right: 10 })
                      .fontSize(11)
                      .fontWeight(FontWeight.Bold)
                      .fontColor(PivoTheme.primaryTextDark)
                      .backgroundColor(PivoTheme.primary)
                      .borderRadius(13)
                      .onClick(() => {
                        this.onOpenAuthModal();
                      })
                  }
                }
                .width('100%')

                Row() {
                  Text(this.isCloudLoggedIn
                    ? `当前登录：${this.currentUserNickname || this.currentUserUsername || '云端用户'} · ${this.cloudSyncStatusText || '数据保持实时同步'}`
                    : '登录后可在多设备间自动同步我的收藏、歌单与配置')
                    .fontSize(11)
                    .fontColor(this.isCloudLoggedIn ? PivoTheme.textSecondary : PivoTheme.textMuted)
                    .layoutWeight(1)
                }
                .width('100%')
                .padding(8)
                .backgroundColor(PivoTheme.surface)
                .borderRadius(8)
              }
              .width('100%')
              .padding(14)
              .backgroundColor(PivoTheme.surfaceRaised)
              .borderRadius(14)
              .border({ width: 1, color: PivoTheme.border })
            }
            .width('100%')
            .padding({ left: 16, right: 16, top: 16, bottom: 24 })
          }
          .layoutWeight(1)
          .width('100%')

          // 底部关闭确认条
          Row() {
            Button('完成并关闭')
              .height(40)
              .width('100%')
              .fontSize(14)
              .fontWeight(FontWeight.Bold)
              .fontColor(PivoTheme.primaryTextDark)
              .backgroundColor(PivoTheme.primary)
              .borderRadius(20)
              .onClick(() => this.onClose())
          }
          .width('100%')
          .padding({ left: 20, right: 20, top: 10, bottom: 14 })
          .border({ width: { top: 1 }, color: PivoTheme.border })
        }
        .width(this.expanded ? '520vp' : '94%')
        .height(this.expanded ? '720vp' : '88%')
        .backgroundColor(PivoTheme.background)
        .borderRadius(20)
        .border({ width: 1, color: PivoTheme.borderHighlight })
        .shadow({ radius: 32, color: 'rgba(0, 0, 0, 0.28)' })
      }
      .width('100%')
      .height('100%')
      .position({ x: 0, y: 0 })
      .zIndex(999)
    }
  }
}
