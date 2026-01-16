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
	"fmt"

	"github.com/golang/glog"
)

type DevConfigInterface interface {
	Init() error
	// Returns true if configuration of device is supported
	isDeviceConfigSupported() bool
	// Setup device HW before allocating to a workload
	ConfigHwForDeviceIDs([]string) error
}

type DevConfigHandler struct {
	clients []DevConfigInterface
}

func NewDevConfigHandler() *DevConfigHandler {
	hdlr := DevConfigHandler{
		clients: []DevConfigInterface{},
	}
	return &hdlr
}

func (dh *DevConfigHandler) RegisterDevClient(client DevConfigInterface) {
	glog.Infof("registering device HW Client %v, isBM %v", client, bareMetal)
	dh.clients = append(dh.clients, client)
}

func (dh *DevConfigHandler) SetupDeviceHw(deviceIDs []string) error {
	var ret error
	for _, client := range dh.clients {
		err := client.ConfigHwForDeviceIDs(deviceIDs)
		if err != nil {
			ret = err
		}
	}
	return ret
}

func (dh *DevConfigHandler) InitDeviceClients() error {
	var ret error
	for _, client := range dh.clients {
		err := client.Init()
		if err != nil {
			ret = fmt.Errorf("%s: %v", ret, err)
		}
	}
	return ret
}
