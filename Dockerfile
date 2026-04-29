FROM ghcr.io/cyberrangecz/docker-image-builder:latest

RUN DEBIAN_FRONTEND=noninteractive apt-get update && apt-get install -y --no-install-recommends \
    ovmf \
    swtpm \
    swtpm-tools \
    gdisk \
    parted \
    && apt-get -y clean
