/**
 * 主题色彩系统 - 深色/浅色双主题
 */

export interface ThemePalette {
  primary: string
  primaryDark: string
  secondary: string
  accent: string
  success: string
  warning: string
  danger: string
  info: string

  bgDark: string
  bgCard: string
  bgCardHover: string
  bgGlass: string
  bgGlassLight: string

  textPrimary: string
  textSecondary: string
  textTertiary: string
  textAccent: string

  borderGlass: string
  borderGlassFocus: string
}

export const DARK_THEME: ThemePalette = {
  primary: '#00D4FF',
  primaryDark: '#0099CC',
  secondary: '#7B68EE',
  accent: '#00E5FF',
  success: '#00E676',
  warning: '#FFD740',
  danger: '#FF5252',
  info: '#448AFF',

  bgDark: '#0A0E27',
  bgCard: 'rgba(255, 255, 255, 0.06)',
  bgCardHover: 'rgba(255, 255, 255, 0.12)',
  bgGlass: 'rgba(18, 22, 55, 0.7)',
  bgGlassLight: 'rgba(255, 255, 255, 0.08)',

  textPrimary: '#FFFFFF',
  textSecondary: 'rgba(255, 255, 255, 0.7)',
  textTertiary: 'rgba(255, 255, 255, 0.4)',
  textAccent: '#00D4FF',

  borderGlass: 'rgba(255, 255, 255, 0.1)',
  borderGlassFocus: 'rgba(255, 255, 255, 0.25)'
}

export const LIGHT_THEME: ThemePalette = {
  primary: '#0077CC',
  primaryDark: '#005599',
  secondary: '#5B4CC4',
  accent: '#0099CC',
  success: '#00A84D',
  warning: '#E6A800',
  danger: '#D93025',
  info: '#1A73E8',

  bgDark: '#F0F2F5',
  bgCard: 'rgba(0, 0, 0, 0.03)',
  bgCardHover: 'rgba(0, 0, 0, 0.06)',
  bgGlass: 'rgba(255, 255, 255, 0.85)',
  bgGlassLight: 'rgba(0, 0, 0, 0.03)',

  textPrimary: '#1F1F1F',
  textSecondary: 'rgba(0, 0, 0, 0.6)',
  textTertiary: 'rgba(0, 0, 0, 0.35)',
  textAccent: '#0077CC',

  borderGlass: 'rgba(0, 0, 0, 0.08)',
  borderGlassFocus: 'rgba(0, 0, 0, 0.2)'
}

export const DARK_GRADIENT_START = '#0A0E27'
export const DARK_GRADIENT_MID = '#121637'
export const DARK_GRADIENT_END = '#0A0E27'

export const LIGHT_GRADIENT_START = '#E8ECF1'
export const LIGHT_GRADIENT_MID = '#F5F7FA'
export const LIGHT_GRADIENT_END = '#E8ECF1'
