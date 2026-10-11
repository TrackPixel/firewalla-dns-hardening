#!/bin/bash
# firewalla-dns-hardening: read-only health report. Changes nothing.
# Run it after install, after a firmware update, or whenever in doubt.
. "$(dirname "$(readlink -f "$0")")/common.sh"
DIR=$CFG/fw-hardening

ok()  { echo "[OK] $*"; }
bad() { echo "[!!] $*"; }
inf() { echo "[i]  $*"; }
chk() { if eval "$2" >/dev/null 2>&1; then ok "$1"; else bad "$1"; fi; }
age() { [ -e "$1" ] && echo "$(( ($(date +%s) - $(stat -c %Y "$1")) / 3600 ))h" || echo "missing"; }
cnt() { grep -cv '^\s*\(#\|$\)' "$1" 2>/dev/null || echo 0; }

echo "=== SYSTEM ==="
echo "Date: $(date '+%F %T')  Boot: $(uptime -s)  Uptime: $(uptime -p)"
echo "Firewalla: $(cd /home/pi/firewalla 2>/dev/null && git describe --tags 2>/dev/null || echo unknown)  Kernel: $(uname -r)"
echo "LAN_IF: $LAN_IF  FW_IP: ${FW_IP:-NOT FOUND}  Load: $(cut -d' ' -f1-3 /proc/loadavg)"

echo; echo "=== FILES (age) ==="
for f in "$DIR"/*.sh "$CFG/fw-hardening.env" "$CFG/doh-ips.txt" "$CFG/doh-ips-allow.txt" "$CFG/post_main.d/fw-hardening-boot.sh"; do
  printf "%-40s %s\n" "${f#$CFG/}" "$(age "$f")"
done
for f in "$DNSMASQ_DIR"/hagezi-*.conf "$DNSMASQ_DIR"/fwh-*.conf; do
  [ -e "$f" ] && printf "%-40s %-8s %s lines\n" "$(basename "$f")" "$(age "$f")" "$(cnt "$f")"
done

echo; echo "=== CRON ==="
crontab -l 2>/dev/null | grep 'fw-hardening' || bad "no fw-hardening cron entries"

echo; echo "=== SERVICES ==="
chk "firerouter_dns active" "systemctl is-active --quiet firerouter_dns"
chk "dnsmasq running" "pgrep -x dnsmasq"

echo; echo "=== DNS TESTS (via $FW_IP) ==="
q() { dig +short +time=3 +tries=1 "$1" @"$FW_IP" | grep -E '^[0-9a-fA-F:.]+$' | head -n1; }
r=$(q "$CONTROL_DOMAIN");     [ -n "$r" ] && ok "$CONTROL_DOMAIN -> $r" || bad "$CONTROL_DOMAIN does not resolve"
r=$(q "$CANARY_DOMAIN");      [ -z "$r" ] || [ "$r" = "0.0.0.0" ] && ok "canary $CANARY_DOMAIN blocked" || bad "$CANARY_DOMAIN -> $r (canary not blocked)"
r=$(q 192.168.0.10.nip.io);   [ -z "$r" ] && ok "rebind protection active" || bad "192.168.0.10.nip.io -> $r (rebind not active)"
r=$(q localtest.me);          [ -n "$r" ] && ok "localtest.me -> $r (localhost allowed)" || bad "localtest.me does not resolve"
r=$(q dns.google);            inf "dns.google -> ${r:-blocked} (expected blocked by hagezi doh list)"

echo; echo "=== IPTABLES ==="
V4=$(sudo iptables-save); V6=$(sudo ip6tables-save)
n=$(echo "$V4" | grep -c -- "--dport 53 .*DNAT --to-destination $FW_IP\$"); [ "$n" -ge 2 ] && ok "DNS redirect DNAT 53 ($n)" || bad "DNS redirect DNAT 53: $n rules"
n=$(echo "$V4" | grep -c -- '--dport 853 .*REJECT');  [ "$n" -ge 2 ] && ok "IPv4 DoT 853 rejected ($n)" || bad "IPv4 DoT 853 rejects: $n"
n=$(echo "$V6" | grep -cE -- '--dport (53|853) .*REJECT'); [ "$n" -ge 4 ] && ok "IPv6 DNS/DoT rejected ($n)" || bad "IPv6 DNS/DoT rejects: $n"
if [ "$BLOCK_SMTP" = "1" ]; then
  n=$(echo "$V4" | grep -c -- '--dport 25 .*REJECT'); [ "$n" -ge 1 ] && ok "SMTP 25 rejected ($n)" || bad "SMTP 25 rejects: $n"
fi
n=$(echo "$V4" | grep -c "$DOH_SET .*REJECT"); [ "$n" -ge 2 ] && ok "DoH IP block ($n rules)" || bad "DoH IP block: $n rules"
sudo iptables -L FORWARD -v -n | grep "$DOH_SET" | awk '{print "     rejected so far: "$1" packets ("$4")"}'

echo; echo "=== IPSET ==="
n=$(sudo ipset list $DOH_SET 2>/dev/null | grep -c '^[0-9]'); [ "$n" -ge 500 ] && ok "$DOH_SET: $n addresses" || bad "$DOH_SET: $n addresses"
inf "allow-list: $(cnt "$CFG/doh-ips-allow.txt") exceptions"

echo; echo "=== BOOT HOOK ==="
grep 'boot_enforce: rules applied' /var/log/syslog 2>/dev/null | tail -n 2 | sed 's/^/     /'
[ -x "$CFG/post_main.d/fw-hardening-boot.sh" ] && ok "boot hook installed" || bad "boot hook missing"

echo; echo "=== CANARY ==="
inf "streak: $(cat "$CFG/dns_canary.state" 2>/dev/null || echo missing)  (0 = healthy)"
tail -n 3 "$CFG/dns_canary.log" 2>/dev/null | sed 's/^/     /'
[ -n "$HC_URL" ] && inf "external alerting: on" || inf "external alerting: off (HC_URL empty)"

echo; echo "=== RECENT LOG ==="
grep 'fw-hardening' /var/log/syslog 2>/dev/null | tail -n 5 | sed 's/^/     /'

echo; echo "=== LISTENING PORTS (not localhost) ==="
sudo ss -tlnp | awk 'NR>1 && $4 !~ /^(127\.|\[::1\])/ {split($6,a,"\""); print "     "$4"  "a[2]}' | sort -u
echo; echo "=== END ==="
