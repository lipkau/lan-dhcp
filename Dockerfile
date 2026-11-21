# dnsmasq built from the upstream release tarball. The image holds no configuration: README.md
# describes the /config and /data contract. Bump DNSMASQ_VERSION and DNSMASQ_SHA256 together.
ARG DNSMASQ_VERSION=2.93
ARG DNSMASQ_SHA256=cc967771abdafeb43d10db18932d6b59fd4bed2c69c22acf8cb96aff6920d55f

FROM alpine:3.24.4@sha256:f59abe656b692d901e184be3445e084786602108599d2a51d229c0f5a48c71bf AS build
ARG DNSMASQ_VERSION
ARG DNSMASQ_SHA256
# bld/get-version needs GNU sort to read the version from the tarball's VERSION file.
RUN apk add --no-cache build-base coreutils linux-headers
WORKDIR /src
RUN wget -q -O dnsmasq.tar.gz "https://thekelleys.org.uk/dnsmasq/dnsmasq-${DNSMASQ_VERSION}.tar.gz" \
  && echo "${DNSMASQ_SHA256}  dnsmasq.tar.gz" | sha256sum -c - \
  && tar -xzf dnsmasq.tar.gz --strip-components=1 \
  && make -j"$(nproc)" \
  && strip src/dnsmasq \
  && src/dnsmasq --version | grep -q "^Dnsmasq version ${DNSMASQ_VERSION} "

FROM alpine:3.24.4@sha256:f59abe656b692d901e184be3445e084786602108599d2a51d229c0f5a48c71bf
ARG DNSMASQ_VERSION
LABEL org.opencontainers.image.title="lan-dhcp" \
  org.opencontainers.image.description="dnsmasq ${DNSMASQ_VERSION} DHCPv4 server and lease DNS, configured from /config" \
  org.opencontainers.image.url="https://github.com/lipkau/lan-dhcp" \
  org.opencontainers.image.source="https://github.com/lipkau/lan-dhcp" \
  org.opencontainers.image.vendor="Oliver Lipkau"
COPY --from=build /src/src/dnsmasq /usr/sbin/dnsmasq
COPY --chmod=0755 entrypoint.sh /usr/local/bin/lan-dhcp
# Starts as root on purpose: dnsmasq binds UDP 67 and opens the lease file, then drops to nobody.
ENTRYPOINT ["/usr/local/bin/lan-dhcp"]
