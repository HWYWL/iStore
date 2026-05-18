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
  @State activeCategory: string = 'all'
  @State searchText: string = ''
  private apiService: ApiService = new ApiService()

  categories: string[] = ['all', 'network', 'nas', 'vpn', 'docker', 'utility', 'monitor', 'media']

  aboutToAppear(): void {
    this.loadPlugins()
  }

  async loadPlugins(): Promise<void> {
    this.isLoading = true
    try {
      this.plugins = await this.apiService.fetchPlugins()
      if (this.plugins.length === 0) {
        this.plugins = this.getMockPlugins()
      }
    } catch (plgErr) {
      this.plugins = this.getMockPlugins()
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

  getMockPlugins(): Plugin[] {
    return [
      { id: '1', name: 'luci-app-passwall', displayName: 'PassWall', description: '科学上网代理工具', version: '4.7.0', author: 'xiaorouji', category: 'vpn', installed: true, enabled: true, running: true, iconUrl: '', size: '2.3MB' },
      { id: '2', name: 'luci-app-adguardhome', displayName: 'AdGuard Home', description: '网络级广告拦截与跟踪保护', version: '0.107.48', author: 'AdGuard Team', category: 'network', installed: true, enabled: true, running: true, iconUrl: '', size: '15.6MB' },
      { id: '3', name: 'luci-app-dockerman', displayName: 'Docker Man', description: 'Docker 容器管理器', version: '1.0.0', author: 'lisaac', category: 'docker', installed: true, enabled: true, running: true, iconUrl: '', size: '8.2MB' },
      { id: '4', name: 'luci-app-istorex', displayName: 'iStore X', description: '应用商店增强版', version: '1.5.2', author: 'linkease', category: 'utility', installed: true, enabled: true, running: true, iconUrl: '', size: '3.1MB' },
      { id: '5', name: 'luci-app-netdata', displayName: 'NetData', description: '实时性能监控面板', version: '2.0.3', author: 'NetData Team', category: 'monitor', installed: true, enabled: false, running: false, iconUrl: '', size: '12.8MB' },
      { id: '6', name: 'luci-app-samba4', displayName: 'Samba 共享', description: '网络文件共享服务', version: '4.19.4', author: 'Samba Team', category: 'nas', installed: true, enabled: true, running: true, iconUrl: '', size: '5.4MB' },
      { id: '7', name: 'luci-app-aria2', displayName: 'Aria2', description: '多协议下载工具', version: '1.37.0', author: 'aria2', category: 'utility', installed: false, enabled: false, running: false, iconUrl: '', size: '1.8MB' },
      { id: '8', name: 'luci-app-jellyfin', displayName: 'Jellyfin', description: '开源媒体服务器', version: '10.9.6', author: 'Jellyfin Team', category: 'media', installed: false, enabled: false, running: false, iconUrl: '', size: '25.3MB' },
      { id: '9', name: 'luci-app-openclash', displayName: 'OpenClash', description: 'Clash 代理客户端', version: '0.46.003', author: 'vernesong', category: 'vpn', installed: false, enabled: false, running: false, iconUrl: '', size: '4.2MB' },
      { id: '10', name: 'luci-app-qbittorrent', displayName: 'qBittorrent', description: 'BT 下载工具', version: '4.6.3', author: 'qBittorrent', category: 'utility', installed: false, enabled: false, running: false, iconUrl: '', size: '8.7MB' },
      { id: '11', name: 'luci-app-smartdns', displayName: 'SmartDNS', description: '智能 DNS 加速与防污染', version: '1.2024.43', author: 'pymumu', category: 'network', installed: true, enabled: true, running: true, iconUrl: '', size: '1.2MB' },
      { id: '12', name: 'luci-app-cifs-mount', displayName: 'CIFS 挂载', description: '远程文件系统挂载', version: '1.0.0', author: 'community', category: 'nas', installed: false, enabled: false, running: false, iconUrl: '', size: '0.5MB' }
    ]
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
                      Text(`v${plugin.version}`).fontSize(10).fontColor(StyleConstants.TEXT_TERTIARY).margin({ top: 2 })
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
