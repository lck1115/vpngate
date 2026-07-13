FROM debian:12-slim

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        dante-server \
        iproute2 \
        iptables \
        openvpn \
        procps \
        python3 \
    && rm -rf /var/lib/apt/lists/*

COPY bin/vpngate /usr/local/bin/vpngate
RUN chmod +x /usr/local/bin/vpngate \
    && mkdir -p /data /run/vpngate

ENTRYPOINT ["/usr/local/bin/vpngate"]
CMD ["run"]
