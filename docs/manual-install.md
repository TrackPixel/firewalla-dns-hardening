# Manual install

`install.sh` does all of this for you. Use this page if you want to understand each step, or install only some layers.

All commands run on the Firewalla as user `pi`. `CFG` is `/home/pi/.firewalla/config`.

## 0. Before you start

```bash
ssh pi@<firewalla-ip>
git clone https://github.com/TrackPixel/firewalla-dns-hardening.git
cd firewalla-dns-hardening
CFG=/home/pi/.firewalla/config
```

Do the "before" tests in [testing.md](testing.md) first, so you can compare.

## 1. Scripts and settings

```bash
mkdir -p $CFG/fw-hardening
cp scripts/*.sh $CFG/fw-hardening/
chmod 755 $CFG/fw-hardening/*.sh
cp config/fw-hardening.env.example $CFG/fw-hardening.env
nano $CFG/fw-hardening.env      # set CONTROL_DOMAIN, optionally HC_URL
```

Check that the IP is detected:

```bash
bash -c ". $CFG/fw-hardening/common.sh; echo \"\$LAN_IF \$FW_IP\""
```

## 2. Blocklists (layer 1)

```bash
$CFG/fw-hardening/update_blocklist.sh
ls -l $CFG/dnsmasq_local/hagezi-*.conf
```

## 3. DNS rebinding protection (layer 5)

```bash
cp config/rebind.conf $CFG/dnsmasq_local/fwh-rebind.conf
sudo systemctl restart firerouter_dns
```

## 4. Canary sentinel (layer 8)

```bash
cp config/canary.conf $CFG/dnsmasq_local/fwh-canary.conf   # blocks example.net
sudo systemctl restart firerouter_dns
```

If you change `CANARY_DOMAIN`, change the `local=/.../` line too.

## 5. Firewall rules (layers 2, 3, 6, 7)

```bash
$CFG/fw-hardening/enforce_dns.sh
sudo iptables -t nat -S PREROUTING | grep 'dport 53'
```

## 6. DoH by IP (layer 4)

```bash
cp config/doh-ips-allow.txt.example $CFG/doh-ips-allow.txt
$CFG/fw-hardening/doh_ipblock.sh update
sudo iptables -S FORWARD | grep doh_block
```

## 7. Boot hook (layer 9)

```bash
mkdir -p $CFG/post_main.d
cp scripts/boot_enforce.sh $CFG/post_main.d/fw-hardening-boot.sh
chmod 755 $CFG/post_main.d/fw-hardening-boot.sh
```

## 8. Cron

Firewalla keeps user cron entries in `$CFG/user_crontab`. Back it up, add the lines you want, and reload:

```bash
cp $CFG/user_crontab $CFG/user_crontab.bak.$(date +%Y%m%d)
cat >> $CFG/user_crontab <<'EOF'
30 4 * * * /home/pi/.firewalla/config/fw-hardening/update_blocklist.sh # fw-hardening
40 4 * * * /home/pi/.firewalla/config/fw-hardening/doh_ipblock.sh update # fw-hardening
*/5 * * * * /home/pi/.firewalla/config/fw-hardening/enforce_dns.sh # fw-hardening
*/5 * * * * /home/pi/.firewalla/config/fw-hardening/doh_ipblock.sh enforce # fw-hardening
*/10 * * * * /home/pi/.firewalla/config/fw-hardening/dns_canary.sh # fw-hardening
EOF
bash /home/pi/firewalla/scripts/update_crontab.sh
crontab -l | grep fw-hardening
```

## 9. Alerting (optional)

1. Create a check on healthchecks.io: period **1 hour**, grace **20 minutes**.
2. Put the ping URL in `fw-hardening.env` as `HC_URL`.
3. Run `$CFG/fw-hardening/dns_canary.sh` once; the check should turn green.

## 10. Verify

```bash
$CFG/fw-hardening/healthcheck.sh
```

Then do the client tests in [testing.md](testing.md).
