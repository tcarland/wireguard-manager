FROM ubuntu:24.04

ARG yq_url="https://github.com/mikefarah/yq/releases/download"
ARG yq_version="v4.53.3"

ENV DEBIAN_FRONTEND=noninteractive
ENV HOME=/opt/wireguard-manager

RUN apt-get update && apt-get install -y \
    bash \
    ca-certificates \
    wget \
    wireguard-tools \
    diffutils \
    && rm -rf /var/lib/apt/lists/*

COPY ca.cr[t] /opt/tdh-k8s/
RUN if [ -f ca.crt ]; then \
        cp ca.crt /usr/local/share/ca-certificates/tdh-ca.crt && \
        update-ca-certificates && \
        keytool -import -trustcacerts -cacerts -storepass changeit -noprompt -alias tdh-ca -file /usr/local/share/ca-certificates/tdh-ca.crt; \
    fi

RUN curl -L ${yq_url}/${yq_version}/yq_linux_amd64 -o /usr/local/bin/yq && \
    chmod +x /usr/local/bin/yq

WORKDIR /opt/wireguard-manager
COPY . /opt/wireguard-manager

CMD ["/opt/wireguard-manager/bin/test-wireconfig.sh"]
