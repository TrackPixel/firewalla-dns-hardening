#!/bin/bash
# firewalla-dns-hardening: block known DNS-over-HTTPS servers by IP address.
#
# Blocking DoH hostnames (Hagezi "doh" list) stops apps that look up their
# resolver by name. Apps or malware that connect straight to an IP such as
# 1.1.1.1:443 bypass that. This script loads Hagezi's DoH IP list into an
# ipset and rejects tcp+udp 443 from clients to those addresses.
#
# The rule lives in the FORWARD chain, so the Firewalla's own encrypted DNS
# (OUTPUT chain) keeps working.
#
# Allow-list: put one IP per line in doh-ips-allow.txt (comments with #) and
# run "doh_ipblock.sh reload". Exceptions survive the nightly update.
#
# Usage: doh_ipblock.sh update    download list, load ipset, add rules (daily)
#        doh_ipblock.sh enforce   re-add rules / reload set if missing (5 min)
#        doh_ipblock.sh reload    re-apply allow-list without downloading
#        doh_ipblock.sh remove    delete rules and ipset
. "$(dirname "$(readlink -f "$0")")/common.sh"

LIST=$CFG/doh-ips.txt
ALLOW=$CFG/doh-ips-allow.txt
URL=https://raw.githubusercontent.com/hagezi/dns-blocklists/main/ips/doh.txt
MIN=500

load_set() {
  [ -s "$LIST" ] || return 1
  touch "$ALLOW"
  sudo ipset create $DOH_SET hash:net -exist
  sudo ipset create ${DOH_SET}_new hash:net -exist
  sudo ipset flush ${DOH_SET}_new
  awk -v allow="$ALLOW" 'FILENAME == allow { if ($1 != "" && $1 !~ /^#/) skip[$1]; next } !($1 in skip)' "$ALLOW" "$LIST" \
    | sed "s/^/add ${DOH_SET}_new /" | sudo ipset restore -exist
  sudo ipset swap ${DOH_SET}_new $DOH_SET
  sudo ipset destroy ${DOH_SET}_new
}

enforce_rules() {
  for p in tcp udp; do
    sudo iptables -C FORWARD -p $p --dport 443 -m set --match-set $DOH_SET dst -j REJECT 2>/dev/null || \
    sudo iptables -I FORWARD -p $p --dport 443 -m set --match-set $DOH_SET dst -j REJECT
  done
}

remove_all() {
  for p in tcp udp; do
    while sudo iptables -C FORWARD -p $p --dport 443 -m set --match-set $DOH_SET dst -j REJECT 2>/dev/null; do
      sudo iptables -D FORWARD -p $p --dport 443 -m set --match-set $DOH_SET dst -j REJECT
    done
  done
  sudo ipset destroy $DOH_SET 2>/dev/null
  rm -f "$LIST"
  log "DoH IP block removed (allow-list kept: $ALLOW)"
}

update() {
  local tmp
  tmp=$(mktemp)
  curl -fsS --max-time 60 "$URL" | grep -E '^[0-9]{1,3}(\.[0-9]{1,3}){3}(/[0-9]{1,2})?$' > "$tmp"
  if [ "$(wc -l < "$tmp")" -ge $MIN ]; then
    chmod 644 "$tmp"
    mv "$tmp" "$LIST"
    log "DoH IP list updated ($(wc -l < "$LIST") addresses)"
  else
    rm -f "$tmp"
    log "DoH IP download failed or too short, keeping previous list"
  fi
  load_set && enforce_rules
}

case "$1" in
  update)  update ;;
  enforce) sudo ipset list -n $DOH_SET >/dev/null 2>&1 || load_set; enforce_rules ;;
  reload)  load_set && enforce_rules ;;
  remove)  remove_all ;;
  *) echo "usage: $0 update|enforce|reload|remove"; exit 1 ;;
esac
