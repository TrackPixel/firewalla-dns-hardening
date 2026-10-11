#!/bin/bash
# firewalla-dns-hardening: complete undo. Run on the Firewalla as user pi.
#   bash uninstall.sh           remove everything, keep your settings files
#   bash uninstall.sh --purge   also delete fw-hardening.env and doh-ips-allow.txt
# Afterwards the box behaves exactly as stock Firewalla again.

CFG=/home/pi/.firewalla/config
DIR=$CFG/fw-hardening
CRON=$CFG/user_crontab
say() { echo "==> $*"; }

say "Removing cron entries"
if [ -f "$CRON" ]; then
  cp "$CRON" "$CRON.bak.uninstall.$(date +%Y%m%d-%H%M%S)"
  sed -i '/fw-hardening/d' "$CRON"
  [ -x /home/pi/firewalla/scripts/update_crontab.sh ] && bash /home/pi/firewalla/scripts/update_crontab.sh
fi

say "Removing boot hook"
rm -f "$CFG/post_main.d/fw-hardening-boot.sh"

if [ -d "$DIR" ]; then
  say "Removing firewall rules and ipset"
  bash "$DIR/enforce_dns.sh" remove
  bash "$DIR/doh_ipblock.sh" remove
else
  say "Script folder not found, cannot remove rules automatically (a reboot clears them)"
  echo "    Check manually with: sudo iptables-save | grep -E 'dport (53|853|25)|doh_block'"
fi

say "Removing dnsmasq configs and blocklists"
rm -f "$CFG"/dnsmasq_local/hagezi-*.conf "$CFG"/dnsmasq_local/fwh-*.conf
sudo systemctl restart firerouter_dns

say "Removing scripts, state and logs"
rm -rf "$DIR"
rm -f "$CFG/doh-ips.txt" "$CFG/dns_canary.state" "$CFG/dns_canary.log"

if [ "$1" = "--purge" ]; then
  rm -f "$CFG/fw-hardening.env" "$CFG/doh-ips-allow.txt"
  say "Settings files deleted"
else
  echo "    kept: fw-hardening.env, doh-ips-allow.txt (use --purge to delete)"
fi

echo
say "Done. If you use healthchecks.io, pause or delete the check, or it will alert."
say "Verify: sudo iptables-save | grep -c doh_block  (should be 0)"
