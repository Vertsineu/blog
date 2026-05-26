#import "@hugo/templates:0.1.0": article
#import "@hugo/utils:0.1.0": *

#show: article.with(
  title: "在华为 910B 上部署模型推理服务",
  date: datetime(year: 2026, month: 5, day: 26),
  tags: (
    platforms: ("linux", "docker", "npu"),
    domains: "deployment",
    intents: "introduction",
  ),
  draft: false
)

= 前言

之前接手了一个 8 卡 910B 的华为服务器集群，性能看上去还是可以的，但是平时几乎没啥人用（#strike[可能是华为卡真的很难用吧]），闲来无事，拉了几台机器来玩玩（#strike[反正我使用 kubernetes 部署的，想要让出来直接 `kubectl delete` 就是了]），主要是用于自己部署一些开源大模型。

本文主要就是分享一下部署过程中我所使用的脚本而已，并不会深入讲解具体的配置细节，因为我也不是做这方面的，纯粹是好玩（

= 背景

首先介绍一下每台服务器上的配置：

```bash
$ npu-smi info
+------------------------------------------------------------------------------------------------+
| npu-smi 25.3.rc1                 Version: 25.3.rc1                                             |
+---------------------------+---------------+----------------------------------------------------+
| NPU   Name                | Health        | Power(W)    Temp(C)           Hugepages-Usage(page)|
| Chip                      | Bus-Id        | AICore(%)   Memory-Usage(MB)  HBM-Usage(MB)        |
+===========================+===============+====================================================+
| 0     910B3               | OK            | 96.7        32                0    / 0             |
| 0                         | 0000:C1:00.0  | 0           0    / 0          60056/ 65536         |
+===========================+===============+====================================================+
| 1     910B3               | OK            | 93.7        30                0    / 0             |
| 0                         | 0000:C2:00.0  | 0           0    / 0          60050/ 65536         |
+===========================+===============+====================================================+
| 2     910B3               | OK            | 92.7        30                0    / 0             |
| 0                         | 0000:81:00.0  | 0           0    / 0          60050/ 65536         |
+===========================+===============+====================================================+
| 3     910B3               | OK            | 89.0        31                0    / 0             |
| 0                         | 0000:82:00.0  | 0           0    / 0          60051/ 65536         |
+===========================+===============+====================================================+
| 4     910B3               | OK            | 88.7        36                0    / 0             |
| 0                         | 0000:01:00.0  | 0           0    / 0          60050/ 65536         |
+===========================+===============+====================================================+
| 5     910B3               | OK            | 90.1        35                0    / 0             |
| 0                         | 0000:02:00.0  | 0           0    / 0          60050/ 65536         |
+===========================+===============+====================================================+
| 6     910B3               | OK            | 94.4        34                0    / 0             |
| 0                         | 0000:41:00.0  | 0           0    / 0          60051/ 65536         |
+===========================+===============+====================================================+
| 7     910B3               | OK            | 86.4        33                0    / 0             |
| 0                         | 0000:42:00.0  | 0           0    / 0          60051/ 65536         |
+===========================+===============+====================================================+
+---------------------------+---------------+----------------------------------------------------+
| NPU     Chip              | Process id    | Process name             | Process memory(MB)      |
+===========================+===============+====================================================+
| 0       0                 | 3329455       | VLLMWorker_TP            | 56683                   |
+===========================+===============+====================================================+
| 1       0                 | 3329456       | VLLMWorker_TP            | 56683                   |
+===========================+===============+====================================================+
| 2       0                 | 3329457       | VLLMWorker_TP            | 56683                   |
+===========================+===============+====================================================+
| 3       0                 | 3329458       | VLLMWorker_TP            | 56683                   |
+===========================+===============+====================================================+
| 4       0                 | 3329459       | VLLMWorker_TP            | 56683                   |
+===========================+===============+====================================================+
| 5       0                 | 3329460       | VLLMWorker_TP            | 56683                   |
+===========================+===============+====================================================+
| 6       0                 | 3329461       | VLLMWorker_TP            | 56683                   |
+===========================+===============+====================================================+
| 7       0                 | 3329465       | VLLMWorker_TP            | 56683                   |
+===========================+===============+====================================================+
```

每台机器上都配备了 8 张 910B3 加速卡，每张卡的显存大小是 64GB，不同机器之间采用 25GbE 高速以太网互联，每节点配备 4 #math.times 25GbE 端口，单节点网络带宽合计 100Gbps。

不同机器的共用存储位于 `/user-storage`，相当于一个高性能的 nfs 实现，具体技术我就不清楚了。

= 部署

== 下载

在部署模型之前，首先应该做的当然是下载模型，这里我采用 modelscope 来下载模型，比如下载 glm-5.1-w8a8 模型：

```bash
modelscope download \ 
  --model Eco-Tech/GLM-5.1-w8a8 \ 
  --local_dir /user-storage/models/GLM-5.1-w8a8 
```

存放在公共存储，这样多节点多实例部署的时候就不用每台机器都下载一遍了。

== 配置

推理框架我所使用的是 vllm-ascend，主要是看在这个推理框架的文档比较丰富，遇到疑难杂症的可能性应该会比较小。

为了减少对本机环境的干扰（#strike[毕竟还是要最终给别人用的]），我使用官方推荐的 Docker 镜像 `quay.io/ascend/vllm-ascend:v0.18.0rc1` 来进行部署。

因为国内访问容器仓库速率太慢或者干脆直接被墙了，所以我采用 #link("https://m.daocloud.io")[m.daocloud.io] 镜像来拉取镜像：

```bash
docker pull m.daocloud.io/quay.io/ascend/vllm-ascend:v0.18.0rc1
```

然后把 910B 设备和共用存储挂载到容器中并运行：

```bash
docker run --rm \ 
  --name vllm-ascend \ 
  --net host \ 
  --shm-size 16g \ 
  --device /dev/davinci0 --device /dev/davinci1 \ 
  --device /dev/davinci2 --device /dev/davinci3 \ 
  --device /dev/davinci4 --device /dev/davinci5 \ 
  --device /dev/davinci6 --device /dev/davinci7 \ 
  --device /dev/davinci_manager \ 
  --device /dev/devmm_svm \ 
  --device /dev/hisi_hdc \ 
  -v /usr/local/dcmi:/usr/local/dcmi \ 
  -v /usr/local/Ascend/driver/tools/hccn_tool:/usr/local/Ascend/driver/tools/hccn_tool \ 
  -v /usr/local/bin/npu-smi:/usr/local/bin/npu-smi \ 
  -v /usr/local/Ascend/driver/lib64/:/usr/local/Ascend/driver/lib64/ \ 
  -v /usr/local/Ascend/driver/version.info:/usr/local/Ascend/driver/version.info \ 
  -v /etc/ascend_install.info:/etc/ascend_install.info \ 
  -v /user-storage:/user-storage \ 
  -v /user-storage/models/.cache:/root/.cache \ 
  -it m.daocloud.io/quay.io/ascend/vllm-ascend:v0.18.0rc1 bash
```

进入到容器后，首先第一步就是必须执行以下命令：

```bash
pip install transformers==5.2.0
```

先把 `transformers` 库更新到某个版本，否则之后运行什么模型都会报错。

需要注意的是，执行这条指令可能也会报错，但是不用管，直接 `clear` 眼不见心为快，之后的模型也能跑，就很神奇。

== glm-5.1-w8a8

最开始我想跑的是 glm-5.1，当时最强的开源编程模型，这个模型还是挺大的，总模型参数量达 754B，如果不量化的话至少要用到 4 台机器，但是在我试验了很多次后，不知道为什么这个模型的 tps 低的离谱，只有个位数，遂放弃转而跑 w8a8 的量化版本。

这个量化版本的 glm-5.1 只需要 2 台机器就行了，其执行的指令分别为：

```bash
# node 1
export HCCL_IF_IP=172.20.1.2
export HCCL_SOCKET_IFNAME=vlan0.12,vlan1.12
export GLOO_SOCKET_IFNAME=vlan0.12
export TP_SOCKET_IFNAME=vlan0.12
export RANK_TABLE_FILE=/user-storage/models/hccl_16p.json
export OMP_PROC_BIND=false
export OMP_NUM_THREADS=1
export PYTORCH_NPU_ALLOC_CONF=expandable_segments:True
export HCCL_OP_EXPANSION_MODE=AIV
export HCCL_BUFFSIZE=200
export HCCL_INTRA_PCIE_ENABLE=1
export HCCL_INTRA_ROCE_ENABLE=0
export HCCL_CONNECT_TIMEOUT=300
export TASK_QUEUE_ENABLE=1
export VLLM_ASCEND_ENABLE_MLAPO=1
export VLLM_ASCEND_BALANCE_SCHEDULING=1
export VLLM_ASCEND_ENABLE_FUSED_MC2=1
export VLLM_ASCEND_ENABLE_FLASHCOMM1=1

vllm serve /user-storage/models/GLM-5.1-w8a8 \ 
  --host 0.0.0.0 \ 
  --port 8000 \ 
  --tensor-parallel-size 16 \ 
  --enable-expert-parallel \ 
  --dtype bfloat16 \ 
  --max-model-len 32768 \ 
  --gpu-memory-utilization 0.96 \ 
  --max-num-seqs 8 \ 
  --max-num-batched-tokens 1024 \ 
  --trust-remote-code \ 
  --quantization ascend \ 
  --enable-chunked-prefill \ 
  --enable-prefix-caching \ 
  --nnodes 2 \ 
  --node-rank 0 \ 
  --master-addr 172.20.1.2 \ 
  --master-port 29500 \ 
  --async-scheduling \ 
  --compilation-config '{"cudagraph_mode": "FULL_DECODE_ONLY"}' \ 
  --additional-config '{"fuse_muls_add": true, "multistream_overlap_shared_expert": true, "enable_shared_expert_dp": true}' \ 
  --speculative-config '{"num_speculative_tokens": 1, "method": "deepseek_mtp"}' \ 
  --chat-template-content-format string \ 
  --served-model-name glm-5.1 \ 
  --reasoning-parser glm45 \ 
  --enable-auto-tool-choice \ 
  --tool-call-parser glm47 2>&1 | tee ./vllm-ascend-$(date +%Y%m%d-%H%M%S).log
```

```bash
# node 2
export HCCL_IF_IP=172.20.1.5
export HCCL_SOCKET_IFNAME=vlan0.12,vlan1.12
export GLOO_SOCKET_IFNAME=vlan0.12
export TP_SOCKET_IFNAME=vlan0.12
export RANK_TABLE_FILE=/user-storage/models/hccl_16p.json
export OMP_PROC_BIND=false
export OMP_NUM_THREADS=1
export PYTORCH_NPU_ALLOC_CONF=expandable_segments:True
export HCCL_OP_EXPANSION_MODE=AIV
export HCCL_BUFFSIZE=200
export HCCL_INTRA_PCIE_ENABLE=1
export HCCL_INTRA_ROCE_ENABLE=0
export HCCL_CONNECT_TIMEOUT=300
export TASK_QUEUE_ENABLE=1
export VLLM_ASCEND_ENABLE_MLAPO=1
export VLLM_ASCEND_BALANCE_SCHEDULING=1
export VLLM_ASCEND_ENABLE_FUSED_MC2=1
export VLLM_ASCEND_ENABLE_FLASHCOMM1=1

vllm serve /user-storage/models/GLM-5.1-w8a8 \ 
  --host 0.0.0.0 \ 
  --port 8000 \ 
  --tensor-parallel-size 16 \ 
  --enable-expert-parallel \ 
  --dtype bfloat16 \ 
  --max-model-len 32768 \ 
  --gpu-memory-utilization 0.96 \ 
  --max-num-seqs 8 \ 
  --max-num-batched-tokens 1024 \ 
  --trust-remote-code \ 
  --quantization ascend \ 
  --enable-chunked-prefill \ 
  --enable-prefix-caching \ 
  --nnodes 2 \ 
  --node-rank 1 \ 
  --headless \ 
  --master-addr 172.20.1.2 \ 
  --master-port 29500 \ 
  --async-scheduling \ 
  --compilation-config '{"cudagraph_mode": "FULL_DECODE_ONLY"}' \ 
  --additional-config '{"fuse_muls_add": true, "multistream_overlap_shared_expert": true, "enable_shared_expert_dp": true}' \ 
  --speculative-config '{"num_speculative_tokens": 1, "method": "deepseek_mtp"}' \ 
  --chat-template-content-format string \ 
  --served-model-name glm-5.1 \ 
  --reasoning-parser glm45 \ 
  --enable-auto-tool-choice \ 
  --tool-call-parser glm47 2>&1 | tee ./vllm-ascend-$(date +%Y%m%d-%H%M%S).log
```

其中 `/user-storage/models/hccl_16.json` 的内容如下：

```json
{
  "version": "1.0",
  "server_count": "2",
  "server_list": [
    {
      "server_id": "172.20.2.2",
      "device": [
        {"device_id": "0", "device_ip": "172.20.0.2", "rank_id": "0"},
        {"device_id": "1", "device_ip": "172.20.0.3", "rank_id": "1"},
        {"device_id": "2", "device_ip": "172.20.0.4", "rank_id": "2"},
        {"device_id": "3", "device_ip": "172.20.0.5", "rank_id": "3"},
        {"device_id": "4", "device_ip": "172.20.0.6", "rank_id": "4"},
        {"device_id": "5", "device_ip": "172.20.0.7", "rank_id": "5"},
        {"device_id": "6", "device_ip": "172.20.0.8", "rank_id": "6"},
        {"device_id": "7", "device_ip": "172.20.0.9", "rank_id": "7"}
      ],
      "host_nic_ip": "reserve"
    },
    {
      "server_id": "172.20.2.3",
      "device": [
        {"device_id": "0", "device_ip": "172.20.0.10", "rank_id": "8"},
        {"device_id": "1", "device_ip": "172.20.0.11", "rank_id": "9"},
        {"device_id": "2", "device_ip": "172.20.0.12", "rank_id": "10"},
        {"device_id": "3", "device_ip": "172.20.0.13", "rank_id": "11"},
        {"device_id": "4", "device_ip": "172.20.0.14", "rank_id": "12"},
        {"device_id": "5", "device_ip": "172.20.0.15", "rank_id": "13"},
        {"device_id": "6", "device_ip": "172.20.0.16", "rank_id": "14"},
        {"device_id": "7", "device_ip": "172.20.0.17", "rank_id": "15"}
      ],
      "host_nic_ip": "reserve"
    }
  ],
  "status": "completed"
}
```

如果你需要自己尝试跑的话，主要需要修改的点就是所有 910B 设备的 IP，以及各个环境变量里的 IP 和设备号了，这我不是很懂，所以不好详细说明。

这样跑起来模型能跑个单请求 20tps 的速率，已经是一个很不错的数字了，但是最大最大的问题就是，这个 vllm-ascend 好像不太支持 kv cache offload，一旦我打开了，这个模型就跑不起来，但是如果我不开的话，这个模型最多只能跑 32k 的上下文，因为显存不够！

我也试过各种各样的办法，问过各种 AI 有什么解决办法，但是无论什么办法，在保持至少 20tps 的速率下，都不能做到有效降低显存提高上下文长度，这就很难受了，因为这就意味着，这个模型的上下文太短，接入不了主流的 claude code 等 AI agent 工具，只能拿来进行简单的对话。

== qwen2.5-coder-32b-instruct

不过接着我发现，与其指望跑一个编程用的大模型，为什么不来跑一个用于 FIM（Fill In the Middle）的简单的补全用的模型，这样至少还有点用。

因此，接下来我就尝试跑 qwen2.5-coder-32b-instruct 这个参数显著降低的补全用的模型，只需要 1 机就能跑起来：

```bash
export PYTORCH_NPU_ALLOC_CONF=expandable_segments:True
export OMP_NUM_THREADS=1
export TASK_QUEUE_ENABLE=1
export HCCL_CONNECT_TIMEOUT=300
export HCCL_OP_EXPANSION_MODE=AIV
export HCCL_BUFFSIZE=200

vllm serve /user-storage/models/Qwen2.5-Coder-32B-Instruct \ 
  --host 0.0.0.0 \ 
  --port 8000 \ 
  --tensor-parallel-size 8 \ 
  --dtype bfloat16 \ 
  --max-model-len 32768 \ 
  --gpu-memory-utilization 0.90 \ 
  --max-num-seqs 16 \ 
  --max-num-batched-tokens 4096 \ 
  --trust-remote-code \ 
  --enable-chunked-prefill \ 
  --enable-prefix-caching \ 
  --served-model-name qwen2.5-coder-32b \ 
  --async-scheduling \ 
  --compilation-config '{"cudagraph_mode": "FULL_DECODE_ONLY"}' \ 
  2>&1 | tee ./vllm-qwen-$(date +%Y%m%d-%H%M%S).log
```

这下模型的速率能跑到单请求 60tps，勉强够用。

= 总结

这篇文章主要就是分享一下我在用华为 910B 卡跑模型时的脚本，因为我在跑模型的时候总是能遇到各种环境上莫名其妙的问题，和 AI 大战 800 回合才解决，现在终于能跑起来了就分享给各位，#strike[省的你们也和 AI 大战 800 回合才能解决]。
