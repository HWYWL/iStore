import { webview } from '@kit.ArkWeb'
/**
 * WebView 内嵌浏览器页面
 * 通过 WebView 加载路由器的 Web 管理界面
 * 支持自动登录（注入用户名密码到登录表单）
 */
import { ThemePalette, DARK_THEME } from '../../common/theme/ThemeColors'
import { AppState } from '../../common/store/AppState'
import { SavedDevice } from '../../common/store/DeviceStore'
import { hilog } from '@kit.PerformanceAnalysisKit'

const TAG = 'WebViewPage'
const DOMAIN = 0x0001

@Entry
@Component
struct WebViewPage {
  @State isDark: boolean = true
  @State theme: ThemePalette = DARK_THEME
  @State loadingProgress: number = 0
  @State isLoading: boolean = true
  @State webUrl: string = ''
  @State errorOccurred: boolean = false
  controller: webview.WebviewController = new webview.WebviewController()
  private username: string = ''
  private password: string = ''
  private autoLoginDone: boolean = false

  aboutToAppear(): void {
    this.isDark = AppState.getInstance().isDarkMode
    this.theme = AppState.getInstance().getTheme()

    AppState.getInstance().onThemeChange(() => {
      this.isDark = AppState.getInstance().isDarkMode
      this.theme = AppState.getInstance().getTheme()
    })

    const activeDevice: SavedDevice | undefined = AppState.getInstance().getActiveDevice()
    if (activeDevice) {
      this.username = activeDevice.username
      this.password = activeDevice.password
    }

    this.buildWebUrl()
  }

  buildWebUrl(): void {
    const activeDevice: SavedDevice | undefined = AppState.getInstance().getActiveDevice()
    if (!activeDevice) {
      this.webUrl = ''
      this.errorOccurred = true
      return
    }
    const protocol: string = activeDevice.useHttps ? 'https://' : 'http://'
    this.webUrl = `${protocol}${activeDevice.host}`
    hilog.info(DOMAIN, TAG, `OpenWRT Web URL: ${this.webUrl}`)
  }

  /**
   * 通过 JS 注入自动登录 OpenWRT LuCI Web 管理界面
   * 轮询等待登录表单渲染完成后填入账号密码并提交
   * 兼容不同发行版的表单结构和字段命名
   */
  private tryAutoLogin(): void {
    if (this.autoLoginDone) {
      return
    }
    if (!this.username || !this.password) {
      hilog.warn(DOMAIN, TAG, 'No credentials available, skip auto login')
      return
    }
    this.autoLoginDone = true

    const escapedUser: string = this.username.replace(/\\/g, '\\\\').replace(/'/g, "\\'")
    const escapedPass: string = this.password.replace(/\\/g, '\\\\').replace(/'/g, "\\'")
    const js: string = `
(function(){
  var MAX_RETRY = 20;
  var INTERVAL = 500;
  var ROOT = document;
  var count = 0;

  // 已登录的标识：页面中存在登出链接、管理菜单等功能元素
  function isAlreadyLoggedIn(doc) {
    if (doc.querySelector('#mainmenu, #maincontent, .mainmenu, ' +
      '.cbi-section, .status-page, .dashboard, [class*="logout"], ' +
      'a[href*="logout"], a[href*="admin/status"], a[href*="admin/logout"], ' +
      '.node-main-logout, .node-admin-status, #menu, .sidebar')) {
      return true;
    }
    return false;
  }

  // 在所有文档（含 iframe）中查找密码框
  function findPasswordInput(doc) {
    var pw = doc.querySelector(
      'input[type="password"]:not([style*="display:none"])'
    );
    return pw;
  }

  function findUserInput(doc) {
    var selectors = [
      'input[name="luci_username"]',
      'input[name="username"]',
      'input[name="user"]',
      'input[name="login"]',
      'input[name="cbi_user"]',
      'input[name="cbi_username"]',
      'input[placeholder*="用户"]',
      'input[placeholder*="账号"]',
      'input[placeholder*="帐号"]',
      'input[placeholder*="用户名"]',
      'input[placeholder*="Username"]',
      'input[placeholder*="User"]',
      'input[placeholder*="user"]',
      'input[autocomplete="username"]',
      'input[type="text"]:not([style*="display:none"]):not(.cbi-input-inline)'
    ];
    for (var i = 0; i < selectors.length; i++) {
      var el = doc.querySelector(selectors[i]);
      if (el) return el;
    }
    return null;
  }

  function fillField(el, value) {
    var setter = Object.getOwnPropertyDescriptor(
      window.HTMLInputElement.prototype, 'value'
    ).set;
    setter.call(el, value);
    el.dispatchEvent(new Event('input', { bubbles: true }));
    el.dispatchEvent(new Event('change', { bubbles: true }));
    // 针对 React: 触发 composition 事件
    el.dispatchEvent(new CompositionEvent('compositionstart', { bubbles: true }));
    el.dispatchEvent(new CompositionEvent('compositionend', { bubbles: true }));
  }

  function trySubmit(pwEl) {
    // 方式1: 查找包含密码框的 <form> 并 submit
    var form = pwEl.closest('form');
    if (form) {
      form.submit();
      return true;
    }
    // 方式2: 查找页面上任意 form（某些框架密码和提交不在同一 form 内）
    var anyForm = document.querySelector('form');
    if (anyForm) {
      anyForm.submit();
      return true;
    }
    // 方式3: 点击登录按钮
    var btnSelectors = [
      'input[type="submit"]',
      'button[type="submit"]',
      '.cbi-button-save',
      '.cbi-button-action',
      '.cbi-button-positive',
      '.btn-primary',
      '.login-btn',
      'button:contains("登录")',
      'button:contains("Login")',
      'button:contains("登 录")',
      'button:contains("Sign in")',
      'button:contains("登入")',
      '.el-button--primary',
      '.ant-btn-primary',
      'button[class*="login"]',
      'button[class*="submit"]',
      'input[class*="login"]',
      'input[class*="submit"]'
    ];
    for (var i = 0; i < btnSelectors.length; i++) {
      var btn = document.querySelector(btnSelectors[i]);
      if (btn) { btn.click(); return true; }
    }
    // 方式4: 模拟回车在密码框
    pwEl.dispatchEvent(new KeyboardEvent('keydown',
      { key: 'Enter', keyCode: 13, bubbles: true }));
    pwEl.dispatchEvent(new KeyboardEvent('keyup',
      { key: 'Enter', keyCode: 13, bubbles: true }));
    return true;
  }

  function doLogin() {
    count++;
    if (count > MAX_RETRY) return;

    // 如果已登录，无需操作
    if (isAlreadyLoggedIn(ROOT)) { return; }

    var pw = findPasswordInput(ROOT);
    if (!pw) {
      // 尝试在 iframe 中查找
      var iframes = ROOT.querySelectorAll('iframe');
      for (var i = 0; i < iframes.length; i++) {
        try {
          var iframeDoc = iframes[i].contentDocument || iframes[i].contentWindow.document;
          if (isAlreadyLoggedIn(iframeDoc)) { return; }
          pw = findPasswordInput(iframeDoc);
          if (pw) { ROOT = iframeDoc; break; }
        } catch(e) {}
      }
      if (!pw) {
        setTimeout(doLogin, INTERVAL);
        return;
      }
    }

    var un = findUserInput(ROOT);
    if (un) {
      fillField(un, '${escapedUser}');
    }
    fillField(pw, '${escapedPass}');

    setTimeout(function() {
      trySubmit(pw);
    }, 300);
  }

  setTimeout(doLogin, 800);
})();
`
    try {
      this.controller.runJavaScript(js)
    } catch (e) {
      hilog.error(DOMAIN, TAG, `Auto login JS failed: ${JSON.stringify(e)}`)
    }
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
            Text(' OpenWRT 首页')
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
              hilog.error(DOMAIN, TAG, `router.back failed: ${e}`)
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

        Stack({ alignContent: Alignment.Top }) {
          if (this.errorOccurred) {
            Column() {
              Text('⚠️')
                .fontSize(48)
                .margin({ bottom: 16 })
              Text('无法加载页面')
                .fontSize(18)
                .fontColor(this.theme.textPrimary)
                .fontWeight(FontWeight.Medium)
                .margin({ bottom: 8 })
              Text('请确认已连接设备，且设备 Web 管理界面可正常访问')
                .fontSize(13)
                .fontColor(this.theme.textTertiary)
                .textAlign(TextAlign.Center)
                .padding({ left: 32, right: 32 })
                .margin({ bottom: 24 })
              Button('重试')
                .backgroundColor(this.theme.primary)
                .borderRadius(8)
                .onClick(() => {
                  this.errorOccurred = false
                  this.isLoading = true
                  this.loadingProgress = 0
                  this.autoLoginDone = false
                  this.buildWebUrl()
                })
            }
            .width('100%')
            .height('100%')
            .justifyContent(FlexAlign.Center)
          } else {
            Web({ src: this.webUrl, controller: this.controller })
              .domStorageAccess(true)
              .javaScriptAccess(true)
              .zoomAccess(true)
              .fileAccess(true)
              .onlineImageAccess(true)
              .mixedMode(MixedMode.All)
              .width('100%')
              .height('100%')
              .onProgressChange((event) => {
                if (event) {
                  this.loadingProgress = event.newProgress
                }
              })
              .onPageBegin(() => {
                this.isLoading = true
                this.loadingProgress = 0
              })
              .onPageEnd(() => {
                this.isLoading = false
                this.tryAutoLogin()
              })
              .onTitleReceive((event) => {
                if (event && event.title) {
                  hilog.info(DOMAIN, TAG, `Page title: ${event.title}`)
                }
              })
              .onErrorReceive((event) => {
                if (event && event.error) {
                  hilog.error(DOMAIN, TAG, `Web error: ${event.error.getErrorInfo()}`)
                  this.errorOccurred = true
                  this.isLoading = false
                }
              })

            if (this.isLoading) {
              Progress({ value: this.loadingProgress, total: 100, type: ProgressType.Linear })
                .color(this.theme.primary)
                .width('100%')
                .height(3)
            }
          }
        }
        .width('100%')
        .layoutWeight(1)
      }
      .width('100%')
      .height('100%')
    }
    .width('100%')
    .height('100%')
  }
}
