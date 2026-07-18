#import "@hugo/templates:0.1.0": article

#show: article.with(
  title: "在 Legion Y9000P IRX8 上使用 qemu/kvm 直通核显流畅运行 Windows 系统",
  date: datetime(year: 2026, month: 7, day: 18),
  tags: (
    platforms: ("linux", "qemu", "kvm"),
    domains: "virtualization",
    intents: "enhancement",
  ),
  draft: false,
)

= 前言

众所周知，我是一个 Arch Linux User。很久之前我就在尽可能迁移在 Windows 的工作流到 Arch Linux 中，希望能够尽可能减少双系统的依赖。但是很遗憾的是，开源最终还是有极限的啊！越是迁移在 Windows 上扎根已深的工作流，越会发现开源社区面对闭源商业软件的无力！（说的就是你，傻逼 Office 全家桶）没办法，折中一下，我开始考虑在 qemu 中跑 Windows kvm 虚拟机。

我使用的笔记本是 Legion Y9000P IRX8，同时拥有 i9 13900HX 的核显和 RTX 4060 laptop 的独显，而我的计划是独显给 Linux 物理机使用，而核显给 Windows 虚拟机使用。不同于社区常见的 Linux 使用核显，Windows 使用独显的方案，我选择这个方案的原因主要是我的主要开发工作流都还在 Linux 中，只有少量闭源商业软件不得不跑在 Windows 里。

= 分析

不同于台式机的核显、独显和显示器是完全独立的不同组件，笔记本通常受限于空间大小和定制化设计，往往存在各种驱动问题或硬件限制，导致方案难以实施，我的笔记本也不例外。

阻碍方案实施的主要是内屏接入的显卡的硬件 MUX，简要来说，在游戏本中，通常存在一个硬件开关，用于在混合模式 (Hybrid) 和独显模式 (Discrete) 间切换，而在混合模式下，内屏是直连核显的，只有在独显模式下，内屏才是直连独显的。

我们可以在 Linux 的 sysfs 中看到 eDP 内屏证明这一点：

```bash
#!/bin/bash

# find which card device correspond to which physical card
for card in /sys/class/drm/card[0-9]*; do
    [[ -e "$card/device/driver" ]] || continue
    driver=$(basename "$(readlink -f "$card/device/driver")")
    echo "$(basename "$card") -> driver: $driver"
done

# find connected status of all eDP ports
for f in /sys/class/drm/card*-eDP-*; do
    echo "$f: $(cat "$f/status")"
done
```

```txt
card0 -> driver: i915
card1 -> driver: nvidia
/sys/class/drm/card0-eDP-2: connected
/sys/class/drm/card1-eDP-1: disconnected
```

其中，只有核显驱动 i915 对应的核显连接着笔记本的 eDP 内屏。

但是，这并不意味这个方案就完蛋了，幸运的是，虽然笔记本的 eDP 内屏连着核显，但是笔记本的 HDMI 输出口是连着独显的！

```bash
#!/bin/bash

# find connected status of all ports
for f in /sys/class/drm/card*-*; do
    echo "$f: $(cat "$f/status")"
done
```

```txt
/sys/class/drm/card0-eDP-2: connected
/sys/class/drm/card1-DP-1: disconnected
/sys/class/drm/card1-DP-2: disconnected
/sys/class/drm/card1-eDP-1: disconnected
/sys/class/drm/card1-HDMI-A-1: connected
```

因此，只要使用外接显示器，放弃使用内屏，那我们还是可以在混合模式下同时使用核显和独显的，而事实证明，确实如此。

= 背景

在开始讲述配置之前，我有必要先讲一下配置前的背景信息：

- 硬件：
  - 一台 Legion Y9000P IRX8 笔记本，搭载 i9 13900HX 核显和 RTX 4060 laptop 独显双显卡
  - 一台使用 HDMI 线连接到笔记本 HDMI 输出口的显示屏（必要，原因如上所述）
- 软件：
  - 宿主机安装好 Arch Linux 系统，使用 GRUB 启动系统，使用 Wayland + SDDM + KDE Plasma 6 桌面环境
  - 宿主机安装好 libvirt (virt-manager) 等虚拟化软件，并安装好一个基于 `pc-i440fx-*.*` 虚拟主板（必要，为了兼容核显），使用 UEFI 启动（必要，BIOS 有驱动问题）的 Windows 10 虚拟机

= 实现

== 宿主机配置

首先，我们需要做的是让宿主机上的 Linux 把核显让出来，不能在开机的时候把核显占用了，否则之后启动虚拟机的时候，虚拟机会抢占核显设备，重新初始化硬件，导致 Linux 部分依赖于核显实现硬件加速的软件（比如基于 Electron 的软件）全都 SIGSEGV 崩溃。

这里我们不能单纯的在 `/etc/modprobe.d` 中把 i915 和 xe 驱动全都 blacklist，Linux 上的音频设备会因为缺乏这些模块无法初始化，也因此无法发出声音。

=== envycontrol

在这里，我首先使用了 #link("https://aur.archlinux.org/packages/envycontrol")[envycontrol] 对进行了全局的 Nvidia 环境进行了配置：

```bash
sudo envycontrol -s nvidia
```

虽然根据 #link("https://docs.nvidia.com/datacenter/tesla/driver-installation-guide/optimus-laptops-and-multi-gpu-desktop-systems.html")[Nvidia 官方所述]，在使用 Nvidia Optimus 技术的笔记本上使用 envycontrol 从而强制所有应用使用 Nvidia 显卡通常是弊大于利的，但是这是限定在我们仅使用内屏的情况下。

如果使用内屏的话，由于内屏直连的是核显，一旦所有应用都使用 Nvidia 显卡渲染，那么数据就必须在显存和内存中频繁搬运，在我的机器上实测这将导致超过 1Gbps 的 RX 和 TX 带宽。但是我采用的是外接显示器的方案，HDMI 接口直连独显，那么就完全没有这样的顾虑，反而使用 envycontrol 大大方便了配置（比如 X11 使用 Nvidia 显卡）。

=== plasma-workspace

虽然 envycontrol 承包了很多配置，但是有一个问题就是 envycontrol 不支持 Wayland，只支持 X11，因此为了能覆盖所有桌面应用，我们还需要给 plasma-workspace 设置环境变量：

```bash
### ~/.config/plasma-workspace/env/nvidia.sh
export KWIN_DRM_DEVICES="/dev/dri/by-path/pci-0000\:01\:00.0-card" # remember to escape colons
export __NV_PRIME_RENDER_OFFLOAD=1
export __NV_PRIME_RENDER_OFFLOAD_PROVIDER=NVIDIA-G0
export __GLX_VENDOR_LIBRARY_NAME=nvidia
export __EGL_VENDOR_LIBRARY_FILENAMES=/usr/share/glvnd/egl_vendor.d/10_nvidia.json
```

都是一些常见的修复 Nvidia 上应用错误以及强制使用 Nvidia 显卡渲染的环境变量，除了 KWin Wayland 特有的变量 `KWIN_DIR_DEVICES`，实际指向了 `/dev/dri/card1`，但是使用 pci 总线地址实现更健壮的定位。

=== kernel cmdline

除了桌面，我还希望开机日志和 tty 都跑在外接显示屏上，这样方便我使用，而且还有核显的直通需要 iommu，顺便一起设置了：

```bash
### /etc/default/grub
GRUB_CMDLINE_LINUX_DEFAULT="... intel_iommu=on iommu=pt fbcon=map:1"
```

其中 `fbcon=map:1` 选项指定了使用 `/dev/fb1` 这个设备来显示 tty 终端，可以通过以下脚本来查看 frame buffer 连接的显卡：

```bash
#!/bin/bash

# find which frame buffer correspond to which physical card
for card in /sys/class/graphics/fb[0-9]*; do
    [[ -e "$card/device/driver" ]] || continue
    driver=$(basename "$(readlink -f "$card/device/driver")")
    echo "$(basename "$card") -> driver: $driver"
done
```

```txt
fb0 -> driver: i915
fb1 -> driver: nvidia
```

=== initcpio

然后，我们需要在 initcpio 中添加 Nvidia 驱动，否则开机日志、tty 和 sddm 都将无法正常显示：

```bash
### /etc/mkinitcpio.conf
MODULES=(nvidia nvidia_modeset nvidia_uvm nvidia_drm)
```

最后更新 grub config 和 initcpio：

```bash
sudo grub-mkconfig -o /boot/grub/grub.cfg
sudo mkinitcpio -P
```

然后重启，应用所有配置，此时从 tty 到 sddm 到 kde 桌面，全链路上的所有软件都会仅使用 Nvidia 显卡输出，而不会占用核显，这为我们后来直通核显而不会干扰宿主机中的软件奠定了基础。

== 虚拟机配置

接着，我们需要给虚拟机配置核显直通和并且给虚拟机打上核显驱动，这部分需要注意的主要是设备的兼容性，需要确保虚拟机内的核显驱动不会报错（如报错，报错代码通常是 Code 43），因此需要再三确认虚拟机是基于 `pc-i440fx-*.*` 虚拟主板的 UEFI 启动的 Windows 系统，否则大概率报错。

=== libvirt

首先我们先配置 libvirt，将核显直通进虚拟机内，这部分不能只使用 virt-manager 的简化操作界面，需要手搓里面的 xml 配置文件，可以使用 virt-manager 的 XML 标签页编辑，也可以使用 `virsh edit <your-virtual-machine-name>` 在终端编辑。

首先是添加给根标签添加额外的 namespace 支持，从而方便直接操作 qemu 命令行参数：

```xml
<domain xmlns:qemu="http://libvirt.org/schemas/domain/qemu/1.0" type="kvm">
...
</domain>
```

然后将核显 pci 透穿到虚拟机内：

```xml
<domain xmlns:qemu="http://libvirt.org/schemas/domain/qemu/1.0" type="kvm">
...
  <devices>
  ...
    <hostdev mode="subsystem" type="pci" managed="yes">
      <driver name="vfio"/>
      <source>
        <address domain="0x0000" bus="0x00" slot="0x02" function="0x0"/>
      </source>
      <alias name="ua-igpu"/>
      <rom file="/usr/share/kvm/igd.rom"/>
      <address type="pci" domain="0x0000" bus="0x00" slot="0x02" function="0x0"/>
    </hostdev>
  ...
  </devices>
...
</domain>
```

其中核显的 pci 地址可以通过以下命令查看：

```bash
lspci -k | grep -A3 -iE "vga|3d|display"
```

```txt
00:02.0 VGA compatible controller: Intel Corporation Raptor Lake-S UHD Graphics (rev 04)
        Subsystem: Lenovo Device 3b53
        Kernel driver in use: vfio-pci
        Kernel modules: i915, xe
--
01:00.0 VGA compatible controller: NVIDIA Corporation AD107M [GeForce RTX 4060 Max-Q / Mobile] (rev a1)
        Subsystem: Lenovo Device 3b53
        Kernel driver in use: nvidia
        Kernel modules: nouveau, nvidia_drm, nvidia
```

或者如果觉得麻烦，直接在 virt-manager 里添加 PCI 设备，然后手动修改 xml 也行。

可以看到，其中我们引用了一个 `/usr/share/kvm/igd.rom` 的设备，这是为了修复核显 PCI ROM 损坏/缺失的问题，我们需要在 #link("https://github.com/LongQT-sea/intel-igpu-passthru")[intel-igpu-passthru] 这个开源仓库中下载：

```bash
sudo curl -L https://github.com/LongQT-sea/intel-igpu-passthru/releases/download/v0.1/RKL_TGL_ADL_RPL_GOPv17.1_igd.rom -o /usr/share/kvm/igd.rom
```

接着，我们还需要给核显添加一系列兼容性配置，使得虚拟机内的核显驱动能够正常启动：

```xml
<domain xmlns:qemu="http://libvirt.org/schemas/domain/qemu/1.0" type="kvm">
...
  <devices>
  ...
  </devices>
  <qemu:override>
    <qemu:device alias="ua-igpu">
      <qemu:frontend>
        <qemu:property name="x-igd-opregion" type="bool" value="true"/>
        <qemu:property name="x-igd-lpc" type="bool" value="true"/>
      </qemu:frontend>
    </qemu:device>
  </qemu:override>
</domain>
```

最后，为了方便之后我们使用 Looking Glass 操作虚拟机，我们需要设置 spice 在 localhost 运行：

```xml
<domain xmlns:qemu="http://libvirt.org/schemas/domain/qemu/1.0" type="kvm">
...
  <devices>
  ...
    <graphics type="spice" port="5900" autoport="yes" listen="127.0.0.1">
      <listen type="address" address="127.0.0.1"/>
      <image compression="off"/>
      <gl enable="no"/>
    </graphics>
  ...
  </devices>
...
</domain>
```

并且设置一个共享内存区域用于抓取虚拟机的画面：

```xml
<domain xmlns:qemu="http://libvirt.org/schemas/domain/qemu/1.0" type="kvm">
...
  <devices>
  ...
    <shmem name='looking-glass'>
      <model type='ivshmem-plain'/>
      <size unit='M'>64</size>
    </shmem>
  ...
  </devices>
...
</domain>
```

=== igpu driver

接着，我们就可以启动虚拟机了，但是现在我们还没有安装核显驱动，因此，我们需要去官网上下载 #link("https://www.intel.cn/content/www/cn/zh/download/864990/intel-11th-14th-gen-processor-graphics-windows.html")[Intel 第 11-14 代 CPU 的核显驱动] 并安装，安装完后，重启虚拟机，打开设备管理器，查看显示适配器列表，应该能看到正常运行中的 Intel 核显驱动。

=== looking glass

最后，为了方便日常操作系统，而不是使用比较卡顿的软件渲染的 QXL，我使用 #link("https://looking-glass.io/")[Looking Glass] 来显示虚拟机的画面和控制虚拟机的输入，安装方式很简单，就是虚拟机内和宿主机内分别安装版本对应的 host 和 client。

然后配置一下虚拟机和宿主机使用的共享内存（记得修改用户名和组名）：

```conf
### /etc/tmpfiles.d/10-looking-glass.conf
f /dev/shm/looking-glass 0660 wuqingyu kvm -
```

立即应用：

```bash
sudo systemd-tmpfiles --create /etc/tmpfiles.d/10-looking-glass.conf
```

最后重启虚拟机使得 service 自动启动就可以正常使用了。此外，为了提升输出的图像质量，我给 client 添加了一个滤镜插件：

```ini
### ~/.looking-glass-client.ini
[egl]
preset=FSR
```

= 效果

至此，我们得以使用直通核显在 Linux 中流畅地使用 Windows 系统了！

#figure(
  caption: [使用直通核显运行在 kvm 中的 Windows 10 系统],
  image("/images/windows-kvm-with-igpu.jpg")
)

= 结语

我目前使用的 qemu 虚拟主板还是比较过时的 i440fx，主要是出于兼容性的考虑（因为我确实没有在 q35 平台跑起来），但是现在主流都是 q35，因为 q35 支持比 i440fx 更多的特性，比如 PCIe、IOMMU 和更多的 USB 端口等等，而且我在逛 github 和 reddit 的时候发现有些大佬已经能在 q35 上跑起来核显直通了，感觉还是之后还是可以多试试，也许就成了呢？但这都是后话了。
