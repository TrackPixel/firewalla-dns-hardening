# Undo

## Everything

From the repo folder on the box:

```bash
bash uninstall.sh            # keeps fw-hardening.env and doh-ips-allow.txt
bash uninstall.sh --purge    # removes those too
```

This removes the cron entries (with a backup of `user_crontab`), the boot hook, all iptables/ip6tables rules and the ipset, the dnsmasq files (lists, rebind, canary), the scripts, state and logs, and restarts DNS. Afterwards the box behaves like stock Firewalla.

Don't forget to pause or delete your healthchecks.io check, or it will alert.

Verify:

```bash
crontab -l | grep -c fw-hardening                 # 0
sudo iptables-save | grep -c doh_block            # 0
ls /home/pi/.firewalla/config/dnsmasq_local/       # no hagezi-* or fwh-* files
```

A reboot also clears every firewall rule once the cron entries and boot hook are gone.

## Pause a layer for a few minutes

Useful to test whether a layer causes a problem. Cron puts the rules back within 5 minutes.

```bash
D=/home/pi/.firewalla/config/fw-hardening
$D/doh_ipblock.sh remove      # DoH IP block off (restore: $D/doh_ipblock.sh update)
$D/enforce_dns.sh remove      # DNS redirect, 853, IPv6 and SMTP rules off
```

## One layer permanently

Remove the matching cron line(s) from `/home/pi/.firewalla/config/user_crontab`, run `bash /home/pi/firewalla/scripts/update_crontab.sh`, then:

| Layer | Remove with |
|---|---|
| Blocklists | `$D/update_blocklist.sh remove` |
| DNS redirect / 853 / IPv6 / SMTP | `$D/enforce_dns.sh remove` (and remove its line from the boot hook) |
| DoH by IP | `$D/doh_ipblock.sh remove` (and remove its line from the boot hook) |
| Rebinding protection | `rm /home/pi/.firewalla/config/dnsmasq_local/fwh-rebind.conf && sudo systemctl restart firerouter_dns` |
| Canary | `rm /home/pi/.firewalla/config/dnsmasq_local/fwh-canary.conf /home/pi/.firewalla/config/dns_canary.*` and restart `firerouter_dns` |
| Boot hook | `rm /home/pi/.firewalla/config/post_main.d/fw-hardening-boot.sh` |
| SMTP block only | set `BLOCK_SMTP=0` in `fw-hardening.env`, then `$D/enforce_dns.sh remove && $D/enforce_dns.sh` |
