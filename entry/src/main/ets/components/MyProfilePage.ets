import { promptAction } from '@kit.ArkUI';
import { Song, MusicSourceKind, MusicSourceMode } from '../domain/MusicModels';
import { PivoTheme } from '../theme/PivoTheme';
import { AudioDevicesModal } from './AudioDevicesModal';
import { AppSettingsModal } from './AppSettingsModal';
import { AccompanimentAsset } from '../domain/AccompanimentModels';
import { isValidArtist } from './MusicRecommendationPage';
import { MusicServerTestResult } from '../services/OnlineMusicSource';
import { ArrayDataSource } from '../domain/ArrayDataSource';

const DEFAULT_SERVER_TEST_FAIL: MusicServerTestResult = { success: false, message: '' };

@Component({ freezeWhenInactive: true })
export struct MyProfilePage {
  @Prop accompanimentCount: number = 0;
  @Prop accompanimentAssets: AccompanimentAsset[] = [];
  onAccompaniment: () => void = (): void => {};
  onPlayAccompaniment: (asset: AccompanimentAsset) => void = (_asset: AccompanimentAsset): void => {};
  onDeleteAccompaniment: (assetId: string) => void = (_assetId: string): void => {};
  onExportAccompaniment: (asset: AccompanimentAsset) => void = (_asset: AccompanimentAsset): void => {};
  @Prop @Watch('onFavoritesChanged') favorites: Song[] = [];
  @Prop @Watch('onLocalSongsChanged') localSongs: Song[] = [];
  @Prop @Watch('onPlayHistoryChanged') playHistory: Song[] = [];
  @Prop totalSongCount: number = 0;
  @Prop latencyMs: number = 25;
  @Prop fastMode: boolean = false;
  @Prop expanded: boolean = false;
  @Prop recordingDir: string = '';
  @Prop musicSourceMode: MusicSourceMode = MusicSourceMode.ONLINE;
  @Prop customMusicServerUrl: string = '';
  @Prop qqMusicApiKey: string = '';
  @Prop currentSongId: string = '';
  @Prop isPlaying: boolean = false;
  @Prop isCloudLoggedIn: boolean = false;
  @Prop currentUserNickname: string = '';
  @Prop currentUserUsername: string = '';
  @Prop isSyncingCloud: boolean = false;
  @Prop cloudSyncStatusText: string = '';
  @State selectedSubTab: number = 0; // 0: 歌单/收藏, 1: 本地音乐与伴奏, 2: 历史播放
  @State localCategoryFilter: number = 0; // 0: 全部, 1: AI伴奏, 2: K歌录音, 3: 外部导入
  @State isBatchMode: boolean = false;
  @State selectedSongIds: string[] = [];
  @State focusedSubTab: number = -1;
  @State focusedRowSongId: string = '';
  @State focusedActionBtn: string = '';
  @State showSettingsModal: boolean = false;
  @State showAudioDevicesModal: boolean = false;
  @State showAuthModal: boolean = false;
  @State authTab: number = 0; // 0: 登录, 1: 注册
  @State authUsername: string = '';
  @State authPassword: string = '';
  @State authNickname: string = '';
  @State authLoading: boolean = false;
  @State authErrorMsg: string = '';

  onSelectSong: (song: Song, queueSource?: string) => void = (_song: Song, _queueSource?: string): void => {};
  onRemoveFavorite: (song: Song) => void = (_song: Song): void => {};
  onRemoveLocal: (song: Song) => void = (_song: Song): void => {};
  onExportSong: (song: Song) => void = (_song: Song): void => {};
  onBatchRemoveFavorites: (songIds: string[]) => void = (_songIds: string[]): void => {};
  onBatchRemoveLocal: (songIds: string[]) => void = (_songIds: string[]): void => {};
  onBatchRemoveHistory: (songIds: string[]) => void = (_songIds: string[]): void => {};
  onImportLocal: () => void = (): void => {};
  onSelectRecordingDir: () => void = (): void => {};
  onUpdateRecordingDir: (path: string) => void = (_path: string): void => {};
  onResetRecordingDir: () => void = (): void => {};
  onUpdateMusicSourceMode: (mode: MusicSourceMode) => Promise<void> = async () => {};
  onTestEngineConnection: () => Promise<MusicServerTestResult> = async () => DEFAULT_SERVER_TEST_FAIL;
  onTestHuibqConnection: () => Promise<MusicServerTestResult> = async () => DEFAULT_SERVER_TEST_FAIL;
  onUpdateCustomMusicServerUrl: (url: string) => Promise<boolean> = async () => false;
  onClearCustomMusicServerUrl: () => Promise<void> = async () => {};
  onTestCustomMusicServerUrl: (url: string) => Promise<MusicServerTestResult> = async () => DEFAULT_SERVER_TEST_FAIL;
  onUpdateQQMusicApiKey: (key: string) => Promise<boolean> = async () => false;
  onClearQQMusicApiKey: () => Promise<void> = async () => {};
  onClearHistory: () => void = (): void => {};
  onGoLibrary: () => void = (): void => {};
  onSearchArtist?: (artist: string) => void = (_artist: string): void => {};
  onLoginCloud: (username: string, password: string) => Promise<boolean> = async () => false;
  onRegisterCloud: (username: string, password: string, nickname?: string) => Promise<boolean> = async () => false;
  onLogoutCloud: () => void = (): void => {};
  onSyncCloud: () => void = (): void => {};

  private favDataSource: ArrayDataSource<Song> = new ArrayDataSource<Song>();
  private localDataSource: ArrayDataSource<Song> = new ArrayDataSource<Song>();
  private historyDataSource: ArrayDataSource<Song> = new ArrayDataSource<Song>();
  private contentScroller: Scroller = new Scroller();

  private onFavoritesChanged(): void {
    this.favDataSource.setData(this.favorites);
  }

  private onLocalSongsChanged(): void {
    this.localDataSource.setData(this.localSongs);
  }

  private onPlayHistoryChanged(): void {
    this.historyDataSource.setData(this.playHistory);
  }

  aboutToAppear(): void {
    this.favDataSource.setData(this.favorites);
    this.localDataSource.setData(this.localSongs);
    this.historyDataSource.setData(this.playHistory);
  }

  private durationLabel(durationMs: number): string {
    if (durationMs <= 0) return '--:--';
    const seconds = Math.floor(durationMs / 1000);
    return `${Math.floor(seconds / 60)}:${(seconds % 60).toString().padStart(2, '0')}`;
  }

  isRecordingSong(song: Song): boolean {
    return song.id.startsWith('rec_') ||
      song.album === 'PivoMic 录音作品库' ||
      song.title.includes('(我的录音)') ||
      song.artist === '我 (本地作品)';
  }

  getRecordingSongs(): Song[] {
    return this.localSongs.filter((s: Song) => this.isRecordingSong(s));
  }

  getImportedSongs(): Song[] {
    return this.localSongs.filter((s: Song) => !this.isRecordingSong(s));
  }

  getTotalLocalCount(): number {
    return this.accompanimentAssets.length + this.localSongs.length;
  }

  private getAllLocalIds(): string[] {
    if (this.localCategoryFilter === 0) {
      return [...this.accompanimentAssets.map(a => a.id), ...this.localSongs.map(s => s.id)];
    } else if (this.localCategoryFilter === 1) {
      return this.accompanimentAssets.map(a => a.id);
    } else if (this.localCategoryFilter === 2) {
      return this.getRecordingSongs().map(s => s.id);
    } else {
      return this.getImportedSongs().map(s => s.id);
    }
  }

  private getCurrentList(): Song[] {
    if (this.selectedSubTab === 0) return this.favorites;
    if (this.selectedSubTab === 1) {
      if (this.localCategoryFilter === 2) return this.getRecordingSongs();
      if (this.localCategoryFilter === 3) return this.getImportedSongs();
      return this.localSongs;
    }
    return this.playHistory;
  }

  private toggleSelectSong(songId: string): void {
    const idx = this.selectedSongIds.indexOf(songId);
    if (idx >= 0) {
      this.selectedSongIds.splice(idx, 1);
    } else {
      this.selectedSongIds.push(songId);
    }
  }

  private isAllSelected(): boolean {
    if (this.selectedSubTab === 1) {
      const ids = this.getAllLocalIds();
      if (ids.length === 0) return false;
      return ids.every(id => this.selectedSongIds.includes(id));
    }
    const currentList = this.getCurrentList();
    if (currentList.length === 0) return false;
    return currentList.every((s: Song) => this.selectedSongIds.includes(s.id));
  }

  private toggleSelectAll(): boolean {
    if (this.selectedSubTab === 1) {
      const ids = this.getAllLocalIds();
      if (this.isAllSelected()) {
        this.selectedSongIds = [];
      } else {
        this.selectedSongIds = [...ids];
      }
      return true;
    }
    const currentList = this.getCurrentList();
    if (this.isAllSelected()) {
      this.selectedSongIds = [];
    } else {
      this.selectedSongIds = currentList.map((s: Song) => s.id);
    }
    return true;
  }

  private confirmDeleteAccompaniment(asset: AccompanimentAsset): void {
    AlertDialog.show({
      title: '删除 AI 伴奏',
      message: `确定要删除「${asset.song.title}」的 AI 伴奏文件吗？\n伴奏将被永久移除，原歌曲仍将保留。`,
      primaryButton: {
        value: '取消',
        fontColor: PivoTheme.textMuted,
        action: () => {}
      },
      secondaryButton: {
        value: '确认删除',
        fontColor: '#EF4444',
        action: () => {
          this.onDeleteAccompaniment(asset.id);
          promptAction.showToast({ message: '伴奏已删除' });
        }
      }
    });
  }

  private confirmDeleteLocalSong(song: Song): void {
    const isRec = this.isRecordingSong(song);
    AlertDialog.show({
      title: isRec ? '删除录音作品' : '移除本地歌曲',
      message: isRec
        ? `确定删除录音作品「${song.title}」吗？\n录音音频文件将从本地存储中彻底移除。`
        : `确定从本地列表中移除「${song.title}」吗？`,
      primaryButton: {
        value: '取消',
        fontColor: PivoTheme.textMuted,
        action: () => {}
      },
      secondaryButton: {
        value: '确认删除',
        fontColor: '#EF4444',
        action: () => {
          this.onRemoveLocal(song);
          promptAction.showToast({ message: isRec ? '录音作品已删除' : '已从本地移除' });
        }
      }
    });
  }

  private promptBatchDelete(): void {
    if (this.selectedSongIds.length === 0) return;
    const tabName = this.selectedSubTab === 0 ? '收藏歌单' : (this.selectedSubTab === 1 ? '本地伴奏与作品' : '播放历史');
    AlertDialog.show({
      title: '确认删除',
      message: `确定要从「${tabName}」中删除选中的 ${this.selectedSongIds.length} 项内容吗？`,
      primaryButton: {
        value: '取消',
        fontColor: '#AAAAAA',
        action: () => {}
      },
      secondaryButton: {
        value: '确认删除',
        fontColor: '#EF4444',
        action: () => {
          if (this.selectedSubTab === 0) {
            this.onBatchRemoveFavorites(this.selectedSongIds);
          } else if (this.selectedSubTab === 1) {
            const songIds = this.selectedSongIds.filter(id => this.localSongs.some(s => s.id === id));
            const assetIds = this.selectedSongIds.filter(id => this.accompanimentAssets.some(a => a.id === id));
            if (songIds.length > 0) {
              this.onBatchRemoveLocal(songIds);
            }
            if (assetIds.length > 0) {
              for (const aid of assetIds) {
                this.onDeleteAccompaniment(aid);
              }
            }
          } else if (this.selectedSubTab === 2) {
            this.onBatchRemoveHistory(this.selectedSongIds);
          }
          this.selectedSongIds = [];
          this.isBatchMode = false;
        }
      }
    });
  }

  private promptClearHistory(): void {
    AlertDialog.show({
      title: '清空播放历史',
      message: '确定要清空所有的最近播放历史记录吗？',
      primaryButton: {
        value: '取消',
        fontColor: '#AAAAAA',
        action: () => {}
      },
      secondaryButton: {
        value: '清空',
        fontColor: '#EF4444',
        action: () => {
          this.onClearHistory();
        }
      }
    });
  }

  @Builder
  songRow(song: Song, type: 'fav' | 'local' | 'history') {
    Row({ space: 12 }) {
      // 1. Batch Selection Checkbox
      if (this.isBatchMode) {
        Stack({ alignContent: Alignment.Center }) {
          if (this.selectedSongIds.includes(song.id)) {
            Row() {
              Text('✓')
                .fontSize(13)
                .fontWeight(FontWeight.Bold)
                .fontColor(PivoTheme.primaryTextDark)
            }
            .width(22)
            .height(22)
            .borderRadius(11)
            .backgroundColor(PivoTheme.primary)
            .justifyContent(FlexAlign.Center)
          } else {
            Row()
              .width(22)
              .height(22)
              .borderRadius(11)
              .border({ width: 1.5, color: PivoTheme.textMuted })
          }
        }
        .width(24)
        .height(24)
      }

      // 2. Cover Image / Fallback Icon
      if ((song.coverUrl ?? '').length > 0) {
        Image(song.coverUrl)
          .width(48)
          .height(48)
          .objectFit(ImageFit.Cover)
          .borderRadius(10)
      } else {
        Column({ space: 2 }) {
          Text(type === 'local' ? '📁' : (type === 'fav' ? '★' : '⏱️'))
            .fontSize(15)
            .fontColor(PivoTheme.primary)
          Text(song.source === MusicSourceKind.LOCAL ? '本地' : (song.provider?.toUpperCase() ?? '云端'))
            .fontSize(8)
            .fontWeight(FontWeight.Bold)
            .fontColor(PivoTheme.textMuted)
        }
        .width(48)
        .height(48)
        .justifyContent(FlexAlign.Center)
        .backgroundColor(PivoTheme.surfaceCircle)
        .borderRadius(10)
      }

      // 3. Song Info
      Column({ space: 4 }) {
        Row({ space: 6 }) {
          Text(song.title)
            .fontSize(14)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.currentSongId === song.id ? PivoTheme.primary : (this.focusedRowSongId === song.id ? PivoTheme.primary : PivoTheme.text))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)

          if (type === 'local') {
            if (this.isRecordingSong(song)) {
              Text('🎙️ K歌录音')
                .fontSize(9)
                .fontWeight(FontWeight.Bold)
                .fontColor('#8B5CF6')
                .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                .backgroundColor('rgba(139, 92, 246, 0.12)')
                .borderRadius(4)
            } else {
              Text('📂 外部导入')
                .fontSize(9)
                .fontWeight(FontWeight.Bold)
                .fontColor('#F59E0B')
                .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                .backgroundColor('rgba(245, 158, 11, 0.12)')
                .borderRadius(4)
            }
          }

          if (this.currentSongId === song.id) {
            Row({ space: 4 }) {
              Text(this.isPlaying ? '▶' : '❚❚')
                .fontSize(9)
                .fontColor(PivoTheme.primary)
              Text(this.isPlaying ? '正在播放' : '已暂停')
                .fontSize(10)
                .fontWeight(FontWeight.Bold)
                .fontColor(PivoTheme.primary)
            }
            .padding({ left: 8, right: 8, top: 2, bottom: 2 })
            .backgroundColor(PivoTheme.surfaceSelected)
            .borderRadius(10)
            .border({ width: 1, color: PivoTheme.borderGlow })
          }
        }
        .width('100%')

        Row({ space: 6 }) {
          Text(song.artist)
            .fontSize(11)
            .fontColor(this.currentSongId === song.id ? PivoTheme.primaryTextSoft : PivoTheme.textSecondary)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
            .padding({ left: 3, right: 3, top: 1, bottom: 1 })
            .borderRadius(3)

          Text('·')
            .fontSize(10)
            .fontColor(PivoTheme.textFaint)

          Text(this.durationLabel(song.durationMs))
            .fontSize(10)
            .fontColor(PivoTheme.textMuted)
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      // 4. Action Buttons (Export & Delete)
      if (!this.isBatchMode && type === 'local') {
        Row({ space: 6 }) {
          if (this.isRecordingSong(song) || song.format.toLowerCase() === 'wav') {
            Button() {
              Row({ space: 3 }) {
                Text('📤')
                  .fontSize(10)
                Text('导出')
                  .fontSize(11)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(PivoTheme.text)
              }
            }
            .height(28)
            .padding({ left: 8, right: 8 })
            .backgroundColor(PivoTheme.surface)
            .borderRadius(14)
            .border({ width: 1, color: PivoTheme.border })
            .onClick(() => this.onExportSong(song))
          }

          Button() {
            Text('🗑️')
              .fontSize(11)
              .fontColor(PivoTheme.danger)
          }
          .height(28)
          .width(28)
          .backgroundColor(PivoTheme.surface)
          .borderRadius(14)
          .border({ width: 1, color: PivoTheme.border })
          .onClick(() => this.confirmDeleteLocalSong(song))
        }
      }
    }
    .width('100%')
    .padding(10)
    .borderRadius(14)
    .backgroundColor(this.currentSongId === song.id ? PivoTheme.surfaceActive : (this.focusedRowSongId === song.id ? PivoTheme.surfaceSelected : (this.isBatchMode && this.selectedSongIds.includes(song.id) ? PivoTheme.surfaceSelectedSubtle : PivoTheme.surfaceRaised)))
    .border({
      width: (this.focusedRowSongId === song.id || this.currentSongId === song.id) ? 2 : 1,
      color: (this.focusedRowSongId === song.id || this.currentSongId === song.id) ? PivoTheme.primary : (this.isBatchMode && this.selectedSongIds.includes(song.id) ? PivoTheme.primary : PivoTheme.border)
    })
    .scale({ x: this.focusedRowSongId === song.id ? 1.02 : 1.0, y: this.focusedRowSongId === song.id ? 1.02 : 1.0 })
    .clip(true)
    .focusable(true)
    .onFocus(() => {
      this.focusedRowSongId = song.id;
    })
    .onBlur(() => {
      if (this.focusedRowSongId === song.id) this.focusedRowSongId = '';
    })
    .onClick(() => {
      if (this.isBatchMode) {
        this.toggleSelectSong(song.id);
      } else {
        this.onSelectSong(song, this.selectedSubTab === 0 ? 'favorites' : (this.selectedSubTab === 1 ? 'local' : 'history'));
      }
    })
    .gesture(
      LongPressGesture({ repeat: false, duration: 400 })
        .onAction((_event: GestureEvent) => {
          if (this.isBatchMode) return;
          if (song.artist && isValidArtist(song.artist)) {
            if (this.onSearchArtist) {
              promptAction.showToast({ message: `正在搜索作者：${song.artist}` });
              this.onSearchArtist(song.artist);
            }
          } else {
            promptAction.showToast({ message: '该歌曲暂无有效作者信息' });
          }
        })
    )
  }

  @Builder
  accompanimentRow(asset: AccompanimentAsset) {
    Row({ space: 12 }) {
      // 1. Batch Selection Checkbox
      if (this.isBatchMode) {
        Stack({ alignContent: Alignment.Center }) {
          if (this.selectedSongIds.includes(asset.id)) {
            Row() {
              Text('✓')
                .fontSize(13)
                .fontWeight(FontWeight.Bold)
                .fontColor(PivoTheme.primaryTextDark)
            }
            .width(22)
            .height(22)
            .borderRadius(11)
            .backgroundColor(PivoTheme.primary)
            .justifyContent(FlexAlign.Center)
          } else {
            Row()
              .width(22)
              .height(22)
              .borderRadius(11)
              .border({ width: 1.5, color: PivoTheme.textMuted })
          }
        }
        .width(24)
        .height(24)
      }

      // 2. Icon / Badge
      Column({ space: 2 }) {
        Text('🤖')
          .fontSize(16)
        Text('伴奏')
          .fontSize(8)
          .fontWeight(FontWeight.Bold)
          .fontColor('#10B981')
      }
      .width(48)
      .height(48)
      .justifyContent(FlexAlign.Center)
      .backgroundColor('rgba(16, 185, 129, 0.1)')
      .borderRadius(10)

      // 3. Info
      Column({ space: 4 }) {
        Row({ space: 6 }) {
          Text(asset.song.title)
            .fontSize(14)
            .fontWeight(FontWeight.Bold)
            .fontColor(PivoTheme.text)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)

          Text('🤖 AI伴奏')
            .fontSize(9)
            .fontWeight(FontWeight.Bold)
            .fontColor('#10B981')
            .padding({ left: 6, right: 6, top: 2, bottom: 2 })
            .backgroundColor('rgba(16, 185, 129, 0.12)')
            .borderRadius(4)
        }
        .width('100%')

        Row({ space: 6 }) {
          Text(asset.song.artist)
            .fontSize(11)
            .fontColor(PivoTheme.textSecondary)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })

          Text('·')
            .fontSize(10)
            .fontColor(PivoTheme.textFaint)

          Text(`${(asset.frameCount * 4 / 1000000).toFixed(1)} MB`)
            .fontSize(10)
            .fontColor(PivoTheme.textMuted)
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      // 4. Action buttons
      if (!this.isBatchMode) {
        Row({ space: 6 }) {
          Button() {
            Row({ space: 3 }) {
              Text('▶')
                .fontSize(9)
                .fontColor(PivoTheme.primaryTextDark)
              Text('播放')
                .fontSize(11)
                .fontWeight(FontWeight.Medium)
                .fontColor(PivoTheme.primaryTextDark)
            }
          }
          .height(28)
          .padding({ left: 8, right: 8 })
          .backgroundColor(PivoTheme.primary)
          .borderRadius(14)
          .onClick(() => {
            this.onPlayAccompaniment(asset);
          })

          Button() {
            Row({ space: 3 }) {
              Text('📤')
                .fontSize(10)
              Text('导出')
                .fontSize(11)
                .fontWeight(FontWeight.Medium)
                .fontColor(PivoTheme.text)
            }
          }
          .height(28)
          .padding({ left: 8, right: 8 })
          .backgroundColor(PivoTheme.surface)
          .borderRadius(14)
          .border({ width: 1, color: PivoTheme.border })
          .onClick(() => {
            this.onExportAccompaniment(asset);
          })

          Button() {
            Text('🗑️')
              .fontSize(11)
              .fontColor(PivoTheme.danger)
          }
          .height(28)
          .width(28)
          .backgroundColor(PivoTheme.surface)
          .borderRadius(14)
          .border({ width: 1, color: PivoTheme.border })
          .onClick(() => {
            this.confirmDeleteAccompaniment(asset);
          })
        }
      }
    }
    .width('100%')
    .padding(10)
    .borderRadius(14)
    .backgroundColor(this.isBatchMode && this.selectedSongIds.includes(asset.id) ? PivoTheme.surfaceSelectedSubtle : PivoTheme.surfaceRaised)
    .border({
      width: 1,
      color: this.isBatchMode && this.selectedSongIds.includes(asset.id) ? PivoTheme.primary : PivoTheme.border
    })
    .onClick(() => {
      if (this.isBatchMode) {
        this.toggleSelectSong(asset.id);
      } else {
        this.onPlayAccompaniment(asset);
      }
    })
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      Column() {
        // 固定头部：个人信息与设置卡片 + 收藏/本地/历史 Tab 切换栏
        Column({ space: 10 }) {
          // 1. Unified User Profile & Cloud Sync Bar
          Row({ space: 10 }) {
            // Left: Avatar Icon with Cloud Status Indicator
            Stack({ alignContent: Alignment.BottomEnd }) {
              Stack({ alignContent: Alignment.Center }) {
                Text('🎤')
                  .fontSize(20)
              }
              .width(42)
              .height(42)
              .borderRadius(21)
              .backgroundColor(PivoTheme.surfaceSelected)
              .border({ width: 1.2, color: PivoTheme.primary })

              if (this.isCloudLoggedIn) {
                Row()
                  .width(10)
                  .height(10)
                  .borderRadius(5)
                  .backgroundColor(PivoTheme.primary)
                  .border({ width: 1.5, color: PivoTheme.surfaceRaised })
              }
            }
            .width(42)
            .height(42)

            // Middle: User Info & Auto Cloud Sync Status
            Column({ space: 3 }) {
              Text(this.isCloudLoggedIn ? (this.currentUserNickname || this.currentUserUsername) : 'PivoMic 个人中心')
                .fontSize(14)
                .fontWeight(FontWeight.Bold)
                .fontColor(this.isCloudLoggedIn ? PivoTheme.primary : PivoTheme.text)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })

              Row({ space: 4 }) {
                Text('48kHz 演播级')
                  .fontSize(10)
                  .fontColor(PivoTheme.textMuted)
                  .maxLines(1)

                Text('·')
                  .fontSize(10)
                  .fontColor(PivoTheme.textFaint)

                Text(this.isCloudLoggedIn ? (this.cloudSyncStatusText || '云端已同步') : '高保真曲库 · 收藏自动同步')
                  .fontSize(10)
                  .fontColor(this.isCloudLoggedIn ? PivoTheme.primary : PivoTheme.textMuted)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .layoutWeight(1)
              }
              .width('100%')
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)

            // Right: Actions (登录/退出 与 统一系统设置)
            Row({ space: 8 }) {
              if (this.isCloudLoggedIn) {
                Button('退出')
                  .height(28)
                  .padding({ left: 10, right: 10 })
                  .fontSize(11)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(PivoTheme.textMuted)
                  .backgroundColor(PivoTheme.surface)
                  .borderRadius(14)
                  .border({ width: 0.8, color: PivoTheme.border })
                  .onClick(() => {
                    this.onLogoutCloud();
                    promptAction.showToast({ message: '已退出账号' });
                  })
              } else {
                Button('登录/注册')
                  .height(28)
                  .padding({ left: 10, right: 10 })
                  .fontSize(11)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(PivoTheme.primaryTextDark)
                  .backgroundColor(PivoTheme.primary)
                  .borderRadius(14)
                  .onClick(() => {
                    this.authErrorMsg = '';
                    this.showAuthModal = true;
                  })
              }

              Button() {
                Row({ space: 4 }) {
                  Text('⚙️')
                    .fontSize(13)
                  Text('设置')
                    .fontSize(11)
                    .fontWeight(FontWeight.Bold)
                    .fontColor(PivoTheme.primaryTextDark)
                }
              }
              .height(28)
              .padding({ left: 10, right: 12 })
              .backgroundColor(PivoTheme.primary)
              .borderRadius(14)
              .onClick(() => {
                this.showSettingsModal = true;
              })
            }
          }
          .width('100%')
          .padding({ left: 12, right: 12, top: 10, bottom: 10 })
          .backgroundColor(PivoTheme.surfaceRaised)
          .borderRadius(16)
          .border({ width: 1, color: this.isCloudLoggedIn ? PivoTheme.borderGlow : PivoTheme.border })

          // 2. Subtabs Switcher (3 equal tabs with layoutWeight(1) to prevent overflow on mobile)
          Row({ space: this.expanded ? 16 : 8 }) {
            // Tab 0: 歌单 / 收藏
            Button({ type: ButtonType.Normal, stateEffect: false }) {
              Column({ space: 4 }) {
                Text(this.expanded ? `我的收藏 (${this.favorites.length})` : `收藏 (${this.favorites.length})`)
                  .fontSize(this.expanded ? 15 : 13)
                  .fontWeight(this.selectedSubTab === 0 || this.focusedSubTab === 0 ? FontWeight.Bold : FontWeight.Medium)
                  .fontColor(this.selectedSubTab === 0 || this.focusedSubTab === 0 ? PivoTheme.primary : PivoTheme.textNavInactive)
                  .maxLines(1)

                if (this.selectedSubTab === 0) {
                  Row()
                    .width(22)
                    .height(3)
                    .borderRadius(1.5)
                    .backgroundColor(PivoTheme.primary)
                    .shadow({ radius: 6, color: PivoTheme.primaryGlow })
                } else {
                  Row().width(22).height(3).backgroundColor(Color.Transparent)
                }
              }
              .width('100%')
              .alignItems(HorizontalAlign.Center)
              .padding({ top: 4, bottom: 4 })
            }
            .layoutWeight(1)
            .backgroundColor(Color.Transparent)
            .borderRadius(8)
            .border({
              width: this.focusedSubTab === 0 ? 1.5 : 0,
              color: PivoTheme.primary
            })
            .focusable(true)
            .id('profile_subtab_0')
            .onFocus(() => {
              this.focusedSubTab = 0;
            })
            .onBlur(() => {
              if (this.focusedSubTab === 0) this.focusedSubTab = -1;
            })
            .onClick(() => {
              this.selectedSubTab = 0;
              this.isBatchMode = false;
              this.selectedSongIds = [];
              this.contentScroller.scrollTo({ xOffset: 0, yOffset: 0 });
            })

            // Tab 1: 本地音乐
            Button({ type: ButtonType.Normal, stateEffect: false }) {
              Column({ space: 4 }) {
                Text(this.expanded ? `本地伴奏与作品 (${this.getTotalLocalCount()})` : `本地 (${this.getTotalLocalCount()})`)
                  .fontSize(this.expanded ? 15 : 13)
                  .fontWeight(this.selectedSubTab === 1 || this.focusedSubTab === 1 ? FontWeight.Bold : FontWeight.Medium)
                  .fontColor(this.selectedSubTab === 1 || this.focusedSubTab === 1 ? PivoTheme.primary : PivoTheme.textNavInactive)
                  .maxLines(1)

                if (this.selectedSubTab === 1) {
                  Row()
                    .width(22)
                    .height(3)
                    .borderRadius(1.5)
                    .backgroundColor(PivoTheme.primary)
                    .shadow({ radius: 6, color: PivoTheme.primaryGlow })
                } else {
                  Row().width(22).height(3).backgroundColor(Color.Transparent)
                }
              }
              .width('100%')
              .alignItems(HorizontalAlign.Center)
              .padding({ top: 4, bottom: 4 })
            }
            .layoutWeight(1)
            .backgroundColor(Color.Transparent)
            .borderRadius(8)
            .border({
              width: this.focusedSubTab === 1 ? 1.5 : 0,
              color: PivoTheme.primary
            })
            .focusable(true)
            .id('profile_subtab_1')
            .onFocus(() => {
              this.focusedSubTab = 1;
            })
            .onBlur(() => {
              if (this.focusedSubTab === 1) this.focusedSubTab = -1;
            })
            .onClick(() => {
              this.selectedSubTab = 1;
              this.isBatchMode = false;
              this.selectedSongIds = [];
              this.contentScroller.scrollTo({ xOffset: 0, yOffset: 0 });
            })

            // Tab 2: 历史播放
            Button({ type: ButtonType.Normal, stateEffect: false }) {
              Column({ space: 4 }) {
                Text(this.expanded ? `播放历史 (${this.playHistory.length})` : `历史 (${this.playHistory.length})`)
                  .fontSize(this.expanded ? 15 : 13)
                  .fontWeight(this.selectedSubTab === 2 || this.focusedSubTab === 2 ? FontWeight.Bold : FontWeight.Medium)
                  .fontColor(this.selectedSubTab === 2 || this.focusedSubTab === 2 ? PivoTheme.primary : PivoTheme.textNavInactive)
                  .maxLines(1)

                if (this.selectedSubTab === 2) {
                  Row()
                    .width(22)
                    .height(3)
                    .borderRadius(1.5)
                    .backgroundColor(PivoTheme.primary)
                    .shadow({ radius: 6, color: PivoTheme.primaryGlow })
                } else {
                  Row().width(22).height(3).backgroundColor(Color.Transparent)
                }
              }
              .width('100%')
              .alignItems(HorizontalAlign.Center)
              .padding({ top: 4, bottom: 4 })
            }
            .layoutWeight(1)
            .backgroundColor(Color.Transparent)
            .borderRadius(8)
            .border({
              width: this.focusedSubTab === 2 ? 1.5 : 0,
              color: PivoTheme.primary
            })
            .focusable(true)
            .id('profile_subtab_2')
            .onFocus(() => {
              this.focusedSubTab = 2;
            })
            .onBlur(() => {
              if (this.focusedSubTab === 2) this.focusedSubTab = -1;
            })
            .onClick(() => {
              this.selectedSubTab = 2;
              this.isBatchMode = false;
              this.selectedSongIds = [];
              this.contentScroller.scrollTo({ xOffset: 0, yOffset: 0 });
            })
          }
          .width('100%')
          .padding({ top: 2, bottom: 2 })
        }
        .width('100%')
        .padding(this.expanded ?
          { left: 32, right: 32, top: 6, bottom: 2 } :
          { left: 16, right: 16, top: 4, bottom: 2 })
        .backgroundColor(PivoTheme.background)

        // 下方独立滚动内容区
        Scroll(this.contentScroller) {
          Column({ space: 16 }) {
            // ==================== TAB 0: 收藏歌单 ====================
          if (this.selectedSubTab === 0) {
            Row() {
              Text('我喜欢的歌曲')
                .fontSize(15)
                .fontWeight(FontWeight.Bold)
                .fontColor(PivoTheme.text)

              Blank()

              Row({ space: 10 }) {
                if (this.favorites.length > 0) {
                  Text(this.isBatchMode ? '完成' : '批量管理')
                    .fontSize(12)
                    .fontWeight(FontWeight.Medium)
                    .fontColor(this.isBatchMode || this.focusedActionBtn === 'batch0' ? PivoTheme.primary : PivoTheme.textSecondary)
                    .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                    .borderRadius(4)
                    .border({
                      width: this.focusedActionBtn === 'batch0' ? 1.5 : 0,
                      color: PivoTheme.primary
                    })
                    .focusable(true)
                    .onFocus(() => {
                      this.focusedActionBtn = 'batch0';
                    })
                    .onBlur(() => {
                      if (this.focusedActionBtn === 'batch0') this.focusedActionBtn = '';
                    })
                    .onClick(() => {
                      this.isBatchMode = !this.isBatchMode;
                      this.selectedSongIds = [];
                    })
                }

                if (!this.isBatchMode) {
                  Text('去选歌 ＋')
                    .fontSize(12)
                    .fontColor(PivoTheme.primary)
                    .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                    .borderRadius(4)
                    .border({
                      width: this.focusedActionBtn === 'go_lib0' ? 1.5 : 0,
                      color: PivoTheme.primary
                    })
                    .focusable(true)
                    .onFocus(() => {
                      this.focusedActionBtn = 'go_lib0';
                    })
                    .onBlur(() => {
                      if (this.focusedActionBtn === 'go_lib0') this.focusedActionBtn = '';
                    })
                    .onClick(() => this.onGoLibrary())
                }
              }
            }
            .width('100%')

            if (this.favorites.length === 0) {
              Column({ space: 10 }) {
                Text('🌟')
                  .fontSize(32)
                Text('暂无收藏歌曲')
                  .fontSize(14)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(PivoTheme.text)
                Text('在发现曲库中点击星号 ★ 即可收藏歌曲')
                  .fontSize(11)
                  .fontColor(PivoTheme.textMuted)

                Button('去发现曲库选歌')
                  .height(34)
                  .padding({ left: 18, right: 18 })
                  .fontSize(12)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(PivoTheme.primaryTextDark)
                  .backgroundColor(PivoTheme.primary)
                  .borderRadius(17)
                  .onClick(() => this.onGoLibrary())
              }
              .width('100%')
              .padding({ top: 28, bottom: 32 })
              .backgroundColor(PivoTheme.surfaceRaised)
              .borderRadius(16)
              .border({ width: 1, color: PivoTheme.border })
            } else {
              Column({ space: 8 }) {
                LazyForEach(this.favDataSource, (song: Song) => {
                  this.songRow(song, 'fav')
                }, (song: Song) => `fav-${song.id}`)
              }
              .width('100%')
            }
          }

          // ==================== TAB 1: 本地伴奏与作品分类管理 ====================
          if (this.selectedSubTab === 1) {
            // 1. 顶部分类胶囊标签切换栏 (全部 / AI伴奏 / K歌录音 / 外部导入)
            Row({ space: 8 }) {
              Button({ type: ButtonType.Normal, stateEffect: true }) {
                Row({ space: 4 }) {
                  Text('全部')
                    .fontSize(12)
                    .fontWeight(this.localCategoryFilter === 0 ? FontWeight.Bold : FontWeight.Normal)
                    .fontColor(this.localCategoryFilter === 0 ? PivoTheme.primaryTextDark : PivoTheme.text)
                  Text(`${this.getTotalLocalCount()}`)
                    .fontSize(10)
                    .fontColor(this.localCategoryFilter === 0 ? PivoTheme.primaryTextDark : PivoTheme.textMuted)
                }
                .padding({ left: 10, right: 10, top: 5, bottom: 5 })
              }
              .height(30)
              .backgroundColor(this.localCategoryFilter === 0 ? PivoTheme.primary : PivoTheme.surface)
              .borderRadius(15)
              .border({ width: 0.8, color: this.localCategoryFilter === 0 ? PivoTheme.primary : PivoTheme.border })
              .onClick(() => {
                this.localCategoryFilter = 0;
                this.selectedSongIds = [];
              })

              Button({ type: ButtonType.Normal, stateEffect: true }) {
                Row({ space: 4 }) {
                  Text('🤖 AI伴奏')
                    .fontSize(12)
                    .fontWeight(this.localCategoryFilter === 1 ? FontWeight.Bold : FontWeight.Normal)
                    .fontColor(this.localCategoryFilter === 1 ? '#FFFFFF' : '#10B981')
                  Text(`${this.accompanimentAssets.length}`)
                    .fontSize(10)
                    .fontColor(this.localCategoryFilter === 1 ? '#FFFFFF' : PivoTheme.textMuted)
                }
                .padding({ left: 10, right: 10, top: 5, bottom: 5 })
              }
              .height(30)
              .backgroundColor(this.localCategoryFilter === 1 ? '#10B981' : PivoTheme.surface)
              .borderRadius(15)
              .border({ width: 0.8, color: this.localCategoryFilter === 1 ? '#10B981' : PivoTheme.border })
              .onClick(() => {
                this.localCategoryFilter = 1;
                this.selectedSongIds = [];
              })

              Button({ type: ButtonType.Normal, stateEffect: true }) {
                Row({ space: 4 }) {
                  Text('🎙️ K歌录音')
                    .fontSize(12)
                    .fontWeight(this.localCategoryFilter === 2 ? FontWeight.Bold : FontWeight.Normal)
                    .fontColor(this.localCategoryFilter === 2 ? '#FFFFFF' : '#8B5CF6')
                  Text(`${this.getRecordingSongs().length}`)
                    .fontSize(10)
                    .fontColor(this.localCategoryFilter === 2 ? '#FFFFFF' : PivoTheme.textMuted)
                }
                .padding({ left: 10, right: 10, top: 5, bottom: 5 })
              }
              .height(30)
              .backgroundColor(this.localCategoryFilter === 2 ? '#8B5CF6' : PivoTheme.surface)
              .borderRadius(15)
              .border({ width: 0.8, color: this.localCategoryFilter === 2 ? '#8B5CF6' : PivoTheme.border })
              .onClick(() => {
                this.localCategoryFilter = 2;
                this.selectedSongIds = [];
              })

              Button({ type: ButtonType.Normal, stateEffect: true }) {
                Row({ space: 4 }) {
                  Text('📂 外部导入')
                    .fontSize(12)
                    .fontWeight(this.localCategoryFilter === 3 ? FontWeight.Bold : FontWeight.Normal)
                    .fontColor(this.localCategoryFilter === 3 ? '#FFFFFF' : '#F59E0B')
                  Text(`${this.getImportedSongs().length}`)
                    .fontSize(10)
                    .fontColor(this.localCategoryFilter === 3 ? '#FFFFFF' : PivoTheme.textMuted)
                }
                .padding({ left: 10, right: 10, top: 5, bottom: 5 })
              }
              .height(30)
              .backgroundColor(this.localCategoryFilter === 3 ? '#F59E0B' : PivoTheme.surface)
              .borderRadius(15)
              .border({ width: 0.8, color: this.localCategoryFilter === 3 ? '#F59E0B' : PivoTheme.border })
              .onClick(() => {
                this.localCategoryFilter = 3;
                this.selectedSongIds = [];
              })
            }
            .width('100%')

            // 2. 上下文操作栏
            Row() {
              Text(
                this.localCategoryFilter === 0 ? '本地伴奏与作品' :
                (this.localCategoryFilter === 1 ? 'AI 伴奏库' :
                (this.localCategoryFilter === 2 ? 'K歌录音作品' : '外部导入歌曲'))
              )
                .fontSize(15)
                .fontWeight(FontWeight.Bold)
                .fontColor(PivoTheme.text)

              Blank()

              Row({ space: 8 }) {
                if (this.getTotalLocalCount() > 0) {
                  Text(this.isBatchMode ? '完成' : '批量管理')
                    .fontSize(12)
                    .fontWeight(FontWeight.Medium)
                    .fontColor(this.isBatchMode || this.focusedActionBtn === 'batch1' ? PivoTheme.primary : PivoTheme.textSecondary)
                    .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                    .borderRadius(4)
                    .border({
                      width: this.focusedActionBtn === 'batch1' ? 1.5 : 0,
                      color: PivoTheme.primary
                    })
                    .focusable(true)
                    .onFocus(() => {
                      this.focusedActionBtn = 'batch1';
                    })
                    .onBlur(() => {
                      if (this.focusedActionBtn === 'batch1') this.focusedActionBtn = '';
                    })
                    .onClick(() => {
                      this.isBatchMode = !this.isBatchMode;
                      this.selectedSongIds = [];
                    })
                }

                if (!this.isBatchMode) {
                  if (this.localCategoryFilter === 1 || this.localCategoryFilter === 0) {
                    Button('✨ 制作新伴奏')
                      .height(30)
                      .padding({ left: 10, right: 10 })
                      .fontSize(11)
                      .fontWeight(FontWeight.Bold)
                      .fontColor(PivoTheme.primaryTextDark)
                      .backgroundColor(PivoTheme.primary)
                      .borderRadius(15)
                      .onClick(() => this.onAccompaniment())
                  }

                  if (this.localCategoryFilter === 3 || this.localCategoryFilter === 0) {
                    Button('📂 导入音频')
                      .height(30)
                      .padding({ left: 10, right: 10 })
                      .fontSize(11)
                      .fontWeight(FontWeight.Bold)
                      .fontColor(PivoTheme.text)
                      .backgroundColor(PivoTheme.surface)
                      .borderRadius(15)
                      .border({ width: 0.8, color: PivoTheme.border })
                      .onClick(() => this.onImportLocal())
                  }
                }
              }
            }
            .width('100%')

            // 3. 列表分类呈现
            // --- 分类 1: AI伴奏 ---
            if (this.localCategoryFilter === 1) {
              if (this.accompanimentAssets.length === 0) {
                Column({ space: 10 }) {
                  Text('🤖')
                    .fontSize(36)
                  Text('暂无 AI 伴奏')
                    .fontSize(14)
                    .fontWeight(FontWeight.Bold)
                    .fontColor(PivoTheme.text)
                  Text('选择曲库或本地任意歌曲，即可在端侧一键提取高质量伴奏')
                    .fontSize(11)
                    .fontColor(PivoTheme.textMuted)

                  Button('✨ 立即选择歌曲提取伴奏')
                    .height(34)
                    .padding({ left: 18, right: 18 })
                    .fontSize(12)
                    .fontWeight(FontWeight.Bold)
                    .fontColor(PivoTheme.primaryTextDark)
                    .backgroundColor(PivoTheme.primary)
                    .borderRadius(17)
                    .onClick(() => this.onAccompaniment())
                }
                .width('100%')
                .padding({ top: 32, bottom: 36 })
                .backgroundColor(PivoTheme.surfaceRaised)
                .borderRadius(16)
                .border({ width: 1, color: PivoTheme.border })
              } else {
                Column({ space: 8 }) {
                  ForEach(this.accompanimentAssets, (asset: AccompanimentAsset) => {
                    this.accompanimentRow(asset)
                  }, (asset: AccompanimentAsset) => `ai-${asset.id}`)
                }
                .width('100%')
              }
            } else if (this.localCategoryFilter === 2) {
              // --- 分类 2: K歌录音作品 ---
              if (this.getRecordingSongs().length === 0) {
                Column({ space: 10 }) {
                  Text('🎙️')
                    .fontSize(36)
                  Text('暂无 K 歌录音作品')
                    .fontSize(14)
                    .fontWeight(FontWeight.Bold)
                    .fontColor(PivoTheme.text)
                  Text('在播放界面开启录音功能，你的个人演播级单曲将保存在这里')
                    .fontSize(11)
                    .fontColor(PivoTheme.textMuted)

                  Button('🎤 去发现曲库点歌录音')
                    .height(34)
                    .padding({ left: 18, right: 18 })
                    .fontSize(12)
                    .fontWeight(FontWeight.Bold)
                    .fontColor(PivoTheme.primaryTextDark)
                    .backgroundColor(PivoTheme.primary)
                    .borderRadius(17)
                    .onClick(() => this.onGoLibrary())
                }
                .width('100%')
                .padding({ top: 32, bottom: 36 })
                .backgroundColor(PivoTheme.surfaceRaised)
                .borderRadius(16)
                .border({ width: 1, color: PivoTheme.border })
              } else {
                Column({ space: 8 }) {
                  ForEach(this.getRecordingSongs(), (song: Song) => {
                    this.songRow(song, 'local')
                  }, (song: Song) => `rec-${song.id}`)
                }
                .width('100%')
              }
            } else if (this.localCategoryFilter === 3) {
              // --- 分类 3: 外部导入歌曲 ---
              if (this.getImportedSongs().length === 0) {
                Column({ space: 10 }) {
                  Text('📂')
                    .fontSize(36)
                  Text('暂无外部导入音频')
                    .fontSize(14)
                    .fontWeight(FontWeight.Bold)
                    .fontColor(PivoTheme.text)
                  Text('支持从设备存储导入 MP3 / FLAC / WAV / M4A 音频')
                    .fontSize(11)
                    .fontColor(PivoTheme.textMuted)

                  Button('📂 立即选择本地文件')
                    .height(34)
                    .padding({ left: 18, right: 18 })
                    .fontSize(12)
                    .fontWeight(FontWeight.Bold)
                    .fontColor(PivoTheme.primaryTextDark)
                    .backgroundColor(PivoTheme.primary)
                    .borderRadius(17)
                    .onClick(() => this.onImportLocal())
                }
                .width('100%')
                .padding({ top: 32, bottom: 36 })
                .backgroundColor(PivoTheme.surfaceRaised)
                .borderRadius(16)
                .border({ width: 1, color: PivoTheme.border })
              } else {
                Column({ space: 8 }) {
                  ForEach(this.getImportedSongs(), (song: Song) => {
                    this.songRow(song, 'local')
                  }, (song: Song) => `imp-${song.id}`)
                }
                .width('100%')
              }
            } else {
              // --- 分类 0: 全部展示 ---
              if (this.getTotalLocalCount() === 0) {
                Column({ space: 10 }) {
                  Text('📁')
                    .fontSize(36)
                  Text('暂无本地伴奏与作品')
                    .fontSize(14)
                    .fontWeight(FontWeight.Bold)
                    .fontColor(PivoTheme.text)
                  Text('支持从设备导入外部音乐，或使用内置 AI 一键生成伴奏')
                    .fontSize(11)
                    .fontColor(PivoTheme.textMuted)

                  Row({ space: 10 }) {
                    Button('📂 导入外部音乐')
                      .height(34)
                      .padding({ left: 16, right: 16 })
                      .fontSize(12)
                      .fontWeight(FontWeight.Bold)
                      .fontColor(PivoTheme.primaryTextDark)
                      .backgroundColor(PivoTheme.primary)
                      .borderRadius(17)
                      .onClick(() => this.onImportLocal())

                    Button('✨ 制作 AI 伴奏')
                      .height(34)
                      .padding({ left: 16, right: 16 })
                      .fontSize(12)
                      .fontWeight(FontWeight.Medium)
                      .fontColor(PivoTheme.text)
                      .backgroundColor(PivoTheme.surface)
                      .borderRadius(17)
                      .border({ width: 1, color: PivoTheme.border })
                      .onClick(() => this.onAccompaniment())
                  }
                }
                .width('100%')
                .padding({ top: 32, bottom: 36 })
                .backgroundColor(PivoTheme.surfaceRaised)
                .borderRadius(16)
                .border({ width: 1, color: PivoTheme.border })
              } else {
                Column({ space: 8 }) {
                  // 先展示 AI 伴奏
                  ForEach(this.accompanimentAssets, (asset: AccompanimentAsset) => {
                    this.accompanimentRow(asset)
                  }, (asset: AccompanimentAsset) => `ai-${asset.id}`)

                  // 再展示本地作品与导入歌曲
                  LazyForEach(this.localDataSource, (song: Song) => {
                    this.songRow(song, 'local')
                  }, (song: Song) => `local-${song.id}`)
                }
                .width('100%')
              }
            }
          }

          // ==================== TAB 2: 历史播放 ====================
          if (this.selectedSubTab === 2) {
            Row() {
              Text('最近播放记录')
                .fontSize(15)
                .fontWeight(FontWeight.Bold)
                .fontColor(PivoTheme.text)

              Blank()

              Row({ space: 10 }) {
                if (this.playHistory.length > 0) {
                  Text(this.isBatchMode ? '完成' : '批量管理')
                    .fontSize(12)
                    .fontWeight(FontWeight.Medium)
                    .fontColor(this.isBatchMode || this.focusedActionBtn === 'batch2' ? PivoTheme.primary : PivoTheme.textSecondary)
                    .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                    .borderRadius(4)
                    .border({
                      width: this.focusedActionBtn === 'batch2' ? 1.5 : 0,
                      color: PivoTheme.primary
                    })
                    .focusable(true)
                    .onFocus(() => {
                      this.focusedActionBtn = 'batch2';
                    })
                    .onBlur(() => {
                      if (this.focusedActionBtn === 'batch2') this.focusedActionBtn = '';
                    })
                    .onClick(() => {
                      this.isBatchMode = !this.isBatchMode;
                      this.selectedSongIds = [];
                    })

                  if (!this.isBatchMode) {
                    Text('🗑️ 清空全部')
                      .fontSize(11)
                      .fontColor(this.focusedActionBtn === 'clear_hist' ? PivoTheme.primary : PivoTheme.textMuted)
                      .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                      .borderRadius(4)
                      .border({
                        width: this.focusedActionBtn === 'clear_hist' ? 1.5 : 0,
                        color: PivoTheme.primary
                      })
                      .focusable(true)
                      .onFocus(() => {
                        this.focusedActionBtn = 'clear_hist';
                      })
                      .onBlur(() => {
                        if (this.focusedActionBtn === 'clear_hist') this.focusedActionBtn = '';
                      })
                      .onClick(() => this.promptClearHistory())
                  }
                }
              }
            }
            .width('100%')

            if (this.playHistory.length === 0) {
              Column({ space: 10 }) {
                Text('⏱️')
                  .fontSize(32)
                Text('暂无播放历史')
                  .fontSize(14)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(PivoTheme.text)
                Text('在发现曲库听歌或演唱后会自动记录在这里')
                  .fontSize(11)
                  .fontColor(PivoTheme.textMuted)

                Button('去发现曲库听歌')
                  .height(34)
                  .padding({ left: 18, right: 18 })
                  .fontSize(12)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(PivoTheme.primaryTextDark)
                  .backgroundColor(PivoTheme.primary)
                  .borderRadius(17)
                  .onClick(() => this.onGoLibrary())
              }
              .width('100%')
              .padding({ top: 28, bottom: 32 })
              .backgroundColor(PivoTheme.surfaceRaised)
              .borderRadius(16)
              .border({ width: 1, color: PivoTheme.border })
            } else {
              Column({ space: 8 }) {
                LazyForEach(this.historyDataSource, (song: Song) => {
                  this.songRow(song, 'history')
                }, (song: Song) => `hist-${song.id}`)
              }
              .width('100%')
            }
          }

            if (this.isBatchMode) {
              Row().height(70)
            }
          }
          .width('100%')
          .constraintSize({ minHeight: '100%' })
          .padding(this.expanded ?
            { left: 32, right: 32, top: 12, bottom: 40 } :
            { left: 16, right: 16, top: 10, bottom: 96 })
          .alignItems(HorizontalAlign.Start)
          .justifyContent(FlexAlign.Start)
        }
        .align(Alignment.Top)
        .layoutWeight(1)
        .width('100%')
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)
      }
      .width('100%')
      .height('100%')

      // Floating Batch Action Bar (Pinned cleanly above bottom navigation)
      if (this.isBatchMode) {
        Row({ space: 10 }) {
          Button(this.isAllSelected() ? '取消全选' : '全选')
            .height(34)
            .fontSize(12)
            .backgroundColor(PivoTheme.surfaceRaised)
            .borderRadius(17)
            .fontColor(PivoTheme.text)
            .border({ width: 1, color: PivoTheme.border })
            .onClick(() => this.toggleSelectAll())

          Text(`已选 ${this.selectedSongIds.length} 首`)
            .fontSize(12)
            .fontColor(PivoTheme.textSecondary)

          Blank()

          Button(`🗑️ 删除 (${this.selectedSongIds.length})`)
            .height(34)
            .padding({ left: 16, right: 16 })
            .fontSize(12)
            .fontWeight(FontWeight.Bold)
            .fontColor('#FFFFFF')
            .backgroundColor(this.selectedSongIds.length > 0 ? '#EF4444' : 'rgba(239, 68, 68, 0.35)')
            .borderRadius(17)
            .enabled(this.selectedSongIds.length > 0)
            .onClick(() => {
              this.promptBatchDelete();
            })
        }
        .width(this.expanded ? '80%' : '92%')
        .padding({ left: 14, right: 14, top: 8, bottom: 8 })
        .margin({ bottom: this.expanded ? 20 : 72 })
        .backgroundColor(PivoTheme.surfaceRaised)
        .borderRadius(20)
        .border({ width: 1, color: PivoTheme.borderHighlight })
        .shadow({ radius: 20, color: 'rgba(120, 105, 85, 0.16)', offsetY: 4 })
      }



      // 登录与注册云端账号弹窗
      if (this.showAuthModal) {
        Stack({ alignContent: Alignment.Center }) {
          Row()
            .width('100%')
            .height('100%')
            .backgroundColor('rgba(98, 98, 98, 0.32)')
            .onClick(() => {
              this.showAuthModal = false;
            })

          Column({ space: 16 }) {
            // Header
            Row() {
              Text(this.authTab === 0 ? '🔑 登录云端账号' : '✨ 注册云端账号')
                .fontSize(17)
                .fontWeight(FontWeight.Bold)
                .fontColor(PivoTheme.text)

              Blank()

              Button('✕')
                .height(28)
                .width(28)
                .fontSize(14)
                .fontColor(PivoTheme.textMuted)
                .backgroundColor(Color.Transparent)
                .onClick(() => {
                  this.showAuthModal = false;
                })
            }
            .width('100%')

            // Tab Switcher (登录 / 注册)
            Row({ space: 8 }) {
              Button('账号登录')
                .layoutWeight(1)
                .height(32)
                .fontSize(13)
                .fontWeight(this.authTab === 0 ? FontWeight.Bold : FontWeight.Normal)
                .fontColor(this.authTab === 0 ? PivoTheme.primaryTextDark : PivoTheme.textSecondary)
                .backgroundColor(this.authTab === 0 ? PivoTheme.primary : PivoTheme.surface)
                .borderRadius(8)
                .onClick(() => {
                  this.authTab = 0;
                  this.authErrorMsg = '';
                })

              Button('新用户注册')
                .layoutWeight(1)
                .height(32)
                .fontSize(13)
                .fontWeight(this.authTab === 1 ? FontWeight.Bold : FontWeight.Normal)
                .fontColor(this.authTab === 1 ? PivoTheme.primaryTextDark : PivoTheme.textSecondary)
                .backgroundColor(this.authTab === 1 ? PivoTheme.primary : PivoTheme.surface)
                .borderRadius(8)
                .onClick(() => {
                  this.authTab = 1;
                  this.authErrorMsg = '';
                })
            }
            .width('100%')

            if (this.authErrorMsg.length > 0) {
              Text(this.authErrorMsg)
                .fontSize(12)
                .fontColor('#EF4444')
                .width('100%')
            }

            // Input Fields
            Column({ space: 10 }) {
              TextInput({ placeholder: '请输入用户名或手机号', text: this.authUsername })
                .height(42)
                .fontSize(13)
                .fontColor(PivoTheme.text)
                .placeholderColor(PivoTheme.textMuted)
                .backgroundColor(PivoTheme.surface)
                .borderRadius(8)
                .border({ width: 1, color: PivoTheme.border })
                .onChange((val: string) => {
                  this.authUsername = val;
                })

              TextInput({ placeholder: '请输入密码 (至少4位)', text: this.authPassword })
                .type(InputType.Password)
                .height(42)
                .fontSize(13)
                .fontColor(PivoTheme.text)
                .placeholderColor(PivoTheme.textMuted)
                .backgroundColor(PivoTheme.surface)
                .borderRadius(8)
                .border({ width: 1, color: PivoTheme.border })
                .onChange((val: string) => {
                  this.authPassword = val;
                })

              if (this.authTab === 1) {
                TextInput({ placeholder: '请输入昵称 (选填，默认同用户名)', text: this.authNickname })
                  .height(42)
                  .fontSize(13)
                  .fontColor(PivoTheme.text)
                  .placeholderColor(PivoTheme.textMuted)
                  .backgroundColor(PivoTheme.surface)
                  .borderRadius(8)
                  .border({ width: 1, color: PivoTheme.border })
                  .onChange((val: string) => {
                    this.authNickname = val;
                  })
              }
            }
            .width('100%')

            // Action Button
            Button(this.authLoading ? '请稍候…' : (this.authTab === 0 ? '立即登录' : '立即注册并登录'))
              .width('100%')
              .height(40)
              .fontSize(14)
              .fontWeight(FontWeight.Bold)
              .fontColor(PivoTheme.primaryTextDark)
              .backgroundColor(PivoTheme.primary)
              .borderRadius(20)
              .enabled(!this.authLoading)
              .onClick(async () => {
                if (this.authUsername.trim().length === 0 || this.authPassword.length === 0) {
                  this.authErrorMsg = '请填写完整的用户名和密码';
                  return;
                }
                this.authLoading = true;
                this.authErrorMsg = '';
                if (this.authTab === 0) {
                  const ok = await this.onLoginCloud(this.authUsername, this.authPassword);
                  this.authLoading = false;
                  if (ok) {
                    this.showAuthModal = false;
                    this.authUsername = '';
                    this.authPassword = '';
                  } else {
                    this.authErrorMsg = '登录失败，请检查用户名与密码';
                  }
                } else {
                  const ok = await this.onRegisterCloud(this.authUsername, this.authPassword, this.authNickname);
                  this.authLoading = false;
                  if (ok) {
                    this.showAuthModal = false;
                    this.authUsername = '';
                    this.authPassword = '';
                    this.authNickname = '';
                  } else {
                    this.authErrorMsg = '注册失败，用户名可能已存在';
                  }
                }
              })
          }
          .width(this.expanded ? '420vp' : '88%')
          .padding(22)
          .backgroundColor(PivoTheme.surfaceRaised)
          .borderRadius(20)
          .border({ width: 1, color: PivoTheme.borderHighlight })
          .shadow({ radius: 24, color: 'rgba(120, 105, 85, 0.18)' })
        }
        .width('100%')
        .height('100%')
        .position({ x: 0, y: 0 })
        .zIndex(998)
      }


      // 统一系统与服务设置抽屉
      AppSettingsModal({
        visible: this.showSettingsModal,
        expanded: this.expanded,
        musicSourceMode: this.musicSourceMode,
        customMusicServerUrl: this.customMusicServerUrl,
        qqMusicApiKey: this.qqMusicApiKey,
        recordingDir: this.recordingDir,
        latencyMs: this.latencyMs,
        fastMode: this.fastMode,
        isCloudLoggedIn: this.isCloudLoggedIn,
        currentUserNickname: this.currentUserNickname,
        currentUserUsername: this.currentUserUsername,
        isSyncingCloud: this.isSyncingCloud,
        cloudSyncStatusText: this.cloudSyncStatusText,
        onClose: () => {
          this.showSettingsModal = false;
        },
        onUpdateMusicSourceMode: this.onUpdateMusicSourceMode,
        onTestEngineConnection: this.onTestEngineConnection,
        onTestHuibqConnection: this.onTestHuibqConnection,
        onUpdateCustomMusicServerUrl: this.onUpdateCustomMusicServerUrl,
        onClearCustomMusicServerUrl: this.onClearCustomMusicServerUrl,
        onTestCustomMusicServerUrl: this.onTestCustomMusicServerUrl,
        onUpdateQQMusicApiKey: this.onUpdateQQMusicApiKey,
        onClearQQMusicApiKey: this.onClearQQMusicApiKey,
        onUpdateRecordingDir: this.onUpdateRecordingDir,
        onResetRecordingDir: this.onResetRecordingDir,
        onOpenAudioDevicesModal: () => {
          this.showAudioDevicesModal = true;
        },
        onOpenAuthModal: () => {
          this.authErrorMsg = '';
          this.showAuthModal = true;
        },
        onLogoutCloud: this.onLogoutCloud,
        onSyncCloud: this.onSyncCloud
      })

      // 音频设备管理与诊断弹窗
      AudioDevicesModal({
        visible: this.showAudioDevicesModal,
        onClose: () => {
          this.showAudioDevicesModal = false;
        }
      })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(PivoTheme.background)
  }
}
