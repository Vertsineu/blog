#import "@hugo/templates:0.1.0": article
#import "@hugo/utils:0.1.0": *

#show: article.with(
  title: "记一次在 Linux 中根据端口号查找进程的经历",
  date: datetime.today(),
  draft: false,
)

= 前言

不久之前，我接手了一套服务器集群，这个集群由一个登录节点和多个计算节点组成，其中登录节点可以通过外网访问，而计算节点只能通过登录节点跳板访问。

拿到手，我最先做的便是探查一下这个集群的网络架构，而在我排查过程中，我发现登录节点 80 端口上开了一个 HTTP 访问，是用于计算节点资源管理的后台管理平台，不足为奇。

但是我有点好奇，想看一下这个 80 端口运行的那个服务是哪个进程管理的，顺便也能看一下这个管理平台是如何搭建起来的。

然后，按照运维的惯例，执行以下几个命令来查找对应进程：

```bash
lsof -i :80
netstat -tlnup | grep :80
ss -tlnup | grep :80
```

并不奇怪，输出结果显示：

```bash
$ netstat -tlnup | grep :80
tcp        0      0 0.0.0.0:80              0.0.0.0:*               LISTEN      3202/nginx: master
```

即，80 端口是一个 nginx 进程在提供服务，但是我们知道，管理平台不是静态网页，nginx 大概率是一个反向代理的作用。

因此，我打开了 `/etc/nginx/nginx.conf` 查看一下 80 端口具体代理了哪里的网络服务（省略无关配置）：

```conf
stream {
  server {
    listen 80;
    proxy_pass 172.20.2.31:80;
  }
}
```

看样子代理了 172.20.2.31 这个计算节点上 80 端口的服务。

接着，我 ssh 连接上了这个节点，同样使用惯例的指令查询 80 端口上的服务，但是这一次，奇怪的事情出现了，终端里什么输出都没有，也就是说，"没有"任何进程在 80 端口上服务？

我一下子就懵了，因为我完全不能理解为什么这些常用的排查命令都失效了！即使我不用 `grep`，反复 check 了 `lsof` `netstat` 和 `ss` 的输出，结果依旧是找不到任何占用 80 端口的进程！

= 排查

== 询问 AI

在 AI 时代，大部分人遇到不理解的事情最先想到的肯定是 AI 了。我问的是 ChatGPT，以下是按 AI 排的概率高低的假说：

+ network namespace
  - 虽然这个是 AI 排的最有可能的情况，但事后我想了一下，这反而是最不可能的情况了。首先，如果这个服务器用 network namespace 的话，那么大概率这个服务器用的是 Docker、Podman、K8S 之类的容器方案，但是这样的话，用 `ss` 和 `netstat` 完全可以找到对应进程，比如使用 Docker 的话，会有 `docker-proxy` 进程在实现 bridge 网络模式下端口转发，而其他网络情况通常并不常见（至少 bridge 和 host 网络模式是非常常用的方案），而如果是小概率的自己设置 namespace，那我请问了，有什么必要？实际上，这个假说在我这边的情况下也不成立。
+ systemd socket activation
  - 依旧随便想想就不可能，systemd socket activation 机制是只有第一个请求到来的时候才会激活一个 socket，然后之后一直保持 socket 有效。但是我之前已经不止一次访问过 80 端口上的服务了，不论是浏览器去看 80 端口是什么服务，还是 curl 测试 80 端口连通性，要激活早激活了，怎么可能是 lazy load 的问题？
+ iptables/nftables (firewall)
  - 最不可能的反而是最可能的，这就是 AI！但是当时我对 kernel firewall 了解不多，实在不好确定是否这是一个可行的假说，还是一个从内行人看来一眼就知道原理上不可能的假说？尤其是在 AI 已经提出了两个显然不可能的假说的前提下。

== 求助大佬

指望 AI 是不可靠了，只能指望懂这方面的大佬了，于是我在我校的 Linux User Group 群里复述了我的问题。果然大佬还是大佬，在看完 `netstat` 的输出后直截了当地就来考虑 iptables 的问题了。

首先是运行 `ipvsdm` 查看是否有 IPVS 参与负载均衡：

```bash
$ ipvsadm
IP Virtual Server version 1.2.1 (size=4096)
Prot LocalAddress:Port Scheduler Flags
  -> RemoteAddress:Port           Forward Weight ActiveConn InActConn
```

只有默认配置，排除。

然后查看服务器使用的是 iptables legacy 方案还是 nftables 方案：

```bash
$ iptables --version
iptables v1.8.7 (legacy)
```

采用 legacy 方案，因此使用以下指令查看 iptables 的 nat 表（负责修改源/目的的 IP 和端口）下的所有 Chain：

```bash
iptables -L -t nat
```

但是由于服务器采用了 k8s，iptables 里的 Chain 非常多，以下仅列出预定义的 Chain 的内容：

```bash
$ iptables -L -t nat
iptables -L -t nat | head -n 40
Chain PREROUTING (policy ACCEPT)
target     prot opt source               destination         
cali-PREROUTING  all  --  anywhere             anywhere             /* cali:6gwbT8clXdHdC1b1 */
KUBE-SERVICES  all  --  anywhere             anywhere             /* kubernetes service portals */
DOCKER     all  --  anywhere             anywhere             ADDRTYPE match dst-type LOCAL

Chain INPUT (policy ACCEPT)
target     prot opt source               destination         

Chain OUTPUT (policy ACCEPT)
target     prot opt source               destination         
cali-OUTPUT  all  --  anywhere             anywhere             /* cali:tVnHkvAo15HuiPy0 */
KUBE-SERVICES  all  --  anywhere             anywhere             /* kubernetes service portals */
DOCKER     all  --  anywhere            !127.0.0.0/8          ADDRTYPE match dst-type LOCAL

Chain POSTROUTING (policy ACCEPT)
target     prot opt source               destination         
cali-POSTROUTING  all  --  anywhere             anywhere             /* cali:O3lYWMrLQYEMJtB5 */
MASQUERADE  all  --  172.18.0.0/16        anywhere            
KUBE-POSTROUTING  all  --  anywhere             anywhere             /* kubernetes postrouting rules */
MASQUERADE  all  --  172.17.0.0/16        anywhere            
LIBVIRT_PRT  all  --  anywhere             anywhere            
MASQUERADE  tcp  --  172.18.0.2           172.18.0.2           tcp dpt:10514
MASQUERADE  tcp  --  172.18.0.9           172.18.0.9           tcp dpt:webcache

```

但是单从预定义的 Chain 里实在是看不出什么端倪来，因为其中并没有一条显式的规则包含 80 端口，或者目标 IP 是本机。

== 自己研究

到目前为止，我只能自己根据集群的情况进行一些合理推测了。

首先，我发现这个集群使用 k8s 进行容器编排，那我很有理由推测这个服务实际上跑在 k8s 里的。

其次，虽然我对 k8s 不太熟悉，但是我至少知道，k8s 通常采用 nginx 作为 ingress controller 对 HTTP 服务进行反向代理、负载均衡、智能路由等功能。

因此，我所访问的服务大概率是由 ingress-nginx 做反向代理的，虽然我不知道为什么 ingress-nginx 没有占用 80 端口。

首先，我先找到 ingress-nginx 的 pod：

```bash
$ kubectl get pods -n ingress-nginx
NAME                                        READY   STATUS    RESTARTS       AGE
ingress-nginx-controller-59c4c457db-srld9   1/1     Running   2 (151d ago)   351d
```

然后，进入到这个 pod 里：

```bash
kubectl exec -it -n ingress-nginx ingress-nginx-controller-59c4c457db-srld9 -- /bin/bash
```

接着，在这个 pod 里通过 `vi` 查看 `/etc/nginx/nginx.conf` 的内容，找到匹配根路径的 location 块（已省略无关内容）：

```conf
http {
  server {
    location ~* '^/' {
      set $namespace      "hero-application";
      set $service_name   "heros-portal-console";
      set $service_port   "5443";
      set $location_path  "";
    }
  }
}
```

发现是一个在 `hero-application` 命名空间里叫 `heros-portal-console` 的 k8s service 在提供服务。

因此，我再去查看一下这个 service 的具体信息：

```bash
$ kubectl get svc heros-portal-console -n hero-application
NAME                   TYPE       CLUSTER-IP    EXTERNAL-IP   PORT(S)          AGE
heros-portal-console   NodePort   10.96.75.57   <none>        5443:30008/TCP   373d
```

说明提供这个服务的 Pod 的 IP 是 10.96.75.57，端口是 5443。

因此，我尝试使用 `curl 10.96.75.57:5443` 访问这个服务，发现和直接 `curl localhost` 的结果是完全一样的！说明位于主机上的 80 端口的服务正是通过 ingress-nginx 反向代理到这个 service 上的。

= 回顾

那为什么 80 端口上的流量会重定向到 ingress-nginx 上呢？我于是重新查找 iptables 的 Chain。

首先，ingress-nginx 是开在 80 端口上的，因此可以使用 `grep` 过滤一下，从而大大减小查找的工作量：

```bash
$ iptables -L -t nat | grep -E ':80$' -B 3
Chain KUBE-SEP-3J3BPC5JPSIBHQN4 (1 references)
target     prot opt source               destination         
KUBE-MARK-MASQ  all  --  10.244.209.252       anywhere             /* basic-component/model-repository:http */
DNAT       tcp  --  anywhere             anywhere             /* basic-component/model-repository:http */ tcp to:10.244.209.252:80
--
Chain KUBE-SEP-437TZ5GT227FODOU (1 references)
target     prot opt source               destination         
KUBE-MARK-MASQ  all  --  10.244.74.240        anywhere             /* ingress-nginx/ingress-nginx-controller:http */
DNAT       tcp  --  anywhere             anywhere             /* ingress-nginx/ingress-nginx-controller:http */ tcp to:10.244.74.240:80
--
Chain KUBE-SEP-YNA7BKMCGAZVRJ7T (1 references)
target     prot opt source               destination         
KUBE-MARK-MASQ  all  --  10.244.74.246        anywhere             /* hero-system/volume-controller:http */
DNAT       tcp  --  anywhere             anywhere             /* hero-system/volume-controller:http */ tcp to:10.244.74.246:80
```

然后，通过 `less` 查看 iptables 的输出，从 `Chain KUBE-SEP-437TZ5GT227FODOU` 开始向上溯源查找，直到找到预定义的 Chain：

```txt
Chain PREROUTING (policy ACCEPT)
target     prot opt source               destination 
KUBE-SERVICES  all  --  anywhere             anywhere             /* kubernetes service portals */

Chain KUBE-SERVICES (2 references)
target     prot opt source               destination 
KUBE-NODEPORTS  all  --  anywhere             anywhere             /* kubernetes service nodeports; NOTE: this must be the last rule in this chain */ ADDRTYPE match dst-type LOCAL

Chain KUBE-NODEPORTS (1 references)
target     prot opt source               destination 
KUBE-EXT-CG5I4G2RS3ZVWGLK  tcp  --  anywhere             anywhere             /* ingress-nginx/ingress-nginx-controller:http */ tcp dpt:http

Chain KUBE-EXT-CG5I4G2RS3ZVWGLK (1 references)
target     prot opt source               destination 
KUBE-SVC-CG5I4G2RS3ZVWGLK  all  --  anywhere             anywhere

Chain KUBE-SVC-CG5I4G2RS3ZVWGLK (2 references)
target     prot opt source               destination
KUBE-SEP-437TZ5GT227FODOU  all  --  anywhere             anywhere             /* ingress-nginx/ingress-nginx-controller:http -> 10.244.74.240:80 */

Chain KUBE-SEP-437TZ5GT227FODOU (1 references)
target     prot opt source               destination
DNAT       tcp  --  anywhere             anywhere             /* ingress-nginx/ingress-nginx-controller:http */ tcp to:10.244.74.240:80
```

观察可以得知，访问 80 端口的流量会通过 `KUBE-NODEPORTS` 这个 Chain 转发到 ingress-nginx，而根据 k8s 的工作原理，在 Service 中使用 NodePort 模式暴露服务时，k8s 会在每个节点上都通过 iptables 添加规则，使得本机对应端口的流量转发到对应的 Service 上。

但是，默认 NodePort 仅允许其端口范围为 30000-32767，进一步查询 k8s 的配置文件 `/etc/kubernetes/manifests/kube-apiserver.yaml` 发现，kube-apiserver 的启动参数里修改了默认端口范围为 1-65535，因此 80 端口的服务能通过 NodePort 的方式暴露出来。\

= 总结

至此，所有疑惑都迎刃而解了，我们可以尝试推测一下这个 80 端口的服务是怎么被拉起来的了：

+ k8s 配置文件里的 NodePort 范围被修改为 1-65535，使得 80 端口的服务能够通过 NodePort 的方式暴露出来。
+ 目标 Service 启用，使用 NodePort 模式暴露服务，k8s 在每个节点上设置 iptables，将访问本机 80 端口的流量转发到这个 Service 上。
+ 在登录节点上启用 nginx 进行反代，将某台计算节点上的 80 端口的服务反代到登录节点的 80 端口上。
+ 用户访问登录节点的 80 端口，成功访问到服务。

= 改进

一个 Service 直接使用 NodePort 暴露 HTTP 服务实在是有点简单粗暴，工业级的做法应该是使用 Ingress，比如 ingress-nginx 这样成熟的 ingress controller 来提供统一的 HTTP 服务入口，不仅方便配置 HTTPS，而且如果之后还有别的 HTTP 服务需要暴露出来的话，交给 ingress controller 来做反代和路由也是非常方便的。

之后如果有时间的话，我可能需要折腾一下了。

除此之外，我可能需要学习一下 k8s 的基本知识了，以后在这个集群里进一步开发和排查的话，基础知识还是很有必要的。
