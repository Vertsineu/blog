#import "@hugo/templates:0.1.0": article

#show: article.with(
  title: "校内个人服务器搭建和配置方案",
  date: datetime(year: 2026, month: 5, day: 11),
  tags: (
    platforms: ("linux", "nginx", "tailscale"),
    domains: "networking",
    intents: "introduction",
  ),
  draft: false,
)

= 前言

最近一直在搞各种大模型 API 中转服务，为了能用上低价甚至免费的 API，我真是煞费苦心，尝试了各种方案：

- 自搭建 GLM-5.1-w8a8 模型，使用 vllm + litellm 提供 API 接入服务
- 购买便宜的 Deepseek v4 pro 的 API
- 在各种二道贩子、小众平台上购买 GPT 号、搭建 GPT 号池并最终反代出 Codex API
- 参与学校的 token plan，拿到免费的 Deepseek v4 pro 和 qwen3.6 的 API
- 接入 Nvidia 自部署并且可以免费使用的各种模型的 API
- #strike[从熟悉的同学那里求来用不完或者免费的 API 额度]

但是随着服务数量的增多和额外需求的增加，我同时也重构了我现在的在校服务器搭建和配置方案，因此在此分享一下我的方案，提供一种可行的思路。同时，也刚好趁这个机会分享一下我搭建服务器和部署服务中遇到的各种细节上的考量。

= 背景

在正式讲述我的搭建方案前，我需要声明一下我所拥有的资源情况：

- 一台位于宿舍由主机改造而来的小型服务器
  - 系统：Debian 13 Trixie
  - 特点：4 核心、8g ddr4 内存、512g 固态硬盘、千兆网卡
  - 限制：宿舍晚上 23:30 熄灯，直到早上 6:00 才上电自动开机，因此无法熬夜使用
- 一台校内 Vlab 平台提供的 kvm 虚拟机
  - 系统：Ubuntu 24.04.4 LTS
  - 特点：2 核心、6g 内存、16g 机械硬盘、千兆网卡
  - 限制：性能一般，尤其是磁盘随机读写性能较差，只能跑一些简单的服务，而且伴有由于维护带来的强制重启和停机的风险
- 一台位于香港的轻量级 VPS
  - 特点：1 核心、512m 内存、5g 固态硬盘、延迟 60ms 左右、千兆网卡
  - 限制：性能较差，尤其是内存和磁盘空间非常有限，只能跑一些基本的代理和反代服务

我的服务有很多种类，首先所有服务都是基于 http 协议的，其次有部分服务是可以忍受晚上断电的，但是有部分服务由于是不仅给我自己使用的，还分享给了其他同学使用，因此需要尽可能保证 24 小时在线。

= 架构

基于上述资源和需求，我设计了如下的架构：

- 宿舍小型服务器：主要用于部署一些重量级和偏私人向的服务，这类服务要么需要较好的性能，要么就不是很需要在我凌晨使用的，因此可以接受晚上断电的限制
- 校内 Vlab 虚拟机：主要用于部署一些轻量级的服务和共享服务，这类服务虽然性能要求不高，但需要尽可能保证 24 小时在线，因此适合部署在 Vlab 上
- 香港 VPS：主要用于将服务暴露到公网，做一个轻量级的反代，不部署任何服务。

= 实现

== 互联

首先，为了实现地理位置和所属网络层次不同的机器之间能够相互畅通连接，我采用 tailscale 建立一个虚拟局域网，好处在于 tailscale 易于安装，能够自动打洞，自动分配 IP，在保持尽可能不通过中转的情况实现互联，完全没有理由不使用。

== 反代

至于服务暴露和反向代理，当之无愧采用的是互联网基石开源项目 —— nginx 来实现，#strike[不需要理由，因为 nginx 就是神！]

首先，我在香港 VPS 的 nginx 中将 http/https 的 80/443 端口反代到校内的两台机器上，核心的配置如下所示：

```conf
### /etc/nginx/nginx.conf
# ...
stream {
    map $ssl_preread_server_name $backend_443 {
        aaa.vertsineu.top  100.xxx.xxx.xxx:443;
        bbb.vertsineu.top  100.xxx.xxx.xxx:443;
        default            100.yyy.yyy.yyy:443;
    }

    server {
        listen 80;
        listen [::]:80;
        proxy_pass 100.xxx.xxx.xxx:80;
    }

    server {
        listen 443;
        listen [::]:443;
        proxy_pass $backend_443;
        ssl_preread on;
    }
}
# ...
```

其中，我没有使用 http 反代，而是使用 stream 模块进行端口转发，这样在面对比如 websocket 这种协议时就不需要额外的配置了，直接交给后端的服务来处理就好了。
同时，我采用 SNI 来区分不同的服务，默认服务都是走宿舍的服务器，只有特定域名的服务才会转发到 Vlab 上，这样就实现了分流机制。

接着，在宿舍服务器和 Vlab 上的 nginx 中，我采用一个固定的模板将 http/https 服务反代出来，并自动套用 ssl/tls：

```conf
### /etc/nginx/sites-available/template.conf
server {
    listen 443 ssl;
    listen [::]:443 ssl;
    server_name ccc.vertsineu.top;

    http2 on;

    include snippets/ssl-certificates.conf;
    include snippets/ssl-params.conf;

    location / {
        proxy_pass http://127.0.0.1:12345;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    proxy_connect_timeout 60s;
    proxy_send_timeout    60s;
    proxy_read_timeout    60s;

    client_body_temp_path   /tmp;
    client_max_body_size    20G;
}
```

这样每次部署一个新的服务时，我只需要将端口映射到宿舍服务器或者 Vlab 上的某个端口，然后在 nginx 中按模板添加一个新配置，修改 `server_name` 并将 `proxy_pass` 指向这个端口就好了，非常方便。

其中，关于 ssl 的配置，我使用 #link("https://acme.sh")[acme.sh] 来自动申请和更新证书（签发通配符证书，这样所有子域名就不需要再签发单独的证书了）：

```bash
acme.sh --issue -d vertsineu.top -d "*.vertsineu.top" --dns dns_cf
```

并将证书和私钥安装 `/etc/ssl/certs` 和 `/etc/ssl/private` 目录下：

```bash
acme.sh --install-cert -d vertsineu.top \ 
  --key-file /etc/ssl/private/vertsineu.top.key \ 
  --fullchain-file /etc/ssl/certs/vertsineu.top.crt \ 
  --reloadcmd "systemctl restart nginx"
```

然后在 nginx 的配置中通过固定的 snippets 来引入证书和相关的参数，这样就实现了自动化的证书管理：

```conf
### /etc/nginx/snippets/ssl-certificates.conf
ssl_certificate /etc/ssl/certs/vertsineu.top.crt;
ssl_certificate_key /etc/ssl/private/vertsineu.top.key;
```

```conf
### /etc/nginx/snippets/ssl-params.conf
ssl_protocols TLSv1.2 TLSv1.3;
ssl_prefer_server_ciphers on;
ssl_dhparam /etc/nginx/dhparam.pem;
# ssl_ciphers EECDH+AESGCM:EDH+AESGCM;
# ssl_ecdh_curve secp384r1;
ssl_ciphers 'ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384';
ssl_ecdh_curve X25519:secp384r1;
ssl_session_timeout  10m;
ssl_session_cache shared:SSL:10m;
ssl_session_tickets off;
# ssl_stapling on;
# ssl_stapling_verify on;
# resolver 8.8.8.8 8.8.4.4 valid=300s;
# resolver_timeout 5s;
# Disable strict transport security for now. You can uncomment the following
# line if you understand the implications.
#add_header Strict-Transport-Security "max-age=63072000; includeSubDomains; preload";
add_header X-Frame-Options DENY;
add_header X-Content-Type-Options nosniff;
add_header X-XSS-Protection "1; mode=block";
```

= 管理

== 服务

为了实现服务的可复现性和易管理性，通常我会将我的服务配置成 systemd service 或 docker compose。其中，systemd service 主要面向于比较基础层面的服务，比如 nginx、mihomo、cron 等等；而 docker compose 主要面向于应用层面，通常比较重型且需要多容器相互配置来实现的服务，比如 memos、forgejo 等等，同时也易于更新迭代。

通常，systemd service 实现的服务都是手动管理的，而 docker compose 文件则会使用 git 管理并上传到自建 git 仓库里。可能之后确实得想个好办法能够更方便地管理 systemd service？

== 备份

对于某些比较重要的需要持久化的服务，我会把这些服务定时加密备份到我校的云盘上，使用 rclone + webdav，示例脚本如下所示：

```bash
### /usr/local/bin/backup.sh
#!/bin/bash
set -e

DIRS=(
    "/path/to/your/service/storage"
)

REMOTE="ustc-crypt:"

LOG="/var/log/backup.log"

for LOCAL_DIR in "${DIRS[@]}"; do
    BASENAME=$(basename "$LOCAL_DIR")
    echo "==> Syncing $LOCAL_DIR to $REMOTE/$BASENAME" | tee -a "$LOG"

    /usr/bin/rclone sync "$LOCAL_DIR" "$REMOTE/$BASENAME" \
        --transfers=4 \
        --checkers=8 \
        --log-file="$LOG" \
        --log-level=INFO
done
```

== 隐私性

对于某些会涉及个人隐私的持久化数据，通常我不会上传到 github 上，即使是 private repo，而是采用#link("https://git.vertsineu.top")[本地自建 git 服务]，当然肯定还是 private repo，里面也会放一些我的日常配置以及实验代码，尽量保持 github 上 repo 的整洁性。

比如，我的 zsh 和 vim 配置可以分别通过以下命令一键安装好，同时我也对插件仓库做了镜像和代理，保证在国内服务器上无需代理也能正常配置：

```bash
sh -c "$(curl -fsSL https://git.vertsineu.top/vertsineu/zsh-config/raw/branch/main/install.sh)"
```

```bash
sh -c "$(curl -fsSL https://git.vertsineu.top/vertsineu/vim-config/raw/branch/main/install.sh)"
```

== 可断电配置

由于宿舍内服务器通常是有线连接 + DHCP 的方式，如果宿舍服务器直连网口，那么每天断电重启后，服务器的 IP 会有变动，比较麻烦。虽然对于 tailscale 来说可能这一层可能不用管，但是对于校内直连和 ssh 直连来说，我倒是不希望必须得套一层 tailscale 才能连服务器。

因此，我现在采用的方案是自制 UPS + 路由器 + DDNS。

对于服务器来说，UPS 所需要的容量和功率还是太大，宿舍里肯定放不下；但是对于路由器来说，十几个小型锂电池（比如 18650）串并联再加上一块小型变压稳压器完全够用了，这样就能保证路由器能够长时间占用网口，锁住 IP。

但是，偶尔还是有时候，校园网出现网络故障，导致 DHCP 重新分配，以至于 IP 产生变动，这时候就需要 DDNS 做兜底了。我采用的是 cloudflare 托管的域名，相应脚本位于 #link("/scripts/cloudflare-ddns-ipv4.sh")[cloudflare-ddns-ipv4.sh] 和 #link("/scripts/cloudflare-ddns-ipv6.sh")[cloudflare-ddns-ipv6.sh]（脚本内容太长就不贴在文章里了）。这两个脚本作为 cron 定时服务配置在路由器中，保证 DNS 的及时更新。

= 后记

在配置服务暴露之前，我还没认识到有 Cloudflare Tunnel 这个东西，后来从其他同学那里了解到后，发现它也能提供端口转发和反代的功能，甚至有自动证书管理等更为方便的功能，而且免费额度也完全够用，但是现在我已经搭建这么一套系统了，迁移成本有点高，所以就先不考虑了，等以后有机会再试试吧。

p.s. #strike[Cloudflare 真是互联网活菩萨，除了 Tunnel 还有 OSS，Database，Pages 等各种有足够免费额度的服务，之后有机会可以试试看。]
