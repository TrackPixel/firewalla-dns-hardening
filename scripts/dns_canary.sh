#!/bin/bash
# firewalla-dns-hardening: canary that proves the filtering layer still works.
#
# Every run (cron, every 10 minutes) checks:
#   1. CANARY_DOMAIN is blackholed (NXDOMAIN) by the Firewalla.
#      It is blocked on purpose in dnsmasq_local/canary.conf. If it resolves,
#      the dnsmasq_local layer is no longer loaded.
#   2. CONTROL_DOMAIN resolves (DNS itself is alive).
#   3. hagezi-tif.mini.conf exists, has >= MIN_LIST_ENTRIES lines and is
#      younger than 48 hours (the daily update is running).
#   4. The DNS redirect (DNAT port 53) is present in iptables.
#
# Each check gets 3 attempts, so a short hiccup does not count as a failure.
# Result handling (healthchecks.io-compatible HC_URL):
#   all OK                          -> ping HC_URL         (check goes green)
#   failed, < CANARY_FAIL_AFTER runs -> ping HC_URL/log    (logged, no alert)
#   failed, >= CANARY_FAIL_AFTER    -> ping HC_URL/fail   (alert)
# The check recovers to green by itself on the next good run.
#
# Note: do NOT use a domain that Firewalla blocks by itself (e.g. through its
# own gaming or ad rules) as canary. It would keep "passing" even if the
# Hagezi layer disappeared.
. "$(dirname "$(readlink -f "$0")")/common.sh"

STATE=$CFG/dns_canary.state
LOGF=$CFG/dns_canary.log
LIST=$DNSMASQ_DIR/hagezi-tif.mini.conf

status_of() { dig +time=3 +tries=1 "$1" @"$FW_IP" 2>/dev/null | awk '/status:/{gsub(",","",$6); print $6; exit}'; }
answer_of() { dig +short +time=3 +tries=1 "$1" @"$FW_IP" 2>/dev/null | grep -E '^[0-9a-fA-F:.]+$' | head -n1; }

check_once() {
  local s a
  s=$(status_of "$CANARY_DOMAIN")
  a=$(answer_of "$CANARY_DOMAIN")
  if [ "$s" != "NXDOMAIN" ] && [ -n "$a" ] && [ "$a" != "0.0.0.0" ]; then
    echo "canary $CANARY_DOMAIN resolves ($a)"; return 1
  fi
  [ -n "$(answer_of "$CONTROL_DOMAIN")" ] || { echo "control $CONTROL_DOMAIN does not resolve"; return 1; }
  [ -f "$LIST" ] || { echo "$(basename "$LIST") missing"; return 1; }
  local n age
  n=$(wc -l < "$LIST")
  [ "$n" -ge "$MIN_LIST_ENTRIES" ] || { echo "list too short ($n)"; return 1; }
  age=$(( ($(date +%s) - $(stat -c %Y "$LIST")) / 3600 ))
  [ "$age" -lt 48 ] || { echo "list is ${age}h old"; return 1; }
  sudo iptables -t nat -S PREROUTING | grep -q -- "--dport 53 .*DNAT" || { echo "DNS DNAT rule missing"; return 1; }
  echo "ok (list $n entries, ${age}h old)"
  return 0
}

result=""; ok=1
for try in 1 2 3; do
  if result=$(check_once); then ok=0; break; fi
  [ "$try" -lt 3 ] && sleep 10
done

streak=$(cat "$STATE" 2>/dev/null || echo 0)
hc_ping() { [ -n "$HC_URL" ] && curl -fsS -m 10 --retry 3 --data-raw "$result" "$HC_URL$1" >/dev/null 2>&1; }

if [ $ok -eq 0 ]; then
  streak=0; hc_ping ""
else
  streak=$((streak + 1))
  if [ "$streak" -ge "$CANARY_FAIL_AFTER" ]; then hc_ping "/fail"; else hc_ping "/log"; fi
fi
echo "$streak" > "$STATE"
echo "$(date '+%F %T') ok=$((1-ok)) streak=$streak $result" >> "$LOGF"

# Keep the log small
if [ "$(wc -l < "$LOGF")" -gt 5000 ]; then
  tail -n 2000 "$LOGF" > "$LOGF.tmp" && mv "$LOGF.tmp" "$LOGF"
fi
