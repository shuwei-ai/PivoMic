export class PivoTheme {
  // 1. Backgrounds & Atmospheric Surfaces (Warm Cream Soda Light Theme)
  static readonly background: string = '#FFF9EE';
  static readonly backgroundDark: string = '#F7FBF5';
  static readonly backgroundGlow: string = '#DDEFFD';
  static readonly atmosphereRadial: string = 'radial-gradient(circle at 40% 45%, #DDEFFD 0%, #F7FBF5 52%, #FFF9EE 100%)';
  static readonly discoveryRadial: string = 'radial-gradient(circle at 50% 38%, #FFF0AD 0%, #FFF9EE 48%, #F7FBF5 100%)';
  
  static readonly surface: string = 'rgba(255, 255, 255, 0.94)';
  static readonly surfaceSolid: string = '#FFFFFF';
  static readonly surfaceActive: string = '#FFF2C9';
  static readonly surfaceRaised: string = '#FFFCF5';
  static readonly surfaceCircle: string = '#FFFFFF';
  static readonly surfaceCircleDark: string = '#F2EEE7';
  static readonly surfaceHover: string = '#FFF2C9';
  static readonly surfaceGlass: string = 'rgba(255, 255, 255, 0.88)';
  static readonly surfaceGlassHeavy: string = 'rgba(255, 252, 245, 0.97)';
  static readonly surfaceSelected: string = 'rgba(200, 240, 75, 0.30)';
  static readonly surfaceSelectedSubtle: string = 'rgba(200, 240, 75, 0.18)';
  static readonly sidebarGradient: string = 'linear-gradient(180deg, #DDEFFD 0%, #FFF9EE 100%)';

  // 2. Borders & Dividers
  static readonly border: string = '#D8D0C5';
  static readonly borderSubtle: string = '#E8E2D8';
  static readonly borderMuted: string = '#D8D0C5';
  static readonly borderSearch: string = '#C8BFB3';
  static readonly borderHighlight: string = '#B8AEA2';
  static readonly borderGlow: string = 'rgba(174, 216, 61, 0.60)';
  static readonly focusRing: string = '#D97706';
  static readonly focusGlow: string = 'rgba(217, 119, 6, 0.24)';

  // 3. Brand Studio Accents (Figma Electric Lime & Neon Cyan)
  static readonly primary: string = '#587000'; // Accessible olive-lime foreground and action
  static readonly primaryDark: string = '#415300';
  static readonly primaryGlow: string = 'rgba(174, 216, 61, 0.28)';
  static readonly primaryHalo: string = 'rgba(200, 240, 75, 0.24)';
  static readonly primaryTextDark: string = '#FFFFFF';
  static readonly primaryTextSoft: string = '#626262';

  static readonly accent: string = '#216C8F'; // Accessible soda-blue foreground
  static readonly accentLight: string = '#DDEFFD';
  static readonly accentDark: string = '#343434';
  static readonly accentGlow: string = 'rgba(99, 190, 232, 0.24)';

  static readonly atmospherePurple: string = '#FFE1D7';
  static readonly atmospherePurpleGlow: string = 'rgba(255, 225, 215, 0.62)';
  static readonly rose: string = '#B23857';
  static readonly roseGlow: string = 'rgba(255, 129, 151, 0.26)';

  // 4. Typography Colors
  static readonly text: string = '#343434';
  static readonly textSecondary: string = '#626262';
  static readonly textMuted: string = '#626262';
  static readonly textFaint: string = '#626262';
  static readonly textNavInactive: string = '#626262';
  static readonly textLightMuted: string = '#626262';

  // 5. Badges & Quality Indicators
  static readonly sqBadgeBg: string = '#DDEFFD';
  static readonly sqBadgeBorder: string = '#63BEE8';
  static readonly sqBadgeText: string = '#343434';

  // 6. Category Card Gradients (Figma 4 Category Cards)
  static readonly catHotGradient: string = 'linear-gradient(90deg, #FFE1D7 0%, #FFF2C9 100%)';
  static readonly catChineseGradient: string = 'linear-gradient(90deg, #DDEFFD 0%, #F7FBF5 100%)';
  static readonly catNostalgiaGradient: string = 'linear-gradient(90deg, #FFF0AD 0%, #FFF9EE 100%)';
  static readonly catSoftGradient: string = 'linear-gradient(90deg, #DDF5E7 0%, #DDEFFD 100%)';
  static readonly heroBannerGradient: string = 'linear-gradient(104deg, #DDEFFD 0%, #DDF5E7 42%, #FFE1D7 76%, #FFF9EE 100%)';
  static readonly albumCoverGradient: string = 'linear-gradient(135deg, #FFF0AD 14%, #FFE1D7 54%, #DDEFFD 86%)';

  // 7. Status Colors
  static readonly warning: string = '#FBBF24';
  static readonly warningGlow: string = 'rgba(251, 191, 36, 0.3)';
  static readonly danger: string = '#EF4444';
  static readonly success: string = '#10B981';

  // 8. Sizing & Ergonomics
  static readonly carTouchTargetMin: number = 48;
  static readonly carButtonHeight: number = 52;
  static readonly carLargeButtonHeight: number = 56;
}
