# AMD Network Device Plugin for Kubernetes

## Introduction

The **AMD Network Device Plugin for Kubernetes** enables Kubernetes clusters to discover, manage, and allocate advanced network devices—specifically **AMD Pollara AI NICs**. This plugin extends Kubernetes’ native device management framework to support high-performance networking hardware, allowing pods and containers to directly access physical or virtual NICs with **low latency and high throughput**.

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

## Deployment

The device plugin must run on all nodes equipped with an AMD AI NIC. The recommended deployment method is a **Kubernetes DaemonSet**, which ensures one instance of the plugin runs on each eligible node.

A pre-built Docker image is available on DockerHub:

👉 [https://hub.docker.com/r/rocm/k8s-network-device-plugin](https://hub.docker.com/r/rocm/k8s-network-device-plugin)

This repository also includes a pre-defined DaemonSet manifest:

```bash
kubectl apply -f ./deployments/k8s-network-device-plugin-daemonset.yaml
```

### Using Helm

You can also deploy the device plugin using Helm. A pre-built Helm chart is available at:

```text
./helm-charts-k8s
```

Once deployed, the device plugin discovers AMD AI NICs and advertises them to the kubelet using the following resource names:

* `amd.com/nic`
* `amd.com/vnic`

## Health Checks

The device plugin supports optional health monitoring through the **AMD Device Metrics Exporter**.

The configuration knob `enableExporterHealthCheck` enables or disables health checks for reported devices. When enabled, the plugin receives health updates from the [AMD Device Metrics Exporter](https://github.com/ROCm/device-metrics-exporter) and updates kubelet accordingly. This ensures that **unhealthy AI NICs are not scheduled** for workloads.

### Example Configuration (Exporter-Based Health Checks)

```json
{
  "resourceList": [
    {
      "resourceName": "nic",
      "resourcePrefix": "amd.com",
      "enableExporterHealthCheck": true,
      "selectors": {
        "vendors": ["1dd8"],
        "devices": ["1002"],
        "drivers": ["ionic"],
        "excludeTopology": true,
        "isRdma": true
      }
    }
  ]
}
```

## Contribution
We welcome contributions from the community! Whether you're fixing bugs, adding features, or improving documentation, your help is appreciated. Please refer to the [Developer Guide](./docs/contributing/developer-guide.md) for details on how to get started.

## Summary
The AMD Network Device Plugin for Kubernetes enables seamless discovery, health monitoring, and allocation of AMD Pollara AI NICs within Kubernetes clusters. By integrating with Kubernetes’ device plugin framework and optional exporter-based health checks, it ensures efficient, reliable, and scalable access to high-performance networking resources for AI and accelerated workloads.