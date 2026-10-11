#!/bin/bash
# firewalla-dns-hardening: re-apply the firewall rules right after boot.
#
# Installed as /home/pi/.firewalla/config/post_main.d/fw-hardening-boot.sh
# Firewalla runs every script in post_main.d once its main service is up.
# Without this, the rules would only come back on the next cron run
# (up to 5 minutes of unfiltered DNS after every reboot).
#
# Runs once immediately and once more after 60 seconds, because Firewalla
# may still rebuild its own iptables rules shortly after startup.
DIR=/home/pi/.firewalla/config/fw-hardening

run() {
  bash "$DIR/enforce_dns.sh"
  bash "$DIR/doh_ipblock.sh" enforce
  logger -t fw-hardening "boot_enforce: rules applied"
}

run
( sleep 60; run ) >/dev/null 2>&1 &
