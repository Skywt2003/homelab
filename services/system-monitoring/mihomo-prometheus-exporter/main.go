// main.go
package main

import (
	"context"
	"flag"
	"fmt"
	"log"
	"net/http"
	"os"
	"os/signal"
	"strings"
	"syscall"
	"time"

	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promhttp"
)

func parseNodeGroupMappings(raw string) ([]NodeGroupMapping, error) {
	if strings.TrimSpace(raw) == "" {
		return nil, nil
	}

	var mappings []NodeGroupMapping
	seenLabels := make(map[string]struct{})
	for _, item := range strings.Split(raw, ",") {
		parts := strings.SplitN(strings.TrimSpace(item), "=", 2)
		if len(parts) != 2 || strings.TrimSpace(parts[0]) == "" || strings.TrimSpace(parts[1]) == "" {
			return nil, fmt.Errorf("invalid node group mapping %q; expected label=proxy-group", item)
		}
		label := strings.TrimSpace(parts[0])
		proxyGroup := strings.TrimSpace(parts[1])
		if _, exists := seenLabels[label]; exists {
			return nil, fmt.Errorf("duplicate node group label %q", label)
		}
		seenLabels[label] = struct{}{}
		mappings = append(mappings, NodeGroupMapping{Label: label, ProxyGroup: proxyGroup})
	}
	return mappings, nil
}

func loadFlagsFromEnv() {
	replacer := strings.NewReplacer(".", "_", "-", "_")

	flag.VisitAll(func(f *flag.Flag) {
		envName := strings.ToUpper(replacer.Replace(f.Name))
		if value, ok := os.LookupEnv(envName); ok {
			if err := flag.Set(f.Name, value); err != nil {
				log.Printf("Failed to set flag '%s' from environment variable '%s': %v", f.Name, envName, err)
			} else {
				log.Printf("Loaded flag '%s' from environment variable '%s'", f.Name, envName)
			}
		}
	})
}
func main() {
	// 命令行参数定义
	listenAddress := flag.String("web.listen-address", ":9188", "Address to listen on for web interface and telemetry.")
	mihomoAPI := flag.String("mihomo.api-url", "http://127.0.0.1:9097", "Mihomo API base URL.")
	mihomoToken := flag.String("mihomo.api-token", "", "Mihomo API secret token (if any).")
	scrapeInterval := flag.Duration("scrape.interval", 1*time.Second, "Interval at which to scrape Mihomo API.")
	latencyInterval := flag.Duration("latency.interval", 60*time.Second, "Interval at which to test proxy latency.")
	metricPrefix := flag.String("metric.prefix", "mihomo", "Prefix for all exported metrics.")
	enableTotalTraffic := flag.Bool("metrics.enable-total-traffic", true, "Enable accurate total traffic metrics from Mihomo API.")
	enableNodeAggregation := flag.Bool("metrics.enable-node-aggregation", true, "Enable connection metrics aggregated by outbound node.")
	enableDestinationAggregation := flag.Bool("metrics.enable-destination-aggregation", true, "Enable connection metrics aggregated by destination.")
	nodeGroups := flag.String("metrics.node-groups", "", "Comma-separated node-group mappings in label=proxy-group form.")
	flag.Parse()

	// 从环境变量加载配置，环境变量会覆盖命令行参数
	loadFlagsFromEnv()

	log.Println("Starting mihomo-prometheus-exporter...")
	log.Printf("Listening on %s", *listenAddress)
	log.Printf("Connecting to Mihomo API at %s", *mihomoAPI)

	// 创建 Mihomo 客户端
	client, err := NewMihomoClient(*mihomoAPI, *mihomoToken)
	if err != nil {
		log.Fatalf("Failed to create Mihomo client: %v", err)
	}
	nodeGroupMappings, err := parseNodeGroupMappings(*nodeGroups)
	if err != nil {
		log.Fatalf("Failed to parse node group mappings: %v", err)
	}

	// 创建并注册 Collector
	collector := NewMihomoCollector(client, *metricPrefix, *enableTotalTraffic, *enableNodeAggregation, *enableDestinationAggregation, nodeGroupMappings)
	prometheus.MustRegister(collector)

	// 创建一个带取消功能的 context 用于优雅关闭
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	// 在后台启动双轨异步更新器
	collector.StartMonitors(ctx, *scrapeInterval, *latencyInterval)

	// 设置 HTTP 服务器
	http.Handle("/metrics", promhttp.Handler())
	http.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		_, _ = w.Write([]byte(`<html>
             <head><title>Mihomo Exporter</title></head>
             <body>
             <h1>Mihomo Exporter</h1>
             <p><a href='/metrics'>Metrics</a></p>
             </body>
             </html>`))
	})

	server := &http.Server{Addr: *listenAddress}

	// 优雅关闭
	go func() {
		sigchan := make(chan os.Signal, 1)
		signal.Notify(sigchan, syscall.SIGINT, syscall.SIGTERM)
		<-sigchan
		log.Println("Shutdown signal received, gracefully shutting down...")
		cancel() // 通知更新器停止
		shutdownCtx, shutdownCancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer shutdownCancel()
		if err := server.Shutdown(shutdownCtx); err != nil {
			log.Fatalf("HTTP server shutdown failed: %v", err)
		}
	}()

	// 启动 HTTP 服务器
	if err := server.ListenAndServe(); err != http.ErrServerClosed {
		log.Fatalf("HTTP server ListenAndServe: %v", err)
	}

	log.Println("Exporter stopped.")
}
