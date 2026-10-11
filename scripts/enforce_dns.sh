#!/bin/bash
# firewalla-dns-hardening: force all client DNS through the Firewalla.
#
# IPv4
#   - DNAT every tcp/udp port 53 packet arriving on LAN_IF to the Firewalla
#     itself, so a device hardcoded to 8.8.8.8 still gets filtered answers.
#   - REJECT DNS-over-TLS / DNS-over-QUIC (tcp+udp 853) so clients fall back
#     to plain DNS, which is then redirected.
#   - Optional: REJECT outbound SMTP (tcp 25) from clients (BLOCK_SMTP=1).
# IPv6
#   - REJECT forwarded DNS (53) and DoT (853), plus SMTP if enabled.
#     IPv6 DNS cannot be redirected the same way, so it is refused instead
#     and clients fall back to IPv4 DNS.
#
# Firewalla rebuilds its iptables rules from time to time. This script is
# idempotent (iptables -C || -I) and is meant to run from cron every few
# minutes and at boot, so the rules are always re-asserted.
#
# Usage: enforce_dns.sh          add any missing rules
#        enforce_dns.sh remove   delete all rules this script adds
. "$(dirname "$(readlink -f "$0")")/common.sh"

if [ -z "$FW_IP" ]; then
  log "cannot determine FW_IP on $LAN_IF, aborting"
  exit 1
fi

MODE=add
[ "$1" = "remove" ] && MODE=remove

# rule <iptables|ip6tables> <table> <chain> <rule args...>
rule() {
  local bin=$1 table=$2 chain=$3; shift 3
  if [ "$MODE" = "remove" ]; then
    while sudo "$bin" -t "$table" -C "$chain" "$@" 2>/dev/null; do
      sudo "$bin" -t "$table" -D "$chain" "$@"
    done
  else
    sudo "$bin" -t "$table" -C "$chain" "$@" 2>/dev/null || \
      sudo "$bin" -t "$table" -I "$chain" "$@"
  fi
}

for p in tcp udp; do
  # IPv4: redirect DNS to the Firewalla (not for the box itself)
  rule iptables nat PREROUTING ! -s "$FW_IP/32" ! -d "$FW_IP/32" -i "$LAN_IF" \
       -p $p -m $p --dport 53 -j DNAT --to-destination "$FW_IP"
  # IPv4: refuse DoT / DoQ
  rule iptables filter FORWARD -p $p --dport 853 -j REJECT
  # IPv6: refuse DNS and DoT from clients
  rule ip6tables filter FORWARD -p $p --dport 53 -j REJECT
  rule ip6tables filter FORWARD -p $p --dport 853 -j REJECT
done

if [ "$BLOCK_SMTP" = "1" ] || [ "$MODE" = "remove" ]; then
  rule iptables filter FORWARD -p tcp --dport 25 -j REJECT
  rule ip6tables filter FORWARD -p tcp --dport 25 -j REJECT
fi
