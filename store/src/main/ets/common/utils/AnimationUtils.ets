import { StyleConstants } from '../constants/StyleConstants'

export class AnimationUtils {
  static springIn(duration: number = StyleConstants.ANIM_NORMAL): Object {
    return {
      duration: duration,
      curve: Curve.Friction,
      delay: 0,
      iterations: 1,
      playMode: PlayMode.Normal
    }
  }

  static fadeIn(duration: number = StyleConstants.ANIM_NORMAL): Object {
    return {
      duration: duration,
      curve: Curve.EaseOut,
      delay: 0,
      iterations: 1,
      playMode: PlayMode.Normal
    }
  }

  static scaleIn(duration: number = 300): Object {
    return {
      duration: duration,
      curve: Curve.FastOutSlowIn,
      delay: 0,
      iterations: 1,
      playMode: PlayMode.Normal
    }
  }

  static slideUp(duration: number = StyleConstants.ANIM_SLOW): Object {
    return {
      duration: duration,
      curve: Curve.FastOutSlowIn,
      delay: 0,
      iterations: 1,
      playMode: PlayMode.Normal
    }
  }

  static staggerDelay(index: number, baseDelay: number = 50): number {
    return index * baseDelay
  }
}
