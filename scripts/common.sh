#!/bin/bash
# shellcheck disable=SC2034
# firewalla-dns-hardening: shared settings and helpers.
# Sourced by the other scripts; not meant to be run directly.

CFG=/home/pi/.firewalla/config
DNSMASQ_DIR=$CFG/dnsmasq_local
ENV_FILE=$CFG/fw-hardening.env

# Defaults (overridden by fw-hardening.env)
LAN_IF="br0"
FW_IP=""
CONTROL_DOMAIN="example.com"
CANARY_DOMAIN="example.net"
HAGEZI_LISTS="tif.mini doh fake"
MIN_LIST_ENTRIES=100
BLOCK_SMTP=1
HC_URL=""
CANARY_FAIL_AFTER=3

# shellcheck disable=SC1090
[ -r "$ENV_FILE" ] && . "$ENV_FILE"

if [ -z "$FW_IP" ]; then
  FW_IP=$(ip -4 -o addr show "$LAN_IF" 2>/dev/null | awk '{print $4}' | cut -d/ -f1 | head -n1)
fi

DOH_SET=doh_block

log() { logger -t fw-hardening "$(basename "$0"): $*"; }
