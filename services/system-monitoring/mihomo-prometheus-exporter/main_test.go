package main

import "testing"

func TestParseNodeGroupMappings(t *testing.T) {
	mappings, err := parseNodeGroupMappings("airport=AIRPORT,self_hosted=SELF-HOSTED")
	if err != nil {
		t.Fatalf("parseNodeGroupMappings returned error: %v", err)
	}
	if len(mappings) != 2 {
		t.Fatalf("got %d mappings, want 2", len(mappings))
	}
	if mappings[0].Label != "airport" || mappings[0].ProxyGroup != "AIRPORT" {
		t.Fatalf("unexpected first mapping: %+v", mappings[0])
	}
	if mappings[1].Label != "self_hosted" || mappings[1].ProxyGroup != "SELF-HOSTED" {
		t.Fatalf("unexpected second mapping: %+v", mappings[1])
	}
}

func TestParseNodeGroupMappingsRejectsInvalidValues(t *testing.T) {
	for _, value := range []string{"airport", "=AIRPORT", "airport=", "airport=AIRPORT,airport=OTHER"} {
		if _, err := parseNodeGroupMappings(value); err == nil {
			t.Fatalf("parseNodeGroupMappings(%q) unexpectedly succeeded", value)
		}
	}
}

func TestUpdateNodeGroups(t *testing.T) {
	collector := NewMihomoCollector(nil, "mihomo", true, true, false, []NodeGroupMapping{
		{Label: "airport", ProxyGroup: "AIRPORT"},
		{Label: "self_hosted", ProxyGroup: "SELF-HOSTED"},
	})
	proxies := &ProxiesResponse{Proxies: map[string]ProxyInfo{
		"AIRPORT":     {Type: "Selector", All: []string{"Airport A", "Airport B", "Traffic: 42 GB", "Expire: tomorrow"}},
		"SELF-HOSTED": {Type: "Selector", All: []string{"SG-AnyTLS"}},
	}}

	collector.updateNodeGroupsLocked(proxies)
	if got := collector.nodeGroupLocked("Airport A"); got != "airport" {
		t.Fatalf("Airport A group = %q, want airport", got)
	}
	if got := collector.nodeGroupLocked("SG-AnyTLS"); got != "self_hosted" {
		t.Fatalf("SG-AnyTLS group = %q, want self_hosted", got)
	}
	if got := collector.nodeGroupLocked("PASS"); got != "unclassified" {
		t.Fatalf("PASS group = %q, want unclassified", got)
	}
	if got := collector.nodeGroupLocked("Traffic: 42 GB"); got != "unclassified" {
		t.Fatalf("subscription metadata group = %q, want unclassified", got)
	}
}

func TestExcludedMonitoringProxy(t *testing.T) {
	for _, name := range []string{"PASS", "PASS-RULE", "REJECT-DROP", "COMPATIBLE", "Traffic: 42 GB", "Expire: tomorrow"} {
		if !isExcludedMonitoringProxy(name) {
			t.Fatalf("%q should be excluded", name)
		}
	}
	if isExcludedMonitoringProxy("SG-AnyTLS") {
		t.Fatal("SG-AnyTLS should not be excluded")
	}
}
