/**
 * Copyright (c) 2026 Huawei Device Co., Ltd.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

interface HeartSparkle {
  angle: number;
  speed: number;
  color: string;
  size: number;
}

@Component({ freezeWhenInactive: true })
export struct HeartBurstCanvas {
  @Prop @Watch('onFavoriteChange') isFavorite: boolean = true;
  @Prop @Watch('onTrigger') trigger: number = 0;

  onFavoriteChange(): void {
    if (this.animTimer !== -1) {
      this.initSparkles();
    }
  }

  private settings: RenderingContextSettings = new RenderingContextSettings(true);
  private ctx: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings);

  private widthPx: number = 240;
  private heightPx: number = 240;
  private animTimer: number = -1;
  private startTime: number = 0;
  private readonly animDurationMs: number = 650;
  private sparkles: HeartSparkle[] = [];

  private initSparkles(): void {
    this.sparkles = [];
    const colors = this.isFavorite
      ? ['#FF2D55', '#FF758C', '#FFD166', '#00F5D4', '#FFFFFF', '#FF007F']
      : ['#FFFFFF', 'rgba(255, 255, 255, 0.8)', '#B0E0E6', '#F0F8FF'];

    for (let i = 0; i < 14; i++) {
      const angle = (Math.PI * 2 * i) / 14 + (Math.random() - 0.5) * 0.35;
      const speed = 40 + Math.random() * 50;
      const color = colors[i % colors.length];
      const size = 3.0 + Math.random() * 2.5;
      this.sparkles.push({ angle, speed, color, size });
    }
  }

  onTrigger(): void {
    if (this.trigger === 0) return;
    this.initSparkles();
    this.startTime = Date.now();
    if (this.animTimer !== -1) {
      clearInterval(this.animTimer);
    }
    this.animTimer = setInterval(() => {
      this.renderFrame();
    }, 16);
  }

  aboutToDisappear(): void {
    if (this.animTimer !== -1) {
      clearInterval(this.animTimer);
      this.animTimer = -1;
    }
  }

  private renderFrame(): void {
    const elapsed = Date.now() - this.startTime;
    const progress = Math.min(1.0, elapsed / this.animDurationMs);

    this.ctx.clearRect(0, 0, this.widthPx, this.heightPx);

    if (progress >= 1.0) {
      if (this.animTimer !== -1) {
        clearInterval(this.animTimer);
        this.animTimer = -1;
      }
      return;
    }

    const cx = this.widthPx / 2;
    const cy = this.heightPx / 2;

    // 1. Calculate Heart Scale & Opacity via Elastic Ease
    let scale = 1.0;
    let opacity = 1.0;
    let offsetY = 0.0;
    let rotation = 0.0;

    if (progress < 0.28) {
      // Fast Overshoot Pop: 0.3 -> 1.32
      const p = progress / 0.28;
      scale = 0.3 + 1.02 * Math.sin(p * Math.PI * 0.5);
      rotation = (1.0 - p) * -0.15; // slight entry tilt
    } else if (progress < 0.50) {
      // Elastic Settle: 1.32 -> 1.0
      const p = (progress - 0.28) / 0.22;
      scale = 1.32 - 0.32 * Math.sin(p * Math.PI * 0.5);
      rotation = 0.0;
    } else {
      // Float Up and Fade Out: 1.0 -> 0.85, Y lifts -22px
      const p = (progress - 0.50) / 0.50;
      scale = 1.0 - 0.15 * p;
      opacity = 1.0 - p * p;
      offsetY = -24 * p;
    }

    this.ctx.save();
    this.ctx.globalAlpha = opacity;
    this.ctx.translate(cx, cy + offsetY);
    this.ctx.rotate(rotation);
    this.ctx.scale(scale, scale);

    // 2. Draw Heart Glow Background
    const glowRadius = 58;
    const glow = this.ctx.createRadialGradient(0, -5, 10, 0, -5, glowRadius);
    if (this.isFavorite) {
      glow.addColorStop(0.0, 'rgba(255, 45, 85, 0.50)');
      glow.addColorStop(0.6, 'rgba(255, 0, 100, 0.20)');
      glow.addColorStop(1.0, 'rgba(255, 0, 100, 0.0)');
    } else {
      glow.addColorStop(0.0, 'rgba(255, 255, 255, 0.40)');
      glow.addColorStop(0.6, 'rgba(255, 255, 255, 0.12)');
      glow.addColorStop(1.0, 'rgba(255, 255, 255, 0.0)');
    }
    this.ctx.fillStyle = glow;
    this.ctx.beginPath();
    this.ctx.arc(0, -5, glowRadius, 0, Math.PI * 2);
    this.ctx.fill();

    // 3. Draw Bézier Parametric Heart Body
    const s = 1.85; // Base scale
    this.ctx.beginPath();
    this.ctx.moveTo(0, 16 * s);
    // Left curve
    this.ctx.bezierCurveTo(-22 * s, 1 * s, -24 * s, -18 * s, -8 * s, -18 * s);
    this.ctx.bezierCurveTo(-2 * s, -18 * s, 0, -11 * s, 0, -11 * s);
    // Right curve
    this.ctx.bezierCurveTo(0, -11 * s, 2 * s, -18 * s, 8 * s, -18 * s);
    this.ctx.bezierCurveTo(24 * s, -18 * s, 22 * s, 1 * s, 0, 16 * s);
    this.ctx.closePath();

    if (this.isFavorite) {
      // Rich Vibrant 3D Gradient Fill
      const grad = this.ctx.createLinearGradient(0, -18 * s, 0, 16 * s);
      grad.addColorStop(0.0, '#FF4D6D');
      grad.addColorStop(0.45, '#FF0844');
      grad.addColorStop(1.0, '#D90429');
      this.ctx.fillStyle = grad;
      this.ctx.shadowColor = 'rgba(255, 45, 85, 0.85)';
      this.ctx.shadowBlur = 20;
      this.ctx.fill();

      // Glossy Top Specular Highlight
      this.ctx.save();
      this.ctx.beginPath();
      this.ctx.ellipse(-7 * s, -12 * s, 4 * s, 2.4 * s, -Math.PI / 4, 0, Math.PI * 2);
      this.ctx.fillStyle = 'rgba(255, 255, 255, 0.60)';
      this.ctx.shadowBlur = 0;
      this.ctx.fill();
      this.ctx.restore();
    } else {
      // Sleek Frosted Outline Heart for Unfavorite
      this.ctx.fillStyle = 'rgba(255, 255, 255, 0.18)';
      this.ctx.fill();
      this.ctx.strokeStyle = '#FFFFFF';
      this.ctx.lineWidth = 3.5;
      this.ctx.shadowColor = 'rgba(255, 255, 255, 0.6)';
      this.ctx.shadowBlur = 14;
      this.ctx.stroke();
    }

    this.ctx.restore();

    // 4. Draw Radial Sparks / Fireworks Particles
    if (this.sparkles.length > 0 && progress > 0.08) {
      const sparkProgress = (progress - 0.08) / 0.92;
      const sparkAlpha = Math.max(0.0, 1.0 - sparkProgress * 1.3);

      for (let i = 0; i < this.sparkles.length; i++) {
        const sp = this.sparkles[i];
        const dist = sp.speed * Math.pow(sparkProgress, 0.75);
        const px = cx + Math.cos(sp.angle) * dist;
        const py = cy + Math.sin(sp.angle) * dist + (sparkProgress * 15); // subtle gravity
        const currentSize = Math.max(0.5, sp.size * (1.0 - sparkProgress * 0.8));

        this.ctx.save();
        this.ctx.globalAlpha = sparkAlpha;
        this.ctx.fillStyle = sp.color;
        this.ctx.shadowColor = sp.color;
        this.ctx.shadowBlur = 8;
        this.ctx.beginPath();
        this.ctx.arc(px, py, currentSize, 0, Math.PI * 2);
        this.ctx.fill();
        this.ctx.restore();
      }
    }
  }

  build() {
    Canvas(this.ctx)
      .width(this.widthPx)
      .height(this.heightPx)
      .onReady(() => {
        if (this.trigger > 0) {
          this.onTrigger();
        }
      })
      .hitTestBehavior(HitTestMode.None)
  }
}
