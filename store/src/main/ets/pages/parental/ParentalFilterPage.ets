import { ThemePalette, DARK_THEME } from '../../common/theme/ThemeColors'
/**
 * 家长控制 - 应用过滤
 * 管理应用分类过滤、时间段设定和用户选择
 * 支持三个子 Tab：应用列表/时间段/用户管理
 */
import { AppState } from '../../common/store/AppState'
import { ApiService } from '../../api/ApiService'
import { AppClass, AppItem, AppFilterTime, AppFilterUser, OafUser } from '../../models/Models'
import { hilog } from '@kit.PerformanceAnalysisKit'

@Entry
@Component
struct ParentalFilterPage {
  @State isDark: boolean = true
  @State theme: ThemePalette = DARK_THEME
  @State subTab: number = 0

  aboutToAppear(): void {
    this.isDark = AppState.getInstance().isDarkMode
    this.theme = AppState.getInstance().getTheme()

    AppState.getInstance().onThemeChange(() => {
      this.isDark = AppState.getInstance().isDarkMode
      this.theme = AppState.getInstance().getTheme()
    })
  }

  build() {
    Stack() {
      Column()
        .width('100%')
        .height('100%')
        .linearGradient({
          angle: 180,
          colors: this.isDark
            ? [['#0A0E27', 0], ['#121637', 0.5], ['#0A0E27', 1]]
            : [['#E8ECF1', 0], ['#F5F7FA', 0.5], ['#E8ECF1', 1]]
        })

      Column() {
        Row() {
          Row() {
            Text('←')
              .fontSize(18)
              .fontColor(this.theme.primary)
            Text(' 应用过滤规则')
              .fontSize(16)
              .fontColor(this.theme.textPrimary)
              .fontWeight(FontWeight.Medium)
          }
          .padding({ left: 12, right: 16, top: 6, bottom: 6 })
          .borderRadius(100)
          .backgroundColor(this.theme.bgCard)
          .backdropBlur(20)
          .border({ width: 0.5, color: this.theme.borderGlass })
          .onClick(() => {
            try {
              this.getUIContext().getRouter().back()
            } catch (e) {
              hilog.error(0x0001, 'ParentalFilterPage', `router.back failed: ${e}`)
            }
          })

          Blank()

          Row() {
            Text(this.isDark ? '☀️' : '🌙')
              .fontSize(18)
          }
          .width(36)
          .height(36)
          .borderRadius(18)
          .backgroundColor(this.theme.bgCard)
          .border({ width: 0.5, color: this.theme.borderGlass })
          .justifyContent(FlexAlign.Center)
          .onClick(() => {
            AppState.getInstance().toggleTheme()
          })
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 48, bottom: 8 })

        Row() {
          Row() {
            Text('应用过滤规则')
              .fontSize(12)
              .fontColor(this.subTab === 0 ? this.theme.textPrimary : this.theme.textTertiary)
              .fontWeight(this.subTab === 0 ? FontWeight.Medium : FontWeight.Normal)
          }
          .flexGrow(1)
          .height(36)
          .justifyContent(FlexAlign.Center)
          .borderRadius(10)
          .backgroundColor(this.subTab === 0 ? this.theme.bgCardHover : 'transparent')
          .onClick(() => { this.subTab = 0 })

          Row() {
            Text('时间配置')
              .fontSize(12)
              .fontColor(this.subTab === 1 ? this.theme.textPrimary : this.theme.textTertiary)
              .fontWeight(this.subTab === 1 ? FontWeight.Medium : FontWeight.Normal)
          }
          .flexGrow(1)
          .height(36)
          .justifyContent(FlexAlign.Center)
          .borderRadius(10)
          .backgroundColor(this.subTab === 1 ? this.theme.bgCardHover : 'transparent')
          .onClick(() => { this.subTab = 1 })

          Row() {
            Text('用户配置')
              .fontSize(12)
              .fontColor(this.subTab === 2 ? this.theme.textPrimary : this.theme.textTertiary)
              .fontWeight(this.subTab === 2 ? FontWeight.Medium : FontWeight.Normal)
          }
          .flexGrow(1)
          .height(36)
          .justifyContent(FlexAlign.Center)
          .borderRadius(10)
          .backgroundColor(this.subTab === 2 ? this.theme.bgCardHover : 'transparent')
          .onClick(() => { this.subTab = 2 })
        }
        .width('100%')
        .height(44)
        .padding({ left: 12, right: 12 })
        .borderRadius(12)
        .backgroundColor(this.theme.bgCard)
        .margin({ left: 16, right: 16, bottom: 8 })

        Scroll() {
          Column() {
            if (this.subTab === 0) {
              AppFilterRulesTab({ theme: this.theme })
            }
            if (this.subTab === 1) {
              AppFilterTimeTab({ theme: this.theme })
            }
            if (this.subTab === 2) {
              AppFilterUserTab({ theme: this.theme })
            }
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 4, bottom: 40 })
        }
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Off)
      }
      .width('100%')
      .height('100%')
    }
    .width('100%')
    .height('100%')
  }
}

@Component
struct AppFilterRulesTab {
  @Prop theme: ThemePalette
  @State isLoading: boolean = true
  @State classes: AppClass[] = []
  @State errorText: string = ''
  @State expandedIds: Set<number> = new Set()

  aboutToAppear(): void {
    this.loadData()
  }

  async loadData(): Promise<void> {
    this.isLoading = true
    this.errorText = ''
    try {
      const api = new ApiService()
      this.classes = await api.fetchAppFilter()
    } catch (e) {
      this.errorText = '加载过滤规则失败'
    }
    this.isLoading = false
  }

  toggleExpand(id: number): void {
    if (this.expandedIds.has(id)) {
      this.expandedIds.delete(id)
    } else {
      this.expandedIds.add(id)
    }
    this.expandedIds = new Set(this.expandedIds)
  }

  build() {
    Column() {
      if (this.isLoading) {
        Column() {
          LoadingProgress().width(40).height(40).color(this.theme.primary)
          Text('加载中...')
            .fontSize(14)
            .fontColor(this.theme.textSecondary)
            .margin({ top: 12 })
        }
        .width('100%')
        .height(200)
        .justifyContent(FlexAlign.Center)
      } else if (this.errorText && this.classes.length === 0) {
        Row() {
          Text('⚠')
            .fontSize(16)
            .margin({ right: 8 })
          Text(this.errorText)
            .fontSize(12)
            .fontColor(this.theme.warning)
        }
        .width('100%')
        .padding(16)
        .borderRadius(14)
        .margin({ top: 8 })
        .backgroundColor(this.theme.bgCard)
        .border({ width: 0.5, color: this.theme.borderGlass })
      } else {
        ForEach(this.classes, (c: AppClass) => {
          Column() {
            Row() {
              Text(c.name)
                .fontSize(14)
                .fontColor(this.theme.textPrimary)
                .fontWeight(FontWeight.Medium)
                .layoutWeight(1)
              Text(`${c.apps.length} 个应用`)
                .fontSize(11)
                .fontColor(this.theme.textTertiary)
                .margin({ right: 8 })
              Text(this.expandedIds.has(c.id) ? '▲' : '▼')
                .fontSize(12)
                .fontColor(this.theme.textTertiary)
            }
            .width('100%')
            .padding(14)
            .onClick(() => { this.toggleExpand(c.id) })

            if (this.expandedIds.has(c.id)) {
              Column() {
                ForEach(c.apps, (app: AppItem) => {
                  Row() {
                    Text(app.name)
                      .fontSize(13)
                      .fontColor(this.theme.textSecondary)
                      .layoutWeight(1)
                    Toggle({ type: ToggleType.Switch, isOn: app.enabled })
                      .selectedColor(this.theme.primary)
                      .onChange((isOn: boolean) => {
                        app.enabled = isOn
                      })
                  }
                  .width('100%')
                  .padding({ left: 20, right: 14, top: 8, bottom: 8 })
                  .border({ width: { bottom: 0.3 }, color: this.theme.borderGlass })
                }, (app: AppItem): string => `${c.id}_${app.id}`)

                Button() {
                  Text('保存分类')
                    .fontSize(12)
                    .fontColor('#FFFFFF')
                }
                .width('100%')
                .height(36)
                .borderRadius(10)
                .margin({ top: 10, bottom: 8 })
                .linearGradient({
                  angle: 135,
                  colors: [[this.theme.primary, 0], [this.theme.secondary, 1]]
                })
                .onClick(async () => {
                  try {
                    const api = new ApiService()
                    await api.saveAppFilter(this.classes)
                  } catch (e) {}
                })
              }
              .width('100%')
              .padding({ left: 0, right: 0, bottom: 8 })
            }
          }
          .width('100%')
          .borderRadius(14)
          .margin({ top: 8 })
          .backgroundColor(this.theme.bgCard)
          .backdropBlur(20)
          .border({ width: 0.5, color: this.theme.borderGlass })
        }, (c: AppClass): string => `${c.id}`)
      }
    }
    .width('100%')
  }
}

@Component
struct AppFilterTimeTab {
  @Prop theme: ThemePalette
  @State isLoading: boolean = true
  @State timeConfig: AppFilterTime = {
    fixedTimes: [], dynamicMinutes: 0, dynamicStartHour: 0,
    dynamicStartMin: 0, dynamicEndHour: 0, dynamicEndMin: 0, weekdays: []
  }
  @State errorText: string = ''
  @State showAddSlot: boolean = false
  @State newStartHour: number = 8
  @State newStartMin: number = 0
  @State newEndHour: number = 22
  @State newEndMin: number = 0

  aboutToAppear(): void {
    this.loadData()
  }

  async loadData(): Promise<void> {
    this.isLoading = true
    this.errorText = ''
    try {
      const api = new ApiService()
      this.timeConfig = await api.fetchAppFilterTime()
    } catch (e) {
      this.errorText = '加载时间配置失败'
    }
    this.isLoading = false
  }

  async doSave(): Promise<void> {
    try {
      const api = new ApiService()
      await api.saveAppFilterTime(this.timeConfig)
    } catch (e) {}
  }

  pad(num: number): string {
    return num < 10 ? `0${num}` : `${num}`
  }

  build() {
    Column() {
      if (this.isLoading) {
        Column() {
          LoadingProgress().width(40).height(40).color(this.theme.primary)
          Text('加载中...')
            .fontSize(14)
            .fontColor(this.theme.textSecondary)
            .margin({ top: 12 })
        }
        .width('100%')
        .height(200)
        .justifyContent(FlexAlign.Center)
      } else if (this.errorText && this.timeConfig.fixedTimes.length === 0) {
        Row() {
          Text('⚠')
            .fontSize(16)
            .margin({ right: 8 })
          Text(this.errorText)
            .fontSize(12)
            .fontColor(this.theme.warning)
        }
        .width('100%')
        .padding(16)
        .borderRadius(14)
        .margin({ top: 8 })
        .backgroundColor(this.theme.bgCard)
        .border({ width: 0.5, color: this.theme.borderGlass })

        Column() {
          Text('重试')
            .fontSize(14)
            .fontColor(this.theme.primary)
        }
        .width('100%')
        .padding(14)
        .borderRadius(14)
        .margin({ top: 8 })
        .backgroundColor(this.theme.bgCard)
        .border({ width: 0.5, color: this.theme.borderGlass })
        .onClick(() => { this.loadData() })
      } else {
        Column() {
          Text('固定时间段')
            .fontSize(14)
            .fontColor(this.theme.textPrimary)
            .fontWeight(FontWeight.Medium)
            .margin({ bottom: 10 })
            .width('100%')

          ForEach(this.timeConfig.fixedTimes, (slot: ESObject, idx: number) => {
            Row() {
              Text(`${this.pad(slot['startHour'])}:${this.pad(slot['startMin'])} - ${this.pad(slot['endHour'])}:${this.pad(slot['endMin'])}`)
                .fontSize(13)
                .fontColor(this.theme.textPrimary)
                .layoutWeight(1)
              Text('×')
                .fontSize(18)
                .fontColor(this.theme.danger)
                .padding({ left: 12, right: 4 })
                .onClick(() => {
                  this.timeConfig.fixedTimes.splice(idx, 1)
                  const newConfig: AppFilterTime = {
                    fixedTimes: [],
                    dynamicMinutes: this.timeConfig.dynamicMinutes,
                    dynamicStartHour: this.timeConfig.dynamicStartHour,
                    dynamicStartMin: this.timeConfig.dynamicStartMin,
                    dynamicEndHour: this.timeConfig.dynamicEndHour,
                    dynamicEndMin: this.timeConfig.dynamicEndMin,
                    weekdays: []
                  }
                  for (let fi = 0; fi < this.timeConfig.fixedTimes.length; fi++) {
                    newConfig.fixedTimes.push(this.timeConfig.fixedTimes[fi])
                  }
                  for (let wi = 0; wi < this.timeConfig.weekdays.length; wi++) {
                    newConfig.weekdays.push(this.timeConfig.weekdays[wi])
                  }
                  this.timeConfig = newConfig
                  this.doSave()
                })
            }
            .width('100%')
            .padding(14)
            .borderRadius(14)
            .margin({ top: 6 })
            .backgroundColor(this.theme.bgCard)
            .backdropBlur(20)
            .border({ width: 0.5, color: this.theme.borderGlass })
          }, (slot: ESObject, idx: number): string => `${idx}`)

          if (this.timeConfig.fixedTimes.length === 0) {
            Text('暂无固定时间段')
              .fontSize(12)
              .fontColor(this.theme.textTertiary)
              .padding(20)
              .width('100%')
              .textAlign(TextAlign.Center)
          }

          if (this.showAddSlot) {
            Column() {
              Row() {
                Column() {
                  Text('开始')
                    .fontSize(10)
                    .fontColor(this.theme.textTertiary)
                    .margin({ bottom: 4 })
                  Text(`${this.pad(this.newStartHour)}:${this.pad(this.newStartMin)}`)
                    .fontSize(15)
                    .fontColor(this.theme.textPrimary)
                    .fontWeight(FontWeight.Medium)
                    .fontFamily('monospace')
                }
                .padding(10)
                .borderRadius(10)
                .backgroundColor(this.theme.bgGlassLight)
                .onClick(() => {
                  this.newStartHour = (this.newStartHour + 1) % 24
                })

                Text('→')
                  .fontSize(18)
                  .fontColor(this.theme.textTertiary)
                  .margin({ left: 10, right: 10 })

                Column() {
                  Text('结束')
                    .fontSize(10)
                    .fontColor(this.theme.textTertiary)
                    .margin({ bottom: 4 })
                  Text(`${this.pad(this.newEndHour)}:${this.pad(this.newEndMin)}`)
                    .fontSize(15)
                    .fontColor(this.theme.textPrimary)
                    .fontWeight(FontWeight.Medium)
                    .fontFamily('monospace')
                }
                .padding(10)
                .borderRadius(10)
                .backgroundColor(this.theme.bgGlassLight)
                .onClick(() => {
                  this.newEndHour = (this.newEndHour + 1) % 24
                })
              }
              .width('100%')
              .justifyContent(FlexAlign.Center)

              Row() {
                Button() {
                  Text('取消')
                    .fontSize(12)
                    .fontColor(this.theme.textSecondary)
                }
                .height(36)
                .borderRadius(10)
                .margin({ right: 8 })
                .backgroundColor(this.theme.bgGlassLight)
                .flexGrow(1)
                .onClick(() => { this.showAddSlot = false })

                Button() {
                  Text('添加')
                    .fontSize(12)
                    .fontColor('#FFFFFF')
                }
                .height(36)
                .borderRadius(10)
                .linearGradient({
                  angle: 135,
                  colors: [[this.theme.primary, 0], [this.theme.secondary, 1]]
                })
                .flexGrow(1)
                .onClick(() => {
                  this.timeConfig.fixedTimes.push({
                    startHour: this.newStartHour, startMin: 0,
                    endHour: this.newEndHour, endMin: 0
                  })
                  this.showAddSlot = false
                  this.doSave()
                })
              }
              .width('100%')
              .margin({ top: 12 })
            }
            .width('100%')
            .padding(14)
            .borderRadius(14)
            .margin({ top: 8 })
            .backgroundColor(this.theme.bgCard)
            .backdropBlur(20)
            .border({ width: 0.5, color: this.theme.borderGlass })
          }

          Row() {
            Text('+ 添加时间段')
              .fontSize(12)
              .fontColor(this.theme.primary)
          }
          .width('100%')
          .padding(14)
          .borderRadius(14)
          .margin({ top: 8 })
          .backgroundColor(this.theme.bgCard)
          .border({ width: 0.5, color: this.theme.borderGlass })
          .onClick(() => { this.showAddSlot = true })
          .justifyContent(FlexAlign.Center)
        }
        .width('100%')
        .padding(14)
        .borderRadius(14)
        .margin({ top: 8 })
        .backgroundColor(this.theme.bgCard)
        .backdropBlur(20)
        .border({ width: 0.5, color: this.theme.borderGlass })
      }
    }
    .width('100%')
  }
}

@Component
struct AppFilterUserTab {
  @Prop theme: ThemePalette
  @State isLoading: boolean = true
  @State userConfig: AppFilterUser = { mode: 'auto', users: [] }
  @State errorText: string = ''

  aboutToAppear(): void {
    this.loadData()
  }

  async loadData(): Promise<void> {
    this.isLoading = true
    this.errorText = ''
    try {
      const api = new ApiService()
      this.userConfig = await api.fetchAppFilterUser()
    } catch (e) {
      this.errorText = '加载用户配置失败'
    }
    this.isLoading = false
  }

  async doSave(): Promise<void> {
    try {
      const api = new ApiService()
      await api.saveAppFilterUser(this.userConfig)
    } catch (e) {}
  }

  build() {
    Column() {
      if (this.isLoading) {
        Column() {
          LoadingProgress().width(40).height(40).color(this.theme.primary)
          Text('加载中...')
            .fontSize(14)
            .fontColor(this.theme.textSecondary)
            .margin({ top: 12 })
        }
        .width('100%')
        .height(200)
        .justifyContent(FlexAlign.Center)
      } else if (this.errorText) {
        Row() {
          Text('⚠')
            .fontSize(16)
            .margin({ right: 8 })
          Text(this.errorText)
            .fontSize(12)
            .fontColor(this.theme.warning)
        }
        .width('100%')
        .padding(16)
        .borderRadius(14)
        .margin({ top: 8 })
        .backgroundColor(this.theme.bgCard)
        .border({ width: 0.5, color: this.theme.borderGlass })

        Column() {
          Text('重试')
            .fontSize(14)
            .fontColor(this.theme.primary)
        }
        .width('100%')
        .padding(14)
        .borderRadius(14)
        .margin({ top: 8 })
        .backgroundColor(this.theme.bgCard)
        .border({ width: 0.5, color: this.theme.borderGlass })
        .onClick(() => { this.loadData() })
      } else {
        Column() {
          Text('用户模式')
            .fontSize(14)
            .fontColor(this.theme.textPrimary)
            .fontWeight(FontWeight.Medium)
            .margin({ bottom: 10 })
            .width('100%')

          Row() {
            Row() {
              Text('自动模式')
                .fontSize(13)
                .fontColor(this.userConfig.mode === 'auto' ? this.theme.textPrimary : this.theme.textTertiary)
                .fontWeight(this.userConfig.mode === 'auto' ? FontWeight.Medium : FontWeight.Normal)
            }
            .flexGrow(1)
            .height(36)
            .justifyContent(FlexAlign.Center)
            .borderRadius(10)
            .backgroundColor(this.userConfig.mode === 'auto' ? this.theme.bgCardHover : 'transparent')
            .onClick(() => {
              this.userConfig.mode = 'auto'
            })

            Row() {
              Text('手动模式')
                .fontSize(13)
                .fontColor(this.userConfig.mode === 'manual' ? this.theme.textPrimary : this.theme.textTertiary)
                .fontWeight(this.userConfig.mode === 'manual' ? FontWeight.Medium : FontWeight.Normal)
            }
            .flexGrow(1)
            .height(36)
            .justifyContent(FlexAlign.Center)
            .borderRadius(10)
            .backgroundColor(this.userConfig.mode === 'manual' ? this.theme.bgCardHover : 'transparent')
            .onClick(() => {
              this.userConfig.mode = 'manual'
            })
          }
          .width('100%')
          .height(44)
          .padding({ left: 4, right: 4 })
          .borderRadius(12)
          .backgroundColor(this.theme.bgCard)
          .margin({ top: 4 })

          if (this.userConfig.mode === 'manual' && this.userConfig.users.length > 0) {
            Column() {
              Text('受控用户')
                .fontSize(13)
                .fontColor(this.theme.textSecondary)
                .margin({ top: 12, bottom: 8 })
                .width('100%')

              ForEach(this.userConfig.users, (user: OafUser, idx: number) => {
                Row() {
                  Column() {
                    Text(user.name || 'Unknown')
                      .fontSize(13)
                      .fontColor(this.theme.textPrimary)
                      .fontWeight(FontWeight.Medium)
                    Text(user.mac)
                      .fontSize(10)
                      .fontColor(this.theme.textTertiary)
                      .fontFamily('monospace')
                  }
                  .alignItems(HorizontalAlign.Start)
                  .layoutWeight(1)

                  Text('×')
                    .fontSize(18)
                    .fontColor(this.theme.danger)
                    .padding({ left: 12, right: 4 })
                    .onClick(() => {
                      this.userConfig.users.splice(idx, 1)
                      const newUserConfig: AppFilterUser = { mode: this.userConfig.mode, users: [] }
                      for (let ui = 0; ui < this.userConfig.users.length; ui++) {
                        newUserConfig.users.push(this.userConfig.users[ui])
                      }
                      this.userConfig = newUserConfig
                      this.doSave()
                    })
                }
                .width('100%')
                .padding(14)
                .borderRadius(14)
                .margin({ top: 6 })
                .backgroundColor(this.theme.bgCard)
                .backdropBlur(20)
                .border({ width: 0.5, color: this.theme.borderGlass })
              }, (user: OafUser): string => user.mac)

              Button() {
                Text('保存用户配置')
                  .fontSize(12)
                  .fontColor('#FFFFFF')
              }
              .width('100%')
              .height(36)
              .borderRadius(10)
              .margin({ top: 12 })
              .linearGradient({
                angle: 135,
                colors: [[this.theme.primary, 0], [this.theme.secondary, 1]]
              })
              .onClick(async () => { await this.doSave() })
            }
            .width('100%')
            .padding(14)
            .borderRadius(14)
            .margin({ top: 8 })
            .backgroundColor(this.theme.bgCard)
            .backdropBlur(20)
            .border({ width: 0.5, color: this.theme.borderGlass })
          } else if (this.userConfig.mode === 'manual' && this.userConfig.users.length === 0) {
            Text('暂未添加受控用户')
              .fontSize(12)
              .fontColor(this.theme.textTertiary)
              .padding(20)
              .width('100%')
              .textAlign(TextAlign.Center)
          }
        }
        .width('100%')
        .padding(14)
        .borderRadius(14)
        .margin({ top: 8 })
        .backgroundColor(this.theme.bgCard)
        .backdropBlur(20)
        .border({ width: 0.5, color: this.theme.borderGlass })
      }
    }
    .width('100%')
  }
}