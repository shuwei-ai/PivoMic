import { promptAction } from '@kit.ArkUI';
import { Song, RecommendPlaylist, PlaybackState, MusicSourceMode } from '../domain/MusicModels';
import { PivoTheme } from '../theme/PivoTheme';
import { SearchSourceOption, SEARCH_SOURCE_OPTIONS } from '../services/OnlineMusicSource';
import { ArrayDataSource } from '../domain/ArrayDataSource';

function formatDuration(ms: number): string {
  if (!ms || ms <= 0) return '03:30';
  const totalSec = Math.floor(ms / 1000);
  const m = Math.floor(totalSec / 60);
  const s = totalSec % 60;
  return `${m < 10 ? '0' : ''}${m}:${s < 10 ? '0' : ''}${s}`;
}

export interface CategoryTabItem {
  id: string;
  name: string;
}

function getSourceLabel(source: string): string {
  if (!source) return '精选';
  const lower = source.toLowerCase();
  if (lower === 'qq_skill' || lower === 'qq_ai' || lower === 'qq_chart') return 'QQ Skill';
  if (lower === 'netease' || lower.includes('163')) return '网易云';
  if (lower === 'qq' || lower.includes('tencent')) return 'QQ音乐';
  if (lower === 'kugou') return '酷狗';
  if (lower === 'kuwo') return '酷我';
  if (lower === 'migu') return '咪咕';
  if (lower === 'soda') return '汽水';
  if (lower === 'apple') return 'Apple';
  return source.toUpperCase();
}

function getSourceColor(source: string): string {
  if (!source) return '#4F46E5';
  const lower = source.toLowerCase();
  if (lower === 'qq_skill' || lower === 'qq_ai' || lower === 'qq_chart') return '#1DB954';
  if (lower === 'netease' || lower.includes('163')) return '#E60026';
  if (lower === 'qq' || lower.includes('tencent')) return '#1DB954';
  if (lower === 'kugou') return '#00A9F0';
  if (lower === 'kuwo') return '#F5A623';
  return '#4F46E5';
}

export function isValidArtist(artist?: string): boolean {
  if (!artist) return false;
  const trimmed = artist.trim();
  if (trimmed.length === 0) return false;
  const lower = trimmed.toLowerCase();
  if (lower === '未知艺术家' || lower === '未知' || lower === '群星' || lower === 'various artists' || lower === 'unknown') {
    return false;
  }
  return true;
}

export function getSearchArtist(artist?: string): string {
  if (!isValidArtist(artist)) return '';
  const trimmed = artist!.trim();
  const delimiters = [' / ', '/', '、', ',', '，', ' & ', '&', ' feat. ', ' feat '];
  for (let i = 0; i < delimiters.length; i++) {
    const d = delimiters[i];
    const idx = trimmed.indexOf(d);
    if (idx > 0) {
      const first = trimmed.substring(0, idx).trim();
      if (isValidArtist(first)) {
        return first;
      }
    }
  }
  return trimmed;
}

@Component({ freezeWhenInactive: true })
export struct MusicRecommendationPage {
  @Prop wide: boolean = true;
  @Prop @Watch('onDatasetChanged') activeCategory: string = 'daily';
  @Prop @Watch('onFeaturedSongChanged') featuredSong: Song | undefined = undefined;
  @Prop @Watch('onSongsChanged') songs: Song[] = [];
  @Prop @Watch('onPlaylistsChanged') recommendPlaylists: RecommendPlaylist[] = [];
  @Prop @Watch('onDatasetChanged') selectedPlaylistId: string = '';
  @Prop @Watch('onDatasetChanged') currentPlaylistName: string = '';
  @Prop favoriteIds: string[] = [];
  @Prop @Watch('onDatasetChanged') searchKeyword: string = '';
  @Prop @Watch('onFeaturedSongChanged') playbackState: PlaybackState = PlaybackState.IDLE;
  @Prop loadingRecommend: boolean = false;
  @Prop isSearching: boolean = false;
  @Prop selectedSearchSource: string = 'all';
  @Prop isSearchingMore: boolean = false;
  @Prop hasMoreSearchResults: boolean = true;
  @Prop searchHistory: string[] = [];
  @Prop musicSourceMode: MusicSourceMode = MusicSourceMode.ONLINE;
  @Prop customMusicServerUrl: string = '';
  @Prop hasMoreRecommend: boolean = false;
  @Prop isLoadingMoreRecommend: boolean = false;
  @Prop currentPlaylistTotal: number = 0;

  onSelectSong: (song: Song) => void = (_song: Song): void => {};
  onToggleFavorite: (song: Song) => void = (_song: Song): void => {};
  onSelectPlaylist: (playlist: RecommendPlaylist) => void = (_playlist: RecommendPlaylist): void => {};
  onRefreshRecommend: () => void = (): void => {};
  onSelectCategory: (categoryId: string, categoryName: string) => void = (_id: string, _name: string): void => {};
  onSearch: (keyword: string, saveToHistory?: boolean) => void = (_kw: string, _save?: boolean): void => {};
  onRemoveSearchHistory: (keyword: string) => void = (_kw: string): void => {};
  onClearSearchHistory: () => void = (): void => {};
  onSwitchSearchSource: (source: string) => void = (_source: string): void => {};
  onLoadMoreSearch: () => void = (): void => {};
  onLoadMoreRecommend: () => void = (): void => {};
  onNavigateTab: (tabIndex: number) => void = (_tabIndex: number): void => {};
  onOpenServerConfig?: () => void;

  @State localKeyword: string = '';
  @State selectedCategory: string = 'hot';
  @State focusedTab: number = -1;
  @State focusedLogo: boolean = false;
  @State focusedAction: string = '';
  @State focusedSongId: string = '';
  @State focusedPlaylistId: string = '';
  @State focusedSearchSourceId: string = '';
  @State isSearchFocused: boolean = false;
  @State showHistoryDropdown: boolean = false;
  @State showClearConfirmDialog: boolean = false;
  @State refreshRotateAngle: number = 0;

  private listScroller: Scroller = new Scroller();
  private wideListScroller: Scroller = new Scroller();
  private songDataSource: ArrayDataSource<Song> = new ArrayDataSource<Song>();
  private playlistDataSource: ArrayDataSource<RecommendPlaylist> = new ArrayDataSource<RecommendPlaylist>();

  private onFeaturedSongChanged(): void {
    // In-place reactive update on existing ListItem nodes without full recreation
  }

  private onSongsChanged(): void {
    this.songDataSource.setData(this.songs);
  }

  private onPlaylistsChanged(): void {
    this.playlistDataSource.setData(this.recommendPlaylists);
  }

  private onDatasetChanged(): void {
    if (this.searchKeyword !== undefined && this.searchKeyword !== this.localKeyword) {
      this.localKeyword = this.searchKeyword;
    }
    this.songDataSource.setData(this.songs);
    this.playlistDataSource.setData(this.recommendPlaylists);
    try {
      this.listScroller.scrollTo({ xOffset: 0, yOffset: 0 });
    } catch (_) {}
    try {
      this.wideListScroller.scrollTo({ xOffset: 0, yOffset: 0 });
    } catch (_) {}
  }

  private triggerRefreshRecommend(): void {
    animateTo({ duration: 500, curve: Curve.EaseInOut }, () => {
      this.refreshRotateAngle += 360;
    });
    this.onDatasetChanged();
    try {
      promptAction.showToast({
        message: '已为您换一批推荐歌单',
        duration: 1800,
        bottom: 80
      });
    } catch (_) {}
    this.onRefreshRecommend();
  }

  private categoryTabs: CategoryTabItem[] = [
    { id: 'daily', name: '每日推荐' },
    { id: 'ai_playlist', name: 'AI歌单' },
    { id: 'charts', name: '排行榜' },
    { id: 'hot', name: '热唱' },
    { id: 'chinese', name: '华语' },
    { id: 'nostalgia', name: '怀旧' },
    { id: 'soft', name: '轻声' },
    { id: 'cantonese', name: '粤语' },
    { id: 'rock', name: '摇滚' },
    { id: 'folk', name: '民谣' }
  ];

  aboutToAppear(): void {
    this.localKeyword = this.searchKeyword;
    if (this.activeCategory) {
      this.selectedCategory = this.activeCategory;
    }
    this.songDataSource.setData(this.songs);
    this.playlistDataSource.setData(this.recommendPlaylists);
  }

  private isSongFavorite(song: Song): boolean {
    if (!song) return false;
    if (this.favoriteIds.includes(song.id)) return true;
    const songKey = `${(song.title || '').trim().toLowerCase()}:::${(song.artist || '').trim().toLowerCase()}`;
    return this.favoriteIds.includes(songKey);
  }

  @State focusedCategoryIndex: number = -1;
  @State focusedRefreshBtn: boolean = false;

  // Search Source Switcher Tab Bar (All + NetEase, QQ, KuGou, Kuwo, Migu, Qianqian, Soda, Apple)
  @Builder
  searchSourceTabBar(wideMode: boolean) {
    Scroll() {
      Row({ space: 8 }) {
        ForEach(SEARCH_SOURCE_OPTIONS, (sourceOption: SearchSourceOption) => {
          Button({ type: ButtonType.Normal, stateEffect: false }) {
            Row({ space: 6 }) {
              Row()
                .width(7)
                .height(7)
                .borderRadius(3.5)
                .backgroundColor(this.selectedSearchSource === sourceOption.id ? '#FFFFFF' : sourceOption.brandColor)

              Text(sourceOption.name)
                .fontSize(wideMode ? 12 : 11)
                .fontWeight(this.selectedSearchSource === sourceOption.id ? FontWeight.Bold : FontWeight.Normal)
                .fontColor(this.selectedSearchSource === sourceOption.id ? '#FFFFFF' : (this.focusedSearchSourceId === sourceOption.id ? PivoTheme.primary : PivoTheme.text))
            }
            .padding({ left: 10, right: 10, top: 4, bottom: 4 })
          }
          .height(wideMode ? 30 : 26)
          .borderRadius(15)
          .backgroundColor(
            this.selectedSearchSource === sourceOption.id
              ? sourceOption.brandColor
              : (this.focusedSearchSourceId === sourceOption.id ? PivoTheme.surfaceSelected : PivoTheme.surfaceRaised)
          )
          .border({
            width: this.focusedSearchSourceId === sourceOption.id ? 2 : (this.selectedSearchSource === sourceOption.id ? 1 : 0.8),
            color: this.focusedSearchSourceId === sourceOption.id ? PivoTheme.focusRing : (this.selectedSearchSource === sourceOption.id ? sourceOption.brandColor : PivoTheme.border)
          })
          .shadow(
            this.selectedSearchSource === sourceOption.id
              ? { radius: 10, color: `${sourceOption.brandColor}66` }
              : (this.focusedSearchSourceId === sourceOption.id ? { radius: 10, color: PivoTheme.primaryGlow } : undefined)
          )
          .scale({
            x: this.focusedSearchSourceId === sourceOption.id ? 1.05 : 1.0,
            y: this.focusedSearchSourceId === sourceOption.id ? 1.05 : 1.0
          })
          .focusable(true)
          .focusOnTouch(true)
          .id(`tv_search_source_${sourceOption.id}`)
          .onFocus(() => {
            this.focusedSearchSourceId = sourceOption.id;
          })
          .onBlur(() => {
            if (this.focusedSearchSourceId === sourceOption.id) {
              this.focusedSearchSourceId = '';
            }
          })
          .onClick(() => {
            this.onSwitchSearchSource(sourceOption.id);
          })
        }, (item: SearchSourceOption) => item.id)
      }
      .padding({ left: wideMode ? 4 : 16, right: wideMode ? 4 : 16, top: 2, bottom: 2 })
    }
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Off)
    .width('100%')
    .margin({ top: 2, bottom: 4 })
  }

  // Widescreen Dual-Column Layout (TV / 16:9 Landscape - 左侧推荐歌单流 + 右侧宽屏曲目列表)
  @Builder
  widescreenLayout() {
    Column({ space: 10 }) {
      // 1. Top Header Bar: Horizontal Scrollable Category Capsule Selector + Search Bar
      Row() {
        // Left: Category Filter Pills (热唱 / 华语 / 怀旧 / 轻声 / 粤语 / 摇滚 / 民谣) in horizontal scrollable List
        List({ space: 8 }) {
          ForEach(this.categoryTabs, (cat: CategoryTabItem, index: number) => {
            ListItem() {
              Button({ type: ButtonType.Normal, stateEffect: false }) {
                Text(cat.name)
                  .fontSize(13)
                  .fontWeight(this.selectedCategory === cat.id ? FontWeight.Bold : (this.focusedCategoryIndex === index ? FontWeight.Bold : FontWeight.Medium))
                  .fontColor(this.selectedCategory === cat.id ? PivoTheme.primaryTextDark : (this.focusedCategoryIndex === index ? PivoTheme.primary : PivoTheme.text))
              }
              .height(34)
              .padding({ left: 14, right: 14 })
              .borderRadius(17)
              .backgroundColor(this.selectedCategory === cat.id ? PivoTheme.primary : (this.focusedCategoryIndex === index ? PivoTheme.surfaceSelected : PivoTheme.surface))
              .border({
                width: this.focusedCategoryIndex === index ? 2 : (this.selectedCategory === cat.id ? 1 : 1),
                color: this.focusedCategoryIndex === index ? PivoTheme.primary : (this.selectedCategory === cat.id ? PivoTheme.primary : PivoTheme.border)
              })
              .shadow(this.focusedCategoryIndex === index || this.selectedCategory === cat.id ? { radius: 10, color: PivoTheme.primaryGlow } : undefined)
              .scale({ x: this.focusedCategoryIndex === index ? 1.05 : 1.0, y: this.focusedCategoryIndex === index ? 1.05 : 1.0 })
              .focusable(true)
              .focusOnTouch(true)
              .id(`tv_category_tab_${index}`)
              .nextFocus({
                left: index > 0 ? `tv_category_tab_${index - 1}` : undefined,
                right: index < this.categoryTabs.length - 1 ? `tv_category_tab_${index + 1}` : 'tv_search_input',
                down: 'tv_song_item_0'
              })
              .onFocus(() => {
                this.focusedCategoryIndex = index;
              })
              .onBlur(() => {
                if (this.focusedCategoryIndex === index) {
                  this.focusedCategoryIndex = -1;
                }
              })
              .onClick(() => {
                this.selectedCategory = cat.id;
                this.onSelectCategory(cat.id, cat.name);
              })
            }
          }, (cat: CategoryTabItem) => cat.id)
        }
        .listDirection(Axis.Horizontal)
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)
        .layoutWeight(1)
        .height(38)

        // Right: Search Capsule
        Row({ space: 8 }) {
          Text('⌕')
            .fontSize(16)
            .fontColor(this.isSearchFocused ? PivoTheme.primary : PivoTheme.textMuted)

          TextInput({ text: this.localKeyword, placeholder: '搜索歌曲、歌手或歌单' })
            .placeholderColor(PivoTheme.textMuted)
            .fontColor(PivoTheme.text)
            .fontSize(13)
            .backgroundColor(Color.Transparent)
            .caretColor(PivoTheme.primary)
            .layoutWeight(1)
            .focusable(true)
            .enableKeyboardOnFocus(false)
            .id('tv_search_input')
            .nextFocus({
              left: `tv_category_tab_${this.categoryTabs.length - 1}`,
              down: 'tv_song_item_0'
            })
            .onFocus(() => {
              this.isSearchFocused = true;
              if (this.searchHistory.length > 0) {
                this.showHistoryDropdown = true;
              }
            })
            .onBlur(() => {
              this.isSearchFocused = false;
            })
            .onClick(() => {
              if (this.searchHistory.length > 0) {
                this.showHistoryDropdown = true;
              }
            })
            .onChange((value: string) => {
              this.localKeyword = value;
            })
            .onSubmit(() => {
              this.showHistoryDropdown = false;
              this.onSearch(this.localKeyword, true);
            })

          if (this.isSearching) {
            LoadingProgress()
              .color(PivoTheme.primary)
              .width(16)
              .height(16)
          } else if (this.localKeyword.length > 0) {
            Text('✕')
              .fontSize(12)
              .fontColor(PivoTheme.textMuted)
              .padding(4)
              .onClick(() => {
                this.localKeyword = '';
                this.showHistoryDropdown = false;
                this.onSearch('', false);
              })
          }
        }
        .width(260)
        .height(36)
        .margin({ left: 16 })
        .padding({ left: 14, right: 12 })
        .borderRadius(18)
        .backgroundColor(PivoTheme.surface)
        .border({
          width: this.isSearchFocused ? 2 : 1,
          color: this.isSearchFocused ? PivoTheme.primary : PivoTheme.borderSearch
        })
        .shadow(this.isSearchFocused ? { radius: 12, color: PivoTheme.primaryGlow } : undefined)
      }
      .width('100%')
      .padding({ left: 24, right: 24, top: 16, bottom: 4 })

      // 2. Main Dual-Column Content Area (Left: 推荐歌单流 | Right: 宽屏曲目详情列表)
      Row({ space: 20 }) {
        // Left Column: 推荐歌单流 (Width 300)
        Column({ space: 8 }) {
          // Playlist Header (Title + 换一批 Button)
          Row() {
            Row({ space: 6 }) {
              Text('🔥')
                .fontSize(14)
              Text(this.selectedCategory === 'charts' ? '排行榜单' : (this.selectedCategory === 'ai_playlist' ? 'AI 歌单' : (this.selectedCategory === 'daily' ? '今日精选' : '推荐歌单')))
                .fontSize(15)
                .fontWeight(FontWeight.Bold)
                .fontColor(PivoTheme.text)
            }

            Blank()

            Button({ type: ButtonType.Normal, stateEffect: false }) {
              Row({ space: 4 }) {
                Text('↻')
                  .fontSize(12)
                  .fontColor(PivoTheme.primary)
                  .rotate({ angle: this.refreshRotateAngle })
                Text('换一批')
                  .fontSize(11)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(PivoTheme.primary)
              }
            }
            .height(28)
            .padding({ left: 8, right: 8 })
            .borderRadius(14)
            .backgroundColor(this.focusedRefreshBtn ? PivoTheme.surfaceSelected : Color.Transparent)
            .border({
              width: this.focusedRefreshBtn ? 1.5 : 0,
              color: PivoTheme.primary
            })
            .focusable(true)
            .focusOnTouch(true)
            .id('tv_refresh_recommend_btn')
            .nextFocus({
              up: 'tv_category_tab_0',
              right: 'tv_song_item_0',
              down: 'tv_playlist_item_0'
            })
            .onFocus(() => {
              this.focusedRefreshBtn = true;
            })
            .onBlur(() => {
              this.focusedRefreshBtn = false;
            })
            .onClick(() => this.triggerRefreshRecommend())
          }
          .width('100%')
          .padding({ left: 4, right: 4, bottom: 2 })

          // Playlists List
          List({ space: 8, scroller: this.listScroller }) {
            LazyForEach(this.playlistDataSource, (playlist: RecommendPlaylist, index: number) => {
              ListItem() {
                Button({ type: ButtonType.Normal, stateEffect: false }) {
                  Row({ space: 10 }) {
                    // Thumbnail with Platform Source Tag
                    Stack({ alignContent: Alignment.TopEnd }) {
                      if ((playlist.coverUrl ?? '').length > 0) {
                        Image(playlist.coverUrl)
                          .width(54)
                          .height(54)
                          .borderRadius(8)
                          .objectFit(ImageFit.Cover)
                      } else {
                        Row()
                          .width(54)
                          .height(54)
                          .borderRadius(8)
                          .linearGradient({
                            angle: 135,
                            colors: index % 2 === 0 ? [[PivoTheme.surfaceRaised, 0.0], ['#FFE1D7', 1.0]] : [[PivoTheme.surfaceSolid, 0.0], ['#DDEFFD', 1.0]]
                          })
                        Text('♬')
                          .fontSize(20)
                          .fontColor(PivoTheme.textMuted)
                      }

                      // Source Badge
                      Row() {
                        Text(getSourceLabel(playlist.source))
                          .fontSize(8)
                          .fontWeight(FontWeight.Bold)
                          .fontColor('#FFFFFF')
                      }
                      .padding({ left: 4, right: 4, top: 1.5, bottom: 1.5 })
                      .borderRadius(3)
                      .backgroundColor(getSourceColor(playlist.source))
                      .margin({ top: 3, right: 3 })
                    }
                    .width(54)
                    .height(54)

                    // Details (Title, Creator, Track Count)
                    Column({ space: 4 }) {
                      Text(playlist.name)
                        .fontSize(12)
                        .fontWeight(this.focusedPlaylistId === playlist.id || this.selectedPlaylistId === playlist.id ? FontWeight.Bold : FontWeight.Medium)
                        .fontColor(this.focusedPlaylistId === playlist.id || this.selectedPlaylistId === playlist.id ? PivoTheme.primary : PivoTheme.text)
                        .maxLines(2)
                        .textOverflow({ overflow: TextOverflow.Ellipsis })

                      Row({ space: 4 }) {
                        Text(playlist.creator || '精选')
                          .fontSize(10)
                          .fontColor(PivoTheme.textMuted)
                          .maxLines(1)
                          .textOverflow({ overflow: TextOverflow.Ellipsis })
                          .layoutWeight(1)

                        if (playlist.trackCount > 0) {
                          Text(`${playlist.trackCount}首`)
                            .fontSize(10)
                            .fontColor(PivoTheme.textMuted)
                        }
                      }
                      .width('100%')
                    }
                    .layoutWeight(1)
                    .alignItems(HorizontalAlign.Start)
                    .justifyContent(FlexAlign.Center)
                  }
                  .width('100%')
                  .padding({ left: 8, right: 8, top: 6, bottom: 6 })
                  .alignItems(VerticalAlign.Center)
                }
                .width('100%')
                .borderRadius(10)
                .backgroundColor(this.focusedPlaylistId === playlist.id ? PivoTheme.surfaceSelected : ((this.selectedPlaylistId === playlist.id || (this.selectedPlaylistId === '' && index === 0)) ? PivoTheme.surfaceSelectedSubtle : PivoTheme.surfaceSolid))
                .border({
                  width: this.focusedPlaylistId === playlist.id ? 2.5 : ((this.selectedPlaylistId === playlist.id || (this.selectedPlaylistId === '' && index === 0)) ? 1.5 : 1),
                  color: this.focusedPlaylistId === playlist.id ? PivoTheme.primary : ((this.selectedPlaylistId === playlist.id || (this.selectedPlaylistId === '' && index === 0)) ? PivoTheme.primary : PivoTheme.border)
                })
                .shadow(this.focusedPlaylistId === playlist.id ? { radius: 14, color: PivoTheme.primaryGlow } : undefined)
                .scale({ x: this.focusedPlaylistId === playlist.id ? 1.02 : 1.0, y: this.focusedPlaylistId === playlist.id ? 1.02 : 1.0 })
                .focusable(true)
                .focusOnTouch(true)
                .id(`tv_playlist_item_${index}`)
                .nextFocus({
                  left: 'sidebar_nav_tab_0',
                  right: `tv_song_item_${Math.min(index, this.songs.length > 0 ? this.songs.length - 1 : 0)}`,
                  up: index === 0 ? 'tv_refresh_recommend_btn' : `tv_playlist_item_${index - 1}`,
                  down: index < this.recommendPlaylists.length - 1 ? `tv_playlist_item_${index + 1}` : undefined
                })
                .onFocus(() => {
                  this.focusedPlaylistId = playlist.id;
                })
                .onBlur(() => {
                  if (this.focusedPlaylistId === playlist.id) {
                    this.focusedPlaylistId = '';
                  }
                })
                .onClick(() => {
                  this.selectedPlaylistId = playlist.id;
                  this.onDatasetChanged();
                  this.onSelectPlaylist(playlist);
                })
              }
            }, (playlist: RecommendPlaylist, index: number) => `${playlist.id}_${index}`)
          }
          .width('100%')
          .layoutWeight(1)
          .scrollBar(BarState.Off)
          .edgeEffect(EdgeEffect.Spring)
        }
        .width(300)
        .height('100%')
        .alignItems(HorizontalAlign.Start)

        // Right Column: 宽屏歌曲列表 (Song List, LayoutWeight: 1)
        Column({ space: 8 }) {
          // Song List Header (Current Playlist Name / Search Keywords + SQ Badge)
          Row({ space: 8 }) {
            Text(this.searchKeyword ? `搜索结果 (${this.songs.length})` : (this.currentPlaylistName ? `${this.currentPlaylistName}` : `歌单曲目`))
              .fontSize(15)
              .fontWeight(FontWeight.Bold)
              .fontColor(PivoTheme.text)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1)

            Row() {
              Text(this.hasMoreRecommend && this.currentPlaylistTotal > this.songs.length ? `已加载 ${this.songs.length}/${this.currentPlaylistTotal} 首 · SQ 无损` : `${this.songs.length} 首 · SQ 无损`)
                .fontSize(10)
                .fontWeight(FontWeight.Bold)
                .fontColor(PivoTheme.sqBadgeText)
            }
            .padding({ left: 8, right: 8, top: 3, bottom: 3 })
            .borderRadius(4)
            .backgroundColor(PivoTheme.sqBadgeBg)
            .border({ width: 1, color: PivoTheme.sqBadgeBorder })
          }
          .width('100%')
          .padding({ left: 4, right: 4, bottom: 2 })

          if (this.searchKeyword.length > 0) {
            this.searchSourceTabBar(true)
          }

          if (this.isSearching) {
            Column({ space: 10 }) {
              LoadingProgress()
                .color(PivoTheme.primary)
                .width(36)
                .height(36)
              Text(`正在搜索“${this.searchKeyword || this.localKeyword}”…`)
                .fontSize(13)
                .fontColor(PivoTheme.text)
            }
            .width('100%')
            .layoutWeight(1)
            .justifyContent(FlexAlign.Center)
            .alignItems(HorizontalAlign.Center)
          } else if (this.searchKeyword.length > 0 && this.songs.length === 0) {
            Column({ space: 8 }) {
              Text('⌕')
                .fontSize(32)
                .fontColor(PivoTheme.textFaint)
              Text(`未找到与“${this.searchKeyword}”相关的歌曲`)
                .fontSize(13)
                .fontColor(PivoTheme.textMuted)
            }
            .width('100%')
            .layoutWeight(1)
            .justifyContent(FlexAlign.Center)
            .alignItems(HorizontalAlign.Center)
          } else if (this.musicSourceMode === MusicSourceMode.LOCAL && this.songs.length === 0) {
            Column({ space: 14 }) {
              Text('📁')
                .fontSize(40)
              Text('当前处于纯本地模式')
                .fontSize(16)
                .fontWeight(FontWeight.Bold)
                .fontColor(PivoTheme.text)
              Text('已停用外部网络推荐与全网搜索。您可以在【我的】页面中配置在线音乐源或导入本地歌曲。')
                .fontSize(12)
                .fontColor(PivoTheme.textMuted)
                .textAlign(TextAlign.Center)
                .padding({ left: 24, right: 24 })
                .lineHeight(18)

              Row({ space: 12 }) {
                Button('⚙️ 前往音乐源配置')
                  .fontSize(12)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(PivoTheme.primaryTextDark)
                  .backgroundColor(PivoTheme.primary)
                  .height(34)
                  .padding({ left: 18, right: 18 })
                  .borderRadius(17)
                  .onClick(() => {
                    if (this.onOpenServerConfig) {
                      this.onOpenServerConfig();
                    } else {
                      this.onNavigateTab(1);
                    }
                  })
              }
              .margin({ top: 6 })
            }
            .width('100%')
            .layoutWeight(1)
            .justifyContent(FlexAlign.Center)
            .alignItems(HorizontalAlign.Center)
          } else if (this.songs.length === 0) {
            Column({ space: 8 }) {
              Text('♬')
                .fontSize(32)
                .fontColor(PivoTheme.textFaint)
              Text('当前歌单暂无曲目，请选择其他歌单')
                .fontSize(13)
                .fontColor(PivoTheme.textMuted)
            }
            .width('100%')
            .layoutWeight(1)
            .justifyContent(FlexAlign.Center)
            .alignItems(HorizontalAlign.Center)
          } else {
            List({ space: 7, scroller: this.wideListScroller }) {
              LazyForEach(this.songDataSource, (song: Song, index: number) => {
                ListItem() {
                  Button({ type: ButtonType.Normal, stateEffect: false }) {
                    Row({ space: 12 }) {
                      // Index / Sound Wave Playing indicator
                      if (this.featuredSong?.id === song.id && this.playbackState === PlaybackState.PLAYING) {
                        Row({ space: 2.5 }) {
                          Row().width(2.5).height(10).borderRadius(1.25).backgroundColor(PivoTheme.primary)
                          Row().width(2.5).height(16).borderRadius(1.25).backgroundColor(PivoTheme.primary)
                          Row().width(2.5).height(8).borderRadius(1.25).backgroundColor(PivoTheme.primary)
                        }
                        .width(28)
                        .justifyContent(FlexAlign.Center)
                        .alignItems(VerticalAlign.Bottom)
                      } else {
                        Text(`${index + 1 < 10 ? '0' : ''}${index + 1}`)
                          .fontSize(13)
                          .fontWeight(FontWeight.Bold)
                          .fontColor(this.focusedSongId === song.id || this.featuredSong?.id === song.id ? PivoTheme.primary : PivoTheme.textMuted)
                          .width(28)
                          .textAlign(TextAlign.Center)
                      }

                      // Album Cover Thumbnail (38x38)
                      if ((song.coverUrl ?? '').length > 0) {
                        Image(song.coverUrl)
                          .width(38)
                          .height(38)
                          .borderRadius(6)
                          .objectFit(ImageFit.Cover)
                      } else {
                        Row() {
                          Text('🎵')
                            .fontSize(14)
                        }
                        .width(38)
                        .height(38)
                        .borderRadius(6)
                        .backgroundColor(PivoTheme.surfaceRaised)
                        .justifyContent(FlexAlign.Center)
                      }

                      // Title & Artist
                      Column({ space: 3 }) {
                        Text(song.title)
                          .fontSize(14)
                          .fontWeight(this.focusedSongId === song.id || this.featuredSong?.id === song.id ? FontWeight.Bold : FontWeight.Medium)
                          .fontColor(this.focusedSongId === song.id || this.featuredSong?.id === song.id ? PivoTheme.primary : PivoTheme.text)
                          .maxLines(1)
                          .textOverflow({ overflow: TextOverflow.Ellipsis })

                        Row({ space: 6 }) {
                          Text(song.artist)
                            .fontSize(11)
                            .fontColor(PivoTheme.textMuted)
                            .maxLines(1)
                            .textOverflow({ overflow: TextOverflow.Ellipsis })
                            .padding({ left: 4, right: 4, top: 1, bottom: 1 })
                            .borderRadius(4)
                            .backgroundColor(this.focusedSongId === song.id ? 'rgba(0, 0, 0, 0.04)' : Color.Transparent)
                            .onClick(() => {
                              const searchArtist = getSearchArtist(song.artist);
                              if (searchArtist.length > 0) {
                                this.localKeyword = searchArtist;
                                this.onSearch(searchArtist);
                              }
                            })
                        }
                      }
                      .layoutWeight(1)
                      .alignItems(HorizontalAlign.Start)

                      // SQ Lossless Tag
                      Row() {
                        Text('SQ')
                          .fontSize(9)
                          .fontWeight(FontWeight.Bold)
                          .fontColor(PivoTheme.sqBadgeText)
                      }
                      .padding({ left: 5, right: 5, top: 2, bottom: 2 })
                      .borderRadius(3)
                      .backgroundColor(PivoTheme.sqBadgeBg)

                      // Duration
                      Text(formatDuration(song.durationMs))
                        .fontSize(12)
                        .fontColor(PivoTheme.textMuted)
                        .margin({ left: 4, right: 6 })

                      // Favorite Star Button
                      Button({ type: ButtonType.Normal, stateEffect: false }) {
                        Text(this.isSongFavorite(song) ? '★' : '☆')
                          .fontSize(15)
                          .fontColor(this.isSongFavorite(song) ? '#FBBF24' : PivoTheme.textMuted)
                      }
                      .width(32)
                      .height(32)
                      .borderRadius(16)
                      .backgroundColor(Color.Transparent)
                      .onClick(() => {
                        this.onToggleFavorite(song);
                      })

                      // Quick Sing / Play Pill Button
                      Button({ type: ButtonType.Normal, stateEffect: false }) {
                        Row({ space: 4 }) {
                          Image($r('app.media.ic_play'))
                            .width(10)
                            .height(10)
                            .fillColor(PivoTheme.primaryTextDark)
                            .objectFit(ImageFit.Contain)
                          Text('演唱')
                            .fontSize(11)
                            .fontWeight(FontWeight.Bold)
                            .fontColor(PivoTheme.primaryTextDark)
                        }
                      }
                      .height(28)
                      .padding({ left: 10, right: 10 })
                      .borderRadius(14)
                      .backgroundColor(PivoTheme.primary)
                      .shadow(this.focusedSongId === song.id ? { radius: 8, color: PivoTheme.primaryGlow } : undefined)
                      .onClick(() => this.onSelectSong(song))
                    }
                    .width('100%')
                    .height('100%')
                    .padding({ left: 12, right: 12 })
                    .alignItems(VerticalAlign.Center)
                  }
                  .width('100%')
                  .height(48)
                  .borderRadius(10)
                  .backgroundColor(this.focusedSongId === song.id ? PivoTheme.surfaceSelected : (this.featuredSong?.id === song.id ? PivoTheme.surfaceActive : PivoTheme.surfaceSolid))
                  .border({
                    width: this.focusedSongId === song.id ? 2.5 : (this.featuredSong?.id === song.id ? 1.5 : 1),
                    color: this.focusedSongId === song.id ? PivoTheme.primary : (this.featuredSong?.id === song.id ? PivoTheme.primary : PivoTheme.border)
                  })
                  .shadow(this.focusedSongId === song.id ? { radius: 14, color: PivoTheme.primaryGlow } : undefined)
                  .scale({ x: this.focusedSongId === song.id ? 1.015 : 1.0, y: this.focusedSongId === song.id ? 1.015 : 1.0 })
                  .focusable(true)
                  .focusOnTouch(true)
                  .id(`tv_song_item_${index}`)
                  .nextFocus({
                    left: `tv_playlist_item_${Math.min(index, this.recommendPlaylists.length > 0 ? this.recommendPlaylists.length - 1 : 0)}`,
                    right: undefined,
                    up: index === 0 ? 'tv_category_tab_0' : `tv_song_item_${index - 1}`,
                    down: index < this.songs.length - 1 ? `tv_song_item_${index + 1}` : undefined
                  })
                  .onFocus(() => {
                    this.focusedSongId = song.id;
                  })
                  .onBlur(() => {
                    if (this.focusedSongId === song.id) {
                      this.focusedSongId = '';
                    }
                  })
                  .onClick(() => this.onSelectSong(song))
                  .gesture(
                    LongPressGesture({ repeat: false, duration: 400 })
                      .onAction((_event: GestureEvent) => {
                        const searchArtist = getSearchArtist(song.artist);
                        if (searchArtist.length > 0) {
                          this.localKeyword = searchArtist;
                          promptAction.showToast({ message: `正在搜索作者：${searchArtist}` });
                          this.onSearch(searchArtist);
                        } else {
                          promptAction.showToast({ message: '该歌曲暂无有效作者信息' });
                        }
                      })
                  )
                }
              }, (song: Song, index: number) => `${this.selectedPlaylistId || this.selectedCategory || 'hot'}_${song.id}_${index}`)

              if (this.searchKeyword.length > 0) {
                ListItem() {
                  Row({ space: 8 }) {
                    if (this.isSearchingMore) {
                      LoadingProgress()
                        .color(PivoTheme.primary)
                        .width(18)
                        .height(18)
                      Text('正在从源端检索更多歌曲…')
                        .fontSize(12)
                        .fontColor(PivoTheme.textMuted)
                    } else if (!this.hasMoreSearchResults && this.songs.length > 0) {
                      Text('— 已加载全部搜索结果 —')
                        .fontSize(11)
                        .fontColor(PivoTheme.textFaint)
                    }
                  }
                  .width('100%')
                  .height(36)
                  .justifyContent(FlexAlign.Center)
                }
              }

              if (this.searchKeyword.length === 0) {
                ListItem() {
                  Row({ space: 8 }) {
                    if (this.isLoadingMoreRecommend) {
                      LoadingProgress()
                        .color(PivoTheme.primary)
                        .width(18)
                        .height(18)
                      Text('正在加载更多歌曲…')
                        .fontSize(12)
                        .fontColor(PivoTheme.textMuted)
                    } else if (this.hasMoreRecommend) {
                      Text('— 向下滑动加载更多歌曲 —')
                        .fontSize(11)
                        .fontColor(PivoTheme.primary)
                    } else if (this.songs.length > 0) {
                      Text('— 已加载全部歌曲 —')
                        .fontSize(11)
                        .fontColor(PivoTheme.textFaint)
                    }
                  }
                  .width('100%')
                  .height(36)
                  .justifyContent(FlexAlign.Center)
                }
              }
            }
            .width('100%')
            .layoutWeight(1)
            .scrollBar(BarState.Off)
            .edgeEffect(EdgeEffect.Spring)
            .onReachEnd(() => {
              if (this.searchKeyword.length > 0) {
                this.onLoadMoreSearch();
              } else if (this.hasMoreRecommend && !this.isLoadingMoreRecommend) {
                this.onLoadMoreRecommend();
              }
            })
          }
        }
        .layoutWeight(1)
        .height('100%')
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .layoutWeight(1)
      .padding({ left: 24, right: 24, top: 4, bottom: 12 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(PivoTheme.backgroundDark)
  }

  // Portrait Layout (Phone / Vertical Screen - 搜索 + 每日推荐歌单 + 歌单曲目)
  @Builder
  portraitLayout() {
    Column({ space: 10 }) {
      // 1. Mobile Search Header
      Row({ space: 10 }) {
        Text('PivoMic')
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor(PivoTheme.text)

        // Search Input
        Row({ space: 6 }) {
          Text('⌕')
            .fontSize(15)
            .fontColor(PivoTheme.textMuted)

          TextInput({ text: this.localKeyword, placeholder: '搜索歌曲、歌手或歌单' })
            .placeholderColor(PivoTheme.textMuted)
            .fontColor(PivoTheme.text)
            .fontSize(13)
            .backgroundColor(Color.Transparent)
            .layoutWeight(1)
            .enableKeyboardOnFocus(false)
            .onFocus(() => {
              this.isSearchFocused = true;
              if (this.searchHistory.length > 0) {
                this.showHistoryDropdown = true;
              }
            })
            .onBlur(() => {
              this.isSearchFocused = false;
            })
            .onClick(() => {
              if (this.searchHistory.length > 0) {
                this.showHistoryDropdown = true;
              }
            })
            .onChange((val: string) => {
              this.localKeyword = val;
            })
            .onSubmit(() => {
              this.showHistoryDropdown = false;
              this.onSearch(this.localKeyword, true);
            })

          if (this.localKeyword.length > 0) {
            Text('✕')
              .fontSize(12)
              .fontColor(PivoTheme.textMuted)
              .padding(4)
              .onClick(() => {
                this.localKeyword = '';
                this.showHistoryDropdown = false;
                this.onSearch('', false);
              })
          }

          Button({ type: ButtonType.Normal, stateEffect: !this.isSearching }) {
            if (this.isSearching) {
              Row({ space: 4 }) {
                LoadingProgress()
                  .color(PivoTheme.primaryTextDark)
                  .width(14)
                  .height(14)
              }
              .justifyContent(FlexAlign.Center)
              .alignItems(VerticalAlign.Center)
            } else {
              Text('搜索')
                .fontSize(12)
                .fontColor(PivoTheme.primaryTextDark)
                .fontWeight(FontWeight.Bold)
            }
          }
          .height(28)
          .padding({ left: 10, right: 10 })
          .borderRadius(14)
          .backgroundColor(PivoTheme.primary)
          .enabled(!this.isSearching)
          .opacity(this.isSearching ? 0.85 : 1.0)
          .onClick(() => {
            if (this.localKeyword.trim().length > 0 && !this.isSearching) {
              this.showHistoryDropdown = false;
              this.onSearch(this.localKeyword.trim(), true);
            }
          })
        }
        .layoutWeight(1)
        .height(38)
        .padding({ left: 12, right: 6 })
        .borderRadius(19)
        .backgroundColor(PivoTheme.surface)
        .border({ width: 1, color: PivoTheme.borderSearch })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 10, bottom: 2 })

      // 2. 每日推荐歌单 (Horizontal Card Carousel)
      if (this.recommendPlaylists.length > 0) {
        Column({ space: 8 }) {
          Row() {
            Row({ space: 6 }) {
              Text('🔥')
                .fontSize(14)
              Text(this.selectedCategory === 'charts' ? '排行榜单' : (this.selectedCategory === 'ai_playlist' ? 'AI 歌单' : (this.selectedCategory === 'daily' ? '今日精选' : '每日推荐歌单')))
                .fontSize(15)
                .fontWeight(FontWeight.Bold)
                .fontColor(PivoTheme.text)
              Text(this.selectedCategory === 'daily' || this.selectedCategory === 'ai_playlist' || this.selectedCategory === 'charts' ? 'QQ音乐 Skill 精选' : '网易云 · QQ音乐精选')
                .fontSize(11)
                .fontColor(PivoTheme.textMuted)
            }

            Blank()

            Button({ type: ButtonType.Normal, stateEffect: false }) {
              Row({ space: 3 }) {
                Text('↻')
                  .fontSize(12)
                  .fontColor(PivoTheme.primary)
                  .rotate({ angle: this.refreshRotateAngle })
                Text('换一批')
                  .fontSize(11)
                  .fontColor(PivoTheme.primary)
              }
            }
            .backgroundColor(Color.Transparent)
            .onClick(() => this.triggerRefreshRecommend())
          }
          .width('100%')
          .padding({ left: 16, right: 16 })

          List({ space: 10 }) {
            LazyForEach(this.playlistDataSource, (playlist: RecommendPlaylist, index: number) => {
              ListItem() {
                Button({ type: ButtonType.Normal, stateEffect: false }) {
                  Column({ space: 6 }) {
                    // Cover image container
                    Stack({ alignContent: Alignment.BottomStart }) {
                      if ((playlist.coverUrl ?? '').length > 0) {
                        Image(playlist.coverUrl)
                          .width(104)
                          .height(104)
                          .borderRadius(10)
                          .objectFit(ImageFit.Cover)
                      } else {
                        Row()
                          .width(104)
                          .height(104)
                          .borderRadius(10)
                          .linearGradient({
                            angle: 135,
                            colors: index % 3 === 0 ? [['#FFE5DC', 0.0], ['#FFB69E', 1.0]] :
                                    (index % 3 === 1 ? [['#E0F2FE', 0.0], ['#BAE6FD', 1.0]] :
                                                       [['#EDE9FE', 0.0], ['#DDD6FE', 1.0]])
                          })
                        Text('♬')
                          .fontSize(28)
                          .fontColor(PivoTheme.textMuted)
                      }

                      // Top-right Source badge (网易云 / QQ音乐)
                      Row() {
                        Text(getSourceLabel(playlist.source))
                          .fontSize(8)
                          .fontWeight(FontWeight.Bold)
                          .fontColor('#FFFFFF')
                      }
                      .padding({ left: 5, right: 5, top: 2, bottom: 2 })
                      .borderRadius(4)
                      .backgroundColor(getSourceColor(playlist.source))
                      .position({ x: 52, y: 4 })

                      // Bottom gradient overlay with track count
                      if (playlist.trackCount > 0) {
                        Row() {
                          Text(`${playlist.trackCount}首`)
                            .fontSize(9)
                            .fontWeight(FontWeight.Medium)
                            .fontColor('rgba(255, 255, 255, 0.9)')
                        }
                        .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                        .borderRadius(4)
                        .backgroundColor('rgba(98, 98, 98, 0.48)')
                        .margin({ left: 4, bottom: 4 })
                      }
                    }
                    .width(104)
                    .height(104)

                    // Playlist Name
                    Text(playlist.name)
                      .fontSize(11)
                      .fontWeight(this.selectedPlaylistId === playlist.id ? FontWeight.Bold : FontWeight.Medium)
                      .fontColor(this.selectedPlaylistId === playlist.id ? PivoTheme.primary : PivoTheme.text)
                      .maxLines(2)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                      .width(104)
                  }
                  .alignItems(HorizontalAlign.Start)
                }
                .padding(4)
                .borderRadius(12)
                .backgroundColor(this.selectedPlaylistId === playlist.id ? PivoTheme.surfaceSelectedSubtle : Color.Transparent)
                .border({
                  width: this.selectedPlaylistId === playlist.id ? 1.5 : 0,
                  color: this.selectedPlaylistId === playlist.id ? PivoTheme.primary : Color.Transparent
                })
                .shadow(this.selectedPlaylistId === playlist.id ? { radius: 10, color: PivoTheme.primaryGlow } : undefined)
                .onClick(() => {
                  this.onDatasetChanged();
                  this.onSelectPlaylist(playlist);
                })
              }
            }, (playlist: RecommendPlaylist, index: number) => `${playlist.id}_${index}`)
          }
          .listDirection(Axis.Horizontal)
          .width('100%')
          .height(152)
          .padding({ left: 16, right: 16 })
          .scrollBar(BarState.Off)
        }
        .width('100%')
      }

      // 3. 纯文字/药丸胶囊分类 Tabs 栏（水平滑动）
      List({ space: 8 }) {
        ForEach(this.categoryTabs, (cat: CategoryTabItem) => {
          ListItem() {
            Row() {
              Text(cat.name)
                .fontSize(13)
                .fontWeight(this.selectedCategory === cat.id ? FontWeight.Bold : FontWeight.Normal)
                .fontColor(this.selectedCategory === cat.id ? PivoTheme.primaryTextDark : PivoTheme.textSecondary)
            }
            .padding({ left: 14, right: 14, top: 5, bottom: 5 })
            .borderRadius(14)
            .backgroundColor(this.selectedCategory === cat.id ? PivoTheme.primary : PivoTheme.surface)
            .border({
              width: 1,
              color: this.selectedCategory === cat.id ? PivoTheme.primary : PivoTheme.border
            })
            .shadow(this.selectedCategory === cat.id ? { radius: 10, color: PivoTheme.primaryGlow } : undefined)
            .onClick(() => {
              this.selectedCategory = cat.id;
              this.onDatasetChanged();
              this.onSelectCategory(cat.id, cat.name);
            })
          }
        }, (cat: CategoryTabItem) => cat.id)
      }
      .listDirection(Axis.Horizontal)
      .width('100%')
      .height(32)
      .padding({ left: 16, right: 16 })
      .scrollBar(BarState.Off)

      // 4. 歌曲列表 (Song List)
      Column({ space: 8 }) {
        Row() {
          Text(this.searchKeyword ? `搜索结果 (${this.songs.length})` : (this.currentPlaylistName ? (this.hasMoreRecommend && this.currentPlaylistTotal > this.songs.length ? `《${this.currentPlaylistName}》（已加载 ${this.songs.length}/${this.currentPlaylistTotal} 首）` : `《${this.currentPlaylistName}》（${this.songs.length} 首）`) : '精选曲目'))
            .fontSize(14)
            .fontWeight(FontWeight.Bold)
            .fontColor(PivoTheme.text)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)

          Text(this.hasMoreRecommend && this.currentPlaylistTotal > this.songs.length ? `${this.songs.length}/${this.currentPlaylistTotal} 首 · SQ` : `${this.songs.length} 首 · SQ`)
            .fontSize(11)
            .fontColor(PivoTheme.sqBadgeText)
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 2 })

        if (this.searchKeyword.length > 0) {
          this.searchSourceTabBar(false)
        }

        if (this.isSearching) {
          Column({ space: 12 }) {
            LoadingProgress()
              .color(PivoTheme.primary)
              .width(38)
              .height(38)
            Text(`正在全网搜索“${this.searchKeyword || this.localKeyword}”…`)
              .fontSize(14)
              .fontWeight(FontWeight.Bold)
              .fontColor(PivoTheme.text)
            Text('聚合网易云、QQ音乐等全网优质歌曲')
              .fontSize(11)
              .fontColor(PivoTheme.textMuted)
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
        } else if (this.loadingRecommend && this.songs.length === 0) {
          Column({ space: 12 }) {
            LoadingProgress()
              .color(PivoTheme.primary)
              .width(36)
              .height(36)
            Text('正在载入精选曲目…')
              .fontSize(13)
              .fontColor(PivoTheme.textMuted)
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
        } else if (this.searchKeyword.length > 0 && this.songs.length === 0) {
          Column({ space: 12 }) {
            Text('⌕')
              .fontSize(36)
              .fontColor(PivoTheme.textFaint)
            Text(`未找到与“${this.searchKeyword}”相关的歌曲`)
              .fontSize(13)
              .fontWeight(FontWeight.Medium)
              .fontColor(PivoTheme.text)
            Text('请检查歌曲/歌手名是否有误，或换个关键词重试')
              .fontSize(11)
              .fontColor(PivoTheme.textMuted)

            Button('清空搜索，返回精选')
              .fontSize(12)
              .fontColor(PivoTheme.primaryTextDark)
              .fontWeight(FontWeight.Bold)
              .backgroundColor(PivoTheme.primary)
              .height(32)
              .padding({ left: 16, right: 16 })
              .borderRadius(16)
              .margin({ top: 4 })
              .onClick(() => {
                this.localKeyword = '';
                this.onSearch('');
              })
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
          .padding({ left: 24, right: 24 })
        } else if (this.musicSourceMode === MusicSourceMode.LOCAL && this.songs.length === 0) {
          Column({ space: 14 }) {
            Text('📁')
              .fontSize(48)
            Text('当前处于纯本地模式')
              .fontSize(18)
              .fontWeight(FontWeight.Bold)
              .fontColor(PivoTheme.text)
            Text('已停用外部网络推荐与全网搜索。您可以在【我的】页面中配置在线音乐源或导入本地歌曲。')
              .fontSize(13)
              .fontColor(PivoTheme.textMuted)
              .textAlign(TextAlign.Center)
              .padding({ left: 32, right: 32 })
              .lineHeight(20)

            Row({ space: 16 }) {
              Button('⚙️ 前往音乐源配置')
                .fontSize(13)
                .fontWeight(FontWeight.Bold)
                .fontColor(PivoTheme.primaryTextDark)
                .backgroundColor(PivoTheme.primary)
                .height(38)
                .padding({ left: 22, right: 22 })
                .borderRadius(19)
                .onClick(() => {
                  if (this.onOpenServerConfig) {
                    this.onOpenServerConfig();
                  } else {
                    this.onNavigateTab(1);
                  }
                })
            }
            .margin({ top: 8 })
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
          .padding({ left: 32, right: 32 })
        } else if (this.songs.length === 0) {
          Column({ space: 8 }) {
            Text('♬')
              .fontSize(40)
              .fontColor(PivoTheme.textFaint)
            Text('当前歌单暂无曲目，请选择其他歌单')
              .fontSize(14)
              .fontColor(PivoTheme.textMuted)
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
        } else {
          List({ space: 8, scroller: this.listScroller }) {
            LazyForEach(this.songDataSource, (song: Song, index: number) => {
              ListItem() {
                Row({ space: 10 }) {
                  // Index or animated equalizer if playing
                  if (this.featuredSong?.id === song.id && this.playbackState === PlaybackState.PLAYING) {
                    Row({ space: 2 }) {
                      Row().width(2.5).height(10).borderRadius(1.25).backgroundColor(PivoTheme.primary)
                      Row().width(2.5).height(14).borderRadius(1.25).backgroundColor(PivoTheme.primary)
                      Row().width(2.5).height(8).borderRadius(1.25).backgroundColor(PivoTheme.primary)
                    }
                    .width(22)
                    .justifyContent(FlexAlign.Center)
                    .alignItems(VerticalAlign.Bottom)
                  } else {
                    Text(`${index + 1 < 10 ? '0' : ''}${index + 1}`)
                      .fontSize(12)
                      .fontWeight(FontWeight.Medium)
                      .fontColor(this.featuredSong?.id === song.id ? PivoTheme.primary : PivoTheme.textMuted)
                      .width(22)
                      .textAlign(TextAlign.Center)
                  }

                  // Album Cover Thumbnail (38x38)
                  if ((song.coverUrl ?? '').length > 0) {
                    Image(song.coverUrl)
                      .width(38)
                      .height(38)
                      .borderRadius(6)
                      .objectFit(ImageFit.Cover)
                  } else {
                    Row() {
                      Text('🎵')
                        .fontSize(13)
                    }
                    .width(38)
                    .height(38)
                    .borderRadius(6)
                    .backgroundColor(PivoTheme.surfaceRaised)
                    .justifyContent(FlexAlign.Center)
                  }

                  Column({ space: 2 }) {
                    Text(song.title)
                      .fontSize(14)
                      .fontWeight(FontWeight.Bold)
                      .fontColor(this.featuredSong?.id === song.id ? PivoTheme.primary : PivoTheme.text)
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })

                    Row({ space: 6 }) {
                      Text(song.artist)
                        .fontSize(11)
                        .fontColor(PivoTheme.textMuted)
                        .maxLines(1)
                        .padding({ left: 3, right: 3, top: 1, bottom: 1 })
                        .borderRadius(3)

                      Text('·')
                        .fontSize(10)
                        .fontColor(PivoTheme.textFaint)

                      Text(formatDuration(song.durationMs))
                        .fontSize(10)
                        .fontColor(PivoTheme.textMuted)
                    }
                  }
                  .layoutWeight(1)
                  .alignItems(HorizontalAlign.Start)

                  // SQ Badge
                  Row() {
                    Text('SQ')
                      .fontSize(8)
                      .fontWeight(FontWeight.Bold)
                      .fontColor(PivoTheme.sqBadgeText)
                  }
                  .padding({ left: 4, right: 4, top: 2, bottom: 2 })
                  .borderRadius(3)
                  .backgroundColor(PivoTheme.sqBadgeBg)


                }
                .width('100%')
                .padding({ left: 12, right: 12, top: 9, bottom: 9 })
                .borderRadius(12)
                .backgroundColor(this.featuredSong?.id === song.id ? PivoTheme.surfaceActive : PivoTheme.surfaceSolid)
                .border({
                  width: this.featuredSong?.id === song.id ? 1.5 : 1,
                  color: this.featuredSong?.id === song.id ? PivoTheme.primary : PivoTheme.border
                })
                .onClick(() => this.onSelectSong(song))
                .gesture(
                  LongPressGesture({ repeat: false, duration: 400 })
                    .onAction((_event: GestureEvent) => {
                      const searchArtist = getSearchArtist(song.artist);
                      if (searchArtist.length > 0) {
                        this.localKeyword = searchArtist;
                        promptAction.showToast({ message: `正在搜索作者：${searchArtist}` });
                        this.onSearch(searchArtist);
                      } else {
                        promptAction.showToast({ message: '该歌曲暂无有效作者信息' });
                      }
                    })
                )
              }
              .clip(true)
            }, (song: Song, index: number) => `${this.selectedPlaylistId || this.selectedCategory || 'hot'}_${song.id}_${index}`)

            if (this.searchKeyword.length > 0) {
              ListItem() {
                Row({ space: 8 }) {
                  if (this.isSearchingMore) {
                    LoadingProgress()
                      .color(PivoTheme.primary)
                      .width(18)
                      .height(18)
                    Text('正在从源端检索更多歌曲…')
                      .fontSize(12)
                      .fontColor(PivoTheme.textMuted)
                  } else if (!this.hasMoreSearchResults && this.songs.length > 0) {
                    Text('— 已加载全部搜索结果 —')
                      .fontSize(11)
                      .fontColor(PivoTheme.textFaint)
                  }
                }
                .width('100%')
                .height(36)
                .justifyContent(FlexAlign.Center)
              }
            }

            if (this.searchKeyword.length === 0) {
              ListItem() {
                Row({ space: 8 }) {
                  if (this.isLoadingMoreRecommend) {
                    LoadingProgress()
                      .color(PivoTheme.primary)
                      .width(18)
                      .height(18)
                    Text('正在加载更多歌曲…')
                      .fontSize(12)
                      .fontColor(PivoTheme.textMuted)
                  } else if (this.hasMoreRecommend) {
                    Text('— 向下滑动加载更多歌曲 —')
                      .fontSize(11)
                      .fontColor(PivoTheme.primary)
                  } else if (this.songs.length > 0) {
                    Text('— 已加载全部歌曲 —')
                      .fontSize(11)
                      .fontColor(PivoTheme.textFaint)
                  }
                }
                .width('100%')
                .height(36)
                .justifyContent(FlexAlign.Center)
              }
            }
          }
          .layoutWeight(1)
          .width('100%')
          .padding({ left: 16, right: 16, bottom: 16 })
          .scrollBar(BarState.Off)
          .clip(true)
          .edgeEffect(EdgeEffect.Spring)
          .onReachEnd(() => {
            if (this.searchKeyword.length > 0) {
              this.onLoadMoreSearch();
            } else if (this.hasMoreRecommend && !this.isLoadingMoreRecommend) {
              this.onLoadMoreRecommend();
            }
          })
        }
      }
      .layoutWeight(1)
      .width('100%')
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Color.Transparent)
  }

  // Search History Floating Dropdown Overlay
  @Builder
  searchHistoryDropdownOverlay() {
    Stack({ alignContent: this.wide ? Alignment.TopEnd : Alignment.TopStart }) {
      // 1. Transparent full-screen backdrop to dismiss on click outside
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(Color.Transparent)
        .onClick(() => {
          this.showHistoryDropdown = false;
        })

      // 2. Dropdown Card
      Column({ space: 10 }) {
        // Title Bar: 搜索历史 + 清空全部
        Row() {
          Row({ space: 6 }) {
            Text('⏱')
              .fontSize(12)
              .fontColor(PivoTheme.textMuted)
            Text('搜索历史')
              .fontSize(13)
              .fontWeight(FontWeight.Bold)
              .fontColor(PivoTheme.text)
          }

          Blank()

          Button({ type: ButtonType.Normal, stateEffect: true }) {
            Row({ space: 4 }) {
              Text('🗑')
                .fontSize(12)
                .fontColor(PivoTheme.textMuted)
              Text('清空')
                .fontSize(12)
                .fontColor(PivoTheme.textMuted)
            }
          }
          .backgroundColor(Color.Transparent)
          .padding({ left: 6, right: 6, top: 2, bottom: 2 })
          .borderRadius(6)
          .onClick(() => {
            this.showClearConfirmDialog = true;
          })
        }
        .width('100%')

        // Tags List / Wrap Chips
        Scroll() {
          Flex({ wrap: FlexWrap.Wrap }) {
            ForEach(this.searchHistory, (kw: string) => {
              Row({ space: 2 }) {
                // Word text (click to search immediately)
                Text(kw)
                  .fontSize(12)
                  .fontColor(PivoTheme.text)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .constraintSize({ maxWidth: this.wide ? 200 : 160 })
                  .padding({ left: 10, right: 4, top: 6, bottom: 6 })
                  .onClick(() => {
                    this.localKeyword = kw;
                    this.showHistoryDropdown = false;
                    this.onSearch(kw, true);
                  })

                // Delete '✕' (click to remove single item)
                Text('✕')
                  .fontSize(10)
                  .fontColor(PivoTheme.textMuted)
                  .padding({ left: 2, right: 8, top: 6, bottom: 6 })
                  .onClick(() => {
                    this.onRemoveSearchHistory(kw);
                    if (this.searchHistory.length <= 1) {
                      this.showHistoryDropdown = false;
                    }
                  })
              }
              .margin({ right: 8, bottom: 8 })
              .borderRadius(14)
              .backgroundColor(PivoTheme.surface)
              .border({ width: 0.8, color: PivoTheme.borderSearch })
            }, (kw: string) => kw)
          }
        }
        .constraintSize({ maxHeight: 180 })
        .scrollBar(BarState.Auto)
        .width('100%')
      }
      .width(this.wide ? 320 : 'calc(100% - 32vp)')
      .padding({ left: 16, right: 16, top: 12, bottom: 10 })
      .borderRadius(16)
      .backgroundColor(PivoTheme.surfaceGlassHeavy)
      .border({ width: 1, color: PivoTheme.borderHighlight })
      .shadow({ radius: 24, color: 'rgba(52, 52, 52, 0.22)', offsetY: 6 })
      .margin({
        top: this.wide ? 58 : 52,
        right: this.wide ? 24 : 16,
        left: this.wide ? 0 : 16
      })
    }
    .width('100%')
    .height('100%')
    .zIndex(90)
  }

  // Clear History Secondary Confirmation Modal
  @Builder
  clearHistoryConfirmModal() {
    Stack({ alignContent: Alignment.Center }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('rgba(0, 0, 0, 0.45)')
        .onClick(() => {
          this.showClearConfirmDialog = false;
        })

      Column({ space: 16 }) {
        Text('清空搜索历史')
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor(PivoTheme.text)

        Text('确定要清空所有搜索历史记录吗？此操作无法撤销。')
          .fontSize(13)
          .fontColor(PivoTheme.textMuted)
          .textAlign(TextAlign.Center)
          .lineHeight(20)

        Row({ space: 12 }) {
          Button('取消', { type: ButtonType.Normal })
            .layoutWeight(1)
            .height(36)
            .borderRadius(18)
            .backgroundColor(PivoTheme.surfaceRaised)
            .border({ width: 1, color: PivoTheme.border })
            .fontColor(PivoTheme.text)
            .fontSize(13)
            .onClick(() => {
              this.showClearConfirmDialog = false;
            })

          Button('清空', { type: ButtonType.Normal })
            .layoutWeight(1)
            .height(36)
            .borderRadius(18)
            .backgroundColor('#D9363E')
            .fontColor('#FFFFFF')
            .fontSize(13)
            .fontWeight(FontWeight.Bold)
            .onClick(() => {
              this.onClearSearchHistory();
              this.showClearConfirmDialog = false;
              this.showHistoryDropdown = false;
              try {
                promptAction.showToast({
                  message: '已清空搜索历史',
                  duration: 1500,
                  bottom: 80
                });
              } catch (_) {}
            })
        }
        .width('100%')
      }
      .width(this.wide ? 320 : 280)
      .padding(20)
      .borderRadius(20)
      .backgroundColor(PivoTheme.surfaceGlassHeavy)
      .border({ width: 1, color: PivoTheme.borderHighlight })
      .shadow({ radius: 24, color: 'rgba(52, 52, 52, 0.24)', offsetY: 8 })
    }
    .width('100%')
    .height('100%')
    .zIndex(100)
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      if (this.wide) {
        this.widescreenLayout()
      } else {
        this.portraitLayout()
      }

      if (this.showHistoryDropdown && this.searchHistory.length > 0) {
        this.searchHistoryDropdownOverlay()
      }

      if (this.showClearConfirmDialog) {
        this.clearHistoryConfirmModal()
      }
    }
    .width('100%')
    .height('100%')
  }
}
