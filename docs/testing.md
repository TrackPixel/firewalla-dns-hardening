# Testing

Run these from a **PC on your network**, once before installing and once after. Replace `<fw-ip>` with your Firewalla's IP.

## Client tests

Windows (cmd for `nslookup`, PowerShell for `curl.exe`); on macOS/Linux use `dig` and `curl`.

| Test | Before | After |
|---|---|---|
| `nslookup example.com` | resolves | resolves (unchanged) |
| `nslookup <a domain on tif.mini> 8.8.8.8` | resolves | NXDOMAIN, even though you asked Google: the DNAT redirect works |
| `nslookup 192.168.0.10.nip.io` | 192.168.0.10 | no address: rebinding protection works |
| `nslookup 10.0.0.1.nip.io` | 10.0.0.1 | no address |
| `nslookup localtest.me` | 127.0.0.1 / ::1 | unchanged (localhost stays allowed) |
| `nslookup example.net` | resolves | NXDOMAIN (canary sentinel) |
| `curl.exe -s -o NUL -w "%{http_code}" -H "accept: application/dns-json" "https://1.1.1.1/dns-query?name=example.com&type=A"` | 200 | 000: DoH to a hardcoded IP is blocked |
| `curl.exe -s -o NUL -w "%{http_code}" "https://8.8.8.8/resolve?name=example.com"` | 200 | 000 |

To find a domain from the threat list for row 2:

```bash
sed -n '100p' /home/pi/.firewalla/config/dnsmasq_local/hagezi-tif.mini.conf
```

Do not visit it; only look it up.

Note: on Windows, `nslookup` shows the server you asked (e.g. `dns.google`), even though the Firewalla answered. That is the redirect at work.

## On the box

```bash
/home/pi/.firewalla/config/fw-hardening/healthcheck.sh
```

## Reboot test

Checks that the boot hook works, so there is no unfiltered window after a restart. Expect 2 to 3 minutes without internet.

```bash
sudo reboot
# log back in as soon as possible (the SSH password may have changed, see the app)
uptime
sudo iptables -S FORWARD | grep doh_block
sudo iptables -t nat -S PREROUTING | grep 'dport 53'
grep 'boot_enforce: rules applied' /var/log/syslog | tail -n 2
```

Rules present with an uptime under 3 minutes, and a `boot_enforce` log line shortly after boot, means the hook works. If not, `post_main.d` may not run on your firmware; cron still restores the rules within 5 minutes.

## Real-world checks

- Normal browsing, streaming, the Firewalla app
- Work VPN: connect and open an internal app (see troubleshooting if it fails)
- The healthchecks.io check stays green
- The next morning: `grep fw-hardening /var/log/syslog | grep updated`
