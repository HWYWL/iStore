import { AppState } from '../../common/store/AppState'
import { LIGHT_THEME, ThemePalette } from '../../common/theme/ThemeColors'
import { OafStatus, AppFilterBase, AppClass, AppItem, AppFilterTime, AppFilterUser, TimeSlot } from '../../models/Models'
import { ApiService } from '../../api/ApiService'
import { hilog } from '@kit.PerformanceAnalysisKit'
import { LoadingWhimsy } from '../../common/components/LoadingWhimsy'
import { AppNav } from '../../common/utils/AppNav'

/** 星期常量映射 */
const WEEKDAYS: string[] = ['日', '一', '二', '三', '四', '五', '六']

@Entry
@Component
export struct OafPage {
  @State theme: ThemePalette = LIGHT_THEME
  @State isLoading: boolean = true
  @State errorText: string = ''
  @State oafStatus: OafStatus | null = null
  @State appBase: AppFilterBase | null = null
  @State appClasses: AppClass[] = []
  @State appTime: AppFilterTime | null = null
  @State appUser: AppFilterUser | null = null
  @State expandedClasses: Set<number> = new Set()
  // 编辑状态（基础配置）
  @State baseEnabled: boolean = false
  @State baseLog: boolean = false
  @State baseBypass: boolean = false
  @State isSaving: boolean = false
  @State saveMessage: string = ''
  @State saveError: string = ''

  aboutToAppear(): void {
this.theme = AppState.getInstance().getTheme()
        this.loadData()
  }

  async loadData(): Promise<void> {
    this.isLoading = true
    this.errorText = ''
    try {
      const api = new ApiService()
      const results = await Promise.all([
        api.fetchOafStatus(),
        api.fetchAppFilterBase(),
        api.fetchAppFilterClasses(),
        api.fetchAppFilterTime(),
        api.fetchAppFilterUser()
      ])
      this.oafStatus = results[0]
      this.appBase = results[1]
      this.appClasses = results[2]
      this.appTime = results[3]
      this.appUser = results[4]
      // 同步本地编辑状态
      if (this.appBase) {
        this.baseEnabled = this.appBase.appFilterEnabled
        this.baseLog = this.appBase.appLogEnabled
        this.baseBypass = this.appBase.workMode === 'bypass'
      }
      this.saveMessage = ''
      this.saveError = ''
    } catch (e) {
      this.errorText = '加载数据失败'
    }
    this.isLoading = false
  }

  /** 保存基础配置（总开关/工作模式/日志） */
  async saveBase(): Promise<void> {
    if (this.isSaving) return
    this.isSaving = true
    this.saveMessage = ''
    this.saveError = ''
    try {
      const api = new ApiService()
      const base: AppFilterBase = {
        appFilterEnabled: this.baseEnabled,
        appLogEnabled: this.baseLog,
        workMode: this.baseBypass ? 'bypass' : 'gateway'
      }
      const ok: boolean = await api.saveAppFilterBase(base)
      if (ok) {
        this.saveMessage = '基础配置已保存'
        // 刷新状态
        await this.loadData()
      } else {
        this.saveError = '保存失败：设备不支持或接口无权限'
      }
    } catch (e) {
      this.saveError = '保存异常，请重试'
    }
    this.isSaving = false
  }

  /** 切换某个应用的管控状态（本地编辑，不立即提交） */
  toggleAppEnabled(clsId: number, appId: number): void {
    const next: AppClass[] = []
    for (let i = 0; i < this.appClasses.length; i++) {
      const cls = this.appClasses[i]
      const apps: AppItem[] = []
      for (let j = 0; j < cls.apps.length; j++) {
        const app = cls.apps[j]
        if (cls.id === clsId && app.id === appId) {
          apps.push({ id: app.id, name: app.name, enabled: !app.enabled })
        } else {
          apps.push({ id: app.id, name: app.name, enabled: app.enabled })
        }
      }
      next.push({ id: cls.id, name: cls.name, apps: apps })
    }
    this.appClasses = next
    this.saveMessage = ''
    this.saveError = ''
  }

  /** 保存应用管控规则 */
  async saveApps(): Promise<void> {
    if (this.isSaving) return
    this.isSaving = true
    this.saveMessage = ''
    this.saveError = ''
    try {
      const api = new ApiService()
      const ok: boolean = await api.saveAppFilter(this.appClasses)
      if (ok) {
        this.saveMessage = '应用管控已保存'
        await this.loadData()
      } else {
        this.saveError = '保存失败：设备不支持或接口无权限'
      }
    } catch (e) {
      this.saveError = '保存异常，请重试'
    }
    this.isSaving = false
  }

  toggleClassExpand(clsId: number): void {
    const next = new Set(this.expandedClasses)
    if (next.has(clsId)) {
      next.delete(clsId)
    } else {
      next.add(clsId)
    }
    this.expandedClasses = next
  }

  /** 格式化 HH:MM */
  fmtTime(h: number, m: number): string {
    return `${String(h).padStart(2, '0')}:${String(m).padStart(2, '0')}`
  }

  /** 工作日数组转中文 */
  fmtWeekdays(arr: number[]): string {
    if (arr.length === 0) return '未设置'
    if (arr.length === 7) return '每天'
    return arr.map(i => '周' + WEEKDAYS[i]).join('、')
  }

  build() {
    Stack() {
      Column()
        .width('100%')
        .height('100%')
        .linearGradient({
          angle: 135,
          colors: this.theme.pageGradient
        })

      Column() {
        // 顶栏
        Row() {
          Row() {
            Text(' 家长控制')
              .fontSize(16)
              .fontColor(this.theme.textPrimary)
              .fontWeight(FontWeight.Medium)
          }
          .padding({ left: 12, right: 16, top: 6, bottom: 6 })
          .borderRadius(100)
          .backgroundColor(this.theme.bgCard)
          .backdropBlur(20)
          .border({ width: 0.5, color: this.theme.borderGlass })
          .onClick(() => AppNav.getInstance().back())
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 48, bottom: 8 })

        if (this.isLoading) {
          Column() {
            LoadingWhimsy()
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else if (this.errorText) {
          Column() {
            Text('⚠ ' + this.errorText).fontSize(14).fontColor(this.theme.warning).margin({ bottom: 12 })
            Text('点击重试')
              .fontSize(14).fontColor(this.theme.primary)
              .onClick(() => this.loadData())
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else {
          Scroll() {
            Column() {
              // ======== 引擎状态卡片 ========
              Column() {
                Row() {
                  SymbolGlyph($r('sys.symbol.gearshape')).fontSize(15).fontColor(['#3B82F6'])
                  Text(' OAF 引擎状态')
                    .fontSize(14).fontColor(this.theme.textPrimary).fontWeight(FontWeight.Medium)
                }
                .margin({ bottom: 12 })
                this.statRow('插件版本', this.oafStatus?.pluginVersion || '--')
                this.statRow('引擎版本', this.oafStatus?.engineVersion || '--')
                this.statRow('内核版本', this.oafStatus?.kernelVersion || '--')
                Row() {
                  Text('引擎状态')
                    .fontSize(12).fontColor(this.theme.textTertiary).layoutWeight(1)
                  Text(this.oafStatus?.engineStatus === 'running' ? '运行中' : '未运行')
                    .fontSize(12).fontColor(this.oafStatus?.engineStatus === 'running' ? '#00E676' : '#FF5252')
                }.width('100%').margin({ top: 8 })
              }
              .width('100%').padding(16).borderRadius(14).margin({ top: 8, left: 16, right: 16 })
              .backgroundColor('transparent')
              .border({ width: 0.5, color: this.theme.borderGlass })

              // ======== 基础配置卡片 ========
              Column() {
                Row() {
                  SymbolGlyph($r('sys.symbol.circle_grid_2x2')).fontSize(15).fontColor(['#8B5CF6'])
                  Text(' 基础配置')
                    .fontSize(14).fontColor(this.theme.textPrimary)
                    .fontWeight(FontWeight.Medium)
                  Blank()
                  Text(this.isSaving ? '保存中…' : '保存')
                    .fontSize(12).fontColor(this.isSaving ? this.theme.textTertiary : this.theme.primary)
                    .padding({ left: 14, right: 14, top: 5, bottom: 5 })
                    .borderRadius(12)
                    .backgroundColor(this.theme.bgGlassLight)
                    .border({ width: 0.5, color: this.theme.borderGlass })
                    .onClick(() => {
                      if (!this.isSaving) this.saveBase()
                    })
                }
                .width('100%')
                .margin({ bottom: 10 })

                this.configToggle('总开关', this.baseEnabled, (v: boolean) => this.baseEnabled = v)
                this.configToggle('工作模式（网关/旁路）', this.baseBypass, (v: boolean) => this.baseBypass = v, '旁路', '网关')
                this.configToggle('记录日志', this.baseLog, (v: boolean) => this.baseLog = v)
              }
              .width('100%').padding(16).borderRadius(14).margin({ top: 10, left: 16, right: 16 })
              .backgroundColor('transparent')
              .border({ width: 0.5, color: this.theme.borderGlass })

              // ======== 应用分类管控 ========
              Column() {
                Row() {
                  SymbolGlyph($r('sys.symbol.square_grid_2x2')).fontSize(15).fontColor(['#EC4899'])
                  Text(' 应用管控')
                    .fontSize(14).fontColor(this.theme.textPrimary)
                    .fontWeight(FontWeight.Medium)
                  Text(`  ${this.appClasses.length} 类`)
                    .fontSize(11).fontColor(this.theme.textTertiary)
                  Blank()
                  Text(this.isSaving ? '保存中…' : '保存')
                    .fontSize(12).fontColor(this.isSaving ? this.theme.textTertiary : this.theme.primary)
                    .padding({ left: 14, right: 14, top: 5, bottom: 5 })
                    .borderRadius(12)
                    .backgroundColor(this.theme.bgGlassLight)
                    .border({ width: 0.5, color: this.theme.borderGlass })
                    .onClick(() => {
                      if (!this.isSaving) this.saveApps()
                    })
                }
                .margin({ bottom: 10 })

                if (this.appClasses.length === 0) {
                  Text('还没有分类数据，等应用来报到 📭').fontSize(12).fontColor(this.theme.textTertiary)
                    .width('100%').textAlign(TextAlign.Center).padding({ top: 12, bottom: 12 })
                } else {
                  ForEach(this.appClasses, (cls: AppClass, idx: number) => {
                    Column() {
                      Row() {
                        Text(cls.name)
                          .fontSize(13).fontColor(this.theme.textPrimary).fontWeight(FontWeight.Medium)
                        Text(`  ${cls.apps.length} 个`)
                          .fontSize(11).fontColor(this.theme.textTertiary)
                        Blank()
                        Text(this.expandedClasses.has(cls.id) ? '▾' : '▸')
                          .fontSize(14).fontColor(this.theme.textTertiary)
                      }
                      .width('100%')
                      .padding({ top: 8, bottom: 8 })
                      .onClick(() => this.toggleClassExpand(cls.id))

                      if (this.expandedClasses.has(cls.id)) {
                        Column() {
                          ForEach(cls.apps, (app: AppItem) => {
                            Row() {
                              Text(app.name)
                                .fontSize(11).fontColor(this.theme.textSecondary)
                                .layoutWeight(1)
                              Text(app.enabled ? '已管控' : '未管控')
                                .fontSize(10)
                                .fontColor(app.enabled ? '#00E676' : '#9E9E9E')
                                .padding({ left: 8, right: 8, top: 2, bottom: 2 })
                                .borderRadius(8)
                                .backgroundColor(app.enabled ? 'rgba(0,230,118,0.12)' : 'rgba(158,158,158,0.12)')
                            }
                            .width('100%')
                            .padding({ top: 6, bottom: 6 })
                            .onClick(() => this.toggleAppEnabled(cls.id, app.id))
                          })
                        }
                        .width('100%')
                        .padding({ left: 8, top: 4, bottom: 4 })
                      }
                    }
                    .width('100%')
                    .padding({ left: 12, right: 12 })
                    .borderRadius(10)
                    .border({ width: 0.5, color: this.theme.borderGlass })
                    .margin({ bottom: idx < this.appClasses.length - 1 ? 8 : 0 })
                  })
                }

                // 保存结果提示
                if (this.saveMessage) {
                  Text('✓ ' + this.saveMessage)
                    .fontSize(12).fontColor('#00E676').margin({ top: 10 }).width('100%')
                }
                if (this.saveError) {
                  Text('⚠ ' + this.saveError)
                    .fontSize(12).fontColor(this.theme.danger).margin({ top: 10 }).width('100%')
                }
              }
              .width('100%').padding(16).borderRadius(14).margin({ top: 10, left: 16, right: 16 })
              .backgroundColor('transparent')
              .border({ width: 0.5, color: this.theme.borderGlass })

              // ======== 时间段配置 ========
              if (this.appTime) {
                Column() {
                  Row() {
                    SymbolGlyph($r('sys.symbol.clock')).fontSize(15).fontColor(['#F59E0B'])
                    Text(' 时间段配置')
                      .fontSize(14).fontColor(this.theme.textPrimary).fontWeight(FontWeight.Medium)
                  }
                  .margin({ bottom: 10 })

                  // 生效星期
                  this.statRow('生效日期', this.fmtWeekdays(this.appTime.weekdays))

                  // 固定时段
                  if (this.appTime.fixedTimes.length > 0) {
                    Text('固定时段')
                      .fontSize(12).fontColor(this.theme.textTertiary).margin({ top: 8, bottom: 6 })
                    ForEach(this.appTime.fixedTimes, (slot: TimeSlot, i: number) => {
                      Text(`${this.fmtTime(slot.startHour, slot.startMin)} ~ ${this.fmtTime(slot.endHour, slot.endMin)}`)
                        .fontSize(12).fontColor(this.theme.textPrimary)
                        .padding({ top: 4, bottom: 4 })
                    })
                  } else {
                    this.statRow('固定时段', '未设置')
                  }

                  // 动态时长
                  if (this.appTime.dynamicMinutes > 0) {
                    this.statRow('动态时长',
                      `${this.appTime.dynamicMinutes} 分钟（${this.fmtTime(this.appTime.dynamicStartHour, this.appTime.dynamicStartMin)}~${this.fmtTime(this.appTime.dynamicEndHour, this.appTime.dynamicEndMin)}）`)
                  } else {
                    this.statRow('动态时长', '未启用')
                  }
                }
                .width('100%').padding(16).borderRadius(14).margin({ top: 10, left: 16, right: 16 })
                .backgroundColor('transparent')
                .border({ width: 0.5, color: this.theme.borderGlass })
              }

              // ======== 管控用户 ========
              if (this.appUser) {
                Column() {
                  Row() {
                    SymbolGlyph($r('sys.symbol.person_2')).fontSize(15).fontColor(['#06B6D4'])
                    Text(' 管控用户')
                      .fontSize(14).fontColor(this.theme.textPrimary).fontWeight(FontWeight.Medium)
                  }
                  .margin({ bottom: 10 })
                  this.statRow('模式', this.appUser.mode === 'auto' ? '自动' : '手动')
                }
                .width('100%').padding(16).borderRadius(14).margin({ top: 10, left: 16, right: 16 })
                .backgroundColor('transparent')
                .border({ width: 0.5, color: this.theme.borderGlass })
              }

              // 底部留白
              Row().width('100%').height(100)
            }
            .width('100%')
          }
          .width('100%').padding({ left: 0, right: 0, top: 0, bottom: 90 })
          .layoutWeight(1)
          .scrollBar(BarState.Off)
        }
      }
      .width('100%')
      .height('100%')
    }
    .width('100%')
    .height('100%')
  }

  // ========== 辅助 Builder ==========

  @Builder
  statRow(label: string, value: string): void {
    Row() {
      Text(label)
        .fontSize(12).fontColor(this.theme.textTertiary).layoutWeight(1)
      Text(value)
        .fontSize(12).fontColor(this.theme.textPrimary)
    }
    .width('100%')
    .padding({ top: 6, bottom: 6 })
    .border({
      width: { bottom: 0.5 },
      color: this.theme.borderGlass
    })
  }

  @Builder
  configToggle(label: string, value: boolean, onChange: (v: boolean) => void, onText?: string, offText?: string): void {
    Row() {
      Text(label)
        .fontSize(12).fontColor(this.theme.textTertiary).layoutWeight(1)
      Toggle({ type: ToggleType.Switch, isOn: value })
        .selectedColor(this.theme.primary)
        .onChange((isOn: boolean) => {
          onChange(isOn)
        })
      if (onText) {
        Text(value ? onText : offText)
          .fontSize(11)
          .fontColor(value ? '#00E676' : '#9E9E9E')
          .margin({ left: 8 })
      }
    }
    .width('100%')
    .padding({ top: 7, bottom: 7 })
    .border({
      width: { bottom: 0.5 },
      color: this.theme.borderGlass
    })
  }
}
