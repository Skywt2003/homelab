# Mihomo Prometheus Exporter

[![Go Version](https://img.shields.io/badge/go-1.23%2B-blue.svg)](https://golang.org/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

`mihomo-prometheus-exporter` 是一个轻量级、高性能的 Prometheus
Exporter，用于从 [Mihomo](https://github.com/MetaCubeX/mihomo) 中导出详细的运行时指标。

它被设计为异步运行，定期从 Mihomo API 拉取数据并缓存。这意味着 Prometheus 的抓取请求会立即得到响应，不会对 Mihomo
核心造成性能压力，确保了监控的稳定性和低延迟。

## 特性

* **异步抓取 (Asynchronous Scraping)**: 在后台独立地从 Mihomo API 获取数据，与 Prometheus 的抓取周期解耦，避免了在抓取时进行耗时的
  API 调用。
* **详尽的指标 (Detailed Metrics)**: 不仅仅是总流量，我们导出：
    * 实时的上传/下载速率。
    * 每个独立连接的流量、源 IP、目标域名/IP。
    * 每个连接所使用的**出站节点** (包括 `DIRECT`)。
    * 每个代理节点的延迟和可用性。
    * 新增低维度指标导出，避免高纬度指标消耗性能

## 快速开始

### 前提条件

* Go 1.18 或更高版本。
* 一个正在运行的 Mihomo 实例，并已启用 `external-controller`。

### 安装与编译

1. 克隆或下载本项目代码。
2. 在项目根目录下，构建二进制文件：

   ```bash
   go build -o mihomo-exporter .
   ```

### 运行 Exporter

执行以下命令启动 Exporter。请务必将 API 地址和密钥替换为你的配置。

```bash
./mihomo-exporter \
  --web.listen-address=":9188" \
  --mihomo.api-url="http://127.0.0.1:9090" \
  --mihomo.api-token="YOUR_SECRET_TOKEN" \
  --scrape.interval="1s"
```

## 使用方法

### 命令行参数

| 参数 | 环境变量 | 默认值 | 描述                                     |
|----------------------|---------------------|-------------------------|----------------------------------------|
| `web.listen-address` | `WEB_LISTEN_ADDRESS` | `:9188` | Exporter 监听的地址和端口。                     |
| `mihomo.api-url` | `MIHOMO_API_URL` | `http://127.0.0.1:9097` | Mihomo `external-controller` 的 API 地址。 |
| `mihomo.api-token` | `MIHOMO_API_TOKEN` | `""` | Mihomo API 的 `secret` (如果设置了)。         |
| `scrape.interval` | `SCRAPE_INTERVAL` | `1s` | 从 Mihomo API 拉取数据的频率。                  |
| `latency.interval` | `LATENCY_INTERVAL` | `60s` | 从 Mihomo 进行统一延迟测试的频率                   |
| `metric.prefix` | `METRIC_PREFIX` | `mihomo` | 导出的指标前缀                                |
| `metrics.enable-total-traffic` | `METRICS_ENABLE_TOTAL_TRAFFIC` | `true` | 启用精准的累计流量指标（从 Mihomo API 直接读取）。        |
| `metrics.enable-node-aggregation` | `METRICS_ENABLE_NODE_AGGREGATION` | `true` | 启用按出站节点聚合的连接指标（低基数指标）。                 |
| `metrics.enable-destination-aggregation` | `METRICS_ENABLE_DESTINATION_AGGREGATION` | `true` | 启用按目标聚合的连接指标（低基数指标）。                   |

### Docker运行

前台运行测试

```shell
docker run -it --rm -e MIHOMO_API_URL=http://host.docker.internal:9097 -e MIHOMO_API_TOKEN=set-your-secret  -p 9188:9188 ghcr.io/wherearebugs/mihomo-prometheus-exporter:master
```

正常启动

```shell
 docker run -d -e MIHOMO_API_URL=http://host.docker.internal:9097 -e MIHOMO_API_TOKEN=set-your-secret  -p 9188:9188  ghcr.io/wherearebugs/mihomo-prometheus-exporter:master
```

### Docker Compose Service

```yaml
version: "3.3"
services:
  mihomo-prometheus-exporter:
    environment:
      - MIHOMO_API_URL=http://host.docker.internal:9097 # 替换成实际的API地址
      - MIHOMO_API_TOKEN=set-your-secret # 替换成实际的token
      - METRIC_PREFIX=mihomo
    ports:
      - 9188:9188
    image: ghcr.io/wherearebugs/mihomo-prometheus-exporter:master
  # 按需添加其他的service...
networks: {}
```

### Prometheus 配置

将以下内容添加到你的 `prometheus.yml` 文件中，以开始抓取 Exporter 暴露的指标。

```yaml
scrape_configs:
  - job_name: 'mihomo' #或者其他你喜欢的名字
    scrape_interval: 1s #建议与SCRAPE_INTERVAL参数一致
    static_configs:
      - targets: [ 'localhost:9188' ] # 替换为 exporter 运行的地址
```

## 📈 导出的指标

以下是本 Exporter 提供的核心指标列表。

### 流量总量指标

| 指标名称 | 类型 | 标签 | 描述 |
|---------|------|------|------|
| `mihomo_traffic_upload_total_bytes` | Counter | 无 | 从 Mihomo API 直接读取的累计上传字节数。 |
| `mihomo_traffic_download_total_bytes` | Counter | 无 | 从 Mihomo API 直接读取的累计下载字节数。 |

### 低基数聚合指标（推荐用于监控）

| 指标名称 | 类型 | 标签 | 基数 | 描述 |
|---------|------|------|------|------|
| `mihomo_connection_upload_bytes_by_node` | Gauge | `outbound_node` | 节点数 | 按出站节点聚合的上传字节数。 |
| `mihomo_connection_download_bytes_by_node` | Gauge | `outbound_node` | 节点数 | 按出站节点聚合的下载字节数。 |
| `mihomo_connection_upload_bytes_by_destination` | Gauge | `destination`, `outbound_node` | 目标数×节点数 | 按目标聚合的上传字节数。 |
| `mihomo_connection_download_bytes_by_destination` | Gauge | `destination`, `outbound_node` | 目标数×节点数 | 按目标聚合的下载字节数。 |

### V1版本指标

| 指标名称 | 类型 | 标签 | 基数 | 描述 |
|---------|------|------|------|------|
| `mihomo_traffic_upload_speed_bytes` | Gauge | 无 | 1 | 当前全局上传速率（字节/秒）。 |
| `mihomo_traffic_download_speed_bytes` | Gauge | 无 | 1 | 当前全局下载速率（字节/秒）。 |
| `mihomo_connections_active_total` | Gauge | 无 | 1 | 当前活跃连接的总数。 |
| `mihomo_connection_upload_bytes` | Gauge | `source_host`, `destination`, `outbound_node` | 高 | 单个连接累计上传的字节数。 |
| `mihomo_connection_download_bytes` | Gauge | `source_host`, `destination`, `outbound_node` | 高 | 单个连接累计下载的字节数。 |
| `mihomo_proxy_latency_ms` | Gauge | `proxy_name` | 节点数 | 代理节点的延迟（毫秒），-1 表示测试失败。 |
| `mihomo_proxy_available` | Gauge | `proxy_name` | 节点数 | 代理节点的可用性（1=可用，0=不可用）。 |

**基数说明**：
- **精准流量指标**：固定 2 个时间序列（推荐用于计算速率）
- **低基数聚合指标**：基数可控，通常 < 1000 个时间序列（推荐用于监控）
- **原有指标**：基数可能很高（10000+），建议在生产环境中谨慎使用

## PromQL 查询示例 (Grafana 看板示例)

利用这些指标，你可以构建强大的仪表盘。

### 精准流量指标示例

**1. 全局实时下载速率**
```promql
rate(mihomo_traffic_download_total_bytes[1m])
```

**2. 全局实时上传速率**
```promql
rate(mihomo_traffic_upload_total_bytes[1m])
```

**3. 今日总流量（GB）**
```promql
(sum(rate(mihomo_traffic_upload_total_bytes[1m])) + sum(rate(mihomo_traffic_download_total_bytes[1m]))) * 60 / 1024 / 1024 / 1024
```

### 低基数聚合指标示例

**4. 按出站节点统计的实时流量速率**
```promql
sum(rate(mihomo_connection_upload_bytes_by_node[1m])) by (outbound_node)
sum(rate(mihomo_connection_download_bytes_by_node[1m])) by (outbound_node)
```

**5. 按目标统计的下载流量（Top 10）**
```promql
topk(10, sum(rate(mihomo_connection_download_bytes_by_destination[5m])) by (destination))
```

**6. 特定节点的流量趋势**
```promql
sum(rate(mihomo_connection_download_bytes_by_node{outbound_node="HK-Node-1"}[5m]))
```

### 代理延迟监控

**7. 各代理节点的平均延迟（只显示可用节点）**
```promql
avg_over_time(mihomo_proxy_latency_ms[5m])
```

**8. 不可用节点列表**
```promql
mihomo_proxy_available{mihomo_proxy_available="0"}
```

### 连接统计

**9. 统计每个出站节点的活跃连接数**
```promql
count(mihomo_connection_upload_bytes) by (outbound_node)
```

**10. 当前活跃连接总数**
```promql
mihomo_connections_active_total
```

## 贡献

欢迎提交 Pull Requests 或 Issues 来改进这个项目。

## 许可证

本项目基于 [MIT License](./LICENSE) 开源。
