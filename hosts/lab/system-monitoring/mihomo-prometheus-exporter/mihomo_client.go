// mihomo_client.go
package main

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/url"
	"time"
)

// MihomoClient 是与 Mihomo API 交互的客户端
type MihomoClient struct {
	baseURL    string
	apiToken   string
	httpClient *http.Client
}

// NewMihomoClient 创建一个新的客户端实例
func NewMihomoClient(apiURL, apiToken string) (*MihomoClient, error) {
	_, err := url.Parse(apiURL)
	if err != nil {
		return nil, fmt.Errorf("invalid mihomo api url: %w", err)
	}

	return &MihomoClient{
		baseURL:  apiURL,
		apiToken: apiToken,
		httpClient: &http.Client{
			Timeout: 10 * time.Second,
		},
	}, nil
}

// makeRequest 创建并执行一个带认证的 HTTP 请求
func (c *MihomoClient) makeRequest(ctx context.Context, endpoint string, target interface{}) error {
	req, err := http.NewRequestWithContext(ctx, "GET", c.baseURL+endpoint, nil)
	if err != nil {
		return err
	}

	if c.apiToken != "" {
		req.Header.Set("Authorization", "Bearer "+c.apiToken)
	}

	resp, err := c.httpClient.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("api request failed with status: %s", resp.Status)
	}

	return json.NewDecoder(resp.Body).Decode(target)
}

// GetConnections 获取当前所有连接的信息
func (c *MihomoClient) GetConnections(ctx context.Context) (*ConnectionsResponse, error) {
	var connections ConnectionsResponse
	err := c.makeRequest(ctx, "/connections", &connections)
	return &connections, err
}

// GetTraffic 获取实时的流量速率
func (c *MihomoClient) GetTraffic(ctx context.Context) (*Traffic, error) {
	// /traffic 是一个流式端点，我们需要特殊处理：只读取第一个JSON对象然后关闭连接。
	// 因此不能使用通用的 makeRequest 方法。
	req, err := http.NewRequestWithContext(ctx, "GET", c.baseURL+"/traffic", nil)
	if err != nil {
		return nil, err
	}

	if c.apiToken != "" {
		req.Header.Set("Authorization", "Bearer "+c.apiToken)
	}

	resp, err := c.httpClient.Do(req)
	if err != nil {
		return nil, err
	}
	// 关键：确保在函数返回时立即关闭连接，终止流。
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("api request to /traffic failed with status: %s", resp.Status)
	}

	var traffic Traffic
	// 从流中解码第一个 JSON 对象
	if err := json.NewDecoder(resp.Body).Decode(&traffic); err != nil {
		return nil, fmt.Errorf("failed to decode traffic json from stream: %w", err)
	}
	return &traffic, nil
}

// GetProxies 获取所有代理节点的信息
func (c *MihomoClient) GetProxies(ctx context.Context) (*ProxiesResponse, error) {
	var proxies ProxiesResponse
	err := c.makeRequest(ctx, "/proxies", &proxies)
	return &proxies, err
}

// GetProxyDelay 测试指定代理节点的延迟
func (c *MihomoClient) GetProxyDelay(ctx context.Context, proxyName string) (*DelayInfo, error) {
	// 延迟测试的超时时间应该较短
	testURL := "https://www.gstatic.com/generate_204"
	timeout := 5000 // 5秒

	endpoint := fmt.Sprintf("/proxies/%s/delay?url=%s&timeout=%d", url.PathEscape(proxyName), url.QueryEscape(testURL), timeout)
	var delay DelayInfo
	err := c.makeRequest(ctx, endpoint, &delay)
	return &delay, err
}
