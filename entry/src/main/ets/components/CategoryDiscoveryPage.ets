import { Song, PlaybackState } from '../domain/MusicModels';
import { PivoTheme } from '../theme/PivoTheme';

export interface CategoryItem {
  id: string;
  name: string;
  tag: string;
  icon: string;
  iconColor: string;
  gradientColors: [ResourceColor, number][];
}

@Component({ freezeWhenInactive: true })
export struct CategoryDiscoveryPage {
  @Prop wide: boolean = true;
  @Prop recentSongs: Song[] = [];
  @Prop selectedSongId: string = '';
  @Prop playbackState: PlaybackState = PlaybackState.IDLE;
  @State activeCategory: string = 'hot';
  @State focusedHeroBtn: string = '';
  @State focusedCategoryId: string = '';
  @State focusedSongId: string = '';

  onSelectSong: (song: Song) => void = (_song: Song): void => {};
  onStartSinging: () => void = (): void => {};
  onOpenSearch: (categoryKeyword?: string) => void = (_kw?: string): void => {};
  onSelectCategory: (categoryId: string, categoryName: string) => void = (_id: string, _name: string): void => {};

  private categories: CategoryItem[] = [
    {
      id: 'hot',
      name: '热唱',
      tag: '流行热榜',
      icon: '☲',
      iconColor: '#FF5A5F',
      gradientColors: [['#FFE1D7', 0.0], ['#FFF2C9', 1.0]]
    },
    {
      id: 'chinese',
      name: '华语',
      tag: '经典金曲',
      icon: '✤',
      iconColor: '#38B6FF',
      gradientColors: [['#DDEFFD', 0.0], ['#F7FBF5', 1.0]]
    },
    {
      id: 'nostalgia',
      name: '怀旧',
      tag: '岁月回响',
      icon: '◉',
      iconColor: '#FFB347',
      gradientColors: [['#FFF0AD', 0.0], ['#FFF9EE', 1.0]]
    },
    {
      id: 'soft',
      name: '轻声',
      tag: '治愈慢歌',
      icon: '≈',
      iconColor: '#63BEE8',
      gradientColors: [['#DDF5E7', 0.0], ['#DDEFFD', 1.0]]
    }
  ];

  @Builder
  categoryCard(cat: CategoryItem, index: number, isCompact: boolean = false) {
    Column() {
      // Top: Icon + Tag Badge
      Row() {
        Text(cat.icon)
          .fontSize(isCompact ? 16 : 18)
          .fontColor(cat.iconColor)

        Blank()

        Row() {
          Text(cat.tag)
            .fontSize(isCompact ? 9 : 10)
            .fontWeight(FontWeight.Medium)
            .fontColor('rgba(255, 255, 255, 0.75)')
        }
        .padding({ left: 6, right: 6, top: 2, bottom: 2 })
        .borderRadius(4)
        .backgroundColor('rgba(98, 98, 98, 0.32)')
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Blank()

      // Bottom: Title
      Row() {
        Text(cat.name)
          .fontSize(isCompact ? 18 : 20)
          .fontWeight(FontWeight.Bold)
          .fontColor(PivoTheme.text)

        Blank()

        if (this.activeCategory === cat.id) {
          Row()
            .width(6)
            .height(6)
            .borderRadius(3)
            .backgroundColor(PivoTheme.primary)
            .shadow({ radius: 6, color: PivoTheme.primaryGlow })
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
    }
    .layoutWeight(1)
    .height(isCompact ? 92 : 112)
    .padding({ left: 14, right: 14, top: 12, bottom: 12 })
    .alignItems(HorizontalAlign.Start)
    .borderRadius(16)
    .linearGradient({
      angle: 135,
      colors: cat.gradientColors
    })
    .border({
      width: this.focusedCategoryId === cat.id ? 3.5 : (this.activeCategory === cat.id ? 1.5 : 1),
      color: this.focusedCategoryId === cat.id ? PivoTheme.primary : (this.activeCategory === cat.id ? PivoTheme.borderGlow : PivoTheme.border)
    })
    .shadow(this.focusedCategoryId === cat.id ? { radius: 24, color: PivoTheme.primaryGlow } : undefined)
    .scale({ x: this.focusedCategoryId === cat.id ? 1.05 : 1.0, y: this.focusedCategoryId === cat.id ? 1.05 : 1.0 })
    .animation({ duration: 200, curve: Curve.EaseOut })
    .focusable(true)
    .focusOnTouch(true)
    .tabIndex(6 + index)
    .id(`cat_card_${cat.id}`)
    .nextFocus({
      up: index <= 1 ? 'hero_start_btn' : 'hero_search_btn',
      down: this.recentSongs.length > index ? `recent_song_${this.recentSongs[index].id}` : undefined,
      left: index === 0 ? 'sidebar_nav_tab_0' : (index > 0 ? `cat_card_${this.categories[index - 1].id}` : undefined),
      right: index < this.categories.length - 1 ? `cat_card_${this.categories[index + 1].id}` : undefined
    })
    .onFocus(() => {
      this.focusedCategoryId = cat.id;
    })
    .onBlur(() => {
      if (this.focusedCategoryId === cat.id) {
        this.focusedCategoryId = '';
      }
    })
    .onClick(() => {
      this.activeCategory = cat.id;
      this.onSelectCategory(cat.id, cat.name);
    })
  }

  @Builder
  recentSongItem(song: Song, index: number, isVerticalList: boolean = false) {
    Row({ space: 10 }) {
      // Cover box
      Row()
        .width(isVerticalList ? 42 : 36)
        .height(isVerticalList ? 42 : 36)
        .borderRadius(8)
        .linearGradient({
          angle: 135,
          colors: index === 0 ? [['#FFFFFF', 0.0], ['#FFE1D7', 1.0]] :
                  index === 1 ? [['#FFFFFF', 0.0], ['#DDEFFD', 1.0]] :
                  index === 2 ? [['#FFFFFF', 0.0], ['#FFF0AD', 1.0]] :
                                [['#FFFFFF', 0.0], ['#DDF5E7', 1.0]]
        })

      Column({ space: 2 }) {
        Text(song.title)
          .fontSize(isVerticalList ? 14 : 12)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.focusedSongId === song.id ? PivoTheme.primary : PivoTheme.text)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        Row({ space: 6 }) {
          Text(song.artist)
            .fontSize(isVerticalList ? 12 : 10)
            .fontColor(PivoTheme.textMuted)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })

          if (isVerticalList) {
            Text('·')
              .fontSize(10)
              .fontColor(PivoTheme.textFaint)
            Text('48kHz SQ')
              .fontSize(10)
              .fontColor(PivoTheme.sqBadgeText)
          }
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      // Play / Playing Status
      if (index === 0 && this.playbackState === PlaybackState.PLAYING) {
        Row({ space: 2 }) {
          Row().width(2).height(8).borderRadius(1).backgroundColor(PivoTheme.accent)
          Row().width(2).height(13).borderRadius(1).backgroundColor(PivoTheme.accent)
          Row().width(2).height(6).borderRadius(1).backgroundColor(PivoTheme.accent)
        }
        .alignItems(VerticalAlign.Bottom)
        .padding({ right: 2 })
      } else {
        Row() {
          Image($r('app.media.ic_play'))
            .width(isVerticalList ? 11 : 10)
            .height(isVerticalList ? 11 : 10)
            .fillColor(this.focusedSongId === song.id ? '#FFFFFF' : PivoTheme.text)
            .objectFit(ImageFit.Contain)
            .margin({ left: isVerticalList ? 1.5 : 1 })
        }
        .width(isVerticalList ? 28 : 24)
        .height(isVerticalList ? 28 : 24)
        .borderRadius(14)
        .justifyContent(FlexAlign.Center)
        .backgroundColor(this.focusedSongId === song.id ? PivoTheme.text : 'rgba(0, 0, 0, 0.05)')
        .border({
          width: this.focusedSongId === song.id ? 0 : 0.8,
          color: PivoTheme.borderSubtle
        })
        .shadow(this.focusedSongId === song.id ? { radius: 6, color: 'rgba(0, 0, 0, 0.16)' } : undefined)
      }
    }
    .layoutWeight(isVerticalList ? 0 : 1)
    .width(isVerticalList ? '100%' : undefined)
    .height(isVerticalList ? 58 : 54)
    .padding({ left: 10, right: 10 })
    .alignItems(VerticalAlign.Center)
    .borderRadius(12)
    .backgroundColor(this.focusedSongId === song.id ? PivoTheme.surfaceSelectedSubtle : PivoTheme.surface)
    .border({
      width: this.focusedSongId === song.id ? 2.5 : 1,
      color: this.focusedSongId === song.id ? PivoTheme.primary : PivoTheme.border
    })
    .shadow(this.focusedSongId === song.id ? { radius: 14, color: PivoTheme.primaryGlow } : undefined)
    .scale({ x: this.focusedSongId === song.id ? 1.03 : 1.0, y: this.focusedSongId === song.id ? 1.03 : 1.0 })
    .focusable(true)
    .focusOnTouch(true)
    .tabIndex(10 + index)
    .id(`recent_song_${song.id}`)
    .onFocus(() => {
      this.focusedSongId = song.id;
    })
    .onBlur(() => {
      if (this.focusedSongId === song.id) {
        this.focusedSongId = '';
      }
    })
    .onClick(() => this.onSelectSong(song))
  }

  // Widescreen Layout (TV / 16:9 Landscape)
  @Builder
  widescreenLayout() {
    Column() {
      // 1. Compact Sleek Hero Bar: 今晚开唱
      Row() {
        Row({ space: 10 }) {
          Text('今晚开唱')
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor(PivoTheme.text)
            .letterSpacing(0.5)

          Row()
            .width(2)
            .height(12)
            .borderRadius(1)
            .backgroundColor('rgba(255, 255, 255, 0.25)')

          Text('打开一首熟悉的歌，马上进入演唱状态')
            .fontSize(12)
            .fontColor('#94A3B8')
            .maxLines(1)
        }
        .alignItems(VerticalAlign.Center)

        Blank()

        Row({ space: 10 }) {
          // ▶ 开始演唱 Primary Pill
          Row({ space: 6 }) {
            Text('▶')
              .fontSize(12)
              .fontColor(PivoTheme.primaryTextDark)
            Text('开始演唱')
              .fontSize(12)
              .fontWeight(FontWeight.Bold)
              .fontColor(PivoTheme.primaryTextDark)
          }
          .height(32)
          .padding({ left: 14, right: 16 })
          .borderRadius(16)
          .backgroundColor(PivoTheme.primary)
          .shadow(this.focusedHeroBtn === 'sing' ? { radius: 16, color: PivoTheme.primaryGlow } : { radius: 10, color: PivoTheme.primaryGlow })
          .border({
            width: this.focusedHeroBtn === 'sing' ? 2.5 : 0,
            color: '#FFFFFF'
          })
          .scale({ x: this.focusedHeroBtn === 'sing' ? 1.05 : 1.0, y: this.focusedHeroBtn === 'sing' ? 1.05 : 1.0 })
          .focusable(true)
          .focusOnTouch(true)
          .tabIndex(4)
          .id('hero_start_btn')
          .nextFocus({
            left: 'sidebar_nav_tab_0',
            right: 'hero_search_btn',
            down: 'cat_card_hot'
          })
          .onFocus(() => {
            this.focusedHeroBtn = 'sing';
          })
          .onBlur(() => {
            if (this.focusedHeroBtn === 'sing') {
              this.focusedHeroBtn = '';
            }
          })
          .onClick(() => this.onStartSinging())

          // ⌕ 搜索 Capsule
          Row({ space: 5 }) {
            Text('⌕')
              .fontSize(12)
              .fontColor(PivoTheme.text)
            Text('搜索')
              .fontSize(12)
              .fontColor(PivoTheme.text)
          }
          .height(32)
          .padding({ left: 12, right: 14 })
          .borderRadius(16)
          .backgroundColor(PivoTheme.surfaceRaised)
          .border({
            width: this.focusedHeroBtn === 'search' ? 2 : 1,
            color: this.focusedHeroBtn === 'search' ? PivoTheme.primary : PivoTheme.borderMuted
          })
          .shadow(this.focusedHeroBtn === 'search' ? { radius: 14, color: PivoTheme.primaryGlow } : undefined)
          .scale({ x: this.focusedHeroBtn === 'search' ? 1.05 : 1.0, y: this.focusedHeroBtn === 'search' ? 1.05 : 1.0 })
          .focusable(true)
          .focusOnTouch(true)
          .tabIndex(5)
          .id('hero_search_btn')
          .nextFocus({
            left: 'hero_start_btn',
            down: 'cat_card_soft'
          })
          .onFocus(() => {
            this.focusedHeroBtn = 'search';
          })
          .onBlur(() => {
            if (this.focusedHeroBtn === 'search') {
              this.focusedHeroBtn = '';
            }
          })
          .onClick(() => this.onOpenSearch())
        }
      }
      .width('100%')
      .height(52)
      .padding({ left: 18, right: 18 })
      .borderRadius(14)
      .linearGradient({
        angle: 104,
        colors: [
          ['#DDEFFD', 0.0],
          ['#DDF5E7', 0.4],
          ['#FFE1D7', 0.8],
          ['#FFF9EE', 1.0]
        ]
      })
      .border({ width: 1, color: PivoTheme.border })

      Blank()

      // 2. 4 Dominant Category Cards (Rich Visual Cards)
      Row({ space: 14 }) {
        ForEach(this.categories, (cat: CategoryItem, index: number) => {
          this.categoryCard(cat, index, false)
        }, (cat: CategoryItem) => cat.id)
      }
      .width('100%')

      Blank()

      // 3. Bottom Section: 最近播放 (Clean & Elegant)
      Column({ space: 8 }) {
        Row() {
          Text('最近播放')
            .fontSize(15)
            .fontWeight(FontWeight.Bold)
            .fontColor(PivoTheme.text)

          Blank()

          Text('点歌即唱 · 智能伴奏')
            .fontSize(11)
            .fontColor(PivoTheme.textMuted)
        }
        .width('100%')

        Row({ space: 12 }) {
          ForEach(this.recentSongs.slice(0, 4), (song: Song, index: number) => {
            this.recentSongItem(song, index, false)
          }, (song: Song) => song.id)
        }
        .width('100%')
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .height('100%')
    .padding({ left: 24, right: 28, top: 14, bottom: 14 })
    .justifyContent(FlexAlign.SpaceBetween)
  }

  // Portrait Layout (Phone / Vertical Screen)
  @Builder
  portraitLayout() {
    Scroll() {
      Column({ space: 16 }) {
        // 1. 顶部全宽精致搜索框（替换原有开唱卡片）
        Row({ space: 10 }) {
          Text('⌕')
            .fontSize(16)
            .fontColor(PivoTheme.textMuted)

          Text('搜索歌曲、歌手、专辑...')
            .fontSize(14)
            .fontColor(PivoTheme.textMuted)
            .layoutWeight(1)

          Row() {
            Text('搜索')
              .fontSize(12)
              .fontWeight(FontWeight.Medium)
              .fontColor(PivoTheme.primary)
          }
          .padding({ left: 10, right: 10, top: 4, bottom: 4 })
          .borderRadius(12)
          .backgroundColor(PivoTheme.surfaceSelected)
        }
        .width('100%')
        .height(46)
        .padding({ left: 16, right: 12 })
        .borderRadius(23)
        .backgroundColor(PivoTheme.surfaceRaised)
        .border({ width: 1, color: PivoTheme.borderMuted })
        .alignItems(VerticalAlign.Center)
        .focusable(true)
        .focusOnTouch(true)
        .id('hero_search_btn')
        .onClick(() => this.onOpenSearch())

        // 2. 热门分类 (2x2 Grid)
        Column({ space: 10 }) {
          Text('热门分类')
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor(PivoTheme.text)

          // 2x2 Grid using 2 Rows
          Column({ space: 10 }) {
            Row({ space: 10 }) {
              this.categoryCard(this.categories[0], 0, true)
              this.categoryCard(this.categories[1], 1, true)
            }
            .width('100%')

            Row({ space: 10 }) {
              this.categoryCard(this.categories[2], 2, true)
              this.categoryCard(this.categories[3], 3, true)
            }
            .width('100%')
          }
          .width('100%')
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)

        // 3. 最近播放 (Vertical List)
        Column({ space: 10 }) {
          Row() {
            Text('最近播放')
              .fontSize(16)
              .fontWeight(FontWeight.Bold)
              .fontColor(PivoTheme.text)

            Blank()

            Text('点歌即唱 · 智能伴奏')
              .fontSize(11)
              .fontColor(PivoTheme.textMuted)
          }
          .width('100%')

          Column({ space: 8 }) {
            ForEach(this.recentSongs.slice(0, 5), (song: Song, index: number) => {
              this.recentSongItem(song, index, true)
            }, (song: Song) => song.id)
          }
          .width('100%')
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 16, bottom: 24 })
    }
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Off)
  }

  build() {
    if (this.wide) {
      this.widescreenLayout()
    } else {
      this.portraitLayout()
    }
  }
}
