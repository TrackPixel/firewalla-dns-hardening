# How it works

The goal: **malware and phishing domains must stay blocked, whatever a device or app tries.** Each layer below closes one specific way around the filter. They are independent; you can use any subset.

## 1. Threat blocklists in dnsmasq

Firewalla's DNS server is dnsmasq, and it loads every file in `/home/pi/.firewalla/config/dnsmasq_local/`. `update_blocklist.sh` downloads Hagezi lists in dnsmasq format (`local=/domain/`, which answers NXDOMAIN) into that folder.

Why not only Firewalla's own blocking? Rules in the app are tied to monitoring. A device set to "no monitoring", or the whole network during Emergency Access, skips them. Entries in `dnsmasq_local` apply to every DNS query the box answers.

Default lists:

- `tif.mini`: Threat Intelligence Feeds, size-optimised (malware, phishing, C2, cryptojacking)
- `doh`: hostnames of DoH/DoT resolvers, so apps cannot look up an alternative resolver
- `fake`: fake shops and scam sites

**Download guard:** a list only replaces the current one when it has at least `MIN_LIST_ENTRIES` valid lines. A broken download never leaves you with an empty list.

## 2. Forced DNS (DNAT port 53)

Blocklists only help if devices ask the Firewalla. Many devices and apps use 8.8.8.8 or 1.1.1.1 directly. `enforce_dns.sh` adds an iptables DNAT rule that rewrites every client DNS packet on `LAN_IF` to the Firewalla, whatever server the client intended. The client does not notice; it simply gets a filtered answer.

## 3. DoT / DoQ block (port 853)

DNS-over-TLS and DNS-over-QUIC use port 853 and are encrypted, so they cannot be redirected. They are rejected instead. Well-behaved clients (Android Private DNS in automatic mode, for example) then fall back to plain DNS, which layer 2 catches.

## 4. DoH block by IP

DNS-over-HTTPS hides inside normal HTTPS on port 443. The `doh` hostname list already blocks clients that look up their resolver by name (browsers, most apps). What remains are clients that connect to a hardcoded IP like `1.1.1.1:443` or `8.8.8.8:443`; typically malware or stubborn IoT.

`doh_ipblock.sh` loads Hagezi's DoH IP list (about 1,400 IPv4 addresses) into an ipset called `doh_block` and rejects tcp+udp 443 to those addresses in the FORWARD chain. Two details:

- The Firewalla's own encrypted upstream DNS runs in the OUTPUT chain, so it is not affected.
- Those IPs run almost nothing but DNS, so normal browsing does not break. If something legitimate does, add its IP to `doh-ips-allow.txt`.

## 5. DNS rebinding protection

A malicious site can make your browser load its page, then change its DNS record to a private address like `192.168.1.10`. The browser still thinks it is talking to the same site, so the site's script can now talk to your router, NAS or cameras.

`fwh-rebind.conf` enables dnsmasq's `stop-dns-rebind`: answers from upstream that point to private ranges are dropped. `rebind-localhost-ok` keeps 127.0.0.1 working. Legitimate cases (Plex's `plex.direct`, split-horizon company domains) go in as `rebind-domain-ok=/domain/`.

## 6. IPv6

If your ISP gives you global IPv6, a client could send DNS over IPv6 and skip the IPv4 redirect. `enforce_dns.sh` rejects forwarded IPv6 port 53 and 853, so clients fall back to IPv4 DNS. These rules are harmless if you have no IPv6.

## 7. Outbound SMTP (optional)

Infected devices are often used to send spam directly to mail servers on port 25. Normal mail clients use 587 or 465. `BLOCK_SMTP=1` rejects client traffic to tcp/25. Set it to 0 if you run something that needs it.

## 8. Canary

Custom setups fail silently: a firmware update, a broken download, a rebuilt firewall. `dns_canary.sh` runs every 10 minutes and checks:

1. `CANARY_DOMAIN` (blocked on purpose in `fwh-canary.conf`) returns NXDOMAIN. If it resolves, the dnsmasq_local layer is gone.
2. `CONTROL_DOMAIN` resolves, so DNS itself is alive.
3. `hagezi-tif.mini.conf` exists, is big enough and younger than 48 hours.
4. The DNAT rule is present.

Each run retries 3 times. Outcomes go to healthchecks.io (or any compatible service): success pings normally, a failure pings `/log` (recorded, no alert), and only `CANARY_FAIL_AFTER` failed runs in a row ping `/fail`. The next good run turns the check green again, without you touching anything.

Pick a canary domain that **only** your setup blocks. A domain that Firewalla also blocks through its own rules (gaming, ads) keeps passing even if your lists disappear.

## 9. Boot hook and cron

Firewalla rebuilds its iptables rules at boot and occasionally afterwards. Every rule script is idempotent (`-C` check before `-I` insert), so running it again never creates duplicates.

- `post_main.d/fw-hardening-boot.sh` runs right after Firewalla's main service starts, and again 60 seconds later.
- Cron re-asserts the rules every 5 minutes as a safety net.
