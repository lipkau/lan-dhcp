# Changelog

## 1.0.0

- dnsmasq 2.93, built from the upstream release tarball.
- Reads `dnsmasq.conf` from the app config folder and serves the interface in the `interface` option.
- Merges a lease seed from the config folder on start, for taking over from another DHCP server.
- Refuses to start on an interface without an IPv4 address or on loopback.
