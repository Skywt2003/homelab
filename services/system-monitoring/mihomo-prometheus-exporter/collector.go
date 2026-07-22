// collector.go
package main

import (
	"context"
	"log"
	"strings"
	"sync"
	"time"

	"github.com/prometheus/client_golang/prometheus"
)

// MihomoCollector 实现了 prometheus.Collector 接口
type MihomoCollector struct {
	client *MihomoClient
	prefix string
	mutex  sync.RWMutex

	nodeGroupMappings []NodeGroupMapping

	// 配置选项
	enableTotalTraffic           bool
	enableNodeAggregation        bool
	enableDestinationAggregation bool

	// 指标定义
	// === 原有指标（保持不变）===
	up                 *prometheus.Desc
	down               *prometheus.Desc
	activeConnections  *prometheus.Desc
	connectionUpload   *prometheus.Desc
	connectionDownload *prometheus.Desc
	proxyLatency       *prometheus.Desc
	proxyAvailable     *prometheus.Desc
	proxyGroupSelected *prometheus.Desc

	// === 新增：精准用量指标 ===
	trafficUploadTotal   *prometheus.Desc
	trafficDownloadTotal *prometheus.Desc

	// === 新增：低基数聚合指标 ===
	connectionUploadByNode          *prometheus.Desc
	connectionDownloadByNode        *prometheus.Desc
	connectionUploadByDestination   *prometheus.Desc
	connectionDownloadByDestination *prometheus.Desc

	// 缓存从 API 获取的数据
	cachedTraffic        *Traffic
	cachedConnections    *ConnectionsResponse
	cachedProxyLatencies map[string]int
	cachedProxies        *ProxiesResponse
	cachedNodeGroups     map[string]string
}

// NodeGroupMapping maps a stable Prometheus label value to a Mihomo proxy
// group.  Membership is read from Mihomo's /proxies API, so monitoring follows
// the gateway configuration instead of duplicating every node name here.
type NodeGroupMapping struct {
	Label      string
	ProxyGroup string
}

// NewMihomoCollector 创建并初始化一个 Collector
func NewMihomoCollector(client *MihomoClient, prefix string, enableTotalTraffic, enableNodeAgg, enableDestAgg bool, nodeGroupMappings []NodeGroupMapping) *MihomoCollector {
	fqName := func(name string) string {
		return prometheus.BuildFQName(prefix, "", name)
	}
	return &MihomoCollector{
		client:                       client,
		prefix:                       prefix,
		nodeGroupMappings:            nodeGroupMappings,
		enableTotalTraffic:           enableTotalTraffic,
		enableNodeAggregation:        enableNodeAgg,
		enableDestinationAggregation: enableDestAgg,
		up: prometheus.NewDesc(
			fqName("traffic_upload_speed_bytes"),
			"Current upload speed in bytes per second.",
			nil, nil,
		),
		down: prometheus.NewDesc(
			fqName("traffic_download_speed_bytes"),
			"Current download speed in bytes per second.",
			nil, nil,
		),
		activeConnections: prometheus.NewDesc(
			fqName("connections_active_total"),
			"Total number of active connections.",
			nil, nil,
		),
		connectionUpload: prometheus.NewDesc(
			fqName("connection_upload_bytes"),
			"Uploaded bytes for a specific active connection.",
			[]string{"source_host", "destination", "outbound_node"}, nil,
		),
		connectionDownload: prometheus.NewDesc(
			fqName("connection_download_bytes"),
			"Downloaded bytes for a specific active connection.",
			[]string{"source_host", "destination", "outbound_node"}, nil,
		),
		proxyLatency: prometheus.NewDesc(
			fqName("proxy_latency_ms"),
			"Latency of a specific proxy in milliseconds.",
			[]string{"proxy_name", "node_group"}, nil,
		),
		proxyAvailable: prometheus.NewDesc(
			fqName("proxy_available"),
			"Availability of a specific proxy (1 for available, 0 for unavailable).",
			[]string{"proxy_name", "node_group"}, nil,
		),
		proxyGroupSelected: prometheus.NewDesc(
			fqName("proxy_group_selected"),
			"Currently selected proxy for a Mihomo proxy group (1 for the active selection).",
			[]string{"group", "proxy", "type"}, nil,
		),
		trafficUploadTotal: prometheus.NewDesc(
			fqName("traffic_upload_total_bytes"),
			"Total uploaded bytes from Mihomo API (accurate).",
			nil, nil,
		),
		trafficDownloadTotal: prometheus.NewDesc(
			fqName("traffic_download_total_bytes"),
			"Total downloaded bytes from Mihomo API (accurate).",
			nil, nil,
		),
		connectionUploadByNode: prometheus.NewDesc(
			fqName("connection_upload_bytes_by_node"),
			"Total uploaded bytes aggregated by outbound node (low cardinality).",
			[]string{"outbound_node", "node_group"}, nil,
		),
		connectionDownloadByNode: prometheus.NewDesc(
			fqName("connection_download_bytes_by_node"),
			"Total downloaded bytes aggregated by outbound node (low cardinality).",
			[]string{"outbound_node", "node_group"}, nil,
		),
		connectionUploadByDestination: prometheus.NewDesc(
			fqName("connection_upload_bytes_by_destination"),
			"Total uploaded bytes aggregated by destination (low cardinality).",
			[]string{"destination", "outbound_node"}, nil,
		),
		connectionDownloadByDestination: prometheus.NewDesc(
			fqName("connection_download_bytes_by_destination"),
			"Total downloaded bytes aggregated by destination (low cardinality).",
			[]string{"destination", "outbound_node"}, nil,
		),
		cachedProxyLatencies: make(map[string]int),
		cachedNodeGroups:     make(map[string]string),
	}
}

func (c *MihomoCollector) updateNodeGroupsLocked(proxies *ProxiesResponse) {
	groups := make(map[string]string)
	if proxies != nil {
		for _, mapping := range c.nodeGroupMappings {
			proxyGroup, ok := proxies.Proxies[mapping.ProxyGroup]
			if !ok || !isProxyGroupType(proxyGroup.Type) {
				continue
			}
			for _, proxyName := range proxyGroup.All {
				if isExcludedMonitoringProxy(proxyName) {
					continue
				}
				// The first configured mapping wins if groups accidentally overlap.
				if _, exists := groups[proxyName]; !exists {
					groups[proxyName] = mapping.Label
				}
			}
		}
	}
	c.cachedNodeGroups = groups
}

func isExcludedMonitoringProxy(proxyName string) bool {
	switch proxyName {
	case "PASS", "PASS-RULE", "REJECT-DROP", "COMPATIBLE":
		return true
	}
	return strings.HasPrefix(proxyName, "Traffic:") || strings.HasPrefix(proxyName, "Expire:")
}

func (c *MihomoCollector) nodeGroupLocked(proxyName string) string {
	if group, ok := c.cachedNodeGroups[proxyName]; ok {
		return group
	}
	return "unclassified"
}

// getActualOutboundNode 获取实际的出站节点名称
// 遍历 Chains 数组，从后往前查找第一个真正的代理节点
func (c *MihomoCollector) getActualOutboundNode(chains []string) string {
	if c.cachedProxies == nil {
		return getFallbackOutboundNode(chains)
	}

	// 从后往前遍历 Chains，找到第一个真正的代理节点
	for i := len(chains) - 1; i >= 0; i-- {
		chain := chains[i]

		// 检查是否在 Proxies 中存在
		proxy, exists := c.cachedProxies.Proxies[chain]
		if !exists {
			continue
		}

		// 检查是否为真实代理类型（跳过规则组、选择器、DIRECT、REJECT）
		proxyType := proxy.Type
		isProxy := proxyType != "Selector" &&
			proxyType != "URLTest" &&
			proxyType != "Fallback" &&
			proxyType != "LoadBalance" &&
			proxyType != "Relay" &&
			proxyType != "Direct" &&
			proxyType != "Reject"

		if isProxy {
			return chain
		}

		// 如果是选择器，返回当前选择的节点
		if proxyType == "Selector" && proxy.Now != "" {

			// 如果 Now 指向另一个选择器（嵌套），则递归查找真实节点
			// 否则直接使用 Now 值
			nowProxy, nowExists := c.cachedProxies.Proxies[proxy.Now]
			if nowExists && nowProxy.Type == "Selector" {
				// Now 指向另一个选择器，继续递归查找
				// 从 All 数组中取第一个真实代理节点
				if len(nowProxy.All) > 0 {
					firstRealNode := nowProxy.All[0]
					return firstRealNode
				}
				return proxy.Now
			}

			return proxy.Now
		}

		// 如果没有找到真实代理节点，返回默认值
		return getFallbackOutboundNode(chains)
	}

	return getFallbackOutboundNode(chains)
}

// getFallbackOutboundNode 获取备用出站节点名称
// 如果无法识别真实代理节点，返回最后一个元素或 DIRECT
func isProxyGroupType(proxyType string) bool {
	switch proxyType {
	case "Selector", "URLTest", "Fallback", "LoadBalance", "Relay":
		return true
	default:
		return false
	}
}

func getFallbackOutboundNode(chains []string) string {
	if len(chains) == 0 {
		return "DIRECT"
	}
	lastChain := chains[len(chains)-1]
	if lastChain == "" {
		return "DIRECT"
	}
	return lastChain
}

// Describe 将所有指标描述符发送到 channel
func (c *MihomoCollector) Describe(ch chan<- *prometheus.Desc) {
	ch <- c.up
	ch <- c.down
	ch <- c.activeConnections
	ch <- c.connectionUpload
	ch <- c.connectionDownload
	ch <- c.proxyLatency
	ch <- c.proxyAvailable
	ch <- c.proxyGroupSelected

	if c.enableTotalTraffic {
		ch <- c.trafficUploadTotal
		ch <- c.trafficDownloadTotal
	}

	if c.enableNodeAggregation {
		ch <- c.connectionUploadByNode
		ch <- c.connectionDownloadByNode
	}

	if c.enableDestinationAggregation {
		ch <- c.connectionUploadByDestination
		ch <- c.connectionDownloadByDestination
	}
}

// Collect 从缓存中读取数据并生成指标，发送到 channel
func (c *MihomoCollector) Collect(ch chan<- prometheus.Metric) {
	c.mutex.RLock()
	defer c.mutex.RUnlock()

	if c.cachedTraffic != nil {
		ch <- prometheus.MustNewConstMetric(c.up, prometheus.GaugeValue, float64(c.cachedTraffic.Up))
		ch <- prometheus.MustNewConstMetric(c.down, prometheus.GaugeValue, float64(c.cachedTraffic.Down))
	}

	if c.cachedConnections != nil {
		ch <- prometheus.MustNewConstMetric(c.activeConnections, prometheus.GaugeValue, float64(len(c.cachedConnections.Connections)))

		if c.enableTotalTraffic {
			ch <- prometheus.MustNewConstMetric(c.trafficUploadTotal, prometheus.CounterValue, float64(c.cachedConnections.UploadTotal))
			ch <- prometheus.MustNewConstMetric(c.trafficDownloadTotal, prometheus.CounterValue, float64(c.cachedConnections.DownloadTotal))
		}

		type connKey struct {
			sourceHost   string
			destination  string
			outboundNode string
		}
		type connTraffic struct {
			upload   int64
			download int64
		}

		aggregatedConnections := make(map[connKey]connTraffic)
		aggregatedByNode := make(map[string]connTraffic)
		aggregatedByDestination := make(map[string]connTraffic)

		for _, conn := range c.cachedConnections.Connections {
			outboundNode := "DIRECT"
			if len(conn.Chains) > 0 {
				outboundNode = c.getActualOutboundNode(conn.Chains)
			}

			destination := conn.Metadata.Host
			if destination == "" {
				destination = conn.Metadata.DestinationIP
			}

			sourceHost := conn.Metadata.SourceIP

			// 为空标签分配默认值
			if sourceHost == "" {
				sourceHost = "mihomo"
			}
			if destination == "" {
				destination = "unknown"
			}

			// 只有 outboundNode 为空时才跳过
			if outboundNode == "" {
				log.Printf("[WARN] Skipping connection with empty outboundNode. ID: %s, Source: '%s', Destination: '%s'",
					conn.ID, sourceHost, destination)
				continue
			}

			key := connKey{sourceHost: sourceHost, destination: destination, outboundNode: outboundNode}
			traffic := aggregatedConnections[key]
			traffic.upload += conn.Upload
			traffic.download += conn.Download
			aggregatedConnections[key] = traffic

			if c.enableNodeAggregation {
				nodeTraffic := aggregatedByNode[outboundNode]
				nodeTraffic.upload += conn.Upload
				nodeTraffic.download += conn.Download
				aggregatedByNode[outboundNode] = nodeTraffic
			}

			if c.enableDestinationAggregation {
				destKey := destination + "|" + outboundNode
				destTraffic := aggregatedByDestination[destKey]
				destTraffic.upload += conn.Upload
				destTraffic.download += conn.Download
				aggregatedByDestination[destKey] = destTraffic
			}
		}

		for key, traffic := range aggregatedConnections {
			ch <- prometheus.MustNewConstMetric(c.connectionUpload, prometheus.GaugeValue, float64(traffic.upload), key.sourceHost, key.destination, key.outboundNode)
			ch <- prometheus.MustNewConstMetric(c.connectionDownload, prometheus.GaugeValue, float64(traffic.download), key.sourceHost, key.destination, key.outboundNode)
		}

		if c.enableNodeAggregation {
			for node, traffic := range aggregatedByNode {
				nodeGroup := c.nodeGroupLocked(node)
				ch <- prometheus.MustNewConstMetric(c.connectionUploadByNode, prometheus.GaugeValue, float64(traffic.upload), node, nodeGroup)
				ch <- prometheus.MustNewConstMetric(c.connectionDownloadByNode, prometheus.GaugeValue, float64(traffic.download), node, nodeGroup)
			}
		}

		if c.enableDestinationAggregation {
			for key, traffic := range aggregatedByDestination {
				parts := strings.Split(key, "|")
				if len(parts) == 2 {
					ch <- prometheus.MustNewConstMetric(c.connectionUploadByDestination, prometheus.GaugeValue, float64(traffic.upload), parts[0], parts[1])
					ch <- prometheus.MustNewConstMetric(c.connectionDownloadByDestination, prometheus.GaugeValue, float64(traffic.download), parts[0], parts[1])
				}
			}
		}
	}
	if c.cachedProxies != nil {
		for groupName, proxy := range c.cachedProxies.Proxies {
			if !isProxyGroupType(proxy.Type) || proxy.Now == "" {
				continue
			}
			ch <- prometheus.MustNewConstMetric(c.proxyGroupSelected, prometheus.GaugeValue, 1.0, groupName, proxy.Now, proxy.Type)
		}
	}

	if c.cachedProxyLatencies != nil {
		for name, delay := range c.cachedProxyLatencies {
			available := 1.0
			if delay <= 0 { // 延迟为0或负数通常表示超时或不可用
				available = 0.0
			}
			nodeGroup := c.nodeGroupLocked(name)
			ch <- prometheus.MustNewConstMetric(c.proxyLatency, prometheus.GaugeValue, float64(delay), name, nodeGroup)
			ch <- prometheus.MustNewConstMetric(c.proxyAvailable, prometheus.GaugeValue, available, name, nodeGroup)
		}
	}
}

// updateFastMetrics 负责更新变化较快的指标（流量、连接）
func (c *MihomoCollector) updateFastMetrics(ctx context.Context) {
	//log.Println("Updating fast metrics (traffic, connections)...")

	var wg sync.WaitGroup
	var traffic *Traffic
	var connections *ConnectionsResponse
	var proxies *ProxiesResponse
	var err error

	// 并发获取流量、连接和代理信息
	wg.Add(3)
	go func() {
		defer wg.Done()
		traffic, err = c.client.GetTraffic(ctx)
		if err != nil {
			log.Printf("Error getting traffic: %v", err)
			return
		}
		c.mutex.Lock()
		c.cachedTraffic = traffic
		c.mutex.Unlock()
	}()
	go func() {
		defer wg.Done()
		connections, err = c.client.GetConnections(ctx)
		if err != nil {
			log.Printf("Error getting connections: %v", err)
			return
		}
		c.mutex.Lock()
		c.cachedConnections = connections
		c.mutex.Unlock()
	}()
	go func() {
		defer wg.Done()
		proxies, err = c.client.GetProxies(ctx)
		if err != nil {
			log.Printf("Error getting proxies: %v", err)
			return
		}
		c.mutex.Lock()
		c.cachedProxies = proxies
		c.updateNodeGroupsLocked(proxies)
		c.mutex.Unlock()
	}()
	wg.Wait()
}

// updateSlowMetrics 负责更新变化较慢且耗时的指标（代理延迟）
func (c *MihomoCollector) updateSlowMetrics(ctx context.Context) {
	//log.Println("Updating slow metrics (proxy latency)...")

	var proxies *ProxiesResponse
	var err error
	latencies := make(map[string]int)

	// 获取代理列表，然后并发测试延迟
	proxies, err = c.client.GetProxies(ctx)
	if err != nil {
		log.Printf("Error getting proxies: %v", err)
	} else {
		c.mutex.Lock()
		c.cachedProxies = proxies
		c.updateNodeGroupsLocked(proxies)
		c.mutex.Unlock()

		var latencyWg sync.WaitGroup
		var latencyMutex sync.Mutex

		for name, p := range proxies.Proxies {
			// 只测试可用的代理节点，排除选择器、DIRECT等
			if p.Type == "Selector" || p.Type == "URLTest" || p.Type == "Fallback" || p.Type == "LoadBalance" || p.Type == "Direct" || p.Type == "Reject" {
				continue
			}
			if isExcludedMonitoringProxy(name) {
				continue
			}
			latencyWg.Add(1)
			go func(proxyName string) {
				defer latencyWg.Done()
				delayInfo, err := c.client.GetProxyDelay(ctx, proxyName)
				if err != nil {
					//log.Printf("Error getting delay for proxy %s: %v", proxyName, err)
					latencyMutex.Lock()
					latencies[proxyName] = -1
					latencyMutex.Unlock()
					return
				}
				latencyMutex.Lock()
				latencies[proxyName] = delayInfo.Delay
				latencyMutex.Unlock()
			}(name)
		}
		latencyWg.Wait()
	}

	c.mutex.Lock()
	c.cachedProxyLatencies = latencies
	c.mutex.Unlock()
	//log.Println("Proxy latency metrics updated.")
}

// StartMonitors 启动两个后台循环，分别以不同的间隔更新指标
func (c *MihomoCollector) StartMonitors(ctx context.Context, fastInterval, slowInterval time.Duration) {
	// 启动快速监控循环 (流量, 连接)
	go func() {
		ticker := time.NewTicker(fastInterval)
		defer ticker.Stop()
		// 立即执行一次
		c.updateFastMetrics(ctx)
		for {
			select {
			case <-ticker.C:
				c.updateFastMetrics(ctx)
			case <-ctx.Done():
				return
			}
		}
	}()

	// 启动慢速监控循环 (代理延迟)
	go func() {
		ticker := time.NewTicker(slowInterval)
		defer ticker.Stop()
		// 立即执行一次
		c.updateSlowMetrics(ctx)
		for {
			select {
			case <-ticker.C:
				c.updateSlowMetrics(ctx)
			case <-ctx.Done():
				return
			}
		}
	}()
}
