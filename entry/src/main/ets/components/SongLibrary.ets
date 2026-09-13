import { promptAction } from '@kit.ArkUI';
import { Song, MusicSourceKind, RecommendPlaylist } from '../domain/MusicModels';
import { PivoTheme } from '../theme/PivoTheme';
import { SearchSourceOption, SEARCH_SOURCE_OPTIONS } from '../services/OnlineMusicSource';
import { ArrayDataSource } from '../domain/ArrayDataSource';
import { getSearchArtist } from './MusicRecommendationPage';

interface CategoryItem {
  id: string;
  name: string;
  icon: string;
  gradient: string;
  accentColor: string;
}

@Component({ freezeWhenInactive: true })
export struct SongLibrary {
  @Prop @Watch('onSongsChanged') songs: Song[] = [];
  @Prop selectedId: string = '';
  @Prop expanded: boolean = false;
  @Prop searchKeyword: string = '';
  @Prop searching: boolean = false;
  @Prop selectedSearchSource: string = 'all';
  @Prop isSearchingMore: boolean = false;
  @Prop hasMoreSearchResults: boolean = true;
  @Prop favoriteIds: string[] = [];
  @Prop recommendPlaylists: RecommendPlaylist[] = [];
  @Prop selectedPlaylistId: string = '';
  @Prop loadingRecommend: boolean = false;
  @State selectedCategoryIndex: number = 0;
  @State isSearchExpanded: boolean = false;
  @State focusedHeroBtn: string = '';
  @State focusedCatIndex: number = -1;
  @State focusedSpotlightBtn: string = '';
  @State focusedPlaylistId: string = '';
  @State focusedRecentSongId: string = '';
  @State focusedRowSongId: string = '';
  @State focusedToolBtn: string = '';
  @State focusedSearchSourceId: string = '';
  @State isSearchInputFocused: boolean = false;
  private songDataSource: ArrayDataSource<Song> = new ArrayDataSource<Song>();

  private onSongsChanged(): void {
    this.songDataSource.setData(this.songs);
  }

  aboutToAppear(): void {
    this.songDataSource.setData(this.songs);
  }

  onSelect: (song: Song) => void = (_song: Song): void => {};
  onImport: () => void = (): void => {};
  onSearch: (keyword: string) => void = (_keyword: string): void => {};
  onSwitchSearchSource: (source: string) => void = (_source: string): void => {};
  onLoadMoreSearch: () => void = (): void => {};
  onToggleFavorite: (song: Song) => void = (_song: Song): void => {};
  onSelectPlaylist: (playlist: RecommendPlaylist) => void = (_playlist: RecommendPlaylist): void => {};
  onRefreshRecommend: () => void = (): void => {};
  onToggleOrientation: () => void = (): void => {};

  private categories: CategoryItem[] = [
    { id: 'hot', name: '热唱', icon: '▥', gradient: PivoTheme.catHotGradient, accentColor: PivoTheme.primary },
    { id: 'chinese', name: '华语', icon: '✣', gradient: PivoTheme.catChineseGradient, accentColor: PivoTheme.accent },
    { id: 'nostalgia', name: '怀旧', icon: '⊙', gradient: PivoTheme.catNostalgiaGradient, accentColor: PivoTheme.accent },
    { id: 'soft', name: '轻声', icon: '≈', gradient: PivoTheme.catSoftGradient, accentColor: PivoTheme.accent }
  ];

  private getFeaturedSong(): Song | undefined {
    if (this.selectedId.length > 0) {
      const found = this.songs.find((s: Song) => s.id === this.selectedId);
      if (found) return found;
    }
    return this.songs.length > 0 ? this.songs[0] : undefined;
  }

  private isSongFavorite(song: Song): boolean {
    if (!song) return false;
    if (this.favoriteIds.includes(song.id)) return true;
    const songKey = `${(song.title || '').trim().toLowerCase()}:::${(song.artist || '').trim().toLowerCase()}`;
    return this.favoriteIds.includes(songKey);
  }

  // 1. Figma Screen 3 Hero Banner ("今晚开唱")
  @Builder
  heroBanner() {
    Stack({ alignContent: Alignment.TopEnd }) {
      Column({ space: 14 }) {
        Text('今晚开唱')
          .fontSize(36)
          .fontWeight(FontWeight.Bold)
          .fontColor(PivoTheme.text)
          .letterSpacing(0.5)

        Text('打开一首熟悉的歌，马上进入演唱状态')
          .fontSize(16)
          .fontColor(PivoTheme.textNavInactive)

        Button() {
          Row({ space: 8 }) {
            Text('▶')
              .fontSize(16)
              .fontColor(PivoTheme.primaryTextDark)
            Text('开始演唱')
              .fontSize(16)
              .fontWeight(FontWeight.Bold)
              .fontColor(PivoTheme.primaryTextDark)
          }
        }
        .height(48)
        .padding({ left: 24, right: 26 })
        .borderRadius(24)
        .backgroundColor(PivoTheme.primary)
        .border({
          width: this.focusedHeroBtn === 'play' ? 3 : 0,
          color: PivoTheme.surfaceSolid
        })
        .shadow(this.focusedHeroBtn === 'play' ? { radius: 22, color: PivoTheme.primaryGlow } : { radius: 16, color: PivoTheme.primaryGlow })
        .scale({ x: this.focusedHeroBtn === 'play' ? 1.05 : 1.0, y: this.focusedHeroBtn === 'play' ? 1.05 : 1.0 })
        .focusable(true)
        .defaultFocus(true)
        .groupDefaultFocus(true)
        .onFocus(() => {
          this.focusedHeroBtn = 'play';
        })
        .onBlur(() => {
          if (this.focusedHeroBtn === 'play') this.focusedHeroBtn = '';
        })
        .onClick(() => {
          const featured = this.getFeaturedSong();
          if (featured) {
            this.onSelect(featured);
          } else if (this.songs.length > 0) {
            this.onSelect(this.songs[0]);
          }
        })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .justifyContent(FlexAlign.Center)
      .padding({ left: 32, right: 32, top: 28, bottom: 28 })

      // Top-right search pill on hero
      Button() {
        Row({ space: 6 }) {
          Text('⌕')
            .fontSize(16)
            .fontColor(this.focusedHeroBtn === 'search' ? PivoTheme.primary : PivoTheme.text)
          Text('搜索')
            .fontSize(14)
            .fontColor(this.focusedHeroBtn === 'search' ? PivoTheme.primary : PivoTheme.text)
        }
      }
      .height(38)
      .padding({ left: 16, right: 18 })
      .borderRadius(19)
      .backgroundColor(this.focusedHeroBtn === 'search' ? PivoTheme.surfaceSelected : PivoTheme.surfaceGlass)
      .border({
        width: this.focusedHeroBtn === 'search' ? 2.5 : 1,
        color: this.focusedHeroBtn === 'search' ? PivoTheme.primary : PivoTheme.borderHighlight
      })
      .shadow(this.focusedHeroBtn === 'search' ? { radius: 14, color: PivoTheme.primaryGlow } : undefined)
      .scale({ x: this.focusedHeroBtn === 'search' ? 1.05 : 1.0, y: this.focusedHeroBtn === 'search' ? 1.05 : 1.0 })
      .margin({ top: 20, right: 24 })
      .focusable(true)
      .onFocus(() => {
        this.focusedHeroBtn = 'search';
      })
      .onBlur(() => {
        if (this.focusedHeroBtn === 'search') this.focusedHeroBtn = '';
      })
      .onClick(() => {
        this.isSearchExpanded = !this.isSearchExpanded;
      })
    }
    .width('100%')
    .height(200)
    .borderRadius(24)
    .linearGradient({
      angle: 104,
      colors: [
        ['#DDEFFD', 0.0],
        ['#DDF5E7', 0.42],
        ['#FFE1D7', 0.76],
        ['#FFF9EE', 1.0]
      ]
    })
  }

  // 2. Figma Screen 3 Category Cards Row (4 Cards)
  @Builder
  categoryCardsRow() {
    Row({ space: 14 }) {
      ForEach(this.categories, (cat: CategoryItem, index: number) => {
        Column({ space: 12 }) {
          Text(cat.icon)
            .fontSize(22)
            .fontWeight(FontWeight.Bold)
            .fontColor(cat.accentColor)

          Text(cat.name)
            .fontSize(22)
            .fontWeight(FontWeight.Bold)
            .fontColor(PivoTheme.text)
        }
        .layoutWeight(1)
        .height(115)
        .padding({ left: 20, top: 20, bottom: 18, right: 16 })
        .borderRadius(20)
        .alignItems(HorizontalAlign.Start)
        .justifyContent(FlexAlign.SpaceBetween)
        .linearGradient({
          angle: 90,
          colors: index === 0 ? [['#FFE1D7', 0.0], ['#FFF2C9', 1.0]] :
                  index === 1 ? [['#DDEFFD', 0.0], ['#F7FBF5', 1.0]] :
                  index === 2 ? [['#FFF0AD', 0.0], ['#FFF9EE', 1.0]] :
                                [['#DDF5E7', 0.0], ['#DDEFFD', 1.0]]
        })
        .border({
          width: this.focusedCatIndex === index ? 3 : (this.selectedCategoryIndex === index ? 1.5 : 0.8),
          color: this.focusedCatIndex === index ? PivoTheme.focusRing : (this.selectedCategoryIndex === index ? PivoTheme.primaryDark : PivoTheme.border)
        })
        .shadow(this.focusedCatIndex === index || this.selectedCategoryIndex === index ? { radius: 18, color: PivoTheme.primaryGlow } : undefined)
        .scale({ x: this.focusedCatIndex === index ? 1.04 : 1.0, y: this.focusedCatIndex === index ? 1.04 : 1.0 })
        .focusable(true)
        .onFocus(() => {
          this.focusedCatIndex = index;
        })
        .onBlur(() => {
          if (this.focusedCatIndex === index) this.focusedCatIndex = -1;
        })
        .onClick(() => {
          this.selectedCategoryIndex = index;
          if (this.recommendPlaylists.length > index) {
            this.onSelectPlaylist(this.recommendPlaylists[index]);
          } else {
            this.onRefreshRecommend();
          }
        })
      }, (cat: CategoryItem) => cat.id)
    }
    .width('100%')
  }

  // 3. Figma Screen 1 Left Featured Song Spotlight
  @Builder
  songSpotlightCard(song: Song) {
    Row({ space: 24 }) {
      // Large Album Artwork with warm gold shadow
      Stack({ alignContent: Alignment.Center }) {
        if ((song.coverUrl ?? '').length > 0) {
          Image(song.coverUrl)
            .width(180)
            .height(180)
            .objectFit(ImageFit.Cover)
            .borderRadius(24)
        } else {
          Column({ space: 8 }) {
            Text(song.title)
              .fontSize(24)
              .fontWeight(FontWeight.Bold)
              .fontColor(PivoTheme.text)
              .maxLines(1)
            Text(song.artist)
              .fontSize(12)
              .fontColor(PivoTheme.textMuted)
          }
          .width(180)
          .height(180)
          .justifyContent(FlexAlign.Center)
          .borderRadius(24)
          .linearGradient({
            angle: 135,
            colors: [['#FFF0AD', 0.14], ['#FFE1D7', 0.54], ['#DDEFFD', 0.86]]
          })
        }
      }
      .width(180)
      .height(180)
      .shadow({ radius: 24, color: 'rgba(178, 166, 128, 0.22)', offsetY: 6 })

      // Song Details & CTA Buttons
      Column({ space: 8 }) {
        Row({ space: 8 }) {
          Text(song.title)
            .fontSize(24)
            .fontWeight(FontWeight.Bold)
            .fontColor(PivoTheme.text)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)

          // SQ Badge
          Row() {
            Text('SQ')
              .fontSize(11)
              .fontWeight(FontWeight.Bold)
              .fontColor(PivoTheme.sqBadgeText)
          }
          .padding({ left: 6, right: 6, top: 2, bottom: 2 })
          .backgroundColor(PivoTheme.sqBadgeBg)
          .border({ width: 1, color: PivoTheme.sqBadgeBorder })
          .borderRadius(6)
        }
        .width('100%')

        Text(song.artist)
          .fontSize(16)
          .fontColor(PivoTheme.text)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        Row({ space: 6 }) {
          Text('◉')
            .fontSize(12)
            .fontColor(PivoTheme.accent)
          Text('演唱级无损高保真曲库')
            .fontSize(13)
            .fontColor(PivoTheme.textSecondary)
        }

        Blank()

        Row({ space: 12 }) {
          Button() {
            Row({ space: 6 }) {
              Text('▶')
                .fontSize(14)
                .fontColor(PivoTheme.primaryTextDark)
              Text('开始演唱')
                .fontSize(14)
                .fontWeight(FontWeight.Bold)
                .fontColor(PivoTheme.primaryTextDark)
            }
          }
          .height(40)
          .padding({ left: 16, right: 18 })
          .borderRadius(12)
          .backgroundColor(PivoTheme.primary)
          .border({
            width: this.focusedSpotlightBtn === 'play' ? 2.5 : 0,
            color: '#FFFFFF'
          })
          .shadow(this.focusedSpotlightBtn === 'play' ? { radius: 16, color: PivoTheme.primaryGlow } : { radius: 12, color: PivoTheme.primaryGlow })
          .scale({ x: this.focusedSpotlightBtn === 'play' ? 1.05 : 1.0, y: this.focusedSpotlightBtn === 'play' ? 1.05 : 1.0 })
          .focusable(true)
          .onFocus(() => {
            this.focusedSpotlightBtn = 'play';
          })
          .onBlur(() => {
            if (this.focusedSpotlightBtn === 'play') this.focusedSpotlightBtn = '';
          })
          .onClick(() => this.onSelect(song))

          Button() {
            Row({ space: 6 }) {
              Text(this.isSongFavorite(song) ? '★' : '☆')
                .fontSize(15)
                .fontColor(this.isSongFavorite(song) ? '#FBBF24' : PivoTheme.text)
              Text(this.isSongFavorite(song) ? '已收藏' : '收藏')
                .fontSize(13)
                .fontColor(this.focusedSpotlightBtn === 'fav' ? PivoTheme.primary : PivoTheme.text)
            }
          }
          .height(40)
          .padding({ left: 14, right: 16 })
          .borderRadius(12)
          .backgroundColor(this.focusedSpotlightBtn === 'fav' ? PivoTheme.surfaceSelected : PivoTheme.surfaceRaised)
          .border({
            width: this.focusedSpotlightBtn === 'fav' ? 2.5 : 1,
            color: this.focusedSpotlightBtn === 'fav' ? PivoTheme.primary : PivoTheme.borderMuted
          })
          .shadow(this.focusedSpotlightBtn === 'fav' ? { radius: 14, color: PivoTheme.primaryGlow } : undefined)
          .scale({ x: this.focusedSpotlightBtn === 'fav' ? 1.05 : 1.0, y: this.focusedSpotlightBtn === 'fav' ? 1.05 : 1.0 })
          .focusable(true)
          .onFocus(() => {
            this.focusedSpotlightBtn = 'fav';
          })
          .onBlur(() => {
            if (this.focusedSpotlightBtn === 'fav') this.focusedSpotlightBtn = '';
          })
          .onClick(() => this.onToggleFavorite(song))
        }
      }
      .layoutWeight(1)
      .height(180)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .padding(18)
    .borderRadius(20)
    .backgroundColor(PivoTheme.surface)
    .border({ width: 1, color: PivoTheme.border })
  }

  // 4. Figma Screen 1 Right Column Recommendation Item
  @Builder
  recommendListItem(playlist: RecommendPlaylist, index: number) {
    Row({ space: 12 }) {
      // Cover Thumbnail
      Stack({ alignContent: Alignment.Center }) {
        if (playlist.coverUrl.length > 0) {
          Image(playlist.coverUrl)
            .width(58)
            .height(58)
            .objectFit(ImageFit.Cover)
            .borderRadius(12)
        } else {
          Row()
            .width(58)
            .height(58)
            .borderRadius(12)
            .linearGradient({
              angle: 90,
              colors: index === 0 ? [['#FFFFFF', 0.0], ['#FFE1D7', 1.0]] :
                      index === 1 ? [['#FFFFFF', 0.0], ['#DDEFFD', 1.0]] :
                      index === 2 ? [['#FFFFFF', 0.0], ['#FFF0AD', 1.0]] :
                      index === 3 ? [['#FFFFFF', 0.0], ['#DDF5E7', 1.0]] :
                                    [['#FFFFFF', 0.0], ['#FFF2C9', 1.0]]
            })
        }
      }

      Column({ space: 4 }) {
        Text(playlist.name)
          .fontSize(14)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.focusedPlaylistId === playlist.id ? PivoTheme.primary : PivoTheme.text)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        Text(`${playlist.trackCount > 0 ? playlist.trackCount : 20}首`)
          .fontSize(12)
          .fontColor(PivoTheme.textMuted)
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      // Right Play Icon
      Text('▶')
        .fontSize(16)
        .fontColor(this.selectedPlaylistId === playlist.id || this.focusedPlaylistId === playlist.id ? PivoTheme.primary : PivoTheme.textMuted)
        .padding({ right: 6 })
    }
    .width('100%')
    .padding(10)
    .borderRadius(14)
    .backgroundColor(this.focusedPlaylistId === playlist.id ? PivoTheme.surfaceSelected : (this.selectedPlaylistId === playlist.id ? PivoTheme.surface : Color.Transparent))
    .border({
      width: this.focusedPlaylistId === playlist.id ? 2.5 : (this.selectedPlaylistId === playlist.id ? 1.5 : 0.8),
      color: this.focusedPlaylistId === playlist.id ? PivoTheme.focusRing : (this.selectedPlaylistId === playlist.id ? PivoTheme.primaryDark : PivoTheme.border)
    })
    .shadow(this.focusedPlaylistId === playlist.id ? { radius: 14, color: PivoTheme.primaryGlow } : undefined)
    .scale({ x: this.focusedPlaylistId === playlist.id ? 1.03 : 1.0, y: this.focusedPlaylistId === playlist.id ? 1.03 : 1.0 })
    .focusable(true)
    .onFocus(() => {
      this.focusedPlaylistId = playlist.id;
    })
    .onBlur(() => {
      if (this.focusedPlaylistId === playlist.id) this.focusedPlaylistId = '';
    })
    .onClick(() => this.onSelectPlaylist(playlist))
  }

  // 5. Figma Screen 3 Bottom "最近播放" History Card
  @Builder
  recentPlayCard(song: Song) {
    Row({ space: 10 }) {
      Stack({ alignContent: Alignment.Center }) {
        if ((song.coverUrl ?? '').length > 0) {
          Image(song.coverUrl)
            .width(48)
            .height(48)
            .objectFit(ImageFit.Cover)
            .borderRadius(10)
        } else {
          Row()
            .width(48)
            .height(48)
            .borderRadius(10)
            .linearGradient({
              angle: 90,
              colors: [['#FFFFFF', 0.0], ['#FFE1D7', 1.0]]
            })
        }
      }

      Column({ space: 2 }) {
        Text(song.title)
          .fontSize(14)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.focusedRecentSongId === song.id ? PivoTheme.primary : PivoTheme.text)
          .maxLines(1)
        Text(song.artist)
          .fontSize(11)
          .fontColor(PivoTheme.textNavInactive)
          .maxLines(1)
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      // Mini play action circle
      Row() {
        Text(this.selectedId === song.id ? '▥' : '▶')
          .fontSize(12)
          .fontColor(this.focusedRecentSongId === song.id ? PivoTheme.primary : PivoTheme.accent)
      }
      .width(32)
      .height(32)
      .borderRadius(16)
      .justifyContent(FlexAlign.Center)
      .backgroundColor(PivoTheme.backgroundDark)
      .border({ width: 1, color: this.focusedRecentSongId === song.id ? PivoTheme.primary : PivoTheme.borderSubtle })
    }
    .width(220)
    .height(64)
    .padding({ left: 10, right: 12 })
    .borderRadius(14)
    .backgroundColor(this.focusedRecentSongId === song.id ? PivoTheme.surfaceSelected : PivoTheme.surfaceRaised)
    .border({
      width: this.focusedRecentSongId === song.id ? 2.5 : 0.8,
      color: this.focusedRecentSongId === song.id ? PivoTheme.primary : PivoTheme.border
    })
    .shadow(this.focusedRecentSongId === song.id ? { radius: 14, color: PivoTheme.primaryGlow } : undefined)
    .scale({ x: this.focusedRecentSongId === song.id ? 1.04 : 1.0, y: this.focusedRecentSongId === song.id ? 1.04 : 1.0 })
    .focusable(true)
    .onFocus(() => {
      this.focusedRecentSongId = song.id;
    })
    .onBlur(() => {
      if (this.focusedRecentSongId === song.id) this.focusedRecentSongId = '';
    })
    .onClick(() => this.onSelect(song))
  }

  // 6. Generic Song Card (for list / search results)
  @Builder
  songRowCard(song: Song) {
    Row({ space: 12 }) {
      Stack({ alignContent: Alignment.BottomEnd }) {
        if ((song.coverUrl ?? '').length > 0) {
          Image(song.coverUrl)
            .width(50)
            .height(50)
            .objectFit(ImageFit.Cover)
            .borderRadius(12)
        } else {
          Column() {
            Text('♫')
              .fontSize(18)
              .fontColor(PivoTheme.primary)
          }
          .width(50)
          .height(50)
          .justifyContent(FlexAlign.Center)
          .backgroundColor(PivoTheme.surfaceRaised)
          .borderRadius(12)
        }

        Row() {
          Text('SQ')
            .fontSize(8)
            .fontWeight(FontWeight.Bolder)
            .fontColor(PivoTheme.sqBadgeText)
        }
        .padding({ left: 3, right: 3, top: 1, bottom: 1 })
        .backgroundColor(PivoTheme.sqBadgeBg)
        .borderRadius(4)
        .margin(2)
      }

      Column({ space: 4 }) {
        Text(song.title)
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.focusedRowSongId === song.id || this.selectedId === song.id ? PivoTheme.primary : PivoTheme.text)
          .maxLines(1)

        Row({ space: 6 }) {
          Text(song.artist)
            .fontSize(12)
            .fontColor(PivoTheme.textSecondary)
            .maxLines(1)
          Text('·')
            .fontSize(11)
            .fontColor(PivoTheme.textFaint)
          Text('SQ无损')
            .fontSize(10)
            .fontColor(PivoTheme.accent)
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      Row({ space: 8 }) {
        Row() {
          Text(this.isSongFavorite(song) ? '★' : '☆')
            .fontSize(16)
            .fontColor(this.isSongFavorite(song) ? '#FBBF24' : PivoTheme.textMuted)
        }
        .width(36)
        .height(36)
        .borderRadius(18)
        .justifyContent(FlexAlign.Center)
        .backgroundColor(PivoTheme.surfaceRaised)
        .focusable(true)
        .onClick(() => this.onToggleFavorite(song))

        Row() {
          Text('▶')
            .fontSize(13)
            .fontColor(this.selectedId === song.id ? PivoTheme.primaryTextDark : PivoTheme.text)
        }
        .width(36)
        .height(36)
        .borderRadius(18)
        .justifyContent(FlexAlign.Center)
        .backgroundColor(this.selectedId === song.id ? PivoTheme.primary : PivoTheme.surfaceRaised)
        .shadow(this.selectedId === song.id ? { radius: 12, color: PivoTheme.primaryGlow } : undefined)
        .focusable(true)
      }
    }
    .width('100%')
    .padding(12)
    .borderRadius(16)
    .backgroundColor(this.focusedRowSongId === song.id ? PivoTheme.surfaceSelected : (this.selectedId === song.id ? PivoTheme.surfaceSelectedSubtle : PivoTheme.surfaceRaised))
    .border({
      width: this.focusedRowSongId === song.id ? 2.5 : 1,
      color: this.focusedRowSongId === song.id ? PivoTheme.primary : (this.selectedId === song.id ? PivoTheme.primary : PivoTheme.border)
    })
    .shadow(this.focusedRowSongId === song.id ? { radius: 14, color: PivoTheme.primaryGlow } : undefined)
    .scale({ x: this.focusedRowSongId === song.id ? 1.02 : 1.0, y: this.focusedRowSongId === song.id ? 1.02 : 1.0 })
    .focusable(true)
    .onFocus(() => {
      this.focusedRowSongId = song.id;
    })
    .onBlur(() => {
      if (this.focusedRowSongId === song.id) this.focusedRowSongId = '';
    })
    .onClick(() => this.onSelect(song))
    .gesture(
      LongPressGesture({ repeat: false, duration: 400 })
        .onAction((_event: GestureEvent) => {
          const searchArtist = getSearchArtist(song.artist);
          if (searchArtist.length > 0) {
            promptAction.showToast({ message: `正在搜索作者：${searchArtist}` });
            this.onSearch(searchArtist);
          } else {
            promptAction.showToast({ message: '该歌曲暂无有效作者信息' });
          }
        })
    )
  }

  // Search Source Switcher Tab Bar (All + NetEase, QQ, KuGou, Kuwo, Migu, Qianqian, Soda, Apple)
  @Builder
  searchSourceTabBar() {
    Scroll() {
      Row({ space: 8 }) {
        ForEach(SEARCH_SOURCE_OPTIONS, (sourceOption: SearchSourceOption) => {
          Button({ type: ButtonType.Normal, stateEffect: false }) {
            Row({ space: 6 }) {
              Row()
                .width(6)
                .height(6)
                .borderRadius(3)
                .backgroundColor(this.selectedSearchSource === sourceOption.id ? '#FFFFFF' : sourceOption.brandColor)

              Text(sourceOption.name)
                .fontSize(12)
                .fontWeight(this.selectedSearchSource === sourceOption.id ? FontWeight.Bold : FontWeight.Normal)
                .fontColor(this.selectedSearchSource === sourceOption.id ? '#FFFFFF' : (this.focusedSearchSourceId === sourceOption.id ? PivoTheme.primary : PivoTheme.text))
            }
            .padding({ left: 10, right: 10, top: 4, bottom: 4 })
          }
          .height(28)
          .borderRadius(14)
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
          .id(`tv_lib_search_source_${sourceOption.id}`)
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
      .padding({ left: 2, right: 2, top: 2, bottom: 2 })
    }
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Off)
    .width('100%')
    .margin({ top: 2, bottom: 4 })
  }

  build() {
    Stack({ alignContent: Alignment.BottomEnd }) {
      Scroll() {
        Column({ space: 24 }) {
          // Top Search & Tool Bar (Figma Screen 1 Search Capsule)
          Row({ space: 12 }) {
            Row({ space: 8 }) {
              Text('○')
                .fontSize(16)
                .fontColor(this.isSearchInputFocused ? PivoTheme.primary : PivoTheme.textMuted)

              TextInput({ text: this.searchKeyword, placeholder: '搜索歌曲、歌手或专辑' })
                .height(40)
                .layoutWeight(1)
                .fontSize(14)
                .fontColor(PivoTheme.text)
                .placeholderColor(PivoTheme.textMuted)
                .backgroundColor('transparent')
                .padding({ left: 4, right: 4 })
                .focusable(true)
                .onFocus(() => {
                  this.isSearchInputFocused = true;
                })
                .onBlur(() => {
                  this.isSearchInputFocused = false;
                })
                .onChange((value: string) => { this.searchKeyword = value; })
                .onSubmit(() => this.onSearch(this.searchKeyword))

              if (this.searchKeyword.length > 0) {
                Text('✕')
                  .fontSize(14)
                  .fontColor(PivoTheme.textMuted)
                  .padding(6)
                  .onClick(() => {
                    this.searchKeyword = '';
                    this.onSearch('');
                  })
              }
            }
            .layoutWeight(1)
            .height(46)
            .backgroundColor(this.isSearchInputFocused ? PivoTheme.surfaceSelectedSubtle : PivoTheme.surfaceGlass)
            .borderRadius(23)
            .border({
              width: this.isSearchInputFocused ? 2.5 : 1,
              color: this.isSearchInputFocused ? PivoTheme.primary : PivoTheme.borderSearch
            })
            .shadow(this.isSearchInputFocused ? { radius: 14, color: PivoTheme.primaryGlow } : undefined)
            .padding({ left: 16, right: 12 })

            // Orientation Toggle Button
            Button() {
              Text(this.expanded ? '📱' : '📺')
                .fontSize(16)
                .fontColor(this.focusedToolBtn === 'orient' ? PivoTheme.primary : PivoTheme.text)
            }
            .width(46)
            .height(46)
            .backgroundColor(this.focusedToolBtn === 'orient' ? PivoTheme.surfaceSelected : PivoTheme.surfaceGlass)
            .borderRadius(23)
            .border({
              width: this.focusedToolBtn === 'orient' ? 2.5 : 1,
              color: this.focusedToolBtn === 'orient' ? PivoTheme.primary : PivoTheme.borderSearch
            })
            .shadow(this.focusedToolBtn === 'orient' ? { radius: 14, color: PivoTheme.primaryGlow } : undefined)
            .scale({ x: this.focusedToolBtn === 'orient' ? 1.08 : 1.0, y: this.focusedToolBtn === 'orient' ? 1.08 : 1.0 })
            .focusable(true)
            .onFocus(() => {
              this.focusedToolBtn = 'orient';
            })
            .onBlur(() => {
              if (this.focusedToolBtn === 'orient') this.focusedToolBtn = '';
            })
            .onClick(() => this.onToggleOrientation())

            // Refresh Recommendations Button
            Button() {
              Text('↻')
                .fontSize(18)
                .fontColor(this.focusedToolBtn === 'refresh' ? PivoTheme.primary : PivoTheme.text)
            }
            .width(46)
            .height(46)
            .backgroundColor(this.focusedToolBtn === 'refresh' ? PivoTheme.surfaceSelected : PivoTheme.surfaceGlass)
            .borderRadius(23)
            .border({
              width: this.focusedToolBtn === 'refresh' ? 2.5 : 1,
              color: this.focusedToolBtn === 'refresh' ? PivoTheme.primary : PivoTheme.borderSearch
            })
            .shadow(this.focusedToolBtn === 'refresh' ? { radius: 14, color: PivoTheme.primaryGlow } : undefined)
            .scale({ x: this.focusedToolBtn === 'refresh' ? 1.08 : 1.0, y: this.focusedToolBtn === 'refresh' ? 1.08 : 1.0 })
            .focusable(true)
            .onFocus(() => {
              this.focusedToolBtn = 'refresh';
            })
            .onBlur(() => {
              if (this.focusedToolBtn === 'refresh') this.focusedToolBtn = '';
            })
            .onClick(() => this.onRefreshRecommend())
          }
          .width('100%')

          if (this.searchKeyword.length > 0) {
            // Search Results Mode
            Column({ space: 10 }) {
              Row({ space: 6 }) {
                Text('🎵')
                  .fontSize(16)
                Text(`搜索结果 (${this.songs.length} 首)`)
                  .fontSize(16)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(PivoTheme.text)
              }
              .width('100%')

              this.searchSourceTabBar()

              if (this.songs.length === 0) {
                Column({ space: 10 }) {
                  Text(this.searching ? '正在从云端搜寻无损歌曲…' : '未找到匹配歌曲')
                    .fontSize(14)
                    .fontColor(PivoTheme.textMuted)
                }
                .width('100%')
                .height(160)
                .justifyContent(FlexAlign.Center)
              } else {
                List({ space: 10 }) {
                  LazyForEach(this.songDataSource, (song: Song) => {
                    ListItem() { this.songRowCard(song) }
                  }, (song: Song) => `${song.id}_${this.selectedId === song.id ? 'active' : 'idle'}`)

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
                .width('100%')
                .onReachEnd(() => {
                  if (this.searchKeyword.length > 0) {
                    this.onLoadMoreSearch();
                  }
                })
              }
            }
            .width('100%')
          } else {
            // Normal Discovery Mode (Matching Figma Screen 3 & Screen 1)

            // 1. Hero Banner ("今晚开唱")
            this.heroBanner()

            // 2. 4 Category Cards
            this.categoryCardsRow()

            // 3. Figma Screen 1: Spotlight + "为你推荐" Playlist Split
            Row({ space: 24 }) {
              // Left: Spotlight of Featured Song
              Column({ space: 12 }) {
                Text('精选推荐')
                  .fontSize(18)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(PivoTheme.text)

                if (this.getFeaturedSong()) {
                  this.songSpotlightCard(this.getFeaturedSong()!)
                }
              }
              .layoutWeight(1.2)
              .alignItems(HorizontalAlign.Start)

              // Right: "为你推荐" Playlists Column
              Column({ space: 12 }) {
                Row({ space: 6 }) {
                  Text('为你推荐')
                    .fontSize(18)
                    .fontWeight(FontWeight.Bold)
                    .fontColor(PivoTheme.text)
                }

                if (this.recommendPlaylists.length > 0) {
                  Column({ space: 10 }) {
                    ForEach(this.recommendPlaylists.slice(0, 5), (playlist: RecommendPlaylist, index: number) => {
                      this.recommendListItem(playlist, index)
                    }, (playlist: RecommendPlaylist) => playlist.id)
                  }
                  .width('100%')
                }
              }
              .layoutWeight(0.9)
              .alignItems(HorizontalAlign.Start)
            }
            .width('100%')
            .alignItems(VerticalAlign.Top)

            // 4. Figma Screen 3: "最近播放" Section
            Column({ space: 12 }) {
              Text('最近播放')
                .fontSize(18)
                .fontWeight(FontWeight.Bold)
                .fontColor(PivoTheme.text)

              Scroll() {
                Row({ space: 14 }) {
                  ForEach(this.songs.slice(0, 8), (song: Song) => {
                    this.recentPlayCard(song)
                  }, (song: Song) => song.id)
                }
              }
              .width('100%')
              .scrollable(ScrollDirection.Horizontal)
              .scrollBar(BarState.Off)
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
          }
        }
        .width('100%')
        .padding({ left: 24, right: 24, top: 20, bottom: 80 })
      }
      .width('100%')
      .height('100%')
      .scrollBar(BarState.Off)

      // Floating Action Button for Local Import
      Button() {
        Row({ space: 6 }) {
          Text('＋')
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor(PivoTheme.primaryTextDark)
          Text('导入伴奏')
            .fontSize(13)
            .fontWeight(FontWeight.Bold)
            .fontColor(PivoTheme.primaryTextDark)
        }
      }
      .id('btn_fab_import')
      .height(44)
      .padding({ left: 18, right: 20 })
      .borderRadius(22)
      .backgroundColor(PivoTheme.primary)
      .border({
        width: this.focusedToolBtn === 'fab' ? 2.5 : 0,
        color: '#FFFFFF'
      })
      .shadow(this.focusedToolBtn === 'fab' ? { radius: 24, color: PivoTheme.primaryGlow } : { radius: 18, color: PivoTheme.primaryGlow, offsetY: 4 })
      .scale({ x: this.focusedToolBtn === 'fab' ? 1.08 : 1.0, y: this.focusedToolBtn === 'fab' ? 1.08 : 1.0 })
      .margin({ right: 24, bottom: 20 })
      .focusable(true)
      .onFocus(() => {
        this.focusedToolBtn = 'fab';
      })
      .onBlur(() => {
        if (this.focusedToolBtn === 'fab') this.focusedToolBtn = '';
      })
      .onClick(() => this.onImport())
    }
    .width('100%')
    .height('100%')
    .backgroundColor(PivoTheme.background)
  }
}
