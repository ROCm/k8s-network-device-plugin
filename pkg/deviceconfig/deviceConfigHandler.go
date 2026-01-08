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
