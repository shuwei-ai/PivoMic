import { PivoTheme } from '../theme/PivoTheme';
import { common } from '@kit.AbilityKit';
import { pasteboard } from '@kit.BasicServicesKit';
import { DreamAuthService } from '../services/DreamAuthService';
import { UserInfo } from '../services/CloudAuthService';

@Component({ freezeWhenInactive: true })
export struct AuthLoginPage {
  @Prop wide: boolean = false;
  @State authTab: number = 0; // 0: 登录, 1: 注册
  @State username: string = '';
  @State password: string = '';
  @State nickname: string = '';
  @State isLoading: boolean = false;
  @State errorMessage: string = '';
  @State private isWeChatLoading: boolean = false;

  // 微信扫码/验证码授权弹窗状态
  @State showQrModal: boolean = false;
  @State qrCodeImg: string = '';
  @State sceneCode: string = '';
  @State currentSessionNo: string = '';

  @StorageProp('keyboardHeightPx') keyboardHeightPx: number = 0;
  private scroller: Scroller = new Scroller();
  private timerId: number = -1;
  private context = getContext(this) as common.UIAbilityContext;

  private isKeyboardActive(): boolean {
    return this.keyboardHeightPx > 50;
  }

  aboutToDisappear(): void {
    this.stopWeChatPolling();
  }

  private async copyText(text: string, showToast: boolean = true): Promise<void> {
    try {
      const pasteData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text);
      const systemPasteboard = pasteboard.getSystemPasteboard();
      await systemPasteboard.setData(pasteData);
      if (showToast) {
        this.getUIContext().getPromptAction().showToast({
          message: '授权码已复制：' + text,
          duration: 2000
        });
      }
    } catch (_) {
      if (showToast) {
        this.getUIContext().getPromptAction().showToast({
          message: '复制失败，请手动记录授权码',
          duration: 2000
        });
      }
    }
  }

  private startWeChatPolling(sessionNo: string): void {
    this.timerId = setInterval(async () => {
      const res = await DreamAuthService.getInstance().checkStatus(sessionNo);
      if (res.success && res.data) {
        const status = res.data.status;
        if (status === 3) { // 已授权
          this.stopWeChatPolling();
          this.isWeChatLoading = false;
          this.showQrModal = false;
          this.isLoading = false;
          if (res.data.token) {
            // 微信登录成功，触发登录数据保存与状态刷新
            if (this.onWeChatSuccess) {
              this.onWeChatSuccess(res.data.token, res.data.user);
            }
            this.onSuccess();
          } else {
            this.errorMessage = '微信授权成功，但未关联本地账户';
          }
        } else if (status === 4) { // 已取消
          this.stopWeChatPolling();
          this.isWeChatLoading = false;
          this.showQrModal = false;
          this.isLoading = false;
          this.errorMessage = '用户取消了微信授权';
        } else if (status === 7) { // 已过期
          this.stopWeChatPolling();
          this.isWeChatLoading = false;
          this.showQrModal = false;
          this.isLoading = false;
          this.errorMessage = '微信登录授权已过期，请重试';
        }
      }
    }, 2000);
  }

  private stopWeChatPolling(): void {
    if (this.timerId !== -1) {
      clearInterval(this.timerId);
      this.timerId = -1;
    }
  }

  private async handleWeChatLogin(): Promise<void> {
    if (this.isWeChatLoading) {
      return;
    }
    this.isWeChatLoading = true;
    this.errorMessage = '';

    try {
      const sessionRes = await DreamAuthService.getInstance().createSession();
      if (sessionRes.success && sessionRes.data) {
        const sessionNo = sessionRes.data.sessionNo;
        const scene = sessionRes.data.scene;
        const qrcode = sessionRes.data.qrcode || '';

        this.currentSessionNo = sessionNo;
        this.sceneCode = scene;
        this.qrCodeImg = qrcode;
        this.showQrModal = true;
        this.isWeChatLoading = false;

        // 自动复制场景授权码到剪贴板并提示
        this.copyText(scene, true);

        // 启动后台轮询
        this.startWeChatPolling(sessionNo);
      } else {
        this.isWeChatLoading = false;
        this.errorMessage = sessionRes.message || '获取微信授权会话失败';
      }
    } catch (_) {
      this.isWeChatLoading = false;
      this.errorMessage = '网络连接异常，无法发起微信登录';
    }
  }

  onLogin: (u: string, p: string) => Promise<boolean> = async () => false;
  onRegister: (u: string, p: string, n?: string) => Promise<boolean> = async () => false;
  onWeChatSuccess?: (token: string, user?: UserInfo) => void;
  onSuccess: () => void = () => {};

  private async handleSubmit(): Promise<void> {
    const trimmedUser = this.username.trim();
    if (trimmedUser.length === 0) {
      this.errorMessage = '请输入用户名或手机号';
      return;
    }
    if (this.password.length < 4) {
      this.errorMessage = '密码长度至少为 4 位';
      return;
    }

    this.isLoading = true;
    this.errorMessage = '';

    try {
      if (this.authTab === 0) {
        // 登录
        const ok = await this.onLogin(trimmedUser, this.password);
        this.isLoading = false;
        if (ok) {
          this.onSuccess();
        } else {
          this.errorMessage = '登录失败，请检查用户名与密码';
        }
      } else {
        // 注册
        const ok = await this.onRegister(trimmedUser, this.password, this.nickname.trim());
        this.isLoading = false;
        if (ok) {
          this.onSuccess();
        } else {
          this.errorMessage = '注册失败，用户名可能已存在';
        }
      }
    } catch (_) {
      this.isLoading = false;
      this.errorMessage = '网络连接异常，请重试';
    }
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      // 1. Ambient Background Glows
      Row()
        .width('100%')
        .height('100%')
        .backgroundColor(PivoTheme.backgroundDark)

      // Top-center gradient atmosphere glow
      Stack()
        .width(360)
        .height(360)
        .position({ x: '15%', y: '5%' })
        .borderRadius(180)
        .backgroundColor(PivoTheme.surfaceSelectedSubtle)
        .blur(80)

      Stack()
        .width(320)
        .height(320)
        .position({ x: '60%', y: '45%' })
        .borderRadius(160)
        .backgroundColor(PivoTheme.accentGlow)
        .blur(70)

      Scroll(this.scroller) {
        Column({ space: this.wide ? 24 : (this.isKeyboardActive() ? 10 : 18) }) {
          // Brand Logo & Header
          Column({ space: this.isKeyboardActive() ? 4 : 8 }) {
            Stack({ alignContent: Alignment.Center }) {
              Text('🎤')
                .fontSize(this.isKeyboardActive() ? 22 : 32)
            }
            .width(this.isKeyboardActive() ? 46 : 68)
            .height(this.isKeyboardActive() ? 46 : 68)
            .borderRadius(this.isKeyboardActive() ? 23 : 34)
            .backgroundColor(PivoTheme.surfaceSelected)
            .border({ width: 2, color: PivoTheme.primary })
            .shadow({ radius: 20, color: PivoTheme.primaryGlow })

            Text('PivoMic 演播级伴奏')
              .fontSize(this.isKeyboardActive() ? 18 : 22)
              .fontWeight(FontWeight.Bold)
              .fontColor(PivoTheme.text)

            if (!this.isKeyboardActive()) {
              Text('48kHz 演播级无损伴奏 · 端云一体同步')
                .fontSize(12)
                .fontColor(PivoTheme.textMuted)

              // Features Row
              Row({ space: 8 }) {
                Text('☁️ 歌单云漫游')
                  .fontSize(11)
                  .fontColor(PivoTheme.primary)
                  .padding({ left: 8, right: 8, top: 4, bottom: 4 })
                  .backgroundColor(PivoTheme.surfaceSelected)
                  .borderRadius(6)

                Text('🎙️ 演播级低延迟')
                  .fontSize(11)
                  .fontColor(PivoTheme.accent)
                  .padding({ left: 8, right: 8, top: 4, bottom: 4 })
                  .backgroundColor(PivoTheme.accentGlow)
                  .borderRadius(6)

                Text('⚡️ 实时硬件耳返')
                  .fontSize(11)
                  .fontColor(PivoTheme.textSecondary)
                  .padding({ left: 8, right: 8, top: 4, bottom: 4 })
                  .backgroundColor(PivoTheme.surfaceRaised)
                  .borderRadius(6)
              }
              .margin({ top: 2 })
            }
          }
          .alignItems(HorizontalAlign.Center)

          // Form Box
          Column({ space: this.isKeyboardActive() ? 10 : 16 }) {
            // Tab Switcher (登录 / 注册)
            Row({ space: 6 }) {
              Button({ type: ButtonType.Normal }) {
                Text('账号登录')
                  .fontSize(14)
                  .fontWeight(this.authTab === 0 ? FontWeight.Bold : FontWeight.Medium)
                  .fontColor(this.authTab === 0 ? PivoTheme.primaryTextDark : PivoTheme.textMuted)
              }
              .layoutWeight(1)
              .height(36)
              .backgroundColor(this.authTab === 0 ? PivoTheme.primary : PivoTheme.surfaceRaised)
              .borderRadius(10)
              .onClick(() => {
                this.authTab = 0;
                this.errorMessage = '';
              })

              Button({ type: ButtonType.Normal }) {
                Text('新用户注册')
                  .fontSize(14)
                  .fontWeight(this.authTab === 1 ? FontWeight.Bold : FontWeight.Medium)
                  .fontColor(this.authTab === 1 ? PivoTheme.primaryTextDark : PivoTheme.textMuted)
              }
              .layoutWeight(1)
              .height(36)
              .backgroundColor(this.authTab === 1 ? PivoTheme.primary : PivoTheme.surfaceRaised)
              .borderRadius(10)
              .onClick(() => {
                this.authTab = 1;
                this.errorMessage = '';
              })
            }
            .width('100%')
            .padding(4)
            .backgroundColor('rgba(98, 98, 98, 0.24)')
            .borderRadius(14)

            // Error Banner
            if (this.errorMessage.length > 0) {
              Row({ space: 6 }) {
                Text('⚠️')
                  .fontSize(12)
                Text(this.errorMessage)
                  .fontSize(12)
                  .fontColor('#EF4444')
                  .layoutWeight(1)
              }
              .width('100%')
              .padding({ left: 12, right: 12, top: 8, bottom: 8 })
              .backgroundColor('rgba(239, 68, 68, 0.12)')
              .borderRadius(8)
              .border({ width: 1, color: 'rgba(239, 68, 68, 0.3)' })
            }

            // Input Fields
            Column({ space: this.isKeyboardActive() ? 8 : 12 }) {
              Column({ space: 4 }) {
                Text('用户名 / 手机号')
                  .fontSize(12)
                  .fontColor(PivoTheme.textMuted)
                  .width('100%')

                TextInput({ placeholder: '请输入用户名或手机号', text: this.username })
                  .height(44)
                  .fontSize(14)
                  .fontColor(PivoTheme.text)
                  .placeholderColor(PivoTheme.textMuted)
                  .backgroundColor(PivoTheme.surfaceRaised)
                  .borderRadius(10)
                  .border({ width: 1, color: PivoTheme.border })
                  .enterKeyType(EnterKeyType.Next)
                  .onChange((val: string) => {
                    this.username = val;
                  })
                  .onFocus(() => {
                    if (!this.isKeyboardActive()) {
                      this.scroller.scrollEdge(Edge.Bottom);
                    }
                  })
              }
              .alignItems(HorizontalAlign.Start)

              Column({ space: 4 }) {
                Text('登录密码')
                  .fontSize(12)
                  .fontColor(PivoTheme.textMuted)
                  .width('100%')

                TextInput({ placeholder: '请输入密码 (至少4位)', text: this.password })
                  .type(InputType.Password)
                  .height(44)
                  .fontSize(14)
                  .fontColor(PivoTheme.text)
                  .placeholderColor(PivoTheme.textMuted)
                  .backgroundColor(PivoTheme.surfaceRaised)
                  .borderRadius(10)
                  .border({ width: 1, color: PivoTheme.border })
                  .enterKeyType(this.authTab === 0 ? EnterKeyType.Done : EnterKeyType.Next)
                  .onChange((val: string) => {
                    this.password = val;
                  })
                  .onFocus(() => {
                    if (!this.isKeyboardActive()) {
                      this.scroller.scrollEdge(Edge.Bottom);
                    }
                  })
                  .onSubmit(() => {
                    if (this.authTab === 0) {
                      this.handleSubmit();
                    }
                  })
              }
              .alignItems(HorizontalAlign.Start)

              if (this.authTab === 1) {
                Column({ space: 4 }) {
                  Text('个性昵称 (选填)')
                    .fontSize(12)
                    .fontColor(PivoTheme.textMuted)
                    .width('100%')

                  TextInput({ placeholder: '请输入昵称 (默认同用户名)', text: this.nickname })
                    .height(44)
                    .fontSize(14)
                    .fontColor(PivoTheme.text)
                    .placeholderColor(PivoTheme.textMuted)
                    .backgroundColor(PivoTheme.surfaceRaised)
                    .borderRadius(10)
                    .border({ width: 1, color: PivoTheme.border })
                    .enterKeyType(EnterKeyType.Done)
                    .onChange((val: string) => {
                      this.nickname = val;
                    })
                    .onFocus(() => {
                      if (!this.isKeyboardActive()) {
                        this.scroller.scrollEdge(Edge.Bottom);
                      }
                    })
                    .onSubmit(() => {
                      this.handleSubmit();
                    })
                }
                .alignItems(HorizontalAlign.Start)
              }
            }
            .width('100%')

            // Submit Button
            Button(this.isLoading ? '正在处理中…' : (this.authTab === 0 ? '立即登录' : '立即注册并登录'))
              .width('100%')
              .height(44)
              .fontSize(15)
              .fontWeight(FontWeight.Bold)
              .fontColor(PivoTheme.primaryTextDark)
              .backgroundColor(PivoTheme.primary)
              .borderRadius(22)
              .shadow({ radius: 14, color: PivoTheme.primaryGlow })
              .enabled(!this.isLoading)
              .onClick(() => {
                this.handleSubmit();
              })

            // Divider
            Row() {
              Row().height(1).layoutWeight(1).backgroundColor(PivoTheme.border)
              Text('或')
                .fontSize(11)
                .fontColor(PivoTheme.textMuted)
                .margin({ left: 12, right: 12 })
              Row().height(1).layoutWeight(1).backgroundColor(PivoTheme.border)
            }
            .width('100%')
            .margin({ top: 8, bottom: 8 })

            // WeChat Mini Program One-Click Login Button
            Button({ type: ButtonType.Normal }) {
              Row({ space: 8 }) {
                Text('💬')
                  .fontSize(16)
                Text(this.isWeChatLoading ? '正在等待授权…' : '微信小程序一键登录')
                  .fontSize(14)
                  .fontWeight(FontWeight.Medium)
                  .fontColor('#FFFFFF')
              }
            }
            .width('100%')
            .height(40)
            .backgroundColor('#07C160')
            .borderRadius(20)
            .shadow({ radius: 10, color: 'rgba(7, 193, 96, 0.25)' })
            .enabled(!this.isLoading)
            .onClick(() => {
              this.handleWeChatLogin();
            })

            // Bottom Policy Text
            if (!this.isKeyboardActive()) {
              Row({ space: 4 }) {
                Text('🔒 登录即代表同意并使用 PivoMic 云同步服务')
                  .fontSize(11)
                  .fontColor(PivoTheme.textMuted)
              }
              .margin({ top: 4 })
            }
          }
          .width(this.wide ? '440vp' : '92%')
          .padding(this.isKeyboardActive() ? { left: 18, right: 18, top: 14, bottom: 8 } : 22)
          .backgroundColor(PivoTheme.surfaceRaised)
          .borderRadius(20)
          .border({ width: 1, color: PivoTheme.borderHighlight })
          .shadow({ radius: 24, color: 'rgba(120, 105, 85, 0.18)' })
        }
        .width('100%')
        .constraintSize({ minHeight: '100%' })
        .justifyContent(this.isKeyboardActive() ? FlexAlign.Start : FlexAlign.Center)
        .padding({
          top: this.wide ? 32 : (this.isKeyboardActive() ? 125 : 36),
          bottom: this.wide ? 32 : (this.isKeyboardActive() ? 12 : 36)
        })
        .alignItems(HorizontalAlign.Center)
        .animation({ duration: 250, curve: Curve.FastOutSlowIn })
      }
      .width('100%')
      .height('100%')
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)

      // 3. 微信扫码/授权码登录弹窗
      if (this.showQrModal) {
        Stack({ alignContent: Alignment.Center }) {
          // 半透明遮罩层
          Column()
            .width('100%')
            .height('100%')
            .backgroundColor('rgba(98, 98, 98, 0.32)')
            .onClick(() => {
              this.showQrModal = false;
              this.stopWeChatPolling();
            })

          // 弹窗卡片
          Column({ space: 14 }) {
            // 头部标题与关闭按钮
            Row() {
              Row({ space: 6 }) {
                Text('💬')
                  .fontSize(18)
                Text('微信扫码 / 验证码授权')
                  .fontSize(16)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(PivoTheme.text)
              }

              Button({ type: ButtonType.Normal }) {
                Text('✕')
                  .fontSize(16)
                  .fontColor(PivoTheme.textMuted)
              }
              .width(30)
              .height(30)
              .backgroundColor(PivoTheme.surfaceRaised)
              .borderRadius(15)
              .onClick(() => {
                this.showQrModal = false;
                this.stopWeChatPolling();
              })
            }
            .width('100%')
            .justifyContent(FlexAlign.SpaceBetween)
            .alignItems(VerticalAlign.Center)

            // 小程序码图片展示
            if (this.qrCodeImg.length > 0) {
              Column({ space: 6 }) {
                Image(this.qrCodeImg)
                  .width(160)
                  .height(160)
                  .borderRadius(12)
                  .backgroundColor('#FFFFFF')
                  .padding(6)
                  .shadow({ radius: 12, color: 'rgba(120, 105, 85, 0.16)' })

                Text('微信扫一扫上方小程序码')
                  .fontSize(11)
                  .fontColor(PivoTheme.textMuted)
              }
              .alignItems(HorizontalAlign.Center)
            }

            // 场景授权码与复制按钮
            Column({ space: 8 }) {
              Text('或在小程序中手动输入授权码：')
                .fontSize(12)
                .fontColor(PivoTheme.textMuted)

              Row({ space: 10 }) {
                Text(this.sceneCode)
                  .fontSize(18)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(PivoTheme.primary)
                  .letterSpacing(2)
                  .padding({ left: 12, right: 12, top: 6, bottom: 6 })
                  .backgroundColor(PivoTheme.surfaceSelected)
                  .borderRadius(8)
                  .border({ width: 1, color: PivoTheme.primary })

                Button({ type: ButtonType.Normal }) {
                  Row({ space: 4 }) {
                    Text('📋')
                      .fontSize(13)
                    Text('复制')
                      .fontSize(13)
                      .fontWeight(FontWeight.Medium)
                      .fontColor(PivoTheme.primaryTextDark)
                  }
                }
                .height(34)
                .padding({ left: 12, right: 12 })
                .backgroundColor(PivoTheme.primary)
                .borderRadius(8)
                .onClick(() => {
                  this.copyText(this.sceneCode, true);
                })
              }
              .alignItems(VerticalAlign.Center)
            }
            .alignItems(HorizontalAlign.Center)
            .width('100%')
            .padding(10)
            .backgroundColor(PivoTheme.surfaceRaised)
            .borderRadius(12)
            .border({ width: 1, color: PivoTheme.border })

            // 快捷打开微信
            Button({ type: ButtonType.Normal }) {
              Row({ space: 6 }) {
                Text('💬')
                  .fontSize(15)
                Text('打开微信 (已自动复制授权码)')
                  .fontSize(14)
                  .fontWeight(FontWeight.Bold)
                  .fontColor('#FFFFFF')
              }
            }
            .width('100%')
            .height(40)
            .backgroundColor('#07C160')
            .borderRadius(20)
            .shadow({ radius: 8, color: 'rgba(7, 193, 96, 0.3)' })
            .onClick(() => {
              DreamAuthService.getInstance().openWeChat(this.context);
            })

            // 状态等待提示
            Row({ space: 6 }) {
              LoadingProgress()
                .width(14)
                .height(14)
                .color(PivoTheme.accent)
              Text('正在等待微信端确认授权…')
                .fontSize(11)
                .fontColor(PivoTheme.accent)
            }
            .justifyContent(FlexAlign.Center)
            .width('100%')
          }
          .width(this.wide ? '380vp' : '90%')
          .padding(18)
          .backgroundColor(PivoTheme.surfaceRaised)
          .borderRadius(20)
          .border({ width: 1, color: PivoTheme.borderHighlight })
          .shadow({ radius: 30, color: 'rgba(120, 105, 85, 0.20)' })
        }
        .width('100%')
        .height('100%')
      }
    }
    .width('100%')
    .height('100%')
  }
}
