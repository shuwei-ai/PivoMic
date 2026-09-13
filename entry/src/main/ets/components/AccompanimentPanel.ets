import { PivoMicStore } from '../store/PivoMicStore';
import { AccompanimentAsset } from '../domain/AccompanimentModels';
import { PivoTheme } from '../theme/PivoTheme';

@Component
export struct AccompanimentPanel {
  @ObjectLink store: PivoMicStore;
  onClose: () => void = (): void => {};
  @State message: string = '';
  @State showAssets: boolean = false;
  private phaseLabel(): string {
    const phase = this.store.separationSnapshot.job.phase;
    if (phase === 'preparingModel') return '正在准备内置资源';
    if (phase === 'verifyingModel') return '正在校验生成资源';
    if (phase === 'preparing') return '正在准备歌曲';
    if (phase === 'separating') return '正在分离人声';
    if (phase === 'writing') return '正在保存伴奏';
    if (phase === 'completed') return 'AI 伴奏已生成';
    if (phase === 'cancelled') return '生成已取消，可重新生成';
    if (phase === 'error') return '生成失败';
    return '为喜欢的歌生成伴奏';
  }
  private currentAsset(): AccompanimentAsset | undefined {
    return this.store.selectedSong ? this.store.separation?.resolveAsset(this.store.selectedSong) : undefined;
  }
  private deleteAsset(asset: AccompanimentAsset): void {
    try { this.store.separation?.deleteAsset(asset.id); this.message = '伴奏已删除，原曲保留'; }
    catch (error) { this.message = (error as Error).message; }
  }
  build() {
    Column({ space: 16 }) {
      Row() {
        Text('AI 伴奏').fontSize(22).fontWeight(FontWeight.Bold).fontColor(PivoTheme.text)
        Blank()
        Button('关闭').height(44).onClick(() => this.onClose())
      }.width('100%')
      Row({ space: 12 }) {
        Button('生成伴奏').backgroundColor(!this.showAssets ? PivoTheme.primary : PivoTheme.textSecondary)
          .onClick(() => { this.showAssets = false; })
        Button(`已生成 (${this.store.separationSnapshot.assets.length})`)
          .backgroundColor(this.showAssets ? PivoTheme.primary : PivoTheme.textSecondary)
          .onClick(() => { this.showAssets = true; })
      }
      Scroll() {
        Column({ space: 14 }) {
          if (!this.showAssets) {
            Text(this.store.selectedSong?.title ?? '请先选择一首歌曲').fontSize(19).fontWeight(FontWeight.Medium)
            Text('在此设备处理，歌曲不会上传。生成时请保持应用在前台。')
              .fontSize(14).fontColor(PivoTheme.textSecondary)
            Text(this.phaseLabel()).fontSize(15).fontColor(PivoTheme.primary)
            if (this.store.separationSnapshot.busy) {
              Progress({ value: this.store.separationSnapshot.job.progress * 100, total: 100, type: ProgressType.Linear }).width('100%')
              Text(`${Math.round(this.store.separationSnapshot.job.progress * 100)}%`).fontSize(14)
              Button('取消生成').height(44).onClick(() => this.store.separation?.cancel())
            } else {
              if (this.store.separationSnapshot.model.phase !== 'ready') {
                Text('伴奏生成模型已内置，首次使用将自动初始化，无需下载。').fontSize(13).fontColor(PivoTheme.textSecondary)
              }
              Button(this.store.micEnabled ? '关闭麦克风并生成' :
                (this.store.separationSnapshot.model.phase === 'ready' ? '生成伴奏' : '初始化并生成'))
                .height(48).width('100%').backgroundColor(PivoTheme.primary)
                .enabled(this.store.selectedSong !== undefined && !this.store.isRecording && this.store.separation !== undefined)
                .onClick(() => { this.message = ''; this.store.generateAccompaniment(); })
              if (this.store.isRecording) { Text('停止录音后可生成或切换伴奏').fontColor(PivoTheme.textSecondary) }
              if (this.currentAsset()) {
                Row({ space: 12 }) {
                  Button('试听伴奏').height(44).enabled(!this.store.isRecording && !this.store.trackSwitchPending)
                    .onClick(() => { const asset = this.currentAsset(); if (asset) this.store.switchAudioTrack(asset.id, true); })
                  Button('使用伴奏').height(44).enabled(!this.store.isRecording && !this.store.trackSwitchPending)
                    .onClick(() => { const asset = this.currentAsset(); if (asset) this.store.switchAudioTrack(asset.id); })
                }
              }
            }
            if (this.store.separationSnapshot.job.errorMessage) {
              Text(this.store.separationSnapshot.job.errorMessage).fontColor(PivoTheme.danger).fontSize(14)
            }
          } else {
            if (this.store.separationSnapshot.assets.length === 0) { Text('尚未生成伴奏，选择歌曲后即可生成。').fontColor(PivoTheme.textSecondary) }
            ForEach(this.store.separationSnapshot.assets, (asset: AccompanimentAsset) => {
              Column({ space: 8 }) {
                Text(asset.song.title).fontSize(17).fontWeight(FontWeight.Medium).width('100%')
                Text(`${asset.song.artist} · AI 伴奏 · ${(asset.frameCount * 4 / 1000000).toFixed(1)} MB`)
                  .fontSize(12).fontColor(PivoTheme.textSecondary).width('100%')
                Row({ space: 8 }) {
                  Button('播放').height(44).enabled(!this.store.isRecording && !this.store.trackSwitchPending)
                    .onClick(() => { this.store.playAccompaniment(asset); })
                  Button('导出').height(44).onClick(() => { this.store.exportAccompaniment(asset); })
                  Button('删除').height(44).backgroundColor(PivoTheme.textSecondary).onClick(() => this.deleteAsset(asset))
                }
              }.padding(12).width('100%').backgroundColor(PivoTheme.surfaceRaised).borderRadius(12)
            }, (asset: AccompanimentAsset): string => asset.id)
            Divider()
            Text(`生成资源：${this.store.separationSnapshot.model.phase === 'ready' ? '内置资源已就绪' : '已内置，首次使用自动初始化'}`).fontSize(14)

          }
          if (this.message) { Text(this.message).fontColor(PivoTheme.primary).fontSize(14) }
          Text(this.store.statusMessage).fontSize(12).fontColor(PivoTheme.textSecondary)
        }.width('100%')
      }.layoutWeight(1).width('100%')
    }.width('100%').height('100%').padding(24).backgroundColor(PivoTheme.background)
  }
}
