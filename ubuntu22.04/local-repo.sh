#!/usr/bin/env bash
set -eu

LOCAL_REPO_DIR=/usr/local/repos

download_apt_with_dep () {
  local package="$1"
  echo "Attempting to download package: $package"
  
  # Check if package exists first
  if apt-cache search "^${package}$" | grep -q "^${package}"; then
    echo "Package $package found in repositories"
    apt-get download $package
    apt-get download $(apt-cache depends --recurse --no-recommends --no-suggests --no-conflicts --no-breaks --no-replaces --no-enhances $package | grep "^\w" | sort -u)
  else
    echo "WARNING: Package $package not found in repositories"
    # Try to find similar packages
    echo "Searching for similar packages:"
    apt-cache search "nvidia.*${DRIVER_BRANCH}" | head -10
  fi
}

download_driver_package_deps () {
  echo "Starting driver package download process..."
  echo "DRIVER_BRANCH: $DRIVER_BRANCH"
  echo "DRIVER_VERSION: $DRIVER_VERSION"
  echo "KERNEL_VERSION: $KERNEL_VERSION"
  echo "TARGETARCH: $TARGETARCH"
  
  apt-get update
  
  # Show available nvidia packages
  echo "Available NVIDIA packages:"
  apt-cache search "nvidia.*${DRIVER_BRANCH}" | head -20
  
  pushd ${LOCAL_REPO_DIR}
  
  # Try to download packages, but continue even if some fail
  set +e
  
  #download_apt_with_dep linux-objects-nvidia-${DRIVER_BRANCH}-server-${KERNEL_VERSION}
  download_apt_with_dep nvidia-driver-${DRIVER_BRANCH}-server
  download_apt_with_dep nvidia-dkms-${DRIVER_BRANCH}
  download_apt_with_dep linux-headers-generic
  download_apt_with_dep linux-signatures-nvidia-${KERNEL_VERSION}
  download_apt_with_dep linux-modules-nvidia-${DRIVER_BRANCH}-server-${KERNEL_VERSION}
  download_apt_with_dep linux-modules-nvidia-${DRIVER_BRANCH}-server-open-${KERNEL_VERSION}
  download_apt_with_dep nvidia-utils-${DRIVER_BRANCH}-server
  download_apt_with_dep nvidia-headless-no-dkms-${DRIVER_BRANCH}-server
  download_apt_with_dep libnvidia-decode-${DRIVER_BRANCH}-server
  download_apt_with_dep libnvidia-extra-${DRIVER_BRANCH}-server
  download_apt_with_dep libnvidia-encode-${DRIVER_BRANCH}-server
  download_apt_with_dep libnvidia-fbc1-${DRIVER_BRANCH}-server
  
  # Try different package naming conventions
  echo "Trying alternative package names..."
  download_apt_with_dep nvidia-utils-${DRIVER_BRANCH}
  download_apt_with_dep nvidia-headless-no-dkms-${DRIVER_BRANCH}
  download_apt_with_dep libnvidia-decode-${DRIVER_BRANCH}
  download_apt_with_dep libnvidia-extra-${DRIVER_BRANCH}
  download_apt_with_dep libnvidia-encode-${DRIVER_BRANCH}
  download_apt_with_dep libnvidia-fbc1-${DRIVER_BRANCH}
  
  # Try to download fabricmanager and nscq with specific version
  echo "Downloading fabricmanager and nscq..."
  apt-get download nvidia-fabricmanager-${DRIVER_BRANCH}=${DRIVER_VERSION}-1 || echo "Failed to download fabricmanager"
  apt-get download libnvidia-nscq-${DRIVER_BRANCH}=${DRIVER_VERSION}-1 || echo "Failed to download nscq"
  
  set -e
  
  echo "Downloaded packages:"
  ls -al .
  echo "Total packages downloaded: $(ls -1 *.deb 2>/dev/null | wc -l)"
  
  popd
}

build_local_apt_repo () {
  echo "Building local apt repository..."
  pushd ${LOCAL_REPO_DIR}
  
  # Check if we have any packages
  if [ ! -f *.deb ]; then
    echo "ERROR: No .deb packages found in ${LOCAL_REPO_DIR}"
    echo "Contents of directory:"
    ls -la
    exit 1
  fi
  
  # Create Packages.gz
  dpkg-scanpackages . /dev/null | gzip -9c | tee Packages.gz > /dev/null
  
  # Backup existing sources.list
  cp /etc/apt/sources.list /etc/apt/sources.list.backup
  
  # Set up local repository
  echo "deb [trusted=yes] file:${LOCAL_REPO_DIR} ./" > /etc/apt/sources.list
  
  # Show what we're adding
  echo "Local repository contents:"
  ls -la
  echo "Packages.gz contents:"
  zcat Packages.gz | grep "^Package:" | head -20
  
  popd
  
  # Update package lists
  apt-get update
  
  # Verify packages are available
  echo "Checking if packages are now available:"
  apt-cache search "nvidia.*${DRIVER_BRANCH}" | head -10
}

if [ "$1" = "download_driver_package_deps" ]; then
  download_driver_package_deps
elif [ "$1" = "build_local_apt_repo" ]; then
  build_local_apt_repo
else
  echo "Unknown function: $1"
  exit 1
fi