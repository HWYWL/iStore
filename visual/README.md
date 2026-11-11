# 视觉回归基线（visual/）

核心页面在两种材质下的截图基线，用 `scripts/visual-regression.ps1` 采集与比对。
目的是兜住"改主题/材质/布局把某个页面弄坏"这类问题——**不比对文字与素材细节**。

```
visual/
├── baseline/<material>/<page>.png   # 提交进仓库的参照图（720px 宽）
├── current/<material>/<page>.png    # 本次运行的截图（gitignore）
└── diff/<material>-<page>.png       # 差异图：红色=超阈值像素（gitignore）
```

## 用法

```powershell
# 采集基线（需要真机，且分辨率与基线一致）
powershell -File scripts/visual-regression.ps1 -Mode capture -Material solid
powershell -File scripts/visual-regression.ps1 -Mode capture -Material liquid

# 比对（脚本会把材质切到指定值再截图）
powershell -File scripts/visual-regression.ps1 -Mode compare -Material solid
powershell -File scripts/visual-regression.ps1 -Mode compare -Material liquid
```

- 设备：`-Device <hdc target>`，缺省取 `hdc list targets` 第一个；`-HdcPath` 可指定 hdc。
- 页面：脚本里的 `$pages`，用**界面文字**驱动点击（不依赖坐标），找不到会自动滚回顶部再找。
- 判定：`-Tolerance`（默认 8%）是"差异像素占比"上限；超过即退出码 1 并打印差异图路径。

## 为什么是 8%，不是 0.5%

仪表盘数据是活的（速率、连接数、图表形状都在变），逐像素比对必然误报。所以比对做了三件事：

1. **灰度** —— 让强调色/图表颜色的变化不参与判定；
2. **缩到 200px 宽** —— 文字笔画与图线细节被平均掉，卡片几何与栏宽变化保留；
3. **均值归一化** —— 两次采集之间存在约 2~5 级的整体亮度差异（窗口合成），不归一化会盖过真实差异。

在 `PCE-W30`（2880×1920）上实测：

| 场景 | 差异占比 |
|---|---|
| 同材质、同代码，连续两次 | 0.4% ~ 1.5%（solid）／2.9% ~ 3.5%（liquid） |
| 同代码，solid ↔ liquid | 14% ~ 17% |
| 默认容差 | **8%** |

也就是说：它能抓住"材质/主题没生效、卡片塌了、栏宽变了、整块内容缺失"，抓不住"某个数字变了"。
基线是**设备分辨率相关**的，换机型必须重新采集。
