import { PlaybackState } from '../domain/MusicModels';
import { PivoTheme } from '../theme/PivoTheme';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0x0000;
const TAG = 'PivoMicCanvas';

interface StageParticle {
  x: number;
  y: number;
  vx: number;
  vy: number;
  radius: number;
  baseRadius: number;
  alpha: number;
  baseAlpha: number;
  color: string;
  glowColor: string;
  phase: number;
}

interface RhythmWaveRing {
  x: number;
  y: number;
  radius: number;
  maxRadius: number;
  alpha: number;
  color: string;
  speed: number;
  lineWidth: number;
}

@Component
export struct ParticleStageBackground {
  @Prop @Watch('onVisibilityOrStateChanged') isVisible: boolean = true;
  @Prop @Watch('onVisibilityOrStateChanged') state: PlaybackState = PlaybackState.IDLE;
  @Prop microphonePeak: number = 0;

  private settings: RenderingContextSettings = new RenderingContextSettings(true);
  private context: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings);
  private timerId: number = -1;
  private canvasWidth: number = 360;
  private canvasHeight: number = 720;
  private particles: StageParticle[] = [];
  private waveRings: RhythmWaveRing[] = [];
  private lastRingSpawnTime: number = 0;
  private isCanvasReady: boolean = false;

  private readonly PARTICLE_COLORS: string[] = [
    PivoTheme.atmospherePurple,
    PivoTheme.accent,
    PivoTheme.rose,
    PivoTheme.text,
    PivoTheme.primary
  ];

  aboutToAppear(): void {
    this.initParticles();
    hilog.info(DOMAIN, TAG, 'Canvas appeared visible=%{public}s', `${this.isVisible}`);
    if (this.isVisible) {
      this.startAnimationLoop();
    }
  }

  aboutToDisappear(): void {
    this.stopAnimationLoop();
    this.isCanvasReady = false;
    this.particles = [];
    this.waveRings = [];
    hilog.info(DOMAIN, TAG, 'Canvas disappeared and animation stopped');
  }

  onVisibilityOrStateChanged(): void {
    this.stopAnimationLoop();
    if (this.isVisible) {
      this.startAnimationLoop();
    }
  }

  private initParticles(): void {
    const count = 48;
    this.particles = [];
    for (let i = 0; i < count; i++) {
      const colorIdx = i % this.PARTICLE_COLORS.length;
      const baseR = 1.6 + Math.random() * 2.4;
      const baseA = 0.30 + Math.random() * 0.45;
      this.particles.push({
        x: Math.random() * this.canvasWidth,
        y: Math.random() * this.canvasHeight,
        vx: (Math.random() - 0.5) * 0.8,
        vy: (Math.random() - 0.5) * 0.8 - 0.15, // 微微向上缓缓漂浮
        radius: baseR,
        baseRadius: baseR,
        alpha: baseA,
        baseAlpha: baseA,
        color: this.PARTICLE_COLORS[colorIdx],
        glowColor: this.PARTICLE_COLORS[colorIdx],
        phase: Math.random() * Math.PI * 2
      });
    }
  }

  private startAnimationLoop(): void {
    if (!this.isVisible) return;
    if (this.timerId !== -1) return;
    // 播放时约 33ms 每帧 (~30fps)，暂停/空闲时降频至 66ms (~15fps)，兼顾超低功耗与顺滑
    const intervalMs = (this.state === PlaybackState.PLAYING) ? 33 : 66;
    this.timerId = setInterval(() => {
      if (!this.isVisible || !this.isCanvasReady) return;
      this.renderFrame();
    }, intervalMs);
    hilog.info(DOMAIN, TAG, 'Canvas animation started intervalMs=%{public}d', intervalMs);
  }

  private stopAnimationLoop(): void {
    if (this.timerId !== -1) {
      clearInterval(this.timerId);
      this.timerId = -1;
      hilog.info(DOMAIN, TAG, 'Canvas animation timer cleared');
    }
    this.waveRings = [];
  }

  private calculateAudioEnergy(): number {
    if (this.state !== PlaybackState.PLAYING) {
      // 暂停或静止状态：微弱平缓的微动
      return 0.15 + (this.microphonePeak > 0.05 ? this.microphonePeak * 0.6 : 0);
    }

    // 播放状态：伴奏律动 BPM (约 120-128 BPM 模拟节拍波)
    const timeSec = Date.now() / 1000.0;
    const baseBeat = Math.pow(Math.max(0, Math.sin(timeSec * 4.1)), 3) * 0.45;
    const subBeat = Math.sin(timeSec * 2.05) * 0.15 + 0.15;
    const accompanimentEnergy = baseBeat + subBeat;

    // 叠加麦克风实时演唱拾音能量
    const micEnergy = Math.min(1.0, this.microphonePeak * 1.5);

    return Math.min(1.0, accompanimentEnergy * 0.6 + micEnergy * 0.65 + 0.15);
  }

  private renderFrame(): void {
    if (!this.isCanvasReady) return;
    const ctx = this.context;
    const w = this.canvasWidth;
    const h = this.canvasHeight;
    if (w <= 0 || h <= 0) return;

    const energy = this.calculateAudioEnergy();
    const now = Date.now();

    // 1. 清空画布 (向上取整并略微外延以杜绝浮点亚像素边缘残留)
    ctx.clearRect(0, 0, Math.ceil(w) + 2, Math.ceil(h) + 2);

    // 2. 生成中心扩散的律动声波光环 (Ripple Wave Rings)
    const centerX = w * 0.5;
    const centerY = h * 0.46; // 偏向歌词中心区域

    if (this.state === PlaybackState.PLAYING && energy > 0.48 && (now - this.lastRingSpawnTime > 420)) {
      this.lastRingSpawnTime = now;
      this.waveRings.push({
        x: centerX + (Math.random() - 0.5) * 40,
        y: centerY + (Math.random() - 0.5) * 40,
        radius: 20,
        maxRadius: Math.min(w, h) * (0.65 + energy * 0.35),
        alpha: 0.35 + energy * 0.35,
        color: energy > 0.7 ? PivoTheme.primary : (Math.random() > 0.5 ? PivoTheme.accent : PivoTheme.atmospherePurple),
        speed: 2.5 + energy * 3.5,
        lineWidth: 1.5 + energy * 1.5
      });
    }

    // 3. 绘制并更新声波光环
    for (let i = this.waveRings.length - 1; i >= 0; i--) {
      const ring = this.waveRings[i];
      ring.radius += ring.speed;
      ring.alpha *= 0.94; // 逐渐淡出

      if (ring.alpha > 0.02 && ring.radius < ring.maxRadius) {
        ctx.beginPath();
        ctx.arc(ring.x, ring.y, ring.radius, 0, Math.PI * 2);
        ctx.strokeStyle = ring.color;
        ctx.globalAlpha = Math.max(0, Math.min(1, ring.alpha));
        ctx.lineWidth = ring.lineWidth;
        ctx.stroke();
      } else {
        this.waveRings.splice(i, 1);
      }
    }

    // 4. 更新并绘制所有极光粒子（已移除粒子间连线，保持背景纯净无割裂拉丝感）
    const speedMultiplier = 1.0 + energy * 2.2;
    for (let i = 0; i < this.particles.length; i++) {
      const p = this.particles[i];

      // 更新位置
      p.x += p.vx * speedMultiplier;
      p.y += p.vy * speedMultiplier;
      p.phase += 0.05 + energy * 0.08;

      // 边缘平滑环绕或回弹
      if (p.x < -10) p.x = w + 10;
      if (p.x > w + 10) p.x = -10;
      if (p.y < -10) p.y = h + 10;
      if (p.y > h + 10) p.y = -10;

      // 动态呼吸半径与透明度
      const pulse = Math.sin(p.phase) * 0.35;
      const currentRadius = p.baseRadius * (1.0 + pulse + energy * 0.9);
      const currentAlpha = Math.min(0.95, p.baseAlpha * (1.0 + pulse * 0.5 + energy * 0.6));

      // 绘制粒子光晕与核心
      ctx.beginPath();
      ctx.arc(p.x, p.y, currentRadius, 0, Math.PI * 2);
      ctx.fillStyle = p.color;
      ctx.globalAlpha = Math.max(0, Math.min(1, currentAlpha));
      ctx.fill();

      // 对大粒子额外绘制外圈弱光晕
      if (p.baseRadius > 2.8 || energy > 0.6) {
        ctx.beginPath();
        ctx.arc(p.x, p.y, currentRadius * 2.2, 0, Math.PI * 2);
        ctx.fillStyle = p.glowColor;
        ctx.globalAlpha = Math.max(0, Math.min(1, currentAlpha * 0.22));
        ctx.fill();
      }
    }

    // 恢复全局透明度
    ctx.globalAlpha = 1.0;
  }

  build() {
    Canvas(this.context)
      .width('100%')
      .height('100%')
      .hitTestBehavior(HitTestMode.None)
      .onReady(() => {
        this.isCanvasReady = true;
        hilog.info(DOMAIN, TAG, 'Canvas ready visible=%{public}s size=%{public}dx%{public}d',
          `${this.isVisible}`, this.canvasWidth, this.canvasHeight);
      })
      .onAreaChange((_oldVal: Area, newVal: Area) => {
        const width = Number(newVal.width);
        const height = Number(newVal.height);
        if (width > 0 && height > 0) {
          const isInitialSizeChange = (this.canvasWidth === 360 && this.canvasHeight === 720) &&
            (width !== 360 || height !== 720);
          this.canvasWidth = width;
          this.canvasHeight = height;
          if (this.particles.length === 0 || isInitialSizeChange) {
            this.initParticles();
          }
        }
      })
  }
}
