ARG AINIC_VERSIONS="1.117.5-a-77,1.117.5-a-147"
ARG BOOTSTRAP_VERSION=""
# If BOOTSTRAP_VERSION is empty, defaults to the last version in AINIC_VERSIONS

# --- Build stage ---
# Keep in sync with GOLANG_VERSION in dev.env; `make check-golang-version`
# verifies this. The default is used when building without build-args.
ARG GOLANG_VERSION=1.25.8
FROM registry.access.redhat.com/ubi9/go-toolset:${GOLANG_VERSION} AS builder
WORKDIR /usr/src/sriov-network-device-plugin
# Cache Go modules layer separately
COPY go.mod go.sum ./
RUN go mod download
# Copy source and build
COPY . .
RUN git config --global --add safe.directory /usr/src/sriov-network-device-plugin && \
    make clean && make build

# --- nicctl build stage ---
FROM registry.access.redhat.com/ubi9/ubi-minimal:9.6 AS nicctlbuilder
ARG AINIC_VERSIONS
ARG BOOTSTRAP_VERSION
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
ENV DIST=el9

# Build nicctl versions (single: direct install, multi: bootstrap + compressed)
RUN mkdir -p /export/bin /export/lib64 /export/nicctl-versions && \
    IFS=',' read -ra VERSIONS <<< "${AINIC_VERSIONS}" && \
    COUNT="${#VERSIONS[@]}" && \
    if [[ "$COUNT" -eq 0 ]]; then echo "ERROR: AINIC_VERSIONS empty" && exit 1; fi && \
    if [[ "$COUNT" -gt 5 ]]; then echo "ERROR: Max 5 versions, got ${COUNT}" && exit 1; fi && \
    BOOTSTRAP="${BOOTSTRAP_VERSION:-${VERSIONS[-1]}}" && \
    if [[ -n "$BOOTSTRAP_VERSION" ]]; then \
        FOUND=false; for v in "${VERSIONS[@]}"; do [[ "$v" == "$BOOTSTRAP" ]] && FOUND=true; done; \
        if [[ "$FOUND" != "true" ]]; then echo "ERROR: BOOTSTRAP_VERSION '$BOOTSTRAP' not in AINIC_VERSIONS" && exit 1; fi; \
    fi && \
    echo "$BOOTSTRAP" > /etc/dnf/vars/amdainicver && \
    curl --proto '=https' --tlsv1.2 -fsSL -o /etc/yum.repos.d/amdainic.repo "https://repo.radeon.com/amdainic/pensando/${DIST}/amdainic-${DIST}.repo" && \
    curl --proto '=https' --tlsv1.2 -fsSL -o /etc/pki/rpm-gpg/RPM-GPG-KEY-Rocky-9 https://download.rockylinux.org/pub/rocky/RPM-GPG-KEY-Rocky-9 && \
    rpmkeys --import /etc/pki/rpm-gpg/RPM-GPG-KEY-Rocky-9 && \
    curl --proto '=https' --tlsv1.2 -fsSL -o /tmp/dtc.rpm https://download.rockylinux.org/pub/rocky/9/AppStream/x86_64/os/Packages/d/dtc-1.6.0-7.el9.x86_64.rpm && \
    rpm --checksig /tmp/dtc.rpm && \
    rpm -ivh --nodeps /tmp/dtc.rpm && rm -f /tmp/dtc.rpm && \
    microdnf update -y && \
    microdnf install -y binutils-2.35.2 xz-5.2.5 && microdnf clean all && \
    echo "$BOOTSTRAP" > /export/bootstrap-version.txt && \
    if [[ "$COUNT" -eq 1 ]]; then \
        echo "Single version: ${BOOTSTRAP}"; \
        microdnf install -y "nicctl-${BOOTSTRAP//-/.}" && \
        strip /usr/sbin/nicctl -o /export/bin/nicctl; \
    else \
        echo "Multi-version build (bootstrap: $BOOTSTRAP)"; \
        microdnf install -y "nicctl-${BOOTSTRAP//-/.}" && \
        strip /usr/sbin/nicctl -o /export/bin/nicctl-bootstrap && \
        microdnf remove -y "nicctl-${BOOTSTRAP//-/.}"; \
        for ver in "${VERSIONS[@]}"; do \
            [[ "$ver" == "$BOOTSTRAP" ]] && continue; \
            echo "Compressing: ${ver}"; \
            echo "$ver" > /etc/dnf/vars/amdainicver && \
            microdnf install -y "nicctl-${ver//-/.}" && \
            strip /usr/sbin/nicctl -o /tmp/nicctl && \
            xz -9 -c /tmp/nicctl > "/export/nicctl-versions/nicctl-${ver}.xz" && \
            microdnf remove -y "nicctl-${ver//-/.}"; \
        done; \
    fi && \
    cp /lib64/libpci* /export/lib64/ && \
    microdnf clean all && rm -rf /var/cache/yum /var/cache/dnf

# --- Final image ---
FROM registry.access.redhat.com/ubi9/ubi-minimal:9.6
ARG AINIC_VERSIONS
LABEL io.k8s.display-name="SRIOV Network Device Plugin"
LABEL ainic.bundled.versions="${AINIC_VERSIONS}"
ENV PATH=/opt/nic/bin:/opt/nic/sbin:$PATH

COPY --from=nicctlbuilder /export/bin/nicctl* /usr/sbin/
COPY --from=nicctlbuilder /export/nicctl-versions /opt/nicctl-versions
COPY --from=nicctlbuilder /export/bootstrap-version.txt /opt/
COPY --from=nicctlbuilder /export/lib64/libpci* /lib64/

# Pinned runtime packages required for compliance/version checks
RUN microdnf install -y \
    pciutils-3.7.0 \
    kmod-libs-28 \
    systemd-libs-252 \
    jq-1.6 \
    vim-minimal-2:8.2.2637 \
    iproute-6.17.0 \
    xz-5.2.5 && \
    microdnf clean all

COPY --from=builder /usr/src/sriov-network-device-plugin/build/sriovdp /usr/bin/
COPY ./images/nicctl-setup.sh ./images/entrypoint.sh /
RUN chmod +x /nicctl-setup.sh /entrypoint.sh
ENTRYPOINT ["/nicctl-setup.sh"]
