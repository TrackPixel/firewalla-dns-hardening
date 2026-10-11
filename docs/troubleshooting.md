# Troubleshooting

Start with the health report; it usually points at the problem:

```bash
/home/pi/.firewalla/config/fw-hardening/healthcheck.sh
```

## I cannot SSH in after a reboot

Firewalla generates a new SSH password at every reboot unless you made it permanent. Get the new one in the app: Settings > Advanced > Configurations > SSH Console. You can also set a fixed password there, or better, use an SSH key (`~/.ssh/authorized_keys` on the box).

If the host key changed: `ssh-keygen -R <fw-ip>`.

## A local service stopped resolving (Plex, NAS, Home Assistant, `.lan` names)

That is rebinding protection doing its job on a name that legitimately points to a private IP. Add an exception for that domain only:

```bash
echo 'rebind-domain-ok=/plex.direct/' >> /home/pi/.firewalla/config/dnsmasq_local/fwh-rebind.conf
sudo systemctl restart firerouter_dns
```

## Work VPN: internal names do not resolve

Most VPN clients (GlobalProtect, AnyConnect, FortiClient) send DNS through the tunnel, which the Firewalla never sees, so nothing changes. The exception is a split-tunnel VPN where an internal domain is not in the VPN's split-DNS list **and** that domain publishes private IPs in public DNS. Then rebinding protection drops the answer.

Check with PowerShell (not `nslookup`, which ignores the VPN's DNS rules on Windows):

```powershell
Resolve-DnsName intranet.corp.example.com
```

If it fails while the VPN is up, add `rebind-domain-ok=/corp.example.com/` as above.

## Something stopped working and I suspect the DoH IP block

See whether the rule is actually rejecting traffic (the packet counters go up):

```bash
sudo iptables -L FORWARD -v -n | grep doh_block
```

Test an address and allow it:

```bash
sudo ipset test doh_block 203.0.113.10
echo '203.0.113.10' >> /home/pi/.firewalla/config/doh-ips-allow.txt
/home/pi/.firewalla/config/fw-hardening/doh_ipblock.sh reload
```

Or pause the whole layer for 5 minutes to confirm (see [undo.md](undo.md)).

## The canary alerts

Look at the reason in the log:

```bash
tail -n 20 /home/pi/.firewalla/config/dns_canary.log
```

| Message | Meaning |
|---|---|
| `canary ... resolves` | dnsmasq_local is not loaded. Check `systemctl status firerouter_dns` and that `fwh-canary.conf` exists |
| `control ... does not resolve` | DNS is down altogether, or your upstream is |
| `list too short` / `list is ...h old` | The daily download is failing. Check `grep fw-hardening /var/log/syslog` and internet access from the box |
| `DNS DNAT rule missing` | Firewalla rebuilt iptables and cron has not restored it yet. Should fix itself within 5 minutes |

## After a firmware update

```bash
crontab -l | grep fw-hardening
ls /home/pi/.firewalla/config/post_main.d/
/home/pi/.firewalla/config/fw-hardening/healthcheck.sh
```

If the cron entries are gone, re-run `bash install.sh` from the repo folder; it is idempotent.

## Lists are getting large

`tif.mini` holds about 240,000 domains and loads fine on a Gold SE. On smaller boxes, check memory with `free -m` after installing, and drop `fake` from `HAGEZI_LISTS` if needed.
