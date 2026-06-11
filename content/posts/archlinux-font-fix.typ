#import "@hugo/templates:0.1.0": article
#import "@hugo/utils:0.1.0": *

#show: article.with(
  title: "修复 Arch Linux 中中文字体显示过粗的问题",
  date: datetime(year: 2026, month: 6, day: 11),
  tags: (
    platforms: "linux",
    domains: "beautify",
    intents: "troubleshooting",
  ),
  draft: false
)

= 前言

在不知多久前的某次 Arch Linux 的滚动更新中，我的 KDE Plasma 6 桌面环境的很多 KDE 组件，比如 Dolphin、Konsole 以及一些其他常用软件，比如 Telegram 的中文字体突然出现显示过粗的问题：

#figure(
  caption: [修复前 Konsole + Codex 显示情况],
  image("/images/konsole-before-fix.png")
)

#figure(
  caption: [修复后 Konsole + Codex 显示情况],
  image("/images/konsole-after-fix.png")
)

如果单看某一张图的话，你可能不太能发觉这个问题，但是一旦对比起来，就很明显能发现修复前中文字体明显比修复后中文字体显得更粗一点。

= 解决

在 Arch Linux CN 的 tg 群的大佬的帮助下，我最终得知这是一个 qt 框架默认字体设置的 bug，在 qt 社区内也#link("https://qt-project.atlassian.net/browse/QTBUG-95336")[有所讨论]。

简要来说，我的 Noto Sans 字体有一个名为 stem darkening 的特性，而在 #link("https://freetype.org/freetype2/docs/reference/ft2-properties.html#darkening-parameters")[FreeType API Reference] 中，Adobe hinting engine 会按照一定规律加深字干颜色，最终就会导致中文字体在视觉上比英文字体更粗一点。

解决方法很简单，在 `~/.config/environment.d/` 中新建一个名为 `qt-fix-font.conf` 的配置文件，添加一个环境变量：

```bash
FREETYPE_PROPERTIES=cff:darkening-parameters=1,0,1,0,1,0,1,0
```

即可禁用这个 stem darkening 的特性，这样中文字体就恢复到正常的显示情况了。

= 结语

希望本文能帮到各位同样疑惑于中文字体出现同样问题的读者！

最后感谢 Arch Linux CN 的 tg 群的各位大佬的帮助！
