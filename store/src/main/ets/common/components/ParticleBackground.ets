import { StyleConstants } from '../constants/StyleConstants'

@Component
export struct ParticleBackground {
  @State particles: Particle[] = []

  aboutToAppear(): void {
    this.initParticles()
    this.startAnimationLoop()
  }

  initParticles(): void {
    const count: number = 26
    for (let i = 0; i < count; i++) {
      this.particles.push({
        x: Math.random() * 100,
        y: Math.random() * 100,
        size: 1.5 + Math.random() * 2.5,
        opacity: 0.15 + Math.random() * 0.35,
        speedX: (Math.random() - 0.5) * 0.15,
        speedY: -(0.08 + Math.random() * 0.2),
        color: Math.random() > 0.5 ? 'rgba(0, 212, 255, ALPHA)' : 'rgba(123, 104, 238, ALPHA)'
      })
    }
  }

  startAnimationLoop(): void {
    const loop: () => void = (): void => {
      const updated: Particle[] = []
      for (let i = 0; i < this.particles.length; i++) {
        const p: Particle = this.particles[i]
        let nx: number = p.x + p.speedX
        let ny: number = p.y + p.speedY
        if (ny < -5) ny = 105
        if (nx < -5) nx = 105
        if (nx > 105) nx = -5
        if (ny > 105) ny = -5
        updated.push({
          x: nx, y: ny, size: p.size, opacity: p.opacity,
          speedX: p.speedX, speedY: p.speedY, color: p.color
        })
      }
      this.particles = updated
      setTimeout(loop, 50)
    }
    setTimeout(loop, 50)
  }

  build() {
    Stack() {
      ForEach(this.particles, (p: Particle, index: number) => {
        Circle()
          .width(p.size * 4)
          .height(p.size * 4)
          .fill(p.color.replace('ALPHA', p.opacity.toString()))
          .position({ x: `${p.x}%`, y: `${p.y}%` })
          .blendMode(BlendMode.SCREEN, BlendApplyType.OFFSCREEN)
      }, (item: Particle, index: number): string => index.toString())

      Column() {
        Circle()
          .width(120)
          .height(120)
          .position({ x: '15%', y: '20%' })
          .fill('rgba(0, 212, 255, 0.04)')
          .blur(30)
          .blendMode(BlendMode.SCREEN, BlendApplyType.OFFSCREEN)

        Circle()
          .width(180)
          .height(180)
          .position({ x: '75%', y: '55%' })
          .fill('rgba(123, 104, 238, 0.06)')
          .blur(40)
          .blendMode(BlendMode.SCREEN, BlendApplyType.OFFSCREEN)

        Circle()
          .width(100)
          .height(100)
          .position({ x: '50%', y: '80%' })
          .fill('rgba(0, 229, 255, 0.05)')
          .blur(25)
          .blendMode(BlendMode.SCREEN, BlendApplyType.OFFSCREEN)
      }
      .width('100%')
      .height('100%')
    }
    .width('100%')
    .height('100%')
  }
}

interface Particle {
  x: number
  y: number
  size: number
  opacity: number
  speedX: number
  speedY: number
  color: string
}
