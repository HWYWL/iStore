import { router } from '@kit.ArkUI'

@Entry
@Component
struct Index {
  aboutToAppear(): void {
    router.replaceUrl({ url: 'pages/entry/LoginPage' })
  }

  build() {
    Column()
      .width('100%')
      .height('100%')
      .backgroundColor('#0A0E27')
  }
}
