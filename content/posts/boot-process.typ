#import "@hugo/templates:0.1.0": article
#import "@hugo/utils:0.1.0": *

#show: article.with(
  title: "计算机启动过程 —— 以 Arch Linux 安装过程为例",
  date: datetime.today(),
  draft: true,
)

#import "@preview/fletcher:0.5.8": diagram, node, edge

= 前言

从大二上计算机组成原理的时候我就想写一篇这样的文章了，当时我调研了 x86 架构平台的计算机的启动过程，意识到很多人实际上并不是非常了解一台计算机从上电到进入桌面的全过程。

虽然网上有很多关于计算机启动过程的文章，结合了具体的系统，甚至制作了精美的动画，但是我觉得它们为了讲解的清晰，往往省略了实际执行的指令细节，导致*理解启动原理*和*实际安装系统*之间仍存在一定的距离。

因此，本文我将以 x86 架构为例，结合 Arch Linux 系统的安装过程来讲解计算机的启动过程。

= 背景

== 基本流程

虽然很多文章已经讲解过计算机的启动过程了，但是为了便于不了解计算机原理的读者理解，我还是想先介绍一些背景知识。

除了某些嵌入式（Embedded）系统以外，大多数计算机都采取类似的启动过程，如下图所示：

#figure(
  caption: "计算机启动过程",
  placement: auto,
  frame(diagram(
    node-stroke: .5pt,
    node-corner-radius: 2pt,
    node-outset: 2pt,
    spacing: (1em, 4em),
    edge((0, 0), "d", "->", [Power On], label-side: center),
    node((0, 1), "Firmware"),
    edge("->", [Initialize Hardware], label-side: center),
    node((0, 2), "Bootloader"),
    edge("->", [Load Kernel], label-side: center),
    node((0, 3), "Kernel"),
    edge("->", "d", [Load System Services], label-side: center),
  ))
)

即 Firmware、Bootloader 和 Kernel 三个阶段，每个阶段都执行特定的功能，并且在完成后将控制权交给下一个阶段。它们的功能分别如下：

- Firmware：负责计算机的基本硬件初始化和自检，确保系统的基本功能可用，并且找到并加载 Bootloader。
- Bootloader：负责加载操作系统内核，并将控制权交给 Kernel。
- Kernel：负责操作系统的核心功能，如进程管理、内存管理、文件系统等，并且启动用户空间的服务和应用程序。

== 一些示例

有点抽象？没关系，我将根据我的设备来举一些具体的例子：

- 一台装有 GNU/Linux Debian 13 的小型台式主机：
  - Firmware：存放在主板上的 ROM（只读存储器）芯片中，通常是 UEFI（统一可扩展固件接口）规范的实现。当你进入 BIOS 的时候，实际上进入的就是 UEFI BIOS 的设置界面（你可以在进入 BIOS 的时候观察一下上面标签上的字样）。
    - 如何查看：重启电脑，在开机时一直尝试按下某些特殊的键（如 F2、F10、Del 等）进入 BIOS 设置界面，具体按键取决于你的主板型号和厂商。
    - 示例：
      #figure(
        caption: "BIOS 设置界面",
        image("/posts/images/bios.jpg")
      )
  - Bootloader：存放在磁盘的主引导记录（MBR）或者 EFI 系统分区（ESP）中，通常是 GRUB（GRand Unified Bootloader）或者 systemd-boot 等引导加载程序。当你在 Boot Menu 中选择的时候，实际上就是选择不同介质（Media）上的 Bootloader 来加载。
    - 如何查看：重启电脑，不需要按下任何键，在开机后自动会停留到 Bootloader 的界面。
    - 示例：
      #figure(
        caption: "GRUB 启动界面",
        image("/posts/images/grub.jpg")
      )
  - Kernel：在 Linux 系统中，Kernel 通常存放在根文件系统的 /boot 目录下，通常以 vmlinuz 开头的文件。当你在 Bootloader 中选择的时候，实际上就是在选择不同的 Kernel 来加载。
    - 如何查看：在系统中打开终端，输入 `ls -hl /boot` 命令，查看 /boot 目录下的文件。
    - 示例：
      ```bash
      $ ls -hl /boot                                                                         
      total 410M
      -rw-r--r-- 1 root root 254K Jun 21  2024 config-6.1.0-22-amd64
      -rw-r--r-- 1 root root 277K Mar  9 03:54 config-6.12.74+deb13+1-amd64
      -rw-r--r-- 1 root root 290K Mar 15 03:28 config-6.19.6+deb13-amd64
      drwxr-xr-x 5 root root 4.0K Mar 20 20:47 grub
      -rw-r--r-- 1 root root  87M Jan 10 22:53 initrd.img-6.1.0-22-amd64
      -rw-r--r-- 1 root root 137M Mar 15 23:05 initrd.img-6.12.74+deb13+1-amd64
      -rw-r--r-- 1 root root 153M Mar 20 19:26 initrd.img-6.19.6+deb13-amd64
      -rw-r--r-- 1 root root   83 Jun 21  2024 System.map-6.1.0-22-amd64
      -rw-r--r-- 1 root root   83 Mar  9 03:54 System.map-6.12.74+deb13+1-amd64
      -rw-r--r-- 1 root root   92 Mar 15 03:28 System.map-6.19.6+deb13-amd64
      -rw-r--r-- 1 root root 7.8M Jun 21  2024 vmlinuz-6.1.0-22-amd64
      -rw-r--r-- 1 root root  12M Mar  9 03:54 vmlinuz-6.12.74+deb13+1-amd64
      -rw-r--r-- 1 root root  14M Mar 15 03:28 vmlinuz-6.19.6+deb13-amd64
      ```
- 一台装有多个 Windows 系统的笔记本电脑：
  - Firmware：同上，基本上都是 UEFI 标准实现或者传统 BIOS 实现。
  - Bootloader：同上，但是引导加载程序可能是 Windows Boot Manager。
    - 示例：
      #figure(
        caption: "Windows Boot Manager 启动界面",
        image("/posts/images/bootmgr.jpg")
      )
  - Kernel：同上，但是内核文件可能是 ntoskrnl.exe，而不是 vmlinuz 文件。

== 尝试一下

还是有点疑惑？那不妨就用你手上的设备来试试看吧，比如尝试进入 BIOS 设置界面看看，使用键盘上下左右键浏览，问问 AI 各个选项的作用，相信你会有更多的收获的。

= 讲解

在基本了解了背景知识后，我将结合 Arch Linux 的安装过程讲解计算机的启动过程。这部分主要参考的是 #link("https://wiki.archlinux.org/title/Installation_guide")[Install Guide - Arch Wiki]，一个颇为详细的 Arch Linux 安装指南。虽说如此，你不应该将本文当作 Arch Linux 的安装教程来读，而只是为了便于理解计算机启动过程才结合了 Arch Linux 的安装过程来讲解，你也可以把本文当作对于 Install Guide - Arch Wiki 的解读来理解。

== 安装前的准备

=== 准备镜像

这部分对应 Arch Wiki 的 1.1 - 1.3 部分。

通常，在安装任何系统之前，你都需要在一个安装介质（Installation Media）上准备好系统的安装文件，通常，安装介质就是随处可见的 USB 闪存盘（U 盘），而安装文件则是一个以 .iso 结尾的 ISO 镜像文件，里面存放着整个系统的文件系统，包括 Bootloader、Kernel 和基本的用户空间工具等，你可以理解为就是一个可以随身携带的微型系统，安装系统的过程实际上都是在这个微型系统上进行的。

通常，你可以在镜像站中下载到各种系统的 ISO 镜像文件，比如 #link("https://mirrors.ustc.edu.cn")[USTC Mirrors] 和 #link("https://mirrors.tuna.tsinghua.edu.cn")[TUNA Mirrors] 等国内镜像站。

但是，计算机不能在启动时直接读取 ISO 镜像文件来启动，因此，你需要将镜像通过 `dd` 命令（Linux）或者其他工具，比如 Refus（Windows）等按二进制方式直接写入到 U 盘中去。

不过，在这里，我更推荐使用 Ventoy 这个工具来制作安装介质，它最大的好处就是你只需要把 ISO 文件丢进 U 盘里就可以了，不需要每次都使用烧录工具，而且它支持 GUI 操作，在我的系统上的界面如下所示：

#figure(
  caption: "Ventoy 界面",
  image("/posts/images/ventoy-install.png")
)

选择你的 U 盘，点击安装（Install）按钮，然后把 ISO 镜像文件直接丢进 U 盘里就可以了，非常方便。

=== 进入 Live System

这部分对应 Arch Wiki 的 1.4 部分。

Live System 就是我们所说的装在 U 盘上的微型系统。

首先你需要把 U 盘插在计算机上，然后重启/开机，在开机时按下某些特殊的键（如 F2、F10、Del 等）进入 Boot Menu，具体按键取决于你的主板型号和厂商，在 Boot Menu 中选择你的 U 盘来启动。

以我的 ThinkPad e480 笔记本为例，在开机时按下 Enter 键进入 Startup Interrupt Menu：

#figure(
  caption: "Startup Interrupt Menu",
  image("/posts/images/startup-menu.jpg")
)

根据提示，按下 F12 键进入 Boot Menu：

#figure(
  caption: "Boot Menu",
  image("/posts/images/boot-menu.jpg")
)

然后使用上下键切换到 USB HDD 选项，按下 Enter 键就可以进入 Ventoy 的界面了：

#figure(
  caption: "Ventoy 启动界面",
  image("/posts/images/ventoy-boot.jpg")
)

接着，选择你要安装的系统的 ISO 镜像文件，一路按 Enter 键就可以进入 Live System 了：

#figure(
  caption: "Live System 桌面",
  image("/posts/images/archiso.png")
)

从计算机启动过程的视角来看，这一部分完整地从 U 盘中启动了一个系统，因此完全运行了我们之前所说的 Firmware、Bootloader 和 Kernel 三个阶段的功能：

- Firmware：在开机进入 Boot Menu 前执行，完成了计算机的基本硬件初始化和自检，并且找到了 U 盘上的 Bootloader，进入 Boot Menu。
- Bootloader：在 Boot Menu 中选择 U 盘后，被计算机读取到内存中执行，也就是我们的 Ventoy 以及其引导的 systemd-boot 引导加载程序。
- Kernel：在最后一路按 Enter 键的过程中，我们选择了 Arch Linux 的 Live System 的 Kernel 来加载。计算机读取 Kernel 文件到内存中执行，从而顺利启动和进入了 Live System。

=== 一些杂项

这部分对应 Arch Wiki 的 1.5 - 1.8 部分。

这部分主要就是键盘布局、网络连接等和计算机启动过程关系不大的内容了，这里就不展开讲解了。

=== 分区和格式化磁盘

这部分对应 Arch Wiki 的 1.9 - 1.11 部分。


