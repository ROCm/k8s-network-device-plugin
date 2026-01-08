# network-device-plugin-charts

![Version: v0.0.1](https://img.shields.io/badge/Version-v0.0.1-informational?style=flat-square) ![Type: application](https://img.shields.io/badge/Type-application-informational?style=flat-square) ![AppVersion: v0.0.1](https://img.shields.io/badge/AppVersion-v0.0.1-informational?style=flat-square)

A Helm chart for AMD Network Device Plugin

**Homepage:** <https://github.com/ROCm/k8s-network-device-plugin>

## Maintainers

| Name | Email | Url |
| ---- | ------ | --- |
| Sundara Gurunathan | <Sundaramurthy.Gurunathan@amd.com> |  |
| Yuvarani Shankar | <Yuvarani.Shankar@amd.com> |  |
| Shrey Ajmera | <Shrey.Ajmera@amd.com> |  |

## Source Code

* <https://github.com/ROCm/k8s-network-device-plugin>

## Requirements

Kubernetes: `>= 1.29.0-0`

## Values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| annotations | object | `{}` | Additional annotations to add to the DaemonSet pods |
| configMap | object | `{"resourceList":[{"disableDeviceConfig":false,"enableExporterHealthCheck":true,"resourceName":"nic","resourcePrefix":"amd.com","selectors":{"devices":["1002"],"drivers":["ionic"],"excludeTopology":true,"isRdma":true,"vendors":["1dd8"]}},{"disableDeviceConfig":false,"enableExporterHealthCheck":true,"resourceName":"vnic","resourcePrefix":"amd.com","selectors":{"devices":["1003"],"drivers":["ionic"],"excludeTopology":true,"isRdma":true,"vendors":["1dd8"]}}]}` | List of configmap objects which provide info on device resources |
| image | object | `{"initContainerImage":"busybox:1.36","pullPolicy":"IfNotPresent","repository":"registry.test.pensando.io:5000/k8s-network-device-plugin","tag":"v0.0.1"}` | Container image configuration |
| image.initContainerImage | string | `"busybox:1.36"` | initContainer image |
| image.pullPolicy | string | `"IfNotPresent"` | Container image pull policy |
| image.repository | string | `"docker.io/rocm/k8s-network-device-plugin"` | Container image repository |
| image.tag | string | `"v0.0.1"` | Container image tag |
| imagePullSecrets | list | `[]` | Image pull secrets for private registries |
| nodeSelector | object | `{}` | Node selector to constrain pods to specific nodes |
| resources | object | `{}` | Resource limits and requests for the containers |
| securityContext | object | `{"privileged":true}` | Security context for the DaemonSet pods |
| securityContext.privileged | bool | `true` | Run containers in privileged mode (required for accessing host network interfaces) |
| serviceAccountName | string | `""` | Service account name to use. If not set, defaults to Release name |
| tolerations | list | `[{"key":"CriticalAddonsOnly","operator":"Exists"}]` | Tolerations for pod assignment to nodes with taints |
| updateStrategy | object | `{"rollingUpdate":{"maxUnavailable":1},"type":"RollingUpdate"}` | Update strategy for the DaemonSet |
| updateStrategy.rollingUpdate.maxUnavailable | int | `1` | Maximum number of pods that can be unavailable during update |
| updateStrategy.type | string | `"RollingUpdate"` | Type of update strategy (RollingUpdate or OnDelete) |

