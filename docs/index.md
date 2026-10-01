# AMD Network Device Plugin for Kubernetes

## Introduction

The **AMD Network Device Plugin for Kubernetes** enables Kubernetes clusters to discover, manage, and allocate advanced network devices—specifically **AMD Pollara AI NICs**. This plugin extends Kubernetes' native device management framework to support high-performance networking hardware, allowing pods and containers to directly access physical or virtual NICs with **low latency and high throughput**.

## Key Features

### Device Discovery & Management

* Automatically discovers supported network devices on cluster nodes
* Supports device grouping via configurable **selectors**
* User-configurable `resourceName`
* Detects kubelet restarts and automatically re-registers devices
* Extensible design to support additional device types in the future

### Resource Allocation

* Allocates network devices based on pod resource requests
* Prevents over-allocation of scarce network resources

### Health Monitoring

* Integrates with **AMD Device Metrics Exporter** for health checks
* Ensures unhealthy AI NICs are not scheduled for workloads
* Real-time health status updates to kubelet

## Compatibility

### Supported Hardware

| Hardware | Status |
|-----------|---------|
| AMD Pensando™ Pollara AI NIC | ✅ Supported |

### Version Compatibility Matrix

The following matrix summarizes supported NICs and the required AINIC firmware / tooling for each container image version.

| AINIC Firmware Version                                 | Image Version | Supported NICs | Supported Platforms                    |
| ------------------------------------------------------ | ------------- | -------------- | -------------------------------------- |
| N/A (host `nicctl`)                                    | `v1.0.0`      | Pollara 400    | Kubernetes 1.29+                       |
| `1.117.5-a-56`                                         | `v1.1.0`      | Pollara 400    | Kubernetes 1.29+                       |
| `1.117.5-a-56`<br>`1.117.5-a-77`                       | `v1.2.0`      | Pollara 400    | Kubernetes 1.29+                       |
| `1.117.5-a-77`<br>`1.117.5-a-147`<br>`1.117.5-a-196`   | `v1.2.1`      | Pollara 400    | Kubernetes 1.29+, OpenShift 4.21       |

## Prerequisites

* Kubernetes v1.29.0+
* Multus CNI meta-plugin
* Compatible CNI plugins (e.g., `host-device`)
* AMD Pollara AI NIC hardware

## Deployment

### Quick Start

The device plugin can be deployed using either DaemonSet or Helm:

#### DaemonSet Deployment

```bash
kubectl apply -f ./deployments/k8s-network-device-plugin-daemonset.yaml
```

#### Helm Deployment

```bash
helm install amd-network-device-plugin ./helm-charts-k8s
```

For detailed installation instructions, see the [Kubernetes (Helm) Installation Guide](installation/kubernetes-helm.md).

### Integration with AMD Network Operator

The AMD Network Device Plugin is also deployed as part of the AMD Network Operator for comprehensive network infrastructure management. See [AMD Network Operator Integration](installation/network-operator.md) for details.

## Advertised Resources

Once deployed, the device plugin discovers AMD AI NICs and advertises them to the kubelet using the following resource names:

* `amd.com/nic` - Physical Function (PF) network interfaces
* `amd.com/vnic` - Virtual Function (VF) network interfaces

## Documentation

* [Installation Guide](installation/kubernetes-helm.md)
* [AMD Network Operator Integration](installation/network-operator.md)
* [Developer Guide](contributing/developer-guide.md)
* [Release Notes](releasenotes.md)

## Support

For bugs and feature requests, please file an issue on our [GitHub Issues](https://github.com/ROCm/k8s-network-device-plugin/issues) page.

## Summary

The AMD Network Device Plugin for Kubernetes enables seamless discovery, health monitoring, and allocation of AMD Pollara AI NICs within Kubernetes clusters. By integrating with Kubernetes' device plugin framework and optional exporter-based health checks, it ensures efficient, reliable, and scalable access to high-performance networking resources for AI and accelerated workloads.
