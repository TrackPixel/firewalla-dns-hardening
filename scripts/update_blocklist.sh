#!/bin/bash
# firewalla-dns-hardening: download Hagezi blocklists into Firewalla's dnsmasq.
#
# Each list from HAGEZI_LISTS is downloaded in dnsmasq format and written to
#   /home/pi/.firewalla/config/dnsmasq_local/hagezi-<name>.conf
# Firewalla's dnsmasq loads every file in dnsmasq_local, so blocked domains get
# NXDOMAIN for every device that uses the Firewalla for DNS.
#
# Download guard: a list only replaces the current one when it contains at
# least MIN_LIST_ENTRIES valid lines. A failed or truncated download keeps the
# previous list in place, so filtering never silently disappears.
#
# Usage: update_blocklist.sh            update all lists, restart DNS if changed
#        update_blocklist.sh remove     delete all hagezi-*.conf files
. "$(dirname "$(readlink -f "$0")")/common.sh"

BASE=https://raw.githubusercontent.com/hagezi/dns-blocklists/main/dnsmasq

if [ "$1" = "remove" ]; then
  rm -f "$DNSMASQ_DIR"/hagezi-*.conf
  sudo systemctl restart firerouter_dns
  log "hagezi lists removed"
  exit 0
fi

mkdir -p "$DNSMASQ_DIR"
changed=0

for name in $HAGEZI_LISTS; do
  dest="$DNSMASQ_DIR/hagezi-$name.conf"
  tmp=$(mktemp)
  # Keep only well-formed "local=/domain/" lines; drop comments and anything else.
  curl -fsS --max-time 120 "$BASE/$name.txt" \
    | grep -E '^local=/[A-Za-z0-9._-]+/$' > "$tmp"
  count=$(wc -l < "$tmp")

  if [ "$count" -lt "$MIN_LIST_ENTRIES" ]; then
    log "$name: download failed or too short ($count lines), keeping previous list"
    rm -f "$tmp"
    continue
  fi

  if [ -f "$dest" ] && cmp -s "$tmp" "$dest"; then
    rm -f "$tmp"
  else
    chmod 644 "$tmp"
    mv "$tmp" "$dest"
    changed=1
    log "$name: updated ($count entries)"
  fi
done

if [ "$changed" -eq 1 ]; then
  sudo systemctl restart firerouter_dns
  log "firerouter_dns restarted"
fi
