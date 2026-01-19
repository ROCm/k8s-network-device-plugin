ARG AINIC_VER=1.117.5-a-56
# --- Build stage ---
FROM registry.access.redhat.com/ubi9/go-toolset:1.24 AS builder

USER root
COPY . /usr/src/sriov-network-device-plugin
WORKDIR /usr/src/sriov-network-device-plugin
RUN make clean && make build
USER 1001

# --- nicctl build stage ---
FROM registry.access.redhat.com/ubi9/ubi-minimal:9.6 AS nicctlbuilder
ARG AINIC_VER
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
RUN echo "${AINIC_VER}" > /etc/dnf/vars/amdainicver
ENV DIST=el9
RUN curl -o /etc/yum.repos.d/amdainic.repo \
    https://repo.radeon.com/amdainic/pensando/${DIST}/amdainic-${DIST}.repo
RUN NICCTL_PKG_VER="${AINIC_VER//-/.}" && \
    curl -L -o /tmp/dtc.rpm https://download.rockylinux.org/pub/rocky/9/AppStream/x86_64/os/Packages/d/dtc-1.6.0-7.el9.x86_64.rpm && \
    rpm -ivh --nodeps /tmp/dtc.rpm && \
    rm -f /tmp/dtc.rpm && \
    microdnf update -y && \
    microdnf install -y "nicctl-${NICCTL_PKG_VER}" && \
    rm -rf /var/cache/yum /var/cache/dnf && \
    microdnf clean all

# Export binaries and needed libs
RUN mkdir -p /export/bin /export/lib64 && \
    cp -v /usr/sbin/nicctl /export/bin/ && \
    cp -v /lib64/libpci* /export/lib64/

# --- Final image ---
FROM registry.access.redhat.com/ubi9/ubi-minimal:9.6

ARG AINIC_VER
LABEL io.k8s.display-name="SRIOV Network Device Plugin"
LABEL ainic.fw.version=${AINIC_VER}
ENV PATH=/opt/nic/bin:/opt/nic/sbin:$PATH

# Copy nicctl binary and its dependencies from nicctlbuilder stage FIRST
COPY --from=nicctlbuilder /export/bin/nicctl /usr/sbin/nicctl
COPY --from=nicctlbuilder /export/lib64/libpci* /lib64/

# Install base packages AFTER copying nicctl libs
RUN microdnf install -y \
    pciutils-3.7.0 \
    kmod-libs-28 \
    systemd-libs-252 \
    jq-1.6 \
    vim-minimal-2:8.2.2637 && \
    microdnf clean all

COPY --from=builder /usr/src/sriov-network-device-plugin/build/sriovdp /usr/bin/
COPY ./images/entrypoint.sh /
WORKDIR /
ENTRYPOINT ["/entrypoint.sh"]
