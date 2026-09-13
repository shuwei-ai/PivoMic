import { PivoTheme } from '../theme/PivoTheme';

@Component({ freezeWhenInactive: true })
export struct NavigationRail {
  @Prop compact: boolean = false;
  @Prop activeTab: number = 0;
  @Prop isPlaying: boolean = false;
  onTabChange: (index: number) => void = (_index: number): void => {};
  onTogglePlay: () => void = (): void => {};

  private isTabActive(index: number): boolean {
    return this.activeTab === index;
  }

  @Builder
  sodaBottomNavItem(label: string, index: number, iconStr: string = '◉') {
    Column({ space: 3 }) {
      Text(iconStr)
        .fontSize(16)
        .fontColor(this.isTabActive(index) ? PivoTheme.primary : PivoTheme.textMuted)

      Text(label)
        .fontSize(this.isTabActive(index) ? 13 : 12)
        .fontWeight(this.isTabActive(index) ? FontWeight.Bold : FontWeight.Medium)
        .fontColor(this.isTabActive(index) ? PivoTheme.primary : PivoTheme.textMuted)

      if (this.isTabActive(index)) {
        Row()
          .width(18)
          .height(2.5)
          .borderRadius(1.25)
          .backgroundColor(PivoTheme.primary)
          .shadow({ radius: 8, color: PivoTheme.primaryGlow })
      } else {
        Row()
          .width(18)
          .height(2.5)
          .backgroundColor(Color.Transparent)
      }
    }
    .layoutWeight(1)
    .height(54)
    .justifyContent(FlexAlign.Center)
    .focusable(true)
    .focusOnTouch(true)
    .id(`bottom_nav_tab_${index}`)
    .onClick(() => this.onTabChange(index))
  }

  @Builder
  sodaCenterPlayNavItem() {
    Column({ space: 2 }) {
      Stack({ alignContent: Alignment.Center }) {
        // Glowing circular pill
        Row()
          .width(this.activeTab === 1 ? 46 : 42)
          .height(this.activeTab === 1 ? 46 : 42)
          .borderRadius(23)
          .backgroundColor(this.activeTab === 1 ? PivoTheme.primary : PivoTheme.surfaceSelected)
          .shadow(this.activeTab === 1 ? { radius: 12, color: PivoTheme.primaryGlow } : undefined)

        if (this.isPlaying) {
          Row({ space: 4 }) {
            Row()
              .width(3)
              .height(14)
              .borderRadius(1.5)
              .backgroundColor(this.activeTab === 1 ? PivoTheme.primaryTextDark : PivoTheme.primary)
            Row()
              .width(3)
              .height(18)
              .borderRadius(1.5)
              .backgroundColor(this.activeTab === 1 ? PivoTheme.primaryTextDark : PivoTheme.primary)
            Row()
              .width(3)
              .height(12)
              .borderRadius(1.5)
              .backgroundColor(this.activeTab === 1 ? PivoTheme.primaryTextDark : PivoTheme.primary)
          }
          .justifyContent(FlexAlign.Center)
          .alignItems(VerticalAlign.Bottom)
        } else {
          Text('🎤')
            .fontSize(18)
        }
      }
      .width(48)
      .height(44)

      Text('演唱')
        .fontSize(this.activeTab === 1 ? 12 : 11)
        .fontWeight(this.activeTab === 1 ? FontWeight.Bold : FontWeight.Medium)
        .fontColor(this.activeTab === 1 ? PivoTheme.primary : PivoTheme.textMuted)
    }
    .layoutWeight(1)
    .height(58)
    .justifyContent(FlexAlign.Center)
    .focusable(true)
    .focusOnTouch(true)
    .id('bottom_nav_play')
    .onClick(() => {
      this.onTabChange(1);
    })
  }

  @State focusedNavIndex: number = -1;

  // Figma Screen 3 Sidebar Nav Item
  @Builder
  figmaSidebarNavItem(icon: string, label: string, index: number) {
    Row({ space: 16 }) {
      if (this.activeTab === index) {
        // Active: Circular lime button with dark icon
        Row() {
          Text(icon)
            .fontSize(20)
            .fontColor(PivoTheme.primaryTextDark)
            .fontWeight(FontWeight.Bold)
        }
        .width(44)
        .height(44)
        .borderRadius(22)
        .justifyContent(FlexAlign.Center)
        .backgroundColor(PivoTheme.primary)
        .shadow({ radius: 14, color: PivoTheme.primaryGlow, offsetY: 2 })
      } else {
        // Inactive: Simple icon
        Row() {
          Text(icon)
            .fontSize(20)
            .fontColor(this.focusedNavIndex === index ? PivoTheme.primary : PivoTheme.textNavInactive)
        }
        .width(44)
        .height(44)
        .borderRadius(22)
        .justifyContent(FlexAlign.Center)
        .backgroundColor(this.focusedNavIndex === index ? PivoTheme.surfaceSelected : Color.Transparent)
      }

      Text(label)
        .fontSize(19)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.activeTab === index || this.focusedNavIndex === index ? PivoTheme.primary : PivoTheme.textNavInactive)
    }
    .width('100%')
    .height(58)
    .padding({ left: 16, right: 16 })
    .borderRadius(16)
    .backgroundColor(this.activeTab === index ? PivoTheme.surfaceSelectedSubtle : (this.focusedNavIndex === index ? PivoTheme.surfaceSelected : Color.Transparent))
    .border({
      width: this.focusedNavIndex === index ? 2.5 : (this.activeTab === index ? 1 : 0),
      color: this.focusedNavIndex === index ? PivoTheme.primary : (this.activeTab === index ? PivoTheme.borderGlow : Color.Transparent)
    })
    .shadow(this.focusedNavIndex === index ? { radius: 16, color: PivoTheme.primaryGlow } : undefined)
    .scale({ x: this.focusedNavIndex === index ? 1.02 : 1.0, y: this.focusedNavIndex === index ? 1.02 : 1.0 })
    .focusable(true)
    .focusOnTouch(true)
    .tabIndex(1 + index)
    .defaultFocus(index === 0)
    .groupDefaultFocus(index === 0)
    .id(`sidebar_nav_tab_${index}`)
    .nextFocus({
      up: index === 2 ? 'sidebar_nav_tab_1' : (index === 1 ? 'sidebar_nav_tab_0' : undefined),
      down: index === 0 ? 'sidebar_nav_tab_1' : (index === 1 ? 'sidebar_nav_tab_2' : undefined),
      right: index === 0 ? 'tv_playlist_item_0' : (index === 1 ? 'tv_play_pause_btn' : 'profile_subtab_0')
    })
    .onFocus(() => {
      this.focusedNavIndex = index;
    })
    .onBlur(() => {
      if (this.focusedNavIndex === index) {
        this.focusedNavIndex = -1;
      }
    })
    .onClick(() => this.onTabChange(index))
  }

  build() {
    if (this.compact) {
      // 1. Mobile Phone 3-Tab Minimalist Navigation Bar
      Row() {
        this.sodaBottomNavItem('发现', 0, '◉')
        this.sodaCenterPlayNavItem()
        this.sodaBottomNavItem('我的', 2, '●')
      }
      .width('100%')
      .height(64)
      .padding({ left: 24, right: 24, top: 4, bottom: 8 })
      .backgroundColor(PivoTheme.surfaceGlassHeavy)
      .border({ width: { top: 0.8 }, color: PivoTheme.border })
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
    } else {
      // 2. Wide Screen / TV Sidebar (Figma Screen 3 Specification)
      Column({ space: 20 }) {
        // App Branding Header
        Row({ space: 12 }) {
          Text('PivoMic')
            .fontSize(28)
            .fontWeight(FontWeight.Bold)
            .fontColor(PivoTheme.text)
            .letterSpacing(0.5)
        }
        .width('100%')
        .padding({ left: 16, top: 28, bottom: 20 })

        // Navigation Items (发现 ◉, 演唱 ♬, 我的 ●)
        this.figmaSidebarNavItem('◉', '发现', 0)
        this.figmaSidebarNavItem('♬', '演唱', 1)
        this.figmaSidebarNavItem('●', '我的', 2)

        Blank()
      }
      .width(210)
      .height('100%')
      .padding({ left: 16, right: 16, top: 12, bottom: 24 })
      .backgroundColor(PivoTheme.backgroundDark)
      .border({ width: { right: 1 }, color: PivoTheme.border })
    }
  }
}
