#!/bin/sh
# Run the entrypoint and a DHCP exchange against an image built from this repository.
#   tests/run.sh <image>
set -eu

[ $# -eq 1 ] || { echo "usage: $0 <image>" >&2; exit 2; }
image=$1
tests=$(cd "$(dirname "$0")" && pwd)
work=$(mktemp -d)
network=lan-dhcp-test-$$
server=lan-dhcp-test-server-$$
failed=0

# shellcheck disable=SC2329 # called by the EXIT trap
cleanup() {
    docker rm -f "$server" >/dev/null 2>&1 || true
    docker network rm "$network" >/dev/null 2>&1 || true
    rm -rf "$work"
}
trap cleanup EXIT

pass() { echo "ok      $1"; }
fail() { echo "FAIL    $1"; sed 's/^/          /' "$work/out"; failed=1; }

# expect <0|1> <expected output> <description> <docker run arguments...>
expect() {
    want=$1 text=$2 name=$3
    shift 3
    if docker run --rm "$@" "$image" >"$work/out" 2>&1; then got=0; else got=1; fi
    if [ "$got" = "$want" ] && grep -qF -- "$text" "$work/out"; then pass "$name"; else fail "$name"; fi
}

config="type=bind,src=$tests/config,dst=/config,readonly"
mkdir -p "$work/empty" "$work/options"
printf '{"interface":"eth0"}\n' >"$work/options/options.json"

expect 0 "syntax check OK" "config passes with LAN_INTERFACE" \
    --mount "$config" -e DNSMASQ_TEST_ONLY=1 -e LAN_INTERFACE=eth0
expect 0 "syntax check OK" "interface from /data/options.json" \
    --mount "$config" --mount "type=bind,src=$work/options,dst=/data" -e DNSMASQ_TEST_ONLY=1
expect 1 "no LAN interface" "fails without an interface" \
    --mount "$config" -e DNSMASQ_TEST_ONLY=1
expect 1 "invalid interface name" "rejects an unsafe interface name" \
    --mount "$config" -e DNSMASQ_TEST_ONLY=1 -e 'LAN_INTERFACE=eth0 --port=53'
expect 1 "/config/dnsmasq.conf is missing" "fails without dnsmasq.conf" \
    --mount "type=bind,src=$work/empty,dst=/config,readonly" -e LAN_INTERFACE=eth0
expect 1 "failed dnsmasq --test" "fails on an invalid config" \
    --mount "type=bind,src=$tests/broken,dst=/config,readonly" -e LAN_INTERFACE=eth0
expect 1 "/data is missing" "fails without /data" \
    --mount "$config" -e LAN_INTERFACE=eth0
expect 1 "lease file" "fails with a read-only /data" \
    --mount "$config" --mount "type=bind,src=$work/empty,dst=/data,readonly" -e LAN_INTERFACE=eth0
expect 1 "loopback" "refuses the loopback interface" \
    --mount "$config" --mount "type=bind,src=$work/empty,dst=/data" -e LAN_INTERFACE=lo
expect 1 "does not exist" "fails on a missing interface" \
    --mount "$config" --mount "type=bind,src=$work/empty,dst=/data" -e LAN_INTERFACE=end0

# A DHCP exchange on a private Docker network: the server leases an address to a client,
# writes the lease to /data, and runs as nobody after binding, with a read-only root filesystem.
mkdir -p "$work/data"
chmod 777 "$work/data"
# An existing lease that the seed must not override (tests/config/dnsmasq.leases.seed also lists
# 172.31.250.121 for another MAC and an expired entry).
printf '4102444800 00:00:5e:00:53:02 172.31.250.121 existing *\n' >"$work/data/dnsmasq.leases"
docker network create --subnet 172.31.250.0/24 --gateway 172.31.250.1 "$network" >/dev/null
docker run -d --name "$server" --network "$network" --ip 172.31.250.2 --cap-add NET_ADMIN --read-only \
    --mount "$config" --mount "type=bind,src=$work/data,dst=/data" -e LAN_INTERFACE=eth0 \
    "$image" >/dev/null
for _ in 1 2 3 4 5 6 7 8 9 10; do
    docker logs "$server" 2>&1 | grep -q "sockets bound exclusively" && break
    sleep 1
done
if docker run --rm --network "$network" --mac-address 02:00:00:00:00:02 --entrypoint udhcpc \
    "$image" -i eth0 -n -q -f -t 5 -s /bin/true >"$work/out" 2>&1 &&
    grep -q "lease of 172\.31\.250\.1[0-4][0-9] obtained" "$work/out"; then
    pass "leases a short-pool address to a randomized MAC"
else
    fail "leases a short-pool address to a randomized MAC"
fi
if docker run --rm --network "$network" --mac-address 02:00:00:00:00:01 --entrypoint udhcpc \
    "$image" -i eth0 -n -q -f -t 5 -s /bin/true >"$work/out" 2>&1 &&
    grep -q "lease of 172\.31\.250\.1[5-9][0-9] obtained" "$work/out"; then
    pass "leases a long-pool address to a MAC exception"
else
    fail "leases a long-pool address to a MAC exception"
fi
docker exec "$server" cat /data/dnsmasq.leases >"$work/out" 2>&1 || true
if grep -q "02:00:00:00:00:02" "$work/out"; then pass "writes the lease file"; else fail "writes the lease file"; fi
if grep -q "00:00:5e:00:53:01 172.31.250.120" "$work/out" && grep -q "00:00:5e:00:53:02 172.31.250.121" "$work/out" &&
    ! grep -qE "00:00:5e:00:53:0[34]" "$work/out" && docker logs "$server" 2>&1 | grep -q "merged 1 leases"; then
    pass "merges only new, unexpired seed leases"
else
    fail "merges only new, unexpired seed leases"
fi
docker exec "$server" ps -o user,args >"$work/out" 2>&1 || true
if grep -q "^nobody .*dnsmasq" "$work/out"; then pass "drops privileges"; else fail "drops privileges"; fi
if [ "$failed" = 1 ]; then
    echo "server log:"
    docker logs "$server" 2>&1 | sed 's/^/          /'
fi

exit "$failed"
