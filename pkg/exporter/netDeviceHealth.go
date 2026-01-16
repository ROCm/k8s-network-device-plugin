/*
Copyright (c) Advanced Micro Devices, Inc. All rights reserved.

Licensed under the Apache License, Version 2.0 (the \"License\");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

     http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an \"AS IS\" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/

package exporter

import (
	"context"
	"fmt"
	"os"
	"strings"
	"sync"
	"time"

	"github.com/golang/glog"
	"google.golang.org/grpc"
	"google.golang.org/grpc/credentials/insecure"
	"google.golang.org/protobuf/types/known/emptypb"
	pluginapi "k8s.io/kubelet/pkg/apis/deviceplugin/v1beta1"

	"github.com/k8snetworkplumbingwg/sriov-network-device-plugin/pkg/exporter/nicmetricssvc"
)

const (
	healthSocket  = "/var/lib/amd-metrics-exporter/amdnic_device_metrics_exporter_grpc.socket"
	maxRetries    = 5 // max connection retries
	retryInterval = 1 * time.Second
)

// MetricsClient holds gRPC client and connection
type MetricsClient struct {
	client nicmetricssvc.MetricsServiceClient
	conn   *grpc.ClientConn
	mu     sync.Mutex
}

// NewMetricsClient creates a new instance of MetricsClient.
func NewMetricsClient() *MetricsClient {
	return &MetricsClient{}
}

// UpdateNICsHealth updates the health of the NICs in the device list
// based on the health service if available, otherwise sets to default health.
func (mc *MetricsClient) UpdateDevicesHealth(devs []*pluginapi.Device, defaultHealth string) {
	var hasHealthSvc = false
	nicHealthMap, err := mc.getNICHealth()
	if err == nil {
		hasHealthSvc = true
	}

	for i := 0; i < len(devs); i++ {
		if !hasHealthSvc {
			devs[i].Health = defaultHealth
		} else {
			// only use if we have the device id entry
			if nicHealthState, ok := nicHealthMap[devs[i].ID]; ok {
				devs[i].Health = nicHealthState
			} else {
				devs[i].Health = defaultHealth
			}
		}
	}
}

// Close closes the gRPC connection. Call this when your application shuts down.
func (mc *MetricsClient) Close() {
	mc.mu.Lock()
	defer mc.mu.Unlock()
	if mc.conn != nil {
		glog.Info("closing gRPC connection for metrics client.")
		if err := mc.conn.Close(); err != nil {
			glog.Errorf("error closing gRPC connection: %v", err)
		}
		mc.conn = nil
		mc.client = nil
	}
}

// getMetricsClient returns the singleton instance of the MetricsClient.
// It initializes the client on the first call.
func (mc *MetricsClient) getMetricsClient() (nicmetricssvc.MetricsServiceClient, error) {
	mc.mu.Lock()
	defer mc.mu.Unlock()

	if mc.conn == nil || mc.client == nil {
		glog.Warning("metrics client not connected. Attempting to connect...")
		if err := mc.connect(); err != nil {
			return nil, fmt.Errorf("failed to connect to metrics service: %w", err)
		}
	}
	return mc.client, nil
}

// connect establishes the gRPC connection and client.
// It can be called multiple times; it will close existing connections first.
func (mc *MetricsClient) connect() error {
	if _, err := os.Stat(healthSocket); err != nil {
		return fmt.Errorf("health socket %s not found: %w", healthSocket, err)
	}
	healthSvcAddress := fmt.Sprintf("unix://%v", healthSocket)

	// close existing connection if any
	if mc.conn != nil {
		glog.Info("closing existing gRPC connection to metrics service.")
		if err := mc.conn.Close(); err != nil {
			glog.Errorf("error closing existing gRPC connection: %v", err)
		}
		mc.conn = nil
		mc.client = nil
	}

	conn, err := grpc.NewClient(healthSvcAddress,
		grpc.WithTransportCredentials(insecure.NewCredentials()))
	if err != nil {
		return fmt.Errorf("error opening client metrics svc: %w", err)
	}

	client := nicmetricssvc.NewMetricsServiceClient(conn)

	mc.conn = conn
	mc.client = client
	glog.Infof("successfully connected to metrics service at %s", healthSocket)
	return nil
}

// getNICHealth returns device id map with health state if the metrics service
// is available else returns error
func (mc *MetricsClient) getNICHealth() (hMap map[string]string, err error) {
	for i := 0; i < maxRetries; i++ {
		client, err := mc.getMetricsClient() // will reconnect if conn == nil
		if err != nil {
			glog.Errorf("attempt %d/%d: error getting metrics client: %v. retrying in %vs...", i+1, maxRetries, err, retryInterval)
			time.Sleep(retryInterval)
			continue // try again
		}

		resp, rpcErr := client.List(context.Background(), &emptypb.Empty{})
		if rpcErr != nil {
			glog.Errorf("attempt %d/%d: error getting health info: %v. retrying in %vs...", i+1, maxRetries, rpcErr, retryInterval)
			mc.mu.Lock()
			if mc.conn != nil {
				glog.Warning("marking connection as broken. closing existing gRPC connection.")
				_ = mc.conn.Close()
			}
			mc.conn = nil // will trigger reconnection on next call
			mc.client = nil
			mc.mu.Unlock()

			time.Sleep(retryInterval)
			continue
		}

		// call was successful
		hMap = make(map[string]string)
		for _, nic := range resp.NICState {
			if strings.EqualFold(nic.Health, strings.ToLower(pluginapi.Healthy)) {
				hMap[nic.Device] = pluginapi.Healthy
			} else {
				hMap[nic.Device] = pluginapi.Unhealthy
			}
		}
		return hMap, nil
	}

	return nil, fmt.Errorf("failed to get NIC health after %d attempts", maxRetries)
}
