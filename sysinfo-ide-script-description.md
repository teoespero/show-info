# System & Hardware Information / Maintenance IDE

## Description

`sysinfo-ide-v2.sh` is a Bash-based terminal application for Ubuntu and Debian-based Linux systems.

It gives system and hardware information in one place using an IDE-style terminal interface. It also includes basic maintenance tools so you can check system health, install updates, review logs, and look back at previous update activity without leaving the terminal interface.

The script was designed as a system administration utility, not just a system information viewer.

## What It Does

The script can display information about:

- Operating system
- Kernel
- CPU
- Memory
- Storage
- Network interfaces
- Graphics hardware
- Battery
- PCI hardware
- USB devices
- System temperatures
- Disk health
- Failed services
- Reboot status
- Pending software updates

It also includes maintenance functions for:

- Checking Ubuntu package updates
- Installing software and security updates
- Checking firmware updates
- Installing supported firmware updates
- Checking Ubuntu-recommended hardware drivers
- Installing recommended drivers
- Showing update progress inside the terminal interface
- Asking for sudo credentials through a built-in dialog
- Asking before rebooting
- Saving update and install logs
- Viewing logs inside the IDE
- Searching logs
- Viewing rollback history
- Attempting package and driver rollback
- Exporting system reports
- Checking recent system errors and warnings

## Interface

The program uses a terminal user interface with a menu on the left and information on the right.

When UTF-8 is available, it uses Unicode box-drawing characters.

Example:

```text
┌──────────────────────────┬───────────────────────────────────────────────┐
│ SYSTEM INFO              │ System Health                                 │
│                          │                                               │
│   Overview               │ OVERALL STATUS                                │
│   Operating System       │                                               │
│   Processor              │ Memory Usage            34%        OK         │
│   Memory                 │ Root Disk Usage         61%        OK         │
│   Storage                │ CPU Temperature         52 C       OK         │
│   Network                │ Failed Services         0          OK         │
│   Graphics               │ Reboot Required         No         OK         │
│   Updates                │                                               │
│   Logs / Rollback        │                                               │
│ > System Health          │                                               │
└──────────────────────────┴───────────────────────────────────────────────┘
```

If Unicode is not available, the script can fall back to normal ASCII-style borders.

## Main Sections

The menu includes:

- Overview
- Operating System
- Processor
- Memory
- Storage
- Network
- Graphics
- Battery
- Internal Hardware
- USB Devices
- Temperatures
- Updates
- Logs / Rollback
- System Health
- Events / Problems

## Update Functions

The Updates page can:

- Check for available Ubuntu updates
- Show the number of pending packages
- Show security updates
- Check firmware status
- Check recommended hardware drivers
- Install Ubuntu updates
- Install supported drivers
- Install supported firmware
- Show the current update action
- Show progress inside the IDE
- Detect when a reboot is needed

The program does not automatically restart the computer. It asks first.

## Logs

Update and installation logs are stored under:

```text
~/.local/state/sysinfo-ide/logs
```

The log viewer can be opened from inside the program.

The viewer supports:

- Scrolling
- Searching
- Viewing errors
- Viewing warnings
- Reviewing previous update activity

## Rollback

The script saves package information before and after supported update operations.

Transaction data is stored under:

```text
~/.local/state/sysinfo-ide/transactions
```

For supported package and driver operations, the rollback function can try to return packages to their previous versions.

Before performing a rollback, the script runs an APT simulation first.

If APT cannot create a valid rollback plan, the script stops before changing the system.

Firmware rollback is not performed automatically.

## System Health

The System Health page gives a quick view of the current condition of the computer.

It can check:

- Memory usage
- Disk usage
- CPU temperature
- Failed services
- Pending updates
- Reboot status
- SMART disk health

Warning levels can be changed in the configuration file.

## Events / Problems

The Events / Problems page gives a quick summary of recent system problems.

It can show:

- Failed services
- Recent boot errors
- Kernel warnings
- Other useful troubleshooting information

This is meant as a quick view and does not replace tools such as `journalctl`.

## Configuration

The script uses a configuration file located at:

```text
~/.config/sysinfo-ide/config
```

Settings can control things such as:

- Log retention
- Update check timeouts
- Cache timing
- Memory warning levels
- Disk warning levels
- Temperature warning levels
- Temperature critical levels

## Export

The script can export system information to files.

Exports are stored under:

```text
~/.local/state/sysinfo-ide/exports
```

Supported report formats include:

- Text
- JSON

## Refresh and Caching

The script uses page caching so slower hardware checks do not run every time the screen redraws.

This helps reduce lag when:

- Opening dialogs
- Closing logs
- Moving through menus
- Refreshing the interface

Pressing `R` or `Enter` forces the current page to refresh.

## Scrolling

Long pages support:

```text
PgUp
PgDn
Home
End
```

This is useful for pages such as:

- USB devices
- Storage
- Hardware information
- Logs
- Events

## Dependencies

The script uses common Linux utilities including:

```text
lscpu
lsblk
lspci
lsusb
ip
upower
sensors
fwupdmgr
ubuntu-drivers
smartctl
systemctl
journalctl
apt
sudo
```

On Ubuntu and Debian-based systems, the script can help install missing dependencies.

## Running the Script

Make the script executable:

```bash
chmod +x sysinfo-ide-v2.sh
```

Run it:

```bash
./sysinfo-ide-v2.sh
```

## Self-Check

The script also includes a self-check option:

```bash
./sysinfo-ide-v2.sh --self-check
```

This can check Bash syntax and use tools such as `shellcheck` and `shfmt` when they are installed.

## Purpose

The script is meant to provide a single terminal-based place for common Linux system information and maintenance tasks.

Instead of running several separate commands for hardware information, updates, logs, health checks, and basic troubleshooting, the script brings them together in one interface.
