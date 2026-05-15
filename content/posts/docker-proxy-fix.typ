#import "@hugo/templates:0.1.0": article
#import "@hugo/utils:0.1.0": *

#show: article.with(
  title: "修复突然无效的 Docker 透明代理",
  date: datetime(year: 2026, month: 5, day: 15),
  tags: (
    platforms: ("linux", "docker", "iptables"),
    domains: "networking",
    intents: "troubleshooting",
  ),
  draft: false,
)

= 前言

昨天早上起来，本想着使用 codex 给我分析一下 Nginx 最新的 CVE 的原理，结果发现，我的中转站一直在超时，于是我检查了一下反代号，发现额度更新刷不出来了，心想，又一次，代理掉了，一般来说只是因为梯子不稳而已，并不少见。

于是我连上服务器测试一下，发现走 http(s)\_proxy 的代理都好好的，但是 Docker 里的 http(s) 请求却一直卡住，超时，才发现，我的 Docker 透明代理挂了。

= 排查

不管怎么说，重启总是能解决 99% 的问题，于是我重启了 mihomo 和 mihomo-tproxy：

```bash
sudo systemctl restart mihomo
sudo systemctl restart mihomo-tproxy
```

但是没有效果。尝试访问 www.google.com 还是卡住：

```bash
$ docker run --rm curlimages/curl curl -v https://chatgpt.com
  % Total    % Received % Xferd  Average Speed  Time    Time    Time   Current
                                 Dload  Upload  Total   Spent   Left   Speed
  0      0   0      0   0      0      0      0                              0* Host chatgpt.com:443 was resolved.
* IPv6: 2001::6ca0:a26d
* IPv4: 211.104.160.39
*   Trying [2001::6ca0:a26d]:443...
* Immediate connect fail for 2001::6ca0:a26d: Network unreachable
*   Trying 211.104.160.39:443...
  0      0   0      0   0      0      0      0           00:03              0
```

由于 iptables 相关的我也不是很熟，于是我就交给了 claude 和 gpt 来帮我排查一下，但是一排查不要紧，排查了一整天还走了点弯路才真正找到问题的根源。

== 调研现象

"没有调研就没有发言权"，在提出任何可能的猜想前，先进行一番细致的调研总是非常必要的。

首先是 iptables 的计数器：

```bash
$ sudo iptables -t mangle -L MIHOMO_TPROXY -n -v
Chain MIHOMO_TPROXY (1 references)
 pkts bytes target     prot opt in     out     source               destination         
    0     0 RETURN     all  --  *      *       0.0.0.0/0            127.0.0.0/8         
    0     0 RETURN     all  --  *      *       0.0.0.0/0            10.0.0.0/8          
 3680  225K RETURN     all  --  *      *       0.0.0.0/0            172.16.0.0/12       
   14   822 RETURN     all  --  *      *       0.0.0.0/0            192.168.0.0/16      
  528 57940 TPROXY     tcp  --  *      *       0.0.0.0/0            0.0.0.0/0            TPROXY redirect 127.0.0.1:7893 mark 0x1/0xffffffff
   82 11286 TPROXY     udp  --  *      *       0.0.0.0/0            0.0.0.0/0            TPROXY redirect 127.0.0.1:7893 mark 0x1/0xffffffff
```

其中，TPROXY 目标的计数器不为 0，说明数据包确实被 MIHOMO_TPROXY 这个链接收了。

但是，从 mihomo 的日志来看，我没有找到任何 www.google.com 的访问记录，说明这个数据包虽然被 iptables 重定向了，但是实际上并没有发送到 mihomo 中去。

接着，我使用 tcpdump 抓取 docker0 和 lo 设备上的数据包，看看数据包的流向：

```bash
$ sudo tcpdump -i docker0 -n -l 'host www.google.com or port 443'
tcpdump: verbose output suppressed, use -v[v]... for full protocol decode
listening on docker0, link-type EN10MB (Ethernet), snapshot length 262144 bytes
14:06:58.323997 IP 172.17.0.2.53358 > 142.250.196.196.443: Flags [S], seq 1974392700, win 64240, options [mss 1460,sackOK,TS val 3028826574 ecr 0,nop,wscale 10], length 0
14:06:59.341869 IP 172.17.0.2.53358 > 142.250.196.196.443: Flags [S], seq 1974392700, win 64240, options [mss 1460,sackOK,TS val 3028827592 ecr 0,nop,wscale 10], length 0
14:07:00.365815 IP 172.17.0.2.53358 > 142.250.196.196.443: Flags [S], seq 1974392700, win 64240, options [mss 1460,sackOK,TS val 3028828616 ecr 0,nop,wscale 10], length 0
14:07:01.389861 IP 172.17.0.2.53358 > 142.250.196.196.443: Flags [S], seq 1974392700, win 64240, options [mss 1460,sackOK,TS val 3028829640 ecr 0,nop,wscale 10], length 0
14:07:02.413833 IP 172.17.0.2.53358 > 142.250.196.196.443: Flags [S], seq 1974392700, win 64240, options [mss 1460,sackOK,TS val 3028830664 ecr 0,nop,wscale 10], length 0
...
```

可以看出，从 docker0 这个 bridge 网段对应的设备上，来自容器的 SYN 数据包确实发送出去了，但是一直没有 SYN ACK 数据包返回来，这解释了为什么请求一直卡住。

```bash
$ sudo tcpdump -i lo -n -l 'host www.google.com or port 443'
tcpdump: verbose output suppressed, use -v[v]... for full protocol decode
listening on lo, link-type EN10MB (Ethernet), snapshot length 262144 bytes
```

但是 lo 设备上却没有收到任何数据包，这就非常奇怪了，说明数据包虽然被 iptables 重定向了，但是并没有被路由到 lo 设备上来。

== 初次猜想

一开始，claude 和 gpt 都认为是 mihomo 创建的 socket 的问题，问题在于，在 mihomo 中使用 `tproxy-port` 设置透明代理端口的时候，这个代理端口对应的 tcp socket 不是创建在 IPv4 上的，而是创建在 IPv6 上的：

```bash
$ sudo netstat -tlnup | grep 7893
tcp6       0      0 :::7893                 :::*                    LISTEN      1040/mihomo
udp6       0      0 :::7893                 :::*                                1040/mihomo
```

这就导致 iptables 中的 TPROXY 目标无法正确将数据包重定向到 mihomo 的对应 socket 中，因为 `setup.sh` 里写的是 `127.0.0.1`，一个 IPv4 地址。

而查看 mihomo 的源代码，我们可以将 mihomo 创建 tproxy socket 的相关代码提取成以下示例：

```go
package main

import (
	"context"
	"net"
)

func main() {
	lc := net.ListenConfig{}
	addr := "0.0.0.0:7893"
	l, err := lc.Listen(context.Background(), "tcp", addr)
	if err != nil {
		panic(err)
	}

	<-make(chan int)
}
```

运行该程序，并使用 netstat 查看监听的 socket 种类：

```bash
$ sudo netstat -tlnup | grep 7893
tcp6       0      0 :::7893                 :::*                    LISTEN      869808/client   
```

可以发现，虽然我们制定了监听在 `0.0.0.0` 这个 IPv4 地址上，但是实际监听的 socket 却是一个 IPv6 的 socket！

从 go 的 net 包实现来看，决定最终所选择的 Address Family 的函数位于 #link("https://github.com/golang/go/blob/master/src/net/ipsock_posix.go#L140-L163")[ipsock_posix.go] 中的 `favoriteAddrFamily` 函数：

```go
func favoriteAddrFamily(network string, laddr, raddr sockaddr, mode string) (family int, ipv6only bool) {
	switch network[len(network)-1] {
	case '4':
		return syscall.AF_INET, false
	case '6':
		return syscall.AF_INET6, true
	}

	if mode == "listen" && (laddr == nil || laddr.isWildcard()) {
		if supportsIPv4map() || !supportsIPv4() {
			return syscall.AF_INET6, false
		}
		if laddr == nil {
			return syscall.AF_INET, false
		}
		return laddr.family(), false
	}

	if (laddr == nil || laddr.family() == syscall.AF_INET) &&
		(raddr == nil || raddr.family() == syscall.AF_INET) {
		return syscall.AF_INET, false
	}
	return syscall.AF_INET6, false
}
```

可以看到，在 listen 模式下，如果本地地址是一个 wildcard 地址（即 `0.0.0.0` 或者 `::`），并且系统支持 IPv4-mapped IPv6 地址或者不支持 IPv4，那么就会选择创建一个 IPv6 的 socket，即使指定的是 `0.0.0.0` 这么一个 IPv4 的地址。

== 质疑

到这里，我已经花了一个上午的时间，好像找到了问题的根源，而且还不好解决，因为修复可能还需要手动重编译 mihomo 的源代码，但实际上，这并非真正的问题所在。

一个合理的质疑是，如果真的是这个 socket 创建的问题，那么为什么之前还正常工作，但是昨天突然就不能工作了呢？以及，进行一个小测试：

```bash
$ nc -vzw 5 127.0.0.1 7893
Connection to 127.0.0.1 7893 port [tcp/*] succeeded!
```

虽然 socket 创建在 IPv6 上，但是我仍然能通过 nc 建立 tcp 连接，说明很大可能这并非真正的问题所在。

== 再次猜想

于是我不得不再次和 claude 和 gpt 重新进行一轮新的讨论，到处试各种可能的方向。

最开始，是通过修改一个名为 `net.ipv4.conf.all.accept_local` 的内核选项发现了可能的线索：

```bash
$ sudo sysctl net.ipv4.conf.all.accept_local=1
```

一旦我这样设置了这个选项，之前卡住的请求就能正常返回了：

```bash
$ docker run --rm curlimages/curl curl -v https://www.google.com
  % Total    % Received % Xferd  Average Speed  Time    Time    Time   Current
                                 Dload  Upload  Total   Spent   Left   Speed
  0      0   0      0   0      0      0      0                              0* Host www.google.com:443 was resolved.
* IPv6: (none)
* IPv4: 142.250.196.196
*   Trying 142.250.196.196:443...
* ALPN: curl offers h2,http/1.1
} [5 bytes data]
* TLSv1.3 (OUT), TLS handshake, Client hello (1):
} [1560 bytes data]
* SSL Trust Anchors:
*   CAfile: /cacert.pem
...
```

但是，这个选项并不能充分解释现象，它的含义是，当内核收到一个数据包时，如果这个数据包的源地址是本地地址，比如某个网卡上的 `172.17.0.1` 或者 `127.0.0.1` 之类的，当 `accept_local=0` 时，内核会丢弃这个数据包；当 `accept_local=1` 时，内核会接受这个数据包。默认这个选项设置为 0，也就是说，内核默认会丢弃源地址为本地地址的数据包。

显然，透明代理转发的包的源地址是容器的 IP 地址，比如 `172.17.0.2`，怎么会是本地地址呢？和这个选项有什么关系呢？

顺便提一嘴，你可能比较好奇，既然 `accept_local` 默认为 0，那如果我在本机执行一个 `curl localhost`，那源地址不就是本机地址吗？可我的包也没被丢啊？也能正常访问本机的 Nginx 啊？这就需要 dive into 内核的具体实现了。

解释这个困惑的代码位于内核的 `net/ipv4/ip_input.c` 文件中的 `ip_rcv_finish_core` 函数中：

```c
static int ip_rcv_finish_core(struct net *net,
			      struct sk_buff *skb, struct net_device *dev,
			      const struct sk_buff *hint)
{
	// ...
	// leave out for brevity
	// ...

	/*
	 *	Initialise the virtual path cache for the packet. It describes
	 *	how the packet travels inside Linux networking.
	 */
	if (!skb_valid_dst(skb)) {
		drop_reason = ip_route_input_noref(skb, iph->daddr, iph->saddr,
						   ip4h_dscp(iph), dev);
		if (unlikely(drop_reason))
			goto drop_error;
	} else {
		struct in_device *in_dev = __in_dev_get_rcu(dev);

		if (in_dev && IN_DEV_ORCONF(in_dev, NOPOLICY))
			IPCB(skb)->flags |= IPSKB_NOPOLICY;
	}

	// ...
	// leave out for brevity
	// ...
}
```

顾名思义，`ip_rcv_finish_core` 函数是在收到 IP 数据包结束时触发的，而其中 `ip_route_input_noref` 函数内部执行了 `accept_local` 选项的逻辑，因此只有当 `skb_valid_dst(skb)` 返回 false 的时候，才会启用 `accept_local` 的检查。

而 `skb_valid_dst` 函数检查的是这个数据包的目标路由是否已经被设置好了，其实现位于 `include/net/dst_metadata.h` 中：

```c
static inline bool skb_valid_dst(const struct sk_buff *skb)
{
	struct dst_entry *dst = skb_dst(skb);

	return dst && !(dst->flags & DST_METADATA);
}
```

其中 `skb_dst` 函数的实现位于 `include/linux/skbuff.h` 中：

```c
static inline struct dst_entry *skb_dst(const struct sk_buff *skb)
{
	/* If refdst was not refcounted, check we still are in a
	 * rcu_read_lock section
	 */
	WARN_ON((skb->_skb_refdst & SKB_DST_NOREF) &&
		!rcu_read_lock_held() &&
		!rcu_read_lock_bh_held());
	return (struct dst_entry *)(skb->_skb_refdst & SKB_DST_PTRMASK);
}
```

对于从本机发出由本机接收的数据包，内核会在发送前就提前设置好这个数据包的 `dst_entry`，因为是发给自己的，提前查表一定就能查到路由信息，具体实现在 `net/ipv4/ip_output.c` 中的 `__ip_queue_xmit` 函数中：

```c
int __ip_queue_xmit(struct sock *sk, struct sk_buff *skb, struct flowi *fl,
		    __u8 tos)
{
	// ...
	// leave out for brevity
	// ...

	/* Skip all of this if the packet is already routed,
	 * f.e. by something like SCTP.
	 */
	fl4 = &fl->u.ip4;
	rt = skb_rtable(skb);
	if (rt)
		goto packet_routed;

	/* Make sure we can route this packet. */
	rt = dst_rtable(__sk_dst_check(sk, 0));
	if (!rt) {
		inet_sk_init_flowi4(inet, fl4);

		/* sctp_v4_xmit() uses its own DSCP value */
		fl4->flowi4_dscp = inet_dsfield_to_dscp(tos);

		/* If this fails, retransmit mechanism of transport layer will
		 * keep trying until route appears or the connection times
		 * itself out.
		 */
		rt = ip_route_output_flow(net, fl4, sk);
		if (IS_ERR(rt))
			goto no_route;
		sk_setup_caps(sk, &rt->dst);
	}
	skb_dst_set_noref(skb, &rt->dst);

packet_routed:
	
	// ...
	// leave out for brevity
	// ...

no_route:
	
	// ...
	// leave out for brevity
	// ...
}
```

这个函数的作用是将上层的数据包，比如 tcp 或 udp 数据包封装成一个 IP 数据包，而在封装之前，这个函数会使用 `dst_rtable` 函数先从路由表中预先查找目标地址的路由信息，然后通过 `skb_dst_set_noref` 函数设置数据包的目标路由。

`skb_dst_set_noref` 函数的实现位于 `include/linux/skbuff.h` 中：

```c
static inline void skb_dst_set_noref(struct sk_buff *skb, struct dst_entry *dst)
{
	skb_dst_check_unset(skb);
	WARN_ON(!rcu_read_lock_held() && !rcu_read_lock_bh_held());
	skb->slow_gro |= !!dst;
	skb->_skb_refdst = (unsigned long)dst | SKB_DST_NOREF;
}
```

而对于从其他机器发送到本机的数据包，内核就无法提前找到路由，就必须执行 `ip_route_input_noref` 函数来找到目标路由，从而受到 `accept_local` 选项的约束。

回到透明代理的问题，由于容器发送的数据包的目标地址本来就不是本机地址，而是 www.google.com 域名对应的地址，因此内核在构造 IP 数据包的时候无法预先查找到目标地址的路由信息，必须在收到 IP 数据包时调用 `ip_route_input_noref` 函数才能知道目标路由，这就会和 `accept_local` 选项有所关联了。

但是，按照 `accept_local` 的原意，容器发送的数据包的源地址不应该算是本地地址，而是其内部 bridge 子网的子网地址，为什么也会被 `accept_local` 选项所拦截呢？这就需要 dive into `accept_local` 这个选项的实现了。

实现 `accept_local` 选项的是位于 `net/ipv4/fib_frontend.c` 里的 `__fib_validate_source` 函数：

```c
static int __fib_validate_source(struct sk_buff *skb, __be32 src, __be32 dst,
				 dscp_t dscp, int oif, struct net_device *dev,
				 int rpf, struct in_device *idev, u32 *itag)
{
	// ...
	// leave out for brevity
	// ...

	if (fib_lookup(net, &fl4, &res, 0))
		goto last_resort;
	if (res.type != RTN_UNICAST) {
		if (res.type != RTN_LOCAL) {
			reason = SKB_DROP_REASON_IP_INVALID_SOURCE;
			goto e_inval;
		} else if (!IN_DEV_ACCEPT_LOCAL(idev)) {
			reason = SKB_DROP_REASON_IP_LOCAL_SOURCE;
			goto e_inval;
		}
	}

	// ...
	// leave out for brevity
	// ...

last_resort:
	if (rpf)
		goto e_rpf;
	*itag = 0;
	return 0;

e_inval:
	return -reason;
e_rpf:
	return -SKB_DROP_REASON_IP_RPFILTER;
}
```

这个函数首先调用 `fib_lookup` 查找内核的路由表，然后如果 `res.type == RTN_LOCAL`，就会走 `IN_DEV_ACCEPT_LOCAL` 宏函数查询 `accept_local` 选项，如果 `accept_local=0`，则以 `SKB_DROP_REASON_IP_LOCAL_SOURCE` 理由丢弃数据包。

因此，一个地址是否是本地地址，实际上取决于查询路由表时是否能查到该 IP 的类型是 `RTN_LOCAL`，这时回看之前设置透明代理的脚本：

```bash
### /etc/mihomo-tproxy/setup.sh
#!/bin/bash
set -e

TABLE=100
MARK=1
CHAIN=MIHOMO_TPROXY
DOCKER_CIDR=172.16.0.0/12
TPROXY_PORT=7893

ip rule add fwmark $MARK table $TABLE priority 100 2>/dev/null || true
ip route add local default dev lo table $TABLE 2>/dev/null || true

# ...
# leave out for brevity
# ...
```

其中 `ip route add local default dev lo table $TABLE` 命令正是设置了所有匹配这条路由表表项的 IP 都属于 `RTN_LOCAL` 类型，比如假设容器的 IP 是 `172.17.0.233`，通过透明代理后，查询路由表的结果如下所示：

```bash
$ ip route get 172.17.0.233 mark 0x1
local 172.17.0.233 dev lo table 100 src 172.17.0.233 mark 1 uid 1000 
    cache <local> 
```

这下我们终于能够理解为什么 `accept_local` 选项会对透明代理的包产生干扰了，正是因为透明代理的包在反查路由表的时候被标记为 `RTN_LOCAL` 类型。

但是，我还是不理解为什么之前还好好了，昨天突然就不能用了，而且 `accept_local` 选项默认就是 0，之前为什么我不需要手动开启。

因此，再次和 gpt 进行沟通后，我发现实际上是一个名为 `net.ipv4.conf.all.src_valid_mark` 选项的问题。这个选项的含义是是否在查询路由表的时候将该数据包的 mark 也放进去查询。

比如容器的 IP 是 `172.17.0.233`，在 `src_valid_mark=1` 的时候，实际查询等价于：

```bash
$ ip route get 172.17.0.233 mark 0x1
local 172.17.0.233 dev lo table 100 src 172.17.0.233 mark 1 uid 1000 
    cache <local> 
```

而在 `src_valid_mark=0` 的时候，实际查询等价于：

```bash
$ ip route get 172.17.0.233
172.17.0.233 dev docker0 src 172.17.0.1 uid 1000 
    cache
```

这个选项默认值是 0，也就是说，是下面一种情况。而在这种情况下，路由表查询结果里没有带 `local`，因此不是 `RTN_LOCAL` 类型的，从而不会因为 `accept_local` 丢包。

但是好巧不巧，现在在我的系统里，这个选项现在的值是 1：

```bash
$ sudo sysctl net.ipv4.conf.all.src_valid_mark
net.ipv4.conf.all.src_valid_mark = 1
```

这就导致了路由表查询结果认为这个容器 IP 是 `RTN_LOCAL` 类型的，从而因为 `accept_local` 丢包。

现在我很有理由怀疑了，很有可能是前天到昨天，我做了一件事情，不小心把这个内核选项打开了，但是谁会没事动内核选项呢？大概率也只有包管理器更新了什么新的 package 导致的吧。于是打开 dpkg 的日志，找到那两天所做的所有安装/更新操作：

```bash
$ grep -E "upgrade|install" /var/log/dpkg.log
...
2026-05-13 09:36:31 upgrade exim4-config:all 4.98.2-1 4.98.2-1+deb13u2
2026-05-13 09:36:31 status half-installed exim4-config:all 4.98.2-1
2026-05-13 09:36:31 upgrade exim4-base:amd64 4.98.2-1 4.98.2-1+deb13u2
2026-05-13 09:36:31 status half-installed exim4-base:amd64 4.98.2-1
2026-05-13 09:36:31 upgrade exim4-daemon-light:amd64 4.98.2-1 4.98.2-1+deb13u2
2026-05-13 09:36:31 status half-installed exim4-daemon-light:amd64 4.98.2-1
2026-05-13 09:36:32 status installed exim4-config:all 4.98.2-1+deb13u2
2026-05-13 09:36:34 status installed exim4-base:amd64 4.98.2-1+deb13u2
2026-05-13 09:36:35 status installed exim4-daemon-light:amd64 4.98.2-1+deb13u2
2026-05-13 09:36:36 status installed man-db:amd64 2.13.1-1
2026-05-14 11:12:28 upgrade docker-buildx-plugin:amd64 0.33.0-1~debian.13~trixie 0.34.0-1~debian.13~trixie
2026-05-14 11:12:28 status half-installed docker-buildx-plugin:amd64 0.33.0-1~debian.13~trixie
2026-05-14 11:12:29 upgrade tailscale:amd64 1.96.4 1.98.1
2026-05-14 11:12:29 status half-installed tailscale:amd64 1.96.4
2026-05-14 11:12:30 status installed docker-buildx-plugin:amd64 0.34.0-1~debian.13~trixie
2026-05-14 11:12:32 status installed tailscale:amd64 1.98.1
2026-05-14 14:54:58 upgrade mihomo:amd64 1.19.18 1.19.24
2026-05-14 14:54:58 status half-installed mihomo:amd64 1.19.18
2026-05-14 14:54:59 status installed mihomo:amd64 1.19.24
2026-05-14 21:22:54 upgrade libnghttp2-14:amd64 1.64.0-1.1 1.64.0-1.1+deb13u1
2026-05-14 21:22:54 status half-installed libnghttp2-14:amd64 1.64.0-1.1
2026-05-14 21:22:54 status installed libnghttp2-14:amd64 1.64.0-1.1+deb13u1
2026-05-14 21:22:54 status installed libc-bin:amd64 2.41-12+deb13u2
...
```

不难想到，最值得怀疑的当然是 tailscale 的更新了，而 gpt 也是很给力，直接给我从它的二进制和日志里找到了关键性证据：

```bash
$ strings /usr/sbin/tailscaled | grep -oP '.{20}src_valid_mark.{20}'          
%vnet.ipv4.conf.all.src_valid_markno Taildrop director
g: failed to enable src_valid_mark: %vfixupWSLMTU: cou
```

```bash
$ sudo journalctl -b -u tailscaled.service --no-pager
...
May 15 06:00:32 debian-server tailscaled[1055]: router: enabling connmark-based rp_filter workaround
...
```

根据内核文档 #link("https://docs.kernel.org/networking/ip-sysctl.html")[IP Sysctl] 中所述：

```txt
src_valid_mark - BOOLEAN
	- 0 - The fwmark of the packet is not included in reverse path
	  route lookup.  This allows for asymmetric routing configurations
	  utilizing the fwmark in only one direction, e.g., transparent
	  proxying.

	- 1 - The fwmark of the packet is included in reverse path route
	  lookup.  This permits rp_filter to function when the fwmark is
	  used for routing traffic in both directions.

	This setting also affects the utilization of fmwark when
	performing source address selection for ICMP replies, or
	determining addresses stored for the IPOPT_TS_TSANDADDR and
	IPOPT_RR IP options.

	The max value from conf/{all,interface}/src_valid_mark is used.

	Default value is 0.
```

启用 rp_filter 的前提正是 `src_valid_mark` 需要设置为 1，而 tailscale 启用了 rp_filter，并从其二进制文件里能搜索到这个选项的字符串。

因此不难推测出，造成透明代理突然失效的根本原因正是 tailscale 更新后添加了对 `src_valid_mark` 选项的需求，并设置了该选项为 1，从而导致被透明代理的包被认为是本地发送的包，进而因为 `accept_local=0` 被丢弃，最终导致连接卡住。

= 解决

虽然我们排查了很久很深才找到真正的原因，但是实际上修复这个问题反而很简单。

既然现在内核根据容器 IP + fwmark 查路由表会误认为是本地地址，那我只要修改路由表规则，让这个查询结果不包含 `local` 就行了。

具体来说，就是在 `setup.sh` 脚本中添加一行：

```diff
diff --git a/setup.sh b/etc/mihomo-tproxy/setup.sh
index 273ea40..4ddc4aa 100755
--- a/setup.sh
+++ b/etc/mihomo-tproxy/setup.sh
@@ -8,6 +8,7 @@ DOCKER_CIDR=172.16.0.0/12
 TPROXY_PORT=7893
 
 ip rule add fwmark $MARK table $TABLE priority 100 2>/dev/null || true
+ip route add throw $DOCKER_CIDR table $TABLE 2>/dev/null || true
 ip route add local default dev lo table $TABLE 2>/dev/null || true
 
 iptables -t mangle -N $CHAIN 2>/dev/null || iptables -t mangle -F $CHAIN
```

而在 `teardown.sh` 脚本中添加一行：

```diff
diff --git a/./teardown.sh b/etc/mihomo-tproxy/teardown.sh
index b4b71cb..6503195 100755
--- a/./teardown.sh
+++ b/etc/mihomo-tproxy/teardown.sh
@@ -12,3 +12,4 @@ iptables -t mangle -X $CHAIN 2>/dev/null || true
 
 ip rule del fwmark $MARK table $TABLE 2>/dev/null || true
 ip route del local default dev lo table $TABLE 2>/dev/null || true
+ip route del throw $DOCKER_CIDR table $TABLE 2>/dev/null || true
```

新加上的路由表表项的意图很显然，既然任何容器 IP + fwmark 最终都会在自定义的 table 100 中根据 default 表项被认为是本地地址，那么我只要在 table 100 中添加一个 throw 表项，让所有容器 IP 跳过 table 100 中 default 表项的匹配就行了。

而根据路由表优先级：

```bash
$ ip rule list           
0:      from all lookup local
100:    from all fwmark 0x1 lookup 100
5210:   from all fwmark 0x80000/0xff0000 lookup main
5230:   from all fwmark 0x80000/0xff0000 lookup default
5250:   from all fwmark 0x80000/0xff0000 unreachable
5270:   from all lookup 52
32766:  from all lookup main
32767:  from all lookup default
```

最终，路由表查询会 fallback 到 table 32766，即 main 表：

```bash
$ ip route show table main
default via 192.168.31.1 dev enp1s0 onlink 
169.254.0.0/16 dev enp1s0 scope link metric 1000 
172.17.0.0/16 dev docker0 proto kernel scope link src 172.17.0.1 linkdown 
172.18.0.0/16 dev br-a9b03e92b738 proto kernel scope link src 172.18.0.1 
172.23.0.0/16 dev br-c038990f4cfd proto kernel scope link src 172.23.0.1 
172.26.0.0/16 dev br-f1d772cc8627 proto kernel scope link src 172.26.0.1 
172.27.0.0/16 dev br-c99aaddc755c proto kernel scope link src 172.27.0.1 
172.28.0.0/16 dev br-fcd599ed7f10 proto kernel scope link src 172.28.0.1 
192.168.31.0/24 dev enp1s0 proto kernel scope link src 192.168.31.120 
```

匹配到其中的 docker0 或者其他 br 网段，而这些表项不带有 `local` 选项，因此被透明转发的包自然就不会因 `accept_local=0` 而丢包了。

p.s. 已在原文中修复了这个问题。

= 结语

在开始排查问题之前，我是真没想到这么一个小问题所牵扯的东西竟然这么深入，不愧是 Linux 子系统中最复杂最麻烦的一座大山！

不过也多亏了这个小问题，我也得以一窥 Linux 网络子系统的错综复杂#strike[并深刻理解了不要随意更新系统软件包——能动就不要跑——的至理名言]。
