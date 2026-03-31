#import "@hugo/templates:0.1.0": article
#import "@hugo/utils:0.1.0": *

#show: article.with(
  title: "计算机启动过程 —— 以 Arch Linux 安装过程为例",
  date: datetime(year: 2026, month: 3, day: 31),
  draft: false,
)

#import "@preview/fletcher:0.5.8": diagram, node, edge
#import "@preview/bytefield:0.0.8": *

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

在开始安装前，你应该提前准备好了一台能够正常开机的计算机和一个安装介质（比如 U 盘）。

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

=== 磁盘分区

这部分对应 Arch Wiki 的 1.9 部分。

磁盘分区是计算机启动过程中的一个重要环节，这涉及到 *Firmware 如何找到 Bootloader*，以及 *Bootloader 如何找到 Kernel*，而且在 UEFI 和 BIOS 两种 Firmware 下，分区的要求也是不同的，接下来我们将分别讨论。

==== BIOS

在传统的 BIOS 模式下，磁盘的分区信息存放在磁盘的第一个扇区，即 MBR（Master Boot Record，主引导记录）中，而 Bootloader 则分散存放在 MBR 中、MBR 后面的几个扇区以及某个分区中。

为了方便讲解，我以 GNU GRUB 2 作为 Bootloader 时的磁盘地址空间来讲解，以下是通过 GRUB 引导的计算机的磁盘地址空间示意图：#footnote[图片来源：https://en.wikipedia.org/wiki/BIOS_boot_partition#/media/File:GNU_GRUB_components.svg]

#figure(
  caption: "GRUB 在 BIOS 模式下的磁盘地址空间",
  image("/posts/images/grub-bios.jpg")
)

- Example 1: MBR 部分存放了 GRUB 的第一组成部分 —— `boot.img`，然后 `boot.img` 在执行时会把位于 MBR 后面几个扇区的 `core.img` 加载进内存并跳转执行，而 `core.img` 则作为 GRUB 的第二组成成分，从后面的分区（图中为 `/dev/sda2` 分区）中可选的加载其他 GRUB 模块，从而完成 GRUB 作为 Bootloader 的完整功能。
- Example 2: MBR 依旧存放了 `boot.img`，但是该设备采用 GPT 分区表，MBR 后面的几个扇区是有有效数据的，此时 GRUB 就不能把 `core.img` 存放在这里了，而是必须在分区表里添加一个特殊的 BIOS Boot Partition 分区来存放 `core.img`，GRUB 在执行时会把 `core.img` 从 BIOS Boot Partition 分区中加载进内存并跳转执行，之后就和 Example 1 的流程一样了。

通常，采用传统 BIOS 方案都是因为设备过于老旧，不支持 UEFI，所以也不太可能会采用 GPT 分区表（除非是从新电脑拆下来的用的）。因此在这种情况下，根据 Arch Wiki 的建议，我们的分区策略通常是：

#figure(
  caption: "BIOS 方案的分区示例",
  table(
    columns: 4,
    align: center + horizon,
    [Mount Point], [Partition], [Partition Type], [Suggested Size],
    [[swap]], [/dev/sda1], [Linux swap], [建议和内存大小相同],
    [/], [/dev/sda2], [Linux File System], [设备剩余部分],
  )
)

需要注意的是，在使用 fdisk 进行分区时，磁盘的前 2048 个扇区（即前 1 MiB）通常会保留从而禁止被分配空间，这是因为 GRUB 的 `boot.img` 和 `core.img` 都需要存放在这里。你可以通过 `fdisk -l` 指令查看最终分区情况，比如在我装有 GNU/Linux Debian 系统的采用传统 BIOS 方案的设备上，输出情况如下所示：

```bash
$ fdisk -l
Disk /dev/sda: 447.14 GiB, 480113590272 bytes, 937721856 sectors
Disk model: WDC WDS480G2G0B-
Units: sectors of 1 * 512 = 512 bytes
Sector size (logical/physical): 512 bytes / 512 bytes
I/O size (minimum/optimal): 512 bytes / 512 bytes
Disklabel type: dos
Disk identifier: 0x400c0e55

Device     Boot     Start       End   Sectors   Size Id Type
/dev/sda1  *         2048 935720959 935718912 446.2G 83 Linux
/dev/sda2       935723006 937719807   1996802   975M  5 Extended
/dev/sda5       935723008 937719807   1996800   975M 82 Linux swap / Solaris
```

可以看到前 2048 个扇区被保留了，之后的分区都是从 2048 开始分配的。

你可以会好奇，Extended 分区有什么用？这个主要是 MBR 分区表的一个限制，MBR 分区表最多只能支持 4 个主分区（Primary Partition），如果你需要更多的分区，就需要把其中一个主分区设置为 Extended 分区，然后在 Extended 分区中创建逻辑分区（Logical Partition）来使用，不过在这里使用 Extended 分区主要还是 Debian 系统安装器默认行为的历史原因，不必过于纠结于此了。

==== UEFI

在 UEFI 模式下，磁盘的分区信息则存放在紧邻 MBR 后面的 GPT（GUID Partition Table，GUID 分区表）中，而 Bootloader 则存放在一个特殊的分区中，即 ESP（EFI System Partition，EFI 系统分区）中。

同样，为了方便讲解，我以 GNU GRUB 2 作为 Bootloader 时的磁盘地址空间来讲解，以下是通过 GRUB 引导的计算机的磁盘地址空间示意图：#footnote[根据原图片进行修改：https://en.wikipedia.org/wiki/BIOS_boot_partition#/media/File:GNU_GRUB_components.svg]

#figure(
  caption: "GRUB 在 UEFI 模式下的磁盘地址空间",
  image("/posts/images/grub-uefi.jpg")
)

- Example 1: MBR 部分放置了 Protective MBR（保护性 MBR），它的作用是为了兼容旧的 BIOS 系统，防止 BIOS 系统误认为磁盘没有分区而进行错误的操作（在 BIOS 看来，这块磁盘就是一个全占满数据的磁盘）。GPT 分区表则存放在紧邻 MBR 后面的几个扇区中，而 GRUB 则把 bootx64.efi 等 EFI 可执行文件放在 ESP 分区中，在执行时由 UEFI 直接加载 bootx64.efi 文件来启动 GRUB。
  - 需要注意的是，EFI 分区实际上并没有 `/boot` 目录，而是因为安装系统时通常都会把 ESP 分区挂载到 `/boot` 目录下，所以在进入系统后 `/boot/grub` 目录实际上是 ESP 分区中的 `/grub` 目录。

不同于传统 BIOS 方案，UEFI 方案下，磁盘还需要额外分配一个 ESP 分区来存放 Bootloader，因此在这种情况下，根据 Arch Wiki 的建议，我们的分区策略通常是：

#figure(
  caption: "UEFI 方案的分区示例",
  table(
    columns: 4,
    align: center + horizon,
    [Mount Point], [Partition], [Partition Type], [Suggested Size],
    [/boot], [/dev/sda1], [EFI System], [1 GiB],
    [[swap]], [/dev/sda2], [Linux swap], [建议和内存大小相同],
    [/], [/dev/sda3], [Linux File System], [设备剩余部分],
  )
)

EFI 分区我的建议是大一点比较好，比如 1 GiB 就足够了，因为如果你之后想装双系统，或者多内核，其他系统的 Bootloader 和各个版本的 Kernel 文件也需要放在这个分区，如果分区太小了，只能通过缩减 swap 分区来给 ESP 分区腾出空间了，#strike[强迫症要难受死了]。

比如在我的装有 Arch Linux 系统的采用 UEFI 方案的设备上，`fdisk -l` 输出情况如下所示：

```bash
$ fdisk -l    
Disk /dev/nvme1n1: 953.87 GiB, 1024209543168 bytes, 2000409264 sectors
Disk model: SAMSUNG MZVL21T0HCLR-00BL2              
Units: sectors of 1 * 512 = 512 bytes
Sector size (logical/physical): 512 bytes / 512 bytes
I/O size (minimum/optimal): 512 bytes / 512 bytes
Disklabel type: gpt
Disk identifier: B8FF745C-1A82-4238-A89A-DB9F81FF075E

Device            Start        End    Sectors   Size Type
/dev/nvme1n1p1     2048    2099199    2097152     1G EFI System
/dev/nvme1n1p2  2099200   34142207   32043008  15.3G Linux swap
/dev/nvme1n1p3 34142208 2000408575 1966266368 937.6G Linux filesystem
```

=== 格式化和挂载分区

这部分对应 Arch Wiki 的 1.10 - 1.11 和 3.1 部分。

创建分区后，第一件事就是要对分区进行格式化（Format），也就是在分区上创建一个文件系统（File System），因为分区只是划分了一个磁盘区域，至于文件是如何在磁盘上存储的，还需要通过文件系统来定义和管理，常见的文件系统有 ext4、FAT32、NTFS 等，不同的文件系统有不同的特点和适用场景。

创建完文件系统，我们还需要挂载（Mount）分区，也就是按照一定的目录结构把分区连接到系统的文件系统树（File System Tree）上，这样我们才能通过路径（Path）来访问分区中的文件。一个分区可以挂载到多个路径上，也可以只挂载到一个路径上，挂载到的路径称之为挂载点（Mount Point），比如我们通常会把 Linux File System 分区挂载到根目录（`/`）上，而把 EFI System 分区挂载到 `/boot` 目录上。

在 Linux 系统的启动过程中，Linux 会根据 `/etc/fstab` (i.e. File System Table) 文件中的配置来自动挂载分区，这个文件中定义了每个分区的设备路径、挂载点、文件系统类型以及挂载选项等信息，Linux 会根据这些信息来正确地挂载分区，从而保证系统的正常运行。比如，在我的 Arch Linux 系统中，`/etc/fstab` 文件的内容如下所示：

```bash
$ cat /etc/fstab
# /dev/nvme1n1p3 LABEL=arch-root
UUID=eea8de7e-b37f-4b3b-b530-1003eeab9746       /               btrfs           rw,relatime,compress=zstd:3,ssd,discard=async,space_cache=v2,subvol=/@  0 0

# /dev/nvme1n1p3 LABEL=arch-root
UUID=eea8de7e-b37f-4b3b-b530-1003eeab9746       /home           btrfs           rw,relatime,compress=zstd:3,ssd,discard=async,space_cache=v2,subvol=/@home   0 0

# /dev/nvme1n1p1
UUID=58AC-071E          /boot           vfat            rw,relatime,fmask=0022,dmask=0022,codepage=437,iocharset=ascii,shortname=mixed,utf8,errors=remount-ro0 2

# /dev/nvme1n1p2
UUID=c06f27fb-de0e-438d-9162-135e9cb735fd       none            swap            defaults        0 0
```

由于我使用的是 GPT 分区方案，因此每个分区都有一个 UUID（Universally Unique Identifier，通用唯一标识符），Linux 会根据这个 UUID 来识别和挂载分区，这样即使分区的设备路径发生了变化（比如从 `/dev/sda1` 变成了 `/dev/sdb1`），Linux 仍然能够正确地挂载分区。

我们可以使用 genfstab 命令来根据目前的挂载情况自动生成 `/etc/fstab` 文件，不需要手动编写，比如，在我的 Arch Linux 系统中，执行 genfstab 命令的结果如下所示：

```bash
$ genfstab -U /
# /dev/nvme1n1p3 LABEL=arch-root
UUID=eea8de7e-b37f-4b3b-b530-1003eeab9746       /               btrfs           rw,relatime,compress=zstd:3,ssd,discard=async,space_cache=v2,subvol=/@  0 0

# kio-fuse
kio-fuse                /run/user/1000/kio-fuse-QpczeW  fuse.kio-fuse   rw,nosuid,nodev,user_id=1000,group_id=1000      0 0

# /dev/nvme1n1p3 LABEL=arch-root
UUID=eea8de7e-b37f-4b3b-b530-1003eeab9746       /home           btrfs           rw,relatime,compress=zstd:3,ssd,discard=async,space_cache=v2,subvol=/@home   0 0

# bilibili.AppImage
bilibili.AppImage       /tmp/.mount_bilibiJnd6TL        fuse.bilibili.AppImage  ro,nosuid,nodev,user_id=1000,group_id=1000      0 0

# /dev/nvme1n1p1
UUID=58AC-071E          /boot           vfat            rw,relatime,fmask=0022,dmask=0022,codepage=437,iocharset=ascii,shortname=mixed,utf8,errors=remount-ro0 2

# /dev/nvme1n1p2
UUID=c06f27fb-de0e-438d-9162-135e9cb735fd       none            swap            defaults        0 0
```

== 安装过程

在这一步骤开始前，你应该已经将一块磁盘划分好了分区，并格式化和挂载了分区，也就是说，你现在可以开始向磁盘正常写入文件了。

=== 软件包

这部分对应 Arch Wiki 的 2.1 - 2.2 部分。

这部分就是安装一个能够基本使用的系统的过程。在这个部分之前，我们已经配置好每个分区以及每个分区的文件系统了，但是分区里没有任何文件，因此这个部分就是将我们向创建好的分区里安装系统最基本的软件的过程了，比如安装包管理器（在 Arch Linux 中是 pacman）以及一些基本的软件包（比如 base），最重要的就是安装 Linux Kernel 及其固件驱动了（即 linux 和 linux-firmware）从而让 Bootloader 能够找到并加载 Kernel 来启动系统。

这部分和计算机启动过程关系不大，因此不做过多讲解。

== 配置系统

在这一步骤开始前，你应该已经成功在磁盘上安装好了组成一个系统的基本软件包，但是只是缺乏一些配置让它正常 work 起来。

=== Chroot

这部分对应 Arch Wiki 的 3.2 部分。

chroot 本质上是一个 Linux 系统调用（System Call），它的唯一作用就是改变当前进程的根目录到指定的路径上，也就*好像进入到了已经安装好的系统里*了一样（虽然仍有差别）。

=== 一些杂项

这部分对应 Arch Wiki 的 3.3 - 3.5 和 3.7 部分。

这部分主要就是时区、语言、网络等和计算机启动过程关系不大的内容了，更多是的个性化的配置，这里就不展开讲解了。

=== Initramfs

这部分对应 Arch Wiki 的 3.6 部分。

Initramfs 是 Linux 内核在启动前必须加载进内存的一个临时的文件系统，里面存放着一些必要的驱动程序和工具，从而让内核能够正确识别和挂载根文件系统，从而完成系统的启动过程。

不过根据 Arch Wiki 的所说，在使用 pacstrap 的时候，pacman 已经自动构建了 initramfs 了，因此我们大部分情况不需要手动构建 initramfs 了。

=== Bootloader

这部分对应 Arch Wiki 的 3.8 部分。

虽然这一步在 Arch Wiki 里只有短短一行，但是这一步反而是整个配置系统过程中*最重要的一步*了，即选择并安装一个合适的 Bootloader 来引导系统的启动。

通常，绝大多数的 Linux 发行版都将 GRUB 作为默认的 Bootloader，因此接下来我将讲述 GRUB 的安装和配置过程。

比如，在我的 Arch Linux 系统中，安装和配置 GRUB 的过程如下所示：

```bash
pacman -Sy grub
grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=arch --modules="tpm" --disable-shim-lock
grub-mkconfig -o /boot/grub/grub.cfg
```

首先，我使用 `grub-install` 指令用于将 GRUB 安装到 `/boot` 目录下，并且以 `arch` 作为 Bootloader 标识符（放在 `/boot/EFI/arch` 目录下），同时我还启用了 TPM 模块来支持 Secure Boot 功能。然后，我使用 `grub-mkconfig` 指令在自动发现当前计算机上安装的所有系统，从而生成 GRUB 的配置文件放在 `/boot/grub/grub.cfg` 中，其中包含了 Arch Linux 系统的启动项以及其他系统的启动项（如果有的话）以便进入 GRUB 的启动界面时能够直接选择进入哪个系统，而不需要手动输入命令来加载模块和引导 Kernel。

== 重启

在这一步骤开始前，你应该已经完成了整个系统的安装和配置，现在只需要重启计算机，计算机就会首先在 Firmware 阶段进行自检和初始化，然后加载你刚刚安装好的 GRUB 作为 Bootloader，在你选择了 Arch Linux 的启动项后，GRUB 就会加载 Arch Linux 的 Kernel 从而启动系统。

= 总结

到此，我们可以回顾一下 Arch Linux 的安装过程来总结一下计算机的启动过程：

- Firmware 阶段：我们实际上在安装过程中几乎完全没有接触和配置过这部分，这是显然的，因为 Firmware，即固件，通常是由计算机厂商预装在主板上的 ROM 芯片中的，我们只能通过进入 BIOS 设置界面来查看和修改一些基本的设置（比如启动顺序、Secure Boot 等），但是我们无法直接修改 Firmware 的代码或者功能。
- Bootloader 阶段：我们首先在*安装前的准备*阶段给 Bootloader 留好了 MBR 和 ESP 分区来存放 Bootloader 的文件，然后在*配置系统*阶段的最后安装了 GRUB 作为 Bootloader，并且生成了 GRUB 的配置文件来让 GRUB 能够正确地引导系统的启动。
- Kernel 阶段：我们首先在*安装前的准备*阶段给 Kernel 留好了 Linux File System 分区和 ESP 分区来存放 Kernel 的文件，然后在*安装过程*阶段通过 pacstrap 安装了 Linux Kernel 以及相关的固件驱动，从而让 Bootloader 能够找到并加载 Kernel 来启动系统。

以上就是本文的全部内容了，希望能够帮助你更好地理解计算机的启动过程，以及在安装系统时每个步骤背后的原理和细节。

#strike[第一次写这种技术性的文章，感觉写得有点啰嗦了，而且有点缺乏章法，但毕竟是第一次写，希望以后能有所改进！]

#hr()
