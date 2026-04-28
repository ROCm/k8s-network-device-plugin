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

## Compatibility Matrix

The following matrix summarizes supported NICs and the required AINIC firmware / tooling for each container image version.

| AINIC Firmware Version           | Image Version | Supported NICs |
| ---------------------------------| ------------- | -------------- |
| N/A (host `nicctl`)              | `v1.0.0`      | Pollara 400    |
| `1.117.5-a-56`                   | `v1.1.0`      | Pollara 400    |
| `1.117.5-a-56`<br>`1.117.5-a-77` | `v1.2.0`      | Pollara 400    |

## Deployment

### Prerequisites

A compatible CNI meta-plugin installation is required for the Device Plugin to obtain the allocated PF/VF device ID in order to configure it.

#### Install Multus

Please refer to the [Multus Quickstart Installation Guide](https://github.com/k8snetworkplumbingwg/multus-cni/blob/master/docs/quickstart.md) to install Multus.

#### Network Object CRDs

Multus uses Custom Resource Definitions (CRDs) for defining additional network attachments. These network attachment CRDs follow the standards defined by the [K8s Network Plumbing Working Group (NPWG)](https://github.com/k8snetworkplumbingwg). Please refer to the [Multus documentation](https://github.com/k8snetworkplumbingwg/multus-cni/blob/master/docs/how-to-use.md) for more information.

#### Create Network Attachment Definition (NAD)

Create the NetworkAttachmentDefinition in the same namespace as the workloads that will use it (replace `<workload-namespace>` with your target namespace):

```bash
kubectl create -n <workload-namespace> -f deployments/host-device-nad.yaml
```

Please ensure that the CNI plugin specified in the NAD (`host-device` in this case) is installed and available on the cluster nodes. The `host-device` CNI plugin is responsible for configuring the allocated network devices within the pod's network namespace.

Here is a quick command that you can run on the cluster nodes to install the CNI plugins:

```bash
docker run -d --name cni-plugins -v /opt/cni/bin:/host/opt/cni/bin docker.io/rocm/k8s-cni-plugins:v1.1.0
```

To stop and remove the container:

```bash
docker stop cni-plugins && docker rm cni-plugins
```

### Deploy the Device Plugin

The device plugin must run on all nodes equipped with an AMD AI NIC. The recommended deployment method is a **Kubernetes DaemonSet**, which ensures one instance of the plugin runs on each eligible node.

A pre-built Docker image is available on DockerHub:

👉 [https://hub.docker.com/r/rocm/k8s-network-device-plugin](https://hub.docker.com/r/rocm/k8s-network-device-plugin)

This repository also includes a pre-defined DaemonSet manifest:

```bash
kubectl apply -f ./deployments/k8s-network-device-plugin-daemonset.yaml
```

### Using Helm

You can also deploy the device plugin using Helm. Add the AMD Helm repository and install the chart:

```bash
helm repo add rocm-network-dp https://rocm.github.io/k8s-network-device-plugin
helm repo update
helm install amd-network-device-plugin rocm-network-dp/network-device-plugin-charts \
  --namespace kube-amd-network \
  --create-namespace \
  --version v1.2.0
```

For detailed installation instructions and configuration options, refer to the [Helm Installation Guide](./docs/installation/kubernetes-helm.md).

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
      "excludeTopology": false,
      "selectors": {
        "vendors": ["1dd8"],
        "devices": ["1002"],
        "drivers": ["ionic"],
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
