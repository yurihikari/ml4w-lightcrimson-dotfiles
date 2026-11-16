---
name: troubleshoot
description: Use to diagnose a technical problem (Windows or Linux workstation, network/Wi-Fi/VPN, Microsoft 365 /
  Exchange / Outlook / Teams, accounts/MFA, printers, telephony, backups, the user's own Linux desktop).
  Gives ranked hypotheses and exact commands, and records findings.
---
# Troubleshoot

## Method
1. **Scope**: one user or many? One device or all? Since when, and what changed
   (update, password, new device, move)? Error messages verbatim.
2. **Search memory first**: Grep `notes/kb/`, `tickets/`, the client file.
3. **Hypotheses**: 2–4, ranked by likelihood × ease of checking. Check cheapest first.
4. **Commands**: exact, copy-pasteable, with what result to expect for each hypothesis.
5. **Record**: findings into the ticket Log (if there is one). A reusable fix goes in `notes/kb/`.
6. **The user's own machine**: investigate directly (journalctl, systemctl status, configs)
   instead of asking the user to run commands.

## Checklists

### Windows workstation (PowerShell, admin when noted)
- Info: `Get-ComputerInfo | Select OsName,OsVersion,CsName` · uptime: `(Get-CimInstance Win32_OperatingSystem).LastBootUpTime`
- Events: `Get-WinEvent -LogName System -MaxEvents 50 | Where Level -le 2`
- Disk/health: `Get-PhysicalDisk` · `chkdsk C: /scan` · `sfc /scannow` (admin) · `DISM /Online /Cleanup-Image /RestoreHealth` (admin)
- Updates: `Get-HotFix | Sort InstalledOn -Desc | Select -First 5`
- Domain/Entra join: `dsregcmd /status`
- Group policy: `gpresult /r` · `gpupdate /force`

### Network
- `ipconfig /all` · `Test-NetConnection 8.8.8.8` · `Test-NetConnection <host> -Port 443`
- DNS: `Resolve-DnsName <name>` · `nslookup <name> 1.1.1.1` · flush: `ipconfig /flushdns`
- Path: `tracert <host>` · Linux: `ip a`, `ip r`, `resolvectl status`, `ping -c 4`, `mtr <host>`
- Wi-Fi: `netsh wlan show interfaces` · `netsh wlan show wlanreport`

### Microsoft 365 / mail
- Status: admin.microsoft.com → Service health.
- Delivery: Exchange admin center → Message trace (sender, recipient, date).
- DNS for a domain: MX, SPF (`v=spf1`), DKIM (`selector1._domainkey`), DMARC (`_dmarc`): `Resolve-DnsName -Type TXT <domain>`
- Outlook: new profile, `outlook.exe /safe`, cached mode / OST rebuild, check the mailbox in OWA first.
- Teams: clear cache `%appdata%\Microsoft\Teams` (classic) / reset the new Teams app.
- Sign-in problems: Entra admin → Users → Sign-in logs (error code), MFA methods, Conditional Access.

### Accounts / MFA
- Locked or disabled? Password expired? Sign-in log error code. MFA device changed?
- Never reset MFA without verifying identity through a second channel.

### Printers
- Spooler: `Restart-Service Spooler` (admin) · queue: `Get-PrintJob -PrinterName <name>`
- Driver/IP: `Get-Printer | Select Name,DriverName,PortName` · ping the printer IP.

### Security / RMM / backup
- RMM (NinjaOne, Datto…): device online? last check-in, failed policies, patch status.
- EDR (SentinelOne, Defender…): threats, quarantined items, agent status before blaming the app.
- Backup: last successful job, restore test date. A backup that was never restored is unverified.

### The user's own Linux desktop
- `journalctl -b -p err` · `systemctl --failed` · `systemctl --user --failed`
- `hyprctl rollinglog` · `qs log` · `coredumpctl list`
