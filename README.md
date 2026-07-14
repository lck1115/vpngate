# VPNGate SOCKS5 Docker

把 VPNGate 的 OpenVPN 节点封装成本机私有 SOCKS5 出口。

运行后，宿主机只会暴露：

```text
127.0.0.1:1080
```

你的 sing-box/v2ray 可以把指定出站流量指向这个 SOCKS5。这个项目不生成、不修改 sing-box/v2ray 配置。

## 工作方式

```text
VPNGate API
  -> 自动选择 OpenVPN 节点
  -> Docker 容器内连接 VPNGate
  -> 容器内启动内置 SOCKS5 server
  -> SOCKS5 出口强制走 tun0
  -> 宿主机通过 127.0.0.1:1080 使用该 SOCKS5
```

默认行为：

- 首次启动自动选择综合最优 VPNGate 节点。
- 可以按国家列出候选节点，例如 `JP` 前 10 个。
- 可以交互式选择编号切换出口 IP。
- 切换失败会尝试回滚到上一个可用节点。
- SOCKS5 只绑定宿主机 `127.0.0.1`，不暴露公网。
- OpenVPN 断开时，SOCKS5 请求应失败，而不是回落到 VPS 原始公网 IP。

## 启动

```bash
docker compose pull
docker compose up -d
```

默认使用 GitHub Actions 构建好的镜像：

```text
ghcr.io/lck1115/vpngate:latest
```

查看日志：

```bash
docker logs -f vpngate-socks5
```

查看当前节点：

```bash
docker exec -it vpngate-socks5 vpngate status
```

验证 SOCKS5 出口 IP：

```bash
curl --socks5-hostname 127.0.0.1:1080 https://api.ipify.org
```

返回值应该是 VPNGate 节点 IP，不应该是 VPS 原始公网 IP。

## 列出指定国家节点

例如列出日本前 10 个综合最优节点：

```bash
docker exec -it vpngate-socks5 vpngate list --country JP --limit 10
```

只看 TCP 节点：

```bash
docker exec -it vpngate-socks5 vpngate list --country JP --limit 10 --protocol tcp_only
```

TCP/UDP 都列出来：

```bash
docker exec -it vpngate-socks5 vpngate list --country JP --limit 10 --protocol any
```

输出示例：

```text
No  Country IP                 Ping  SpeedMbps Sessions UptimeDays Proto   Score
 1  JP      1.2.3.4              32      180.5        3       12.4   tcp   91.20
 2  JP      5.6.7.8              48      220.1        8        5.1   tcp   88.70
```

国家使用 VPNGate 的 `CountryShort` 字段，例如：

```text
JP, US, KR, TW, SG, HK
```

## 交互式切换 IP

```bash
docker exec -it vpngate-socks5 vpngate switch --country JP
```

如果只想从 TCP 节点中选择：

```bash
docker exec -it vpngate-socks5 vpngate switch --country JP --protocol tcp_only
```

命令会展示候选节点，输入编号后自动切换：

```text
Select node number:
```

切换完成后验证：

```bash
docker exec -it vpngate-socks5 vpngate status
curl --socks5-hostname 127.0.0.1:1080 https://api.ipify.org
```

## 自动切换到当前最优节点

不限制国家：

```bash
docker exec -it vpngate-socks5 vpngate auto
```

指定国家：

```bash
docker exec -it vpngate-socks5 vpngate auto --country JP
```

指定国家并只尝试 TCP：

```bash
docker exec -it vpngate-socks5 vpngate auto --country JP --protocol tcp_only
```

## 环境变量

在 `docker-compose.yml` 中调整：

```yaml
environment:
  SOCKS_PORT: "1080"
  DEFAULT_COUNTRY: ""
  LIST_LIMIT: "10"
  MIN_SPEED: "0"
  MAX_PING: "9999"
  PROTOCOL_POLICY: "prefer_tcp"
  PREFER_TCP: "true"
  HEALTHCHECK_URL: "https://api.ipify.org"
  CONNECT_TIMEOUT: "10"
  SWITCH_ROLLBACK: "true"
```

说明：

- `SOCKS_PORT`：容器内 SOCKS5 端口，宿主机默认映射到 `127.0.0.1:1080`。
- `DEFAULT_COUNTRY`：首次启动默认国家，空值表示全球节点中选择最优。
- `LIST_LIMIT`：列表默认展示数量。
- `MIN_SPEED`：过滤低于该 bps 速度的节点。
- `MAX_PING`：过滤高于该 ms 延迟的节点。
- `PROTOCOL_POLICY`：协议策略，支持 `prefer_tcp`、`tcp_only`、`udp_only`、`any`。
- `PREFER_TCP`：旧兼容项；未设置 `PROTOCOL_POLICY` 时，`true` 等同于 `prefer_tcp`，`false` 等同于 `any`。
- `HEALTHCHECK_URL`：用于验证 SOCKS5 出口的 URL。
- `CONNECT_TIMEOUT`：等待 OpenVPN/tun0 的秒数，默认 `10`，用于快速跳过不可用 VPNGate 节点。
- `SWITCH_ROLLBACK`：切换失败时是否回滚到上一个节点。

协议策略说明：

- `prefer_tcp`：默认策略；有 TCP 候选时只选 TCP，没有 TCP 时回退到 TCP/UDP 全部候选。
- `tcp_only`：只选 TCP；适合 UDP 在 VPS 机房不可用或不稳定的场景。
- `udp_only`：只选 UDP；用于排查或特殊网络。
- `any`：TCP/UDP 都参与排序；适合某些国家 TCP 节点很少时扩大候选范围。

## 评分规则

候选节点按综合评分排序：

```text
Speed: 45%
Ping: 25%
NumVpnSessions: 20%
Uptime: 10%
```

规则：

- 速度越高越好。
- Ping 越低越好。
- 在线人数越少越好。
- Uptime 越长越好。

评分只在当前候选集合内归一化，所以 `JP` 的分数只代表日本候选之间的相对结果。

## 防泄漏测试

正常情况下：

```bash
curl --socks5-hostname 127.0.0.1:1080 https://api.ipify.org
```

应该返回 VPNGate 出口 IP。

模拟 VPN 断开：

```bash
docker exec -it vpngate-socks5 pkill openvpn
```

再测试：

```bash
curl --max-time 10 --socks5-hostname 127.0.0.1:1080 https://api.ipify.org
```

预期结果是请求失败。不能返回 VPS 原始公网 IP。

容器会因为 OpenVPN 进程退出而退出，然后由 Docker `restart: unless-stopped` 自动重启。

## 持久化文件

容器状态保存在 `./data`：

```text
data/current.json
data/current.ovpn
data/previous.json
data/previous.ovpn
data/vpngate-cache.csv
data/vpngate-socks5.log
data/openvpn.log
data/socks5.log
```

## 注意事项

- VPNGate 是志愿者节点，速度和稳定性不可控。
- 本项目默认只作为本机私有 SOCKS5 出口，不应该直接暴露公网。
- v1 主要面向 TCP 流量。UDP 需要单独验证 SOCKS5 UDP associate 和上游 VPN 节点可用性。
- 如果你的 VPS 上没有 `/dev/net/tun`，需要先在宿主机启用 TUN 设备。
