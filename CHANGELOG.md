# Changelog

## 1.0.0 (2026-10-11)

First public release, packaging a setup that has been running on a Gold SE (bridge mode) since August 2026.

- Hagezi blocklists (TIF mini, DoH, fake) in dnsmasq with download guard
- Forced DNS (DNAT 53), DoT/DoQ block (853), IPv6 DNS block, optional SMTP block
- DoH block by IP via ipset, with allow-list
- DNS rebinding protection with exception list
- Canary with healthchecks.io alerting, self-recovering after short hiccups
- Boot hook via post_main.d plus 5-minute cron safety net
- Read-only health report
- Installer and full uninstaller
