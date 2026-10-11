#!/bin/bash
# firewalla-dns-hardening installer. Run on the Firewalla as user pi:
#   git clone https://github.com/TrackPixel/firewalla-dns-hardening.git
#   cd firewalla-dns-hardening && bash install.sh
# Safe to re-run: it updates the scripts and never duplicates rules or cron lines.
set -e

SRC=$(cd "$(dirname "$0")" && pwd)
CFG=/home/pi/.firewalla/config
DIR=$CFG/fw-hardening
CRON=$CFG/user_crontab
STAMP=$(date +%Y%m%d-%H%M%S)

say()  { echo "==> $*"; }
fail() { echo "ERROR: $*" >&2; exit 1; }

[ -d "$CFG" ] || fail "$CFG not found. Is this a Firewalla?"
for c in curl dig ipset iptables ip6tables awk logger; do
  command -v "$c" >/dev/null || fail "required command '$c' not found"
done
sudo -n true 2>/dev/null || fail "passwordless sudo is required (run as user pi)"

say "Installing scripts to $DIR"
mkdir -p "$DIR" "$CFG/dnsmasq_local" "$CFG/post_main.d"
cp "$SRC"/scripts/*.sh "$DIR/"
chmod 755 "$DIR"/*.sh

if [ ! -f "$CFG/fw-hardening.env" ]; then
  cp "$SRC/config/fw-hardening.env.example" "$CFG/fw-hardening.env"
  say "Created $CFG/fw-hardening.env (edit it to set HC_URL and CONTROL_DOMAIN)"
else
  say "Keeping existing $CFG/fw-hardening.env"
fi
[ -f "$CFG/doh-ips-allow.txt" ] || cp "$SRC/config/doh-ips-allow.txt.example" "$CFG/doh-ips-allow.txt"

# Load settings (also auto-detects FW_IP)
. "$DIR/common.sh"
[ -n "$FW_IP" ] || fail "could not detect the Firewalla IP on $LAN_IF; set FW_IP in fw-hardening.env"
say "Using LAN_IF=$LAN_IF FW_IP=$FW_IP"

say "Installing dnsmasq configs"
if [ ! -f "$DNSMASQ_DIR/fwh-rebind.conf" ]; then
  cp "$SRC/config/rebind.conf" "$DNSMASQ_DIR/fwh-rebind.conf"
else
  echo "    keeping existing fwh-rebind.conf (your exceptions stay)"
fi
{
  grep '^#' "$SRC/config/canary.conf"
  echo "local=/$CANARY_DOMAIN/"
} > "$DNSMASQ_DIR/fwh-canary.conf"

say "Installing boot hook"
cp "$SRC/scripts/boot_enforce.sh" "$CFG/post_main.d/fw-hardening-boot.sh"
chmod 755 "$CFG/post_main.d/fw-hardening-boot.sh"

say "Updating cron (backup: user_crontab.bak.$STAMP)"
touch "$CRON"
cp "$CRON" "$CRON.bak.$STAMP"
sed -i '/fw-hardening/d' "$CRON"
cat >> "$CRON" <<EOF
30 4 * * * $DIR/update_blocklist.sh # fw-hardening
40 4 * * * $DIR/doh_ipblock.sh update # fw-hardening
*/5 * * * * $DIR/enforce_dns.sh # fw-hardening
*/5 * * * * $DIR/doh_ipblock.sh enforce # fw-hardening
*/10 * * * * $DIR/dns_canary.sh # fw-hardening
EOF
if [ -x /home/pi/firewalla/scripts/update_crontab.sh ]; then
  bash /home/pi/firewalla/scripts/update_crontab.sh
else
  echo "    WARNING: update_crontab.sh not found; check how your firmware loads user_crontab"
fi

say "Downloading blocklists (this can take a minute)"
"$DIR/update_blocklist.sh"
sudo systemctl restart firerouter_dns
sleep 5

say "Applying firewall rules"
"$DIR/enforce_dns.sh"
"$DIR/doh_ipblock.sh" update

say "Running canary once"
"$DIR/dns_canary.sh" || true

say "Health report"
"$DIR/healthcheck.sh"

echo
say "Done. Undo everything with: bash uninstall.sh"
