/*
 * SPDX-FileCopyrightText: Copyright (c) 2022 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
 * SPDX-License-Identifier: Apache-2.0
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

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

package devices_test

import (
	"github.com/jaypipes/ghw"
	. "github.com/onsi/ginkgo"
	. "github.com/onsi/gomega"
	"github.com/stretchr/testify/mock"
	nl "github.com/vishvananda/netlink"

	"github.com/k8snetworkplumbingwg/sriov-network-device-plugin/pkg/devices"
	"github.com/k8snetworkplumbingwg/sriov-network-device-plugin/pkg/types"
	"github.com/k8snetworkplumbingwg/sriov-network-device-plugin/pkg/utils"
	"github.com/k8snetworkplumbingwg/sriov-network-device-plugin/pkg/utils/mocks"
)

var _ = Describe("Devices", func() {
	Describe("GenPciDevice", func() {
		Context("Create new GenPciDevice", func() {
			It("should populate fields", func() {
				pciAddr := "0000:00:00.1"
				in := &ghw.PCIDevice{Address: pciAddr}
				dev, err := devices.NewGenPciDevice(in)

				Expect(dev).NotTo(BeNil())
				Expect(dev.GetPciAddr()).To(Equal(pciAddr))
				Expect(err).NotTo(HaveOccurred())
			})
		})
	})
	Describe("GenNetDevice", func() {
		Context("Create new GenNetDevice for PciNetDeviceType", func() {
			It("should populate fields", func() {
				fs := &utils.FakeFilesystem{
					Dirs: []string{
						"sys/bus/pci/devices/0000:00:00.0/net/ens1f0",
						"sys/bus/pci/devices/0000:00:00.1/net/fakeIfName",
					},
					Symlinks: map[string]string{
						"sys/bus/pci/devices/0000:00:00.1/physfn":  "../0000:00:00.0",
						"sys/bus/pci/devices/0000:00:00.0/virtfn0": "../0000:00:00.1",
					},
				}
				defer fs.Use()()
				utils.SetDefaultMockNetlinkProvider()

				pciAddr := "0000:00:00.1"
				dev, err := devices.NewGenNetDevice(pciAddr, types.NetDeviceType, true)

				Expect(err).NotTo(HaveOccurred())
				Expect(dev).NotTo(BeNil())
				Expect(dev.GetPfNetName()).To(Equal("ens1f0"))
				Expect(dev.GetPfPciAddr()).To(Equal("0000:00:00.0"))
				Expect(dev.GetNetName()).To(Equal("fakeIfName"))
				Expect(dev.GetLinkSpeed()).To(Equal(""))
				Expect(dev.GetLinkType()).To(Equal("fakeLinkType"))
				Expect(dev.GetFuncID()).To(Equal(0))
				Expect(dev.IsRdma()).To(Equal(true))
			})
			It("device's PF name is not available", func() {
				fs := &utils.FakeFilesystem{
					Dirs: []string{
						"sys/bus/pci/devices/0000:00:00.1",
						"sys/bus/pci/devices/0000:00:00.0/net",
					},
					Symlinks: map[string]string{
						"sys/bus/pci/devices/0000:00:00.1/physfn":  "../0000:00:00.0",
						"sys/bus/pci/devices/0000:00:00.0/virtfn0": "../0000:00:00.1",
					},
				}
				defer fs.Use()()
				utils.SetDefaultMockNetlinkProvider()

				pciAddr := "0000:00:00.1"
				dev, err := devices.NewGenNetDevice(pciAddr, types.NetDeviceType, false)

				Expect(err).NotTo(HaveOccurred())
				Expect(dev).NotTo(BeNil())
				Expect(dev.GetPfNetName()).To(Equal(""))
			})
			It("should use PF linkType if own ifName is not available", func() {
				fs := &utils.FakeFilesystem{
					Dirs: []string{
						"sys/bus/pci/devices/0000:00:00.0/net/ens1f0",
						"sys/bus/pci/devices/0000:00:00.1/net/",
					},
					Symlinks: map[string]string{
						"sys/bus/pci/devices/0000:00:00.1/physfn":  "../0000:00:00.0",
						"sys/bus/pci/devices/0000:00:00.0/virtfn0": "../0000:00:00.1",
					},
				}
				defer fs.Use()()
				testMockProvider := mocks.NetlinkProvider{}

				testMockProvider.
					On("GetLinkAttrs", "fakeIfName").
					Return(&nl.LinkAttrs{EncapType: ""}, nil)
				testMockProvider.
					On("GetLinkAttrs", "ens1f0").
					Return(&nl.LinkAttrs{EncapType: "pfLinkType"}, nil)
				testMockProvider.
					On("GetDevLinkDeviceEswitchAttrs", mock.AnythingOfType("string")).
					Return(&nl.DevlinkDevEswitchAttr{Mode: "fakeMode"}, nil)
				testMockProvider.
					On("GetIPv4RouteList", mock.AnythingOfType("string")).
					Return([]nl.Route{{Dst: nil}}, nil)
				testMockProvider.
					On("DevlinkGetDeviceInfoByNameAsMap", mock.AnythingOfType("string"), mock.AnythingOfType("string")).
					Return(map[string]string{"someKey": "someValue"}, nil)
				utils.SetNetlinkProviderInst(&testMockProvider)

				pciAddr := "0000:00:00.1"
				dev, err := devices.NewGenNetDevice(pciAddr, types.NetDeviceType, true)

				Expect(err).NotTo(HaveOccurred())
				Expect(dev).NotTo(BeNil())
				Expect(dev.GetPfNetName()).To(Equal("ens1f0"))
				Expect(dev.GetPfPciAddr()).To(Equal("0000:00:00.0"))
				Expect(dev.GetNetName()).To(Equal(""))
				Expect(dev.GetLinkType()).To(Equal("pfLinkType"))
			})
		})
	})
})
