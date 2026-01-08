# --- Build stage ---
FROM registry.access.redhat.com/ubi9/go-toolset:1.24 AS builder

USER root
COPY . /usr/src/sriov-network-device-plugin
WORKDIR /usr/src/sriov-network-device-plugin
RUN make clean && make build
USER 1001

# --- Final image ---
FROM registry.access.redhat.com/ubi9/ubi-minimal:9.6

LABEL io.k8s.display-name="SRIOV Network Device Plugin"
ENV PATH=/opt/nic/bin:/opt/nic/sbin:$PATH
RUN microdnf install -y pciutils-3.7.0  && microdnf clean all

COPY --from=builder /usr/src/sriov-network-device-plugin/build/sriovdp /usr/bin/
COPY ./images/entrypoint.sh /
WORKDIR /
ENTRYPOINT ["/entrypoint.sh"]
