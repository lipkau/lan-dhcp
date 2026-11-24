# Changelog

## 1.0.2

- Confines LAN DHCP with an AppArmor profile on Home Assistant OS.

## 1.0.1

- Drops expired leases before merging a lease seed. An expired lease for the same MAC or address no longer
  keeps a seed entry out, so a returning server learns every address another server handed out.

## 1.0.0

- dnsmasq 2.93, built from the upstream release tarball.
- Reads `dnsmasq.conf` from the app config folder and serves the interface in the `interface` option.
- Merges a lease seed from the config folder on start, for taking over from another DHCP server.
- Refuses to start on an interface without an IPv4 address or on loopback.
