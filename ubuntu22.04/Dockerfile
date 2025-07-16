FROM nvcr.io/nvidia/cuda:12.9.1-base-ubuntu22.04 as build

ARG TARGETARCH
ARG GOLANG_VERSION

SHELL ["/bin/bash", "-c"]

RUN echo 'debconf debconf/frontend select Noninteractive' | debconf-set-selections

# Remove cuda repository to avoid GPG errors
RUN rm -f /etc/apt/sources.list.d/cuda*

RUN apt-get update && apt-get install -y --no-install-recommends \
        apt-utils \
        build-essential \
        ca-certificates \
        curl \
        git && \
    rm -rf /var/lib/apt/lists/*

# download appropriate binary based on the target architecture for multi-arch builds
RUN OS_ARCH=${TARGETARCH/x86_64/amd64} && OS_ARCH=${OS_ARCH/aarch64/arm64} && \
    curl https://storage.googleapis.com/golang/go${GOLANG_VERSION}.linux-${OS_ARCH}.tar.gz \
    | tar -C /usr/local -xz

ENV PATH /usr/local/go/bin:$PATH

WORKDIR /work

RUN git clone https://github.com/NVIDIA/gpu-driver-container driver && \
    cd driver/vgpu/src && \
    go build -o vgpu-util && \
    mv vgpu-util /work

FROM nvcr.io/nvidia/cuda:12.9.1-base-ubuntu22.04

SHELL ["/bin/bash", "-c"]

ARG BASE_URL=https://us.download.nvidia.com/tesla
ARG TARGETARCH
ENV TARGETARCH=$TARGETARCH
ARG DRIVER_VERSION
ENV DRIVER_VERSION=$DRIVER_VERSION
ARG KERNEL_VERSION
ENV KERNEL_VERSION=$KERNEL_VERSION
ENV DEBIAN_FRONTEND=noninteractive

# Arg to indicate if driver type is either of passthrough(baremetal) or vgpu
ARG DRIVER_TYPE=passthrough
ENV DRIVER_TYPE=$DRIVER_TYPE
ARG DRIVER_BRANCH=570
ENV DRIVER_BRANCH=$DRIVER_BRANCH
ARG VGPU_LICENSE_SERVER_TYPE=NLS
ENV VGPU_LICENSE_SERVER_TYPE=$VGPU_LICENSE_SERVER_TYPE
# Enable vGPU version compability check by default
ARG DISABLE_VGPU_VERSION_CHECK=true
ENV DISABLE_VGPU_VERSION_CHECK=$DISABLE_VGPU_VERSION_CHECK
ENV NVIDIA_VISIBLE_DEVICES=void

RUN echo 'debconf debconf/frontend select Noninteractive' | debconf-set-selections

RUN echo "TARGETARCH=$TARGETARCH"

ADD install.sh /tmp

# Fetch GPG keys for CUDA repo
RUN apt-key del 7fa2af80 && OS_ARCH=${TARGETARCH/amd64/x86_64} && OS_ARCH=${OS_ARCH/arm64/sbsa} && \
    apt-key adv --fetch-keys "https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2204/${OS_ARCH}/3bf863cc.pub"

RUN /tmp/install.sh reposetup && /tmp/install.sh depinstall

# Install additional tools for debugging
RUN apt-get update && \
    apt-get install -y software-properties-common dpkg-dev apt-utils && \
    add-apt-repository restricted && \
    add-apt-repository multiverse && \
    apt-get update && \
    apt-get install -y curl && \
    rm -rf /var/lib/apt/lists/*

# Create repos directory
RUN mkdir -p /usr/local/repos

# Download GRID driver and extract nvidia-installer
RUN cd /usr/local/repos && \
    curl -O https://storage.googleapis.com/nvidia-drivers-us-public/GRID/vGPU18.2/NVIDIA-Linux-x86_64-570.148.08-grid.run && \
    chmod +x NVIDIA-Linux-x86_64-570.148.08-grid.run && \
    echo "=== Extracting nvidia-installer from .run file ===" && \
    ./NVIDIA-Linux-x86_64-570.148.08-grid.run --extract-only && \
    echo "=== Extracted contents ===" && \
    ls -la && \
    echo "=== Making nvidia-installer available globally ===" && \
    if [ -f NVIDIA-Linux-x86_64-570.148.08-grid/nvidia-installer ]; then \
        cp NVIDIA-Linux-x86_64-570.148.08-grid/nvidia-installer /usr/local/bin/; \
        chmod +x /usr/local/bin/nvidia-installer; \
        echo "nvidia-installer copied to /usr/local/bin/"; \
    else \
        echo "nvidia-installer not found in expected location"; \
        find . -name "nvidia-installer" -type f; \
    fi

# Add improved local-repo.sh
ADD local-repo.sh /tmp
RUN chmod +x /tmp/local-repo.sh

# Try to download driver packages and build local repo
RUN echo "=== ATTEMPTING PACKAGE DOWNLOAD ===" && \
    (/tmp/local-repo.sh download_driver_package_deps || echo "Package download had issues, continuing...") && \
    echo "=== BUILDING LOCAL REPO ===" && \
    (/tmp/local-repo.sh build_local_apt_repo || echo "Local repo build had issues, continuing...")

# Check if local repo was created successfully
RUN echo "=== CHECKING LOCAL REPO ===" && \
    ls -la /usr/local/repos/ && \
    if [ -f /usr/local/repos/Packages.gz ]; then \
        echo "Local repository created successfully"; \
        echo "Packages in local repo:"; \
        zcat /usr/local/repos/Packages.gz | grep "^Package:" | head -20; \
    else \
        echo "Local repository was not created successfully"; \
    fi

COPY nvidia-driver /usr/local/bin
COPY --from=build /work/vgpu-util /usr/local/bin

ADD drivers drivers/

# Try to install fabricmanager and libnvidia-nscq from local repo first, fallback to standard repos
RUN if [ "$DRIVER_TYPE" != "vgpu" ]; then \
    echo "=== INSTALLING FABRICMANAGER AND NSCQ ===" && \
    cd drivers && \
    (apt-get install -y --no-install-recommends nvidia-fabricmanager-${DRIVER_BRANCH}=${DRIVER_VERSION}-1 || \
     apt-get install -y --no-install-recommends nvidia-fabricmanager-${DRIVER_BRANCH} || \
     echo "Failed to install fabricmanager, continuing...") && \
    (apt-get install -y --no-install-recommends libnvidia-nscq-${DRIVER_BRANCH}=${DRIVER_VERSION}-1 || \
     apt-get install -y --no-install-recommends libnvidia-nscq-${DRIVER_BRANCH} || \
     echo "Failed to install libnvidia-nscq, continuing...") && \
    rm -rf /var/lib/apt/lists/*; \
fi

# Install additional packages for newer driver branches
RUN if [ "$DRIVER_TYPE" != "vgpu" ] && [ "$DRIVER_BRANCH" -ge "550" ]; then \
    apt-get update && \
    (apt-get install -y --no-install-recommends nvlsm infiniband-diags || echo "Failed to install nvlsm/infiniband-diags, continuing...") && \
    (apt-get install -y --no-install-recommends nvidia-imex-${DRIVER_BRANCH}=${DRIVER_VERSION}-1 || \
     apt-get install -y --no-install-recommends nvidia-imex-${DRIVER_BRANCH} || \
     echo "Failed to install nvidia-imex, continuing...") && \
    rm -rf /var/lib/apt/lists/*; \
fi

# libnvsdm packages are not available for arm64
RUN if [ "$DRIVER_TYPE" != "vgpu" ] && [ "$DRIVER_BRANCH" -ge "560" ] && [ "$TARGETARCH" != "arm64" ]; then \
    apt-get update && \
    (apt-get install -y --no-install-recommends libnvsdm-${DRIVER_BRANCH}=${DRIVER_VERSION}-1 || \
     apt-get install -y --no-install-recommends libnvsdm-${DRIVER_BRANCH} || \
     echo "Failed to install libnvsdm, continuing...") && \
    rm -rf /var/lib/apt/lists/*; \
fi

WORKDIR /drivers

ARG PUBLIC_KEY=empty
COPY ${PUBLIC_KEY} kernel/pubkey.x509

# Install the gcc-12 package - PRESERVE LOCAL REPO CONFIGURATION
RUN echo "=== INSTALLING GCC-12 WHILE PRESERVING LOCAL REPO ===" && \
    cp /etc/apt/sources.list /etc/apt/sources.list.backup && \
    echo "deb http://archive.ubuntu.com/ubuntu jammy main universe" > /etc/apt/sources.list.new && \
    echo "deb http://archive.ubuntu.com/ubuntu jammy-updates main universe" >> /etc/apt/sources.list.new && \
    echo "deb http://archive.ubuntu.com/ubuntu jammy-security main universe" >> /etc/apt/sources.list.new && \
    if [ -f /usr/local/repos/Packages.gz ]; then \
        echo "deb [trusted=yes] file:/usr/local/repos ./" >> /etc/apt/sources.list.new; \
    fi && \
    mv /etc/apt/sources.list.new /etc/apt/sources.list && \
    apt-get update && \
    apt-get install -y --no-install-recommends gcc-12 g++-12 && \
    update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-12 12 && \
    update-alternatives --install /usr/bin/g++ g++ /usr/bin/g++-12 12 && \
    rm -rf /var/lib/apt/lists/*

# Install / upgrade packages here that are required to resolve CVEs
ARG CVE_UPDATES
RUN if [ -n "${CVE_UPDATES}" ]; then \
        apt-get update && apt-get upgrade -y ${CVE_UPDATES} && \
        rm -rf /var/lib/apt/lists/*; \
    fi

# Remove cuda repository to avoid GPG errors
RUN rm -f /etc/apt/sources.list.d/cuda*

# Add NGC DL license from the CUDA image
RUN mkdir /licenses && mv /NGC-DL-CONTAINER-LICENSE /licenses/NGC-DL-CONTAINER-LICENSE

# Add a script to verify what's available at runtime
RUN cat > /usr/local/bin/debug-nvidia-packages << 'EOF'
#!/bin/bash
echo "=== NVIDIA Driver Container Debug Info ==="
echo "DRIVER_BRANCH: $DRIVER_BRANCH"
echo "DRIVER_VERSION: $DRIVER_VERSION"
echo "DRIVER_TYPE: $DRIVER_TYPE"
echo ""
echo "Current sources.list:"
cat /etc/apt/sources.list
echo ""
echo "Downloaded .run file:"
ls -la /usr/local/repos/*.run
echo ""
echo "Local repository packages:"
ls -la /usr/local/repos/*.deb 2>/dev/null || echo "No .deb packages found"
echo ""
echo "Available NVIDIA packages in apt:"
apt-get update > /dev/null 2>&1
apt-cache search "nvidia.*570" | head -10
echo ""
echo "Available server packages specifically:"
apt-cache search "nvidia.*570.*server" | head -10
EOF

RUN chmod +x /usr/local/bin/debug-nvidia-packages

# Final verification that local repo is still configured
RUN echo "=== FINAL VERIFICATION ===" && \
    echo "Current sources.list content:" && \
    cat /etc/apt/sources.list && \
    echo "" && \
    echo "Checking if local repo packages are available:" && \
    if [ -f /usr/local/repos/Packages.gz ]; then \
        apt-get update > /dev/null 2>&1; \
        echo "nvidia-utils-570-server availability:" && \
        apt-cache search "^nvidia-utils-570-server$" || echo "Not found"; \
        echo "nvidia-headless-no-dkms-570-server availability:" && \
        apt-cache search "^nvidia-headless-no-dkms-570-server$" || echo "Not found"; \
    else \
        echo "Local repository not found"; \
    fi

ENTRYPOINT ["nvidia-driver", "init"]