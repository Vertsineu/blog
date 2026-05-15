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

但是随着服务数量的增多和额外需求的增加，我同时也重构了我现在的在校服务器搭建和配置方案，因此在此分享一下我的方案，提供一种可行的思路。

= 背景

在正式讲述我的搭建方案前，我需要声明一下我所拥有的资源情况：

- 一台位于宿舍由主机改造而来的小型服务器
  - 特点：4 核心、8g ddr4 内存、512g 固态硬盘、千兆网卡
  - 限制：宿舍晚上 23:30 熄灯，直到早上 6:00 才上电自动开机，因此无法熬夜使用
- 一台校内 Vlab 平台提供的 kvm 虚拟机
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

首先我采用 Tailscale 将三台机器连接在一起，形成一个虚拟局域网，这样三台机器就可以畅通无阻地相互访问了。

然后，我在香港的 VPS 上部署了 Nginx，将 80 和 443 端口反代到校内的两台机器上。

核心的配置如下所示：

```nginx
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
```

其中，我没有使用 http 反代，而是使用 stream 模块进行端口转发，这样在面对比如 websocket 这种协议时就不需要额外的配置了，直接交给后端的服务来处理就好了。
同时，我采用 SNI 来区分不同的服务，默认服务都是走宿舍的服务器，只有特定域名的服务才会转发到 Vlab 上，这样就实现了分流机制。

最后，在宿舍和 Vlab 上的 Nginx 中，我采用一个固定的模板将 Docker 容器中的服务反代出来：

```nginx
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

这样每次部署一个新的服务时，我只需要在 Docker 中启动服务，并且将端口映射到宿舍或者 Vlab 上的某个固定端口，然后在 Nginx 中添加一个 server 配置，指向这个端口就好了，非常方便。

其中，关于 ssl 的配置，我使用 #link("https://acme.sh")[acme.sh] 来自动申请和更新证书，并将证书和私钥放在 `/etc/ssl/certs` 和 `/etc/ssl/private` 目录下，然后在 Nginx 的配置中通过固定的 snippets 来引入证书和相关的参数，这样就实现了自动化的证书管理。

= 后记

在配置整个服务之前，我还没认识到有 Cloudflare Tunnel 这个东西，后来从其他同学那里了解到后，发现它也能提供端口转发和反代的功能，甚至有自动证书管理等更为方便的功能，而且免费额度也完全够用，但是现在我已经搭建这么一套系统了，迁移成本有点高，所以就先不考虑了，等以后有机会再试试吧。

p.s. #strike[Cloudflare 真是互联网活菩萨，除了 Tunnel 还有 OSS，Database，Pages 等各种有足够免费额度的服务，之后有机会可以试试看。]
