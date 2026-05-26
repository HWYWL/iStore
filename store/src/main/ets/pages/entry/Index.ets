@Entry
@Component
struct Index {
  aboutToAppear(): void {
    this.getUIContext().getRouter().replaceUrl({ url: 'pages/entry/LoginPage' })
  }

  build() {
    Column()
      .width('100%')
      .height('100%')
      .backgroundColor('#0A0E27')
  }
}
