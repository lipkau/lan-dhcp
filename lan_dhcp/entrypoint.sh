#!/bin/sh
# Start dnsmasq from /config/dnsmasq.conf on one LAN interface, with leases in /data.
# The same contract applies under Home Assistant and Docker; README.md describes it.
#   LAN_INTERFACE        interface to serve; else the `interface` option in /data/options.json
#   DNSMASQ_TEST_ONLY=1  stop after `dnsmasq --test`
# A lease seed (/config/dnsmasq.leases.seed or /data/dnsmasq.leases.seed) is merged into the
# lease file on start: expired leases are dropped, then seed entries whose MAC and address no
# live lease holds are added.
set -eu

config=/config/dnsmasq.conf
data=/data
options=$data/options.json
leases=$data/dnsmasq.leases

die() {
    echo "lan-dhcp: $*" >&2
    exit 1
}

[ $# -eq 0 ] || die "takes no arguments; put dnsmasq options in $config"

[ -f "$config" ] || die "$config is missing: mount the config directory at /config"
[ -r "$config" ] || die "$config is not readable"

interface=${LAN_INTERFACE:-}
if [ -z "$interface" ] && [ -f "$options" ]; then
    # Supervisor writes the validated options as one JSON object; the check below rejects anything
    # that is not a plain interface name, so no JSON escapes need handling.
    interface=$(sed -n 's/.*"interface"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$options" | head -n 1)
fi

# Linux interface names have at most 15 characters.
case $interface in
    '') die "no LAN interface: set LAN_INTERFACE, or the app option interface under Home Assistant" ;;
    . | .. | *[!A-Za-z0-9_.-]*) die "invalid interface name: $interface" ;;
esac
[ ${#interface} -le 15 ] || die "interface name longer than 15 characters: $interface"

dnsmasq --test --conf-file="$config" --interface="$interface" ||
    die "$config failed dnsmasq --test"

[ "${DNSMASQ_TEST_ONLY:-}" != 1 ] || exit 0

# dnsmasq itself fails loudly when it cannot write the lease file.
[ -d "$data" ] || die "$data is missing: mount a writable directory there for $leases"
[ -e "/sys/class/net/$interface" ] || die "interface $interface does not exist on this host"
[ "$interface" != lo ] || die "refusing to serve the loopback interface"
addresses=$(ip -4 -o addr show dev "$interface" | awk '{print $4}' | tr '\n' ' ')
[ -n "$addresses" ] || die "interface $interface has no IPv4 address"

# Merge lease seeds, for example the old DHCP server's leases at a cutover or a fresh export
# at a failover. Expired leases are dropped first: dnsmasq prunes them on start anyway, and a
# stale entry must not hide a seed entry for the same MAC or address. Then only complete seed
# lines with a future expiry and a MAC and address no live lease holds are added, so a seed
# never overrides a lease dnsmasq handed out itself.
touch "$leases" || die "cannot create lease file $leases"
for seed in /config/dnsmasq.leases.seed "$data/dnsmasq.leases.seed"; do
    [ -f "$seed" ] || continue
    awk -v now="$(date +%s)" -v out="$leases.merge" -v seed="$seed" '
        FILENAME == ARGV[1] {
            # Lease lines have at least four fields; keep any other line (duid, vendorclass).
            if (NF >= 4 && $1 ~ /^[0-9]+$/ && $1 != 0 && $1 <= now) { expired++; next }
            if (NF >= 4) { mac[$2] = 1; ip[$3] = 1 }
            print > out
            next
        }
        NF == 5 && $1 ~ /^[0-9]+$/ && $1 > now && $2 ~ /^[0-9a-f:]+$/ && length($2) == 17 &&
            $3 ~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/ && !($2 in mac) && !($3 in ip) {
            print > out; mac[$2] = 1; ip[$3] = 1; added++
        }
        END {
            printf "" > out
            printf "lan-dhcp: merged %d leases from %s, dropped %d expired\n", added, seed, expired
        }
    ' "$leases" "$seed" || die "cannot merge lease seed $seed"
    mv "$leases.merge" "$leases" || die "cannot replace lease file $leases"
done

# The web page is optional for DHCP, and the standalone NAS container has no Supervisor.
if [ -n "${SUPERVISOR_SOCKET:-}${SUPERVISOR_TOKEN:-}" ]; then
    (
        port=$(/usr/local/bin/lan-dhcp-status ingress-port) || exit 1
        # Pass a read-only lease descriptor and strip the Supervisor credentials.
        exec env -i /sbin/su-exec lan-dhcp-status /usr/local/bin/lan-dhcp-status "$port" "$interface" 3<"$leases"
    ) &
fi
unset SUPERVISOR_SOCKET SUPERVISOR_TOKEN HASSIO_TOKEN

echo "lan-dhcp: serving $interface ($addresses), leases in $leases"
exec dnsmasq --keep-in-foreground --log-facility=- --pid-file --conf-file="$config" \
    --interface="$interface" --dhcp-leasefile="$leases"
