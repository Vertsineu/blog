#import "@hugo/templates:0.1.0": article
#import "@hugo/utils:0.1.0": *

#show: article.with(
  title: "如何在 Hugo 中使用 Typst 编写文章",
  date: datetime(year: 2026, month: 3, day: 29),
  draft: false,
)

= 前言

Typst 一直以来都是我非常喜欢的一个排版工具，相比于 LaTeX，Typst 的语法简单，编写体验好；相比于 Markdown，Typst 的功能强大，标准统一，符合我对排版工具的所有想象。

自从我接触到 Typst 之后，不仅我的日常的作业、报告、简历等文档都使用 Typst 写的，而且我也开发了一个 Typst Package 用于在 Typst 中绘制树状图，比如二叉树、红黑树、语法树等等 —— #link("https://github.com/Vertsineu/typst-tdtr")[tdtr] (i.e. tidy tree)，感兴趣的话可以看看。

因此，我一直想在我的 Blog 中使用 Typst 来编写文章，但是苦于 Typst 对 HTML 导出的支持仍然处于实验性阶段，因此搭建 Blog 的想法也一直一拖再拖。

但是，直到最近，我对于搭建 Blog 的需求越来越迫切了，所以我就决定不再等待 Typst 对 HTML 导出的支持了，而是自己动手来实现这个功能。这篇文章讲述的就是我如何实现在 Hugo 中使用 Typst 编写文章的。

Blog 的源代码位于 #link("https://github.com/Vertsineu/blog")[github.com/Vertsineu/blog]，欢迎 star 和 fork。

= 使用

如果你也想像我的 Blog 一样使用 Typst 来编写基于 Hugo 的 Blog 的话，可以按照以下步骤来操作：

首先安装我修改过的 Hugo，目前还没有发布版本，因此需要手动编译安装：

+ 首先，clone 下来我修改过的 Hugo 的代码，并切换到 `support-typst` 分支，即：

  ```bash
  git clone https://github.com/Vertsineu/hugo.git
  cd hugo
  git checkout support-typst
  ```

+ 然后安装 mage 用于编译安装：

  ```bash
  go install github.com/magefile/mage@latest
  ```

+ 接着运行以下命令来编译安装 Hugo：

  ```bash
  mage install
  ```

+ 最后检查一下 Hugo 是否安装成功了：

  ```bash
  hugo version
  ```

  如果 BuildDate 和当前时间相近，并且版本号是 v0.159.1，那么就说明安装成功了。

接下来，我建议你先 clone 我的 Blog 的代码，这样你就可以在此基础上进行修改，而不需要从零开始搭建：

+ 首先，clone 下来我的 Blog 的代码：

  ```bash
  git clone https://github.com/Vertsineu/blog.git
  cd blog
  ```

+ 然后运行 hugo server 来启动本地服务器：

  ```bash
  hugo server -D
  ```

  其中 `-D` 参数是为了让 Hugo 也编译 draft 状态的文章。

此时，你就可以在浏览器中访问 http://localhost:1313 来查看 Blog 的内容了。

然后，你可以尝试在 `content/posts` 目录下新建一个 .typ 文件，导入模板和工具包，然后使用 Typst 编写文章了。

比如，一个简单的示例如下：

```typ
#import "@hugo/templates:0.1.0": article
#import "@hugo/utils:0.1.0": *

#show: article.with(
  title: "如何在 Hugo 中使用 Typst 编写文章",
  date: datetime(year: 2026, month: 3, day: 29),
  draft: true,
)

// your article content here
```

最后，尽情享受使用 Typst 编写 Hugo 博客的乐趣吧！如果你在使用过程中遇到了任何问题，欢迎在我的 Blog 的 GitHub 仓库中提交 issue，我会尽快回复的。

= 实现

实现主要分为两个部分，一个是 Hugo 侧添加对 Typst 的支持，一个是 Typst 侧增强实验性 HTML 导出的功能。

== Hugo

Hugo 本身是不支持 Typst 的，因此我们需要先 fork 一份 Hugo 的代码。为了保证功能稳定性，我选择了最新的稳定版本 v0.159.1 来进行开发，位于 #link("https://github.com/Vertsineu/hugo/tree/support-typst")[github.com/Vertsineu/hugo]。

Hugo 的代码有够多的，因此这部分主要我是使用 gpt-5.3-codex 来帮我实现的（#strike[AI 还是太强大了]）

=== 初步实现

一开始我实现了一个非常简单的版本，核心思路是让 Hugo 去自动识别 .typ 文件，然后调用 Typst CLI 来进行编译，最后把编译生成的 HTML 代码片段插入到最终的页面中。

实现这个功能并不复杂，因为 Hugo 本身已经将 Markdown 的解析过程抽象出来了，我只需要去按照接口将 Typst 的解析过程插入进去就行了，同时添加配置项让用户可以配置 Typst 的相关选项。

具体实现了以下功能：

- 实现对于 Typst CLI 的 go 封装，比如对于 typst compile 的参数的封装如下：

  ```go
  // Location: markup/typst/typstcli/runner.go
  type CompileArgs struct {
    Input  Input
    Output Output

    Format      OutputFormat
    World       WorldArgs
    Pages       []string
    PDFStandard []string
    NoPDFTags   bool
    PPI         float32
    Deps        Output
    DepsFormat  DepsFormat
    Process     ProcessArgs

    Open *string

    Timings *string

    Exec ExecOptions
  }
  ```

  这样我们就可以在 Hugo 中调用 Typst CLI 来编译 Typst 文件了。原本我是想使用 #link("https://github.com/Dadido3/go-typst")[go-typst] 这个库的，但是这个库的只提供了 typst compile 的封装，对于 typst query 和 typst watch 都没有提供封装，索性我就参考 Typst 源代码的 #link("https://github.com/typst/typst/blob/main/crates/typst-cli/src/args.rs")[args.rs] 直接自己实现了一个对 Typst CLI 的封装。

- 实现一个 Provider 和 Converter 用于向 Hugo 添加 Typst 编译支持：

  ```go
  // Location: markup/typst/convert.go
  // Provider is the package entry point.
  var Provider converter.ProviderProvider = provider{}

  type provider struct{}

  // ...

  type typstConverter struct {
    ctx   converter.DocumentContext
    cfg   converter.ProviderConfig
    watch *watchManager
  }
  ```

  并在其中调用 Typst 的 compile 子命令来进行编译：

  ```go
  // Location: markup/typst/convert.go
  runner := typstcli.New(c.cfg.Exec, cfg.Binary)
  world := typstcli.WorldArgsFromConfig(cfg, resolveRootDirectory(cfg.Root, ctx))
  process := typstcli.ProcessArgsFromConfig(cfg)
  process.Features = []typstcli.Feature{typstcli.FeatureHTML}

  // ...

  err := runner.Compile(typstcli.CompileArgs{
    Input:   typstcli.InputStdin,
    Output:  typstcli.OutputStdout,
    Format:  typstcli.OutputFormatHTML,
    World:   world,
    Pages:   pagesFromConfig(cfg.Pages),
    Process: process,
    Exec: typstcli.ExecOptions{
      Stdin:  bytes.NewReader(src),
      Stdout: &out,
      Stderr: &cmderr,
    },
  })
  ```

  这样，Hugo 就可以识别到 .typ 文件并传递给 Converter 去解析生成 HTML 代码片段。

- 实现 Front Matter 的自定义逻辑来支持从 Typst 中提取 metadata：

  ```go
  // Location: hugolib/page__content.go
  runner := typstcli.New(h.Deps.ExecHelper, cfg.Binary)
  process := typstcli.ProcessArgsFromConfig(cfg)
  process.Features = []typstcli.Feature{typstcli.FeatureHTML}
  err := runner.Query(typstcli.QueryArgs{
    Input:    typstcli.Input(filename),
    Selector: "metadata",
    Field:    "value",
    World:    typstcli.WorldArgsFromConfig(cfg, root),
    Process:  process,
    Exec: typstcli.ExecOptions{
      Stdout: &out,
      Stderr: &cmderr,
    },
  })
  ```

  对于 Markdown 文件，Hugo 是通过解析文件开头的 YAML/TOML/JSON 格式的 Front Matter 来提取 metadata 的，而对于 Typst 文件，我采取使用 typst query 通过提取全文第一个 `#metadata` 对象中的内容来作为 metadata。

  比如，在 Typst 的 article 模板中，对 metadata 的支持是通过以下代码实现的：

  ```typ
  #let article(
    title: "",
    description: "",
    tags: (),
    date: datetime.today(),
    weight: 10,
    draft: false,
    body,
    ..args
  ) = {
    // ...

    let prelude = metadata((
      title: title,
      description: description,
      tags: tags,
      date: date.display("[year]-[month]-[day]"),
      weight: weight,
      draft: draft,
      ..args.named()
    ))

    prelude
    body
  }
  ```

  这样，Hugo 就可以通过 typst query 来提取到 .typ 文件的 metadata 了。

- 在 markup 中添加了 Typst 选项并且提供相关的配置项：

  ```go
  // Location: markup/typst/typst_config/config.go
  // Package typst_config holds Typst-related configuration.
  package typst_config

  type WatchConfig struct {
    Enabled bool
    Timeout string
  }

  // Config configures the Typst converter.
  type Config struct {
    Binary string

    // Root sets Typst's project root. If empty, Hugo uses the current .typ file's directory.
    Root string

    // Input values exposed to Typst via sys.inputs.
    Inputs map[string]string

    // FontPaths are additional directories searched for fonts.
    FontPaths []string

    IgnoreSystemFonts   bool
    IgnoreEmbeddedFonts bool

    PackagePath      string
    PackageCachePath string

    Jobs  int
    Pages string

    Watch WatchConfig
  }

  var Default = Config{
    Binary: "typst",
    Watch: WatchConfig{
      Timeout: "3s",
    },
  }
  ```

  这样我就可以在 hugo.toml 中配置 Typst 的相关选项了，比如这个 Blog 的配置如下：

  ```toml
  [markup.typst]
      root = "./content"
      packagePath = "./packages"
      jobs = 4

  [markup.typst.watch]
      enabled = true
      timeout = "3s"
  ```

=== 后续优化

初步实现完成后，修改过的 Hugo 已经能够很好的满足我的写作需求了，但是由于实现过程中使用的是 typst compile 来进行编译的，在运行 hugo server 的时候，每次修改 .typ 文件都会触发一次完整的编译，即使 Typst 文档非常简单，编译时间也会有 500ms 左右，远大于使用 Markdown 编写时 10ms 以内的编译时间。

因此，我添加了对于 typst watch，即增量编译的支持，这样，在 hugo server 的时候，修改 .typ 文件只会触发增量编译，编译时间也可以缩短到 200ms 左右。

具体实现如下：

- 在 Provider 中添加一个 watchManager 专门用于管理 typst watch 进程：

  ```go
  // Location: markup/typst/watch.go
  type watchManager struct {
    runner  typstcli.Runner
    logger  interface{ Warnf(format string, v ...any) }
    timeout time.Duration

    pages     string
    outputDir string

    mu      sync.Mutex
    entries map[string]*watchEntry
    closed  bool
  }

  type watchEntry struct {
    input  string
    output string

    startOnce sync.Once
    cancel    context.CancelFunc
    done      chan struct{}

    errMu sync.RWMutex
    err   error
  }
  ```

  其中 runner 是封装了 Typst CLI 的对象，entries 则是用于记录所有通过 runner 运行 typst watch 的进程相关的信息的，比如输入输出文件、context 的 cancel 函数、完成信号等等。

- 在 Converter 中劫持 typst compile 的调用，如果在配置中启用了 watch，即以下选项在 hugo.toml 中配置了：

  ```toml
  [markup.typst.watch]
    enabled = true
    timeout = "3s"
  ```

  那么就通过 watchManager 的 `render` 方法来调用 typst watch 来进行编译：

  ```go
  // Location: markup/typst/convert.go
  if c.watch != nil && ctx.Filename != "" {
    content, err := c.watch.render(ctx.Filename, world, process)
    if err == nil {
      if len(content) == 0 {
        logger.Warnf("%s watch rendered no output for %s, falling back to compile", cfg.Binary, ctx.DocumentName)
      } else {
        clean := stripHTMLDocument(content)
        return normalizeExternalHelperLineFeeds(clean), nil
      }
    } else {
      logger.Warnf("%s watch failed for %s: %v; falling back to compile", cfg.Binary, ctx.DocumentName, err)
    }
  }
  ```

  watchManager 的 `render` 方法会使用 `sync.Once` 来保证对于同一个输入文件只会启动一个 go routine 用于运行 typst watch 进程：

  ```go
  // Location: markup/typst/watch.go
  entry.startOnce.Do(func() {
    ctx, cancel := context.WithCancel(context.Background())
    entry.cancel = cancel

    go func() {
      defer close(entry.done)
      err := m.runner.Watch(typstcli.WatchArgs{
        Compile: typstcli.CompileArgs{
          Input:   typstcli.Input(entry.input),
          Output:  typstcli.Output(entry.output),
          Format:  typstcli.OutputFormatHTML,
          World:   world,
          Pages:   pagesFromConfig(m.pages),
          Process: process,
          Exec: typstcli.ExecOptions{
            Context: ctx,
            Stderr:  os.Stderr,
          },
        },
        Server: typstcli.ServerArgs{
          NoServe:  true,
          NoReload: true,
        },
      })
      if errors.Is(ctx.Err(), context.Canceled) {
        return
      }
      if err == nil {
        err = errors.New("typst watch exited unexpectedly")
      }
      entry.setErr(err)
      if m.logger != nil {
        m.logger.Warnf("typst watch failed for %q: %v", entry.input, err)
      }
    }()
  })
  ```

  这样，在 hugo server 的时候，每次修改 .typ 文件就会触发 typst watch 来进行增量编译。

  但问题是，Hugo 如何得知 typst watch 何时完成了编译呢？这就需要通过读取输出文件的 modified time 来判断了，在 watchManager 的 `waitReady` 方法中实现了这个功能：

  ```go
  // Location: markup/typst/watch.go
  for {
    if err := entry.getErr(); err != nil {
      return err
    }
    outInfo, err := os.Stat(entry.output)
    if err == nil && !outInfo.ModTime().Before(info.ModTime()) {
      return nil
    }
    if time.Now().After(deadline) {
      return fmt.Errorf("timed out after %s waiting for typst watch output", m.timeout)
    }
    time.Sleep(20 * time.Millisecond)
  }
  ```

  通过每隔 20ms 检查一次输出文件的 modified time 来判断 typst watch 是否完成了编译，如果在配置的 timeout 时间内都没有完成，就返回一个超时错误。

=== 未来计划

虽然通过把 typst compile 改成 typst watch 已经大大提升了编译性能了，但是每次运行 typst query 获取 metadata 的过程仍然是一个完整的编译过程。可惜的是，Typst CLI 目前并没有支持 typst query 的增量编译功能，如果需要实现的话，可能需要修改 Typst CLI 的源代码，这将是一笔不小的工作量，而且考虑到目前的性能已经是可以接受的了，所以我暂时不打算去实现这个功能了。

== Typst

Typst 方面主要是增强实验性 HTML 导出的功能。万幸的是，Typst 目前是可以直接写 HTML 标签的，因此最终实现的效果的上界是有保证的，#strike[你甚至可以直接把 Typst 的内置函数全重写成 HTML 标签然后用 CSS 来控制样式]。

但是，我用 Typst 的目的肯定是尽可能用 Typst 的语法来排版，因此我自制了一个 article 的模板，以及一些常用函数支持，作为 local package 存放在 Blog 的 packages 目录中，以便导入使用。

以下我将简要介绍几个常见的功能的实现：

- 一些辅助函数，主要用于将 Typst 内置类型转换为 CSS 样式，比如 alignment 转换为 CSS 的 place-items：

  ```typ
  // support: place-items, text-align, vertical-align, etc.
  #let to-alignment(alignment) = {
    if type(alignment) != std.alignment {
      panic("Unsupported alignment type, please use a valid alignment!")
    }

    let x-align = alignment.x
    x-align = if x-align == center {
      "center"
    } else if x-align == left {
      "start"
    } else if x-align == right {
      "end"
    } else if x-align == start {
      "start"
    } else if x-align == end {
      "end"
    } else {
      "start" // fallback to start if none
    }

    let y-align = alignment.y
    y-align = if y-align == top {
      "start"
    } else if y-align == horizon {
      "center"
    } else if y-align == bottom {
      "end"
    } else {
      "start" // fallback to start if none
    }

    (x-align, y-align)
  }
  ```

- `#h`、`#v` 和 `#align` 等内置函数的实现：

  ```typ
  #let h-func(it) = {
    let amount = it.amount.to-absolute().pt()
    html.span(
      style: "display: inline-block; width: 100%; width: " + str(amount) + "px;",
    )
  }

  #let v-func(it) = {
    let amount = it.amount.to-absolute().pt()
    html.div(
      style: "height: " + str(amount) + "px;",
    )
  }

  #let align-func(it) = {
    let (x-align, y-align) = to-alignment(it.alignment)
    let place-items = y-align + " " + x-align

    html.div(
      style: "display: grid; place-items: " + place-items + ";",
      it.body,
    )
  }
  ```

  内置函数一律通过 show rules 来重写成 HTML 标签，比如在 article 模板中：

  ```typ
  #show h: h-func
  #show v: v-func
  #show align: align-func
  // ...
  ```

除此之外，针对我使用的 PaperMod 主题的样式，我还实现了一些 CSS 样式，比如对于链接、代码块的样式，位于 `/assets/css/extended` 目录下，具体就不展开介绍了，感兴趣的话可以直接看源代码。

= 总结

最后，从我编写本文的体验来说，使用 Typst 来编写 Blog 文章的体验是非常不错的，Typst 的语法简单，功能强大，能够让我专注于内容的创作，而不需要过多地关注排版的细节。对于常年熟练使用 Typst 的用户来说，使用 Typst 来编写 Blog 我觉得是一个非常不错的选择。

不过说实在，Typst 目前对于 HTML 导出的支持还不够完善，很多内置函数默认是会被 Typst 忽略的，需要手动实现，因此对于新手来说，我还是更加推荐使用 Markdown 来编写 Blog，毕竟各大 Blog 框架对 Markdown 的支持都远比 Typst 完善许多。
