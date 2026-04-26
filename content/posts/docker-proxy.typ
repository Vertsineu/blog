#import "@hugo/templates:0.1.0": article
#import "@hugo/utils:0.1.0": *

#show: article.with(
  title: "如何给 Docker 配置透明代理",
  date: datetime(year: 2026, month: 4, day: 17),
  tags: (
    platforms: ("linux", "docker", "iptables"),
    domains: "networking",
    intents: "enhancement",
  ),
  draft: false,
)

= 前言

通常，代理通常有两种方式，一种是开放端口，让需要代理的应用*主动*通过暴露的端口被代理访问远程服务；一种是使用 tun mode，即虚拟网卡模式，所有流量都会被虚拟网卡设备拦截从而*被动*代理访问远程服务。

对我来说，我并不希望在我的服务器上采取被动方式，因为它会对服务器上的所有应用产生影响，而且一旦代理软件崩溃退出，我将无法访问互联网，而且会影响比如 ping 等工具的执行（拦截 ICMP 数据包），这是极其不好的，因此平时在我的服务器上，我更倾向于使用主动方式，只有应用需要被代理才会主动去访问代理端口。

说是主动，也并不完全主动，无非就是设置环境变量：

```bash
export http_proxy=http://127.0.0.1:7890
export https_proxy=http://127.0.0.1:7890
```

但是，对于 Docker 来说，通过设置环境变量的方式来配置代理会非常麻烦，如果不使用 docker compose，每次运行 docker run 的时候都需要输入长长的一串环境变量；如果使用 docker compose，要修改的部分也非常多，如下所示：

```yaml
services:
  app:
    image: my-app
    environment:
      - HTTP_PROXY=http://host.docker.internal:7890
      - HTTPS_PROXY=http://host.docker.internal:7890
      - NO_PROXY=localhost,127.0.0.1
    extra_hosts:
      - "host.docker.internal:host-gateway" # only for linux
```

除此之外，使用主动代理还有其他弊端：

- 如果 docker compose 中有多个 service，你可能需要花费功夫判断哪些 service 需要代理，哪些不需要代理。
- 如果镜像中的应用不支持通过环境变量配置代理，那么以上配置就完全无效了。
- 最重要的，在 docker build 的过程中，Docker 会起一个临时容器来运行 dockerfile 中的命令，而在这个过程中，如果没有配置代理或镜像，那么一些基本的命令，比如 `apt update`、`apt install` 以及 `pip install` 等等，就会导致镜像构建缓慢，非常折磨人，而在 dockerfile 中配置代理也是一个非常麻烦的事情，很多时候都是发现 docker build 执行缓慢或者失败的时候才想到要配置代理，浪费大把时间。

因此，我的想法就是给 Docker 配置一个被动代理，准确来说，透明代理，从而让 Docker 中的应用完全不需要管代理的事情，所有流量都会被自动代理。

= 背景

在讲述实现前，我需要说明一下我的服务器上的一些基本情况：

- mihomo: 运行在 7890 端口，提供 http/https 代理服务，通过 systemd 管理
- docker: 大部分服务使用的是 bridge 网络模式，因此我只需要考虑给 bridge 模式下的容器配置透明代理
- iptables: legacy mode，不支持 nftables

= 实现

核心思路很简单，通过 iptables 将所有从 bridge 网段发出的流量重定向到 mihomo 的透明代理端口上，从而实现透明代理。

== mihomo

mihomo 这边需要设置 tproxy 的端口和 sniff 功能，需要添加的配置如下所示：

```yaml
tproxy-port: 7893
sniffer:
  enable: true
  sniff:
    HTTP:
      ports: [80]
    TLS:
      ports: [443]
    QUIC:
      ports: [443]
  override-destination: true
```

其中，`tproxy-port` 是 mihomo 监听透明代理流量的端口，而开启 sniffer 是因为不同于显式的 http/https 代理，在不开 sniffer 的情况下，透明代理无法判断当前流量是否是 https 流量，无法得知 SNI，从而在远端的代理和实际访问的服务器之间建立 tls 连接时代理无法发送正确的 SNI，导致代理和服务器之间的 tls 连接无法建立成功，从而无法通过 https 访问；而一旦开启了 sniffer，mihomo 能够从数据包中解析出 SNI，发送给远端的代理，让代理能够发送正确的 SNI，从而成功建立 tls 连接。

== iptables

iptables 需要标记所有来自 bridge 网段的流量，但是忽略所有去往本机/局域网地址的流量，而对于被标记的流量，我们需要对其单独配置路由表，从而防止内核在路由时转发到外部网卡，而是保留到本机处理，因此，iptables 的配置如下所示：

```bash
# /etc/mihomo-tproxy/setup.sh
#!/bin/bash
set -e

TABLE=100
MARK=1
CHAIN=MIHOMO_TPROXY
DOCKER_CIDR=172.16.0.0/12
TPROXY_PORT=7893

ip rule add fwmark $MARK table $TABLE priority 100 2>/dev/null || true
ip route add local default dev lo table $TABLE 2>/dev/null || true

iptables -t mangle -N $CHAIN 2>/dev/null || iptables -t mangle -F $CHAIN

iptables -t mangle -A $CHAIN -d 127.0.0.0/8    -j RETURN
iptables -t mangle -A $CHAIN -d 10.0.0.0/8     -j RETURN
iptables -t mangle -A $CHAIN -d 172.16.0.0/12  -j RETURN
iptables -t mangle -A $CHAIN -d 192.168.0.0/16 -j RETURN

iptables -t mangle -A $CHAIN -p tcp -j TPROXY \
  --on-ip 127.0.0.1 --on-port $TPROXY_PORT --tproxy-mark $MARK
iptables -t mangle -A $CHAIN -p udp -j TPROXY \
  --on-ip 127.0.0.1 --on-port $TPROXY_PORT --tproxy-mark $MARK

iptables -t mangle -A PREROUTING -s $DOCKER_CIDR -j $CHAIN
```

其中，TPROXY 目标会将所有需要被代理的流量关联到 mihomo 的透明代理端口上的那个 socket 上，但是它不能影响路由决策，因此我首先给这部分流量打了一个标记，然后通过 `ip rule` 和 `ip route` 来配置路由表，让被标记的流量转发到本机的 lo 网卡上，这样，lo 网卡收到流量后就会将其交给 mihomo 处理了。

为了保证可维护性，我还编写了一个脚本来删除这些 iptables 规则，以便在代理崩溃退出后能够及时清理规则，恢复网络：

```bash
# /etc/mihomo-tproxy/teardown.sh
#!/bin/bash

TABLE=100
MARK=1
CHAIN=MIHOMO_TPROXY
DOCKER_CIDR=172.16.0.0/12

iptables -t mangle -D PREROUTING -s $DOCKER_CIDR -j $CHAIN 2>/dev/null || true

iptables -t mangle -F $CHAIN 2>/dev/null || true
iptables -t mangle -X $CHAIN 2>/dev/null || true

ip rule del fwmark $MARK table $TABLE 2>/dev/null || true
ip route del local default dev lo table $TABLE 2>/dev/null || true
```

最后，我编写一个 `mihomo-tproxy.service` 来管理这个透明代理，并和 mihomo 的生命周期绑定在一起：

```ini
# /etc/systemd/system/mihomo-tproxy.service
[Unit]
Description=Mihomo transparent proxy iptables rules
After=network.target mihomo.service
BindsTo=mihomo.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/etc/mihomo-tproxy/setup.sh
ExecStop=/etc/mihomo-tproxy/teardown.sh

[Install]
WantedBy=multi-user.target
```

执行 `systemctl enable --now mihomo-tproxy` 启用服务后，透明代理就算是配置完成了。

= 测试

配置完成后，我使用 curl 进行了测试：

```bash
docker run --rm curlimages/curl curl -v https://www.google.com
```

输出：

```txt
  % Total    % Received % Xferd  Average Speed  Time    Time    Time   Current
                                 Dload  Upload  Total   Spent   Left   Speed
  0      0   0      0   0      0      0      0                              0* Host www.google.com:443 was resolved.
...
> GET / HTTP/2
> Host: www.google.com
> User-Agent: curl/8.19.0
> Accept: */*
> 
...
```

正常访问，并且 mihomo 的日志中也正确记录了这次访问，说明透明代理配置成功了。
