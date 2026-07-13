FROM ubuntu:24.04

# Avoid interactive prompts during package installation
ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y \
    bash \
    wget \
    wireguard-tools \
    diffutils \
    && rm -rf /var/lib/apt/lists/*

RUN wget https://github.com/mikefarah/yq/releases/download/v4.53.3/yq_linux_amd64 -O /usr/bin/yq && \
    chmod +x /usr/bin/yq

WORKDIR /opt/wireguard-manager

# Copy the scripts and example files
COPY . /opt/wireguard-manager

ENV HOME=/opt/wireguard-manager

CMD ["/opt/wireguard-manager/bin/test-wireconfig.sh"]
