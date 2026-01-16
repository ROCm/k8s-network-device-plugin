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

package deviceconfig

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"os/exec"
	"strings"
	"sync"
	"time"

	"github.com/golang/glog"
	"github.com/prometheus/procfs"
)

const (
	configClientBinary        = "nicctl"
	configClientTimeoutInSecs = 20
	hypervisorCPUFlag         = "hypervisor"
)

var bareMetal = IsBareMetal()

type DevConfigClient struct {
	devIDtoIntfUUID map[string]string
	mu              sync.Mutex
}

func NewDevConfigClient() *DevConfigClient {
	client := &DevConfigClient{
		devIDtoIntfUUID: make(map[string]string),
	}
	return client
}

func (dc *DevConfigClient) Init() error {
	dc.mu.Lock()
	defer dc.mu.Unlock()
	devMap, err := dc.updateDevIDmap()
	if err != nil {
		err = fmt.Errorf("dev client init failed: %v", err)
		return err
	}
	dc.devIDtoIntfUUID = devMap
	return nil
}

func IsBareMetal() bool {
	// Device Configuration not supported in Hypervisor
	fs, err := procfs.NewDefaultFS()
	if err != nil {
		glog.Errorf("baremetal check, procfs failure: %v", err)
		return false
	}
	cpus, err := fs.CPUInfo()
	if err != nil {
		glog.Errorf("baremetal check, cpuinfo failure: %v", err)
		return false
	}
	for _, cpu := range cpus {
		for _, flag := range cpu.Flags {
			if flag == hypervisorCPUFlag {
				glog.Infof("baremetal check returned false, running in hypervisor")
				return false
			}
		}
	}
	glog.Infof("baremetal check returned true")
	return true
}

func IsDevConfigBinaryPresent() bool {
	if _, err := exec.LookPath(configClientBinary); err != nil {
		glog.Error("device config binary NOT present")
		return false
	}
	return true
}

func (dc *DevConfigClient) isDeviceConfigSupported() bool {
	// Device Configuration supported only on BareMetal and if DevConfig Binary present
	return bareMetal && IsDevConfigBinaryPresent()
}

func (dc *DevConfigClient) ConfigHwForDeviceIDs(deviceIDs []string) error {
	var err error
	if !dc.isDeviceConfigSupported() {
		glog.Infof("dev config skipped for %v, isBM %v\n", deviceIDs, bareMetal)
		return nil
	}
	var wg sync.WaitGroup
	setupFailure := false
	for _, id := range deviceIDs {
		wg.Add(1)
		go func(deviceID string, cfgFail *bool) {
			defer wg.Done()
			if err := dc.setupDevice(deviceID); err != nil {
				*cfgFail = true
				glog.Errorf("failed configuring deviceID %s: %v", deviceID, err)
			}
		}(id, &setupFailure)
	}
	wg.Wait()
	if setupFailure {
		err = fmt.Errorf("device client hit config failure")
	}
	return err
}

func (dc *DevConfigClient) setupDevice(deviceID string) error {
	intfUUID, err := dc.getUUID(deviceID)
	if err != nil {
		return err
	}

	glog.Infof("configuring devID %v, intf UUID %v", deviceID, intfUUID)
	cmd := fmt.Sprintf("nicctl clear rdma internal queue-pair --lif %s", intfUUID)
	cmdResp, err := dc.execWithContext(cmd, configClientTimeoutInSecs)
	if err != nil {
		err = fmt.Errorf("failed exec of cfg cmd %s: %v", cmd, err)
		glog.Errorf("%v", err)
		return err
	}

	matchStr := []byte(": Successful")
	respStr := strings.Trim(string(cmdResp), "\r\n")
	glog.Infof("dev config cmd: %v", cmd)
	glog.Infof("dev config resp: %v", respStr)
	if !bytes.Contains(cmdResp, matchStr) {
		err := fmt.Errorf("config failure for devID %v intfUUID %v", deviceID, intfUUID)
		glog.Errorf("%v", err)
		return err
	}
	glog.Infof("dev config status: Success, for devID %v intfUUID %v", deviceID, intfUUID)
	return nil
}

func (dc *DevConfigClient) getUUID(deviceID string) (string, error) {
	dc.mu.Lock()
	defer dc.mu.Unlock()

	intfUUID, ok := dc.devIDtoIntfUUID[deviceID]
	if !ok {
		devMap, err := dc.updateDevIDmap()
		if err != nil {
			return "", err
		}
		dc.devIDtoIntfUUID = devMap
		intfUUID, ok = dc.devIDtoIntfUUID[deviceID]
	}
	if !ok {
		err := fmt.Errorf("intf UUID not found for %v", deviceID)
		return "", err
	}
	return intfUUID, nil
}

func (dc *DevConfigClient) execWithContext(cmd string, timeoutPeriod time.Duration) ([]byte, error) {
	ctx, cancel := context.WithTimeout(context.Background(), timeoutPeriod*time.Second)
	defer cancel()

	command := exec.CommandContext(ctx, "/bin/sh", "-c", cmd) // bash ??
	return command.Output()
}

func (dc *DevConfigClient) updateDevIDmap() (map[string]string, error) {
	type Response struct {
		NIC []struct {
			ID  string `json:"id"`
			Lif []struct {
				ID        string `json:"id"`
				EthIntf   string `json:"ethernet_interface"`
				RoceIntf  string `json:"roce_interface"`
				EthBDF    string `json:"ethernet_controller_bdf"`
				IPAddrStr string `json:"ip_address"`
			} `json:"lif"`
		} `json:"nic"`
	}

	devMap := map[string]string{}

	if !dc.isDeviceConfigSupported() {
		glog.Infof("skipped DevIDmap update, isBM %v\n", bareMetal)
		return devMap, nil
	} else {
		glog.Infof("updating DevIDmap \n")
	}

	cmdResp, err := dc.execWithContext("nicctl show card device -j", configClientTimeoutInSecs)
	if err != nil {
		err = fmt.Errorf("failed to get device HW data: %v", err)
		glog.Errorf("%v", err)
		return devMap, err
	}
	var resp Response
	err = json.Unmarshal(cmdResp, &resp)
	if err != nil {
		err = fmt.Errorf("error unmarshalling device HW data: %v", err)
		glog.Errorf("%v", err)
		return devMap, err
	}

	for _, nic := range resp.NIC {
		for _, lif := range nic.Lif {
			devMap[lif.EthBDF] = lif.ID
		}
	}
	glog.Info("deviceID map update done")
	return devMap, nil
}
