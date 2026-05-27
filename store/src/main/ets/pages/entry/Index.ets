/**
 * 应用入口页面
 * 启动后立即重定向到登录页面（LoginPage）
 */
@Entry
@Component
struct Index {
  /** 页面加载完成后，自动跳转到登录页面 */
  aboutToAppear(): void {
    this.getUIContext().getRouter().replaceUrl({ url: 'pages/entry/LoginPage' })
  }

  build() {
    Column()
      .width('100%')
      .height('100%')
      .backgroundColor('#0A0E27')  // 启动过渡背景色
  }
}
