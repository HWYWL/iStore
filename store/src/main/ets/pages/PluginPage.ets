import { StyleConstants } from '../common/constants/StyleConstants'
import { ParticleBackground } from '../common/components/ParticleBackground'
import { GlassCard } from '../common/components/GlassCard'
import { ApiService } from '../api/ApiService'
import { Plugin } from '../models/Models'

@Entry
@Component
struct PluginPage {
  @State plugins: Plugin[] = []
  @State isLoading: boolean = true
  @State errorText: string = ''
  @State activeCategory: string = 'all'
  @State searchText: string = ''
  private apiService: ApiService = new ApiService()

  categories: string[] = ['all', 'network', 'nas', 'vpn', 'docker', 'utility', 'monitor', 'media']

  aboutToAppear(): void {
    this.loadPlugins()
  }

  async loadPlugins(): Promise<void> {
    this.isLoading = true
    this.errorText = ''
    try {
      this.plugins = await this.apiService.fetchPlugins()
    } catch (plgErr) {
      this.errorText = '加载插件列表失败'
    }
    this.isLoading = false
  }

  getFilteredPlugins(): Plugin[] {
    let filtered: Plugin[] = this.plugins
    if (this.activeCategory !== 'all') {
      const catFiltered: Plugin[] = []
      for (const p of filtered) {
        if (p.category === this.activeCategory) {
          catFiltered.push(p)
        }
      }
      filtered = catFiltered
    }
    if (this.searchText.trim()) {
      const kw: string = this.searchText.trim().toLowerCase()
      const kwFiltered: Plugin[] = []
      for (const p of filtered) {
        if (p.displayName.toLowerCase().includes(kw) ||
          p.description.toLowerCase().includes(kw) ||
          p.name.toLowerCase().includes(kw)) {
          kwFiltered.push(p)
        }
      }
      filtered = kwFiltered
    }
    return filtered
  }

  getCategoryLabel(cat: string): string {
    const labels: Record<string, string> = {
      'all': '全部', 'network': '网络', 'nas': 'NAS', 'vpn': 'VPN',
      'docker': 'Docker', 'utility': '工具', 'monitor': '监控', 'media': '媒体'
    }
    return labels[cat] || cat
  }

  getPluginIcon(category: string): string {
    const icons: Record<string, string> = { 'vpn': '🔐', 'network': '🌐', 'docker': '🐳', 'utility': '🛠️', 'monitor': '📊', 'nas': '💾', 'media': '🎬' }
    return icons[category] || '📦'
  }

  build() {
    Stack() {
      ParticleBackground()

      Column() {
        Row() {
          Text('插件管理').fontSize(StyleConstants.FONT_XL).fontColor(StyleConstants.TEXT_PRIMARY).fontWeight(FontWeight.Bold)
          Blank()
          Text(`${this.getFilteredPlugins().length} 个插件`).fontSize(StyleConstants.FONT_SM).fontColor(StyleConstants.TEXT_SECONDARY)
        }
        .width('100%').padding({ left: 16, right: 16, top: 48, bottom: 4 })

        Row() {
          TextInput({ placeholder: '搜索插件...', text: this.searchText })
            .placeholderColor(StyleConstants.TEXT_TERTIARY).fontColor(StyleConstants.TEXT_PRIMARY).backgroundColor('transparent')
            .onChange((v: string) => { this.searchText = v }).layoutWeight(1).height(40)
          Text('🔍').fontSize(14).fontColor(StyleConstants.TEXT_SECONDARY).padding({ left: 10, right: 4 })
        }
        .width('100%').height(40).borderRadius(StyleConstants.RADIUS_FULL)
        .backgroundColor(StyleConstants.BG_CARD).backdropBlur(10)
        .border({ width: 0.5, color: StyleConstants.BORDER_GLASS })
        .padding({ left: 14, right: 14 }).margin({ left: 16, right: 16, top: 8, bottom: 8 })

        Scroll() {
          Row() {
            ForEach(this.categories, (cat: string) => {
              Text(this.getCategoryLabel(cat))
                .fontSize(StyleConstants.FONT_SM)
                .fontColor(this.activeCategory === cat ? StyleConstants.TEXT_PRIMARY : StyleConstants.TEXT_TERTIARY)
                .fontWeight(this.activeCategory === cat ? FontWeight.Medium : FontWeight.Normal)
                .padding({ left: 12, right: 12, top: 6, bottom: 6 })
                .borderRadius(StyleConstants.RADIUS_FULL)
                .backgroundColor(this.activeCategory === cat ? 'rgba(0, 212, 255, 0.15)' : 'transparent')
                .border({ width: this.activeCategory === cat ? 0.5 : 0, color: StyleConstants.PRIMARY })
                .margin({ right: 6 })
                .onClick(() => { this.activeCategory = cat })
            }, (item: string): string => item)
          }
          .width('100%').padding({ left: 16, right: 16, top: 4, bottom: 8 })
        }
        .scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off).height(44)

        Scroll() {
          Column() {
            if (this.isLoading) {
              Column() {
                LoadingProgress().width(40).height(40).color(StyleConstants.PRIMARY)
                Text('加载插件列表...').fontSize(StyleConstants.FONT_SM).fontColor(StyleConstants.TEXT_SECONDARY).margin({ top: 12 })
              }
              .width('100%').height(200).justifyContent(FlexAlign.Center)
            } else if (this.errorText) {
              GlassCard({ cardWidth: '100%', marginTop: 12 }) {
                Row() {
                  Text('⚠').fontSize(20).margin({ right: 8 })
                  Text(this.errorText).fontSize(StyleConstants.FONT_SM).fontColor(StyleConstants.WARNING)
                }
                .width('100%')
              }
            } else if (this.plugins.length === 0) {
              GlassCard({ cardWidth: '100%', marginTop: 12 }) {
                Column() {
                  Text('📦').fontSize(48).margin({ bottom: 12 })
                  Text('暂无插件').fontSize(StyleConstants.FONT_LG).fontColor(StyleConstants.TEXT_PRIMARY).fontWeight(FontWeight.Medium)
                  Text('设备暂无安装的插件').fontSize(StyleConstants.FONT_SM).fontColor(StyleConstants.TEXT_TERTIARY).margin({ top: 4 })
                }
                .width('100%').padding({ top: 40, bottom: 40 }).alignItems(HorizontalAlign.Center)
              }
            } else {
              ForEach(this.getFilteredPlugins(), (plugin: Plugin, index: number) => {
                GlassCard({ cardWidth: '100%', marginTop: 6 }) {
                  Row() {
                    Text(this.getPluginIcon(plugin.category)).fontSize(24).width(44).height(44).borderRadius(12).backgroundColor(StyleConstants.BG_CARD).textAlign(TextAlign.Center)

                    Column() {
                      Text(plugin.displayName).fontSize(StyleConstants.FONT_MD).fontColor(StyleConstants.TEXT_PRIMARY).fontWeight(FontWeight.Medium)
                      Text(plugin.description).fontSize(StyleConstants.FONT_XS).fontColor(StyleConstants.TEXT_TERTIARY).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).width('85%')
                    }
                    .margin({ left: 12 }).layoutWeight(1).alignItems(HorizontalAlign.Start)

                    Column() {
                      if (plugin.installed) {
                        Row() {
                          Circle().width(6).height(6)
                            .fill(plugin.running ? StyleConstants.SUCCESS : StyleConstants.WARNING)
                            .shadow(plugin.running ? { radius: 3, color: 'rgba(0,230,118,0.5)', offsetX: 0, offsetY: 0 } :
                              { radius: 0, color: '#00000000', offsetX: 0, offsetY: 0 })
                          Text(plugin.running ? '运行中' : '已停止').fontSize(StyleConstants.FONT_XS).fontColor(plugin.running ? StyleConstants.SUCCESS : StyleConstants.WARNING).margin({ left: 4 })
                        }
                      } else {
                        Text('未安装').fontSize(StyleConstants.FONT_XS).fontColor(StyleConstants.TEXT_TERTIARY)
                      }
                      if (plugin.version) {
                        Text(`v${plugin.version}`).fontSize(10).fontColor(StyleConstants.TEXT_TERTIARY).margin({ top: 2 })
                      }
                    }
                    .alignItems(HorizontalAlign.End)
                  }
                }
              }, (item: Plugin): string => item.id)
            }
          }
          .width('100%').padding({ left: 12, right: 12, top: 8, bottom: 100 })
        }
        .width('100%').layoutWeight(1).scrollBar(BarState.Off)
      }
      .width('100%').height('100%')
    }
    .width('100%').height('100%')
    .linearGradient({ angle: 180, colors: [['#0A0E27', 0], ['#121637', 0.5], ['#0A0E27', 1]] })
  }
}
