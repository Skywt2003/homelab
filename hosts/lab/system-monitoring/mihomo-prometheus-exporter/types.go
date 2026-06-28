// types.go
package main

// Traffic 对应 /traffic API 的响应
type Traffic struct {
	Up   int64 `json:"up"`
	Down int64 `json:"down"`
}

// ConnectionMetadata 对应连接元数据
type ConnectionMetadata struct {
	Network         string `json:"network"`
	Type            string `json:"type"`
	SourceIP        string `json:"sourceIP"`
	DestinationIP   string `json:"destinationIP"`
	SourcePort      string `json:"sourcePort"`
	DestinationPort string `json:"destinationPort"`
	Host            string `json:"host"` // 关键：目标域名
	DNSMode         string `json:"dnsMode"`
	ProcessPath     string `json:"processPath"`
}

// Connection 对应 /connections API 返回的单个连接信息
type Connection struct {
	ID          string             `json:"id"`
	Metadata    ConnectionMetadata `json:"metadata"`
	Upload      int64              `json:"upload"`
	Download    int64              `json:"download"`
	Start       string             `json:"start"`
	Chains      []string           `json:"chains"` // 关键：经过的节点链
	Rule        string             `json:"rule"`
	RulePayload string             `json:"rulePayload"`
}

// ConnectionsResponse 对应 /connections API 的完整响应
type ConnectionsResponse struct {
	DownloadTotal int64        `json:"downloadTotal"`
	UploadTotal   int64        `json:"uploadTotal"`
	Connections   []Connection `json:"connections"`
}

// ProxyInfo 对应 /proxies API 返回的代理信息
type ProxyInfo struct {
	Name string   `json:"name"`
	Type string   `json:"type"`
	Now  string   `json:"now,omitempty"` // for selectors
	All  []string `json:"all,omitempty"` // for selectors
}

// ProxiesResponse 对应 /proxies API 的完整响应
type ProxiesResponse struct {
	Proxies map[string]ProxyInfo `json:"proxies"`
}

// DelayInfo 对应 /proxies/{name}/delay API 的响应
type DelayInfo struct {
	Delay int `json:"delay"`
}
