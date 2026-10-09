# Sysinfo IDE v2 - Updated Script Notes

**Author:** Teo Espero  
**Script:** `sysinfo-ide-v2.sh`  
**Platform:** Ubuntu / Debian-based Linux systems  
**Updated:** October 8, 2026

---

## Overview

`sysinfo-ide-v2.sh` is a terminal-based system information and maintenance app written in Bash.

It gives a simple menu-style interface for checking system information, hardware details, updates, logs, rollback records, and basic system health.

The goal is to make common Linux checks easier to view from one place instead of running several commands one by one.

---

## Main Features

The app includes pages for:

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

It also includes update-related actions such as:

- Checking for Ubuntu package updates
- Installing Ubuntu package updates
- Installing supported firmware updates
- Installing recommended Ubuntu hardware drivers
- Viewing update and install logs
- Browsing rollback transactions

---

## Controls

| Key | Action |
| --- | --- |
| UP / DOWN | Move through the menu |
| ENTER | Refresh the current page |
| R | Refresh the current page |
| E | Export the current system report |
| Q | Quit |

### Updates Page Controls

| Key | Action |
| --- | --- |
| C | Check for updates |
| U | Install Ubuntu package updates |
| F | Install supported firmware updates |
| D | Install Ubuntu-recommended hardware drivers |
| L | Open update/install logs |
| B | Open rollback transactions |

---

## What Was Wrong Before

The app worked, but it felt rough to use.

The biggest problems were:

1. The screen flickered too much.
2. Moving through the menu felt delayed.
3. Some pages ran slower checks right away, even when I was only passing through the menu.
4. The app repeated some system commands more often than needed.

The app was functional, but the experience was not as smooth as it should have been.

---

## What Was Fixed

### 1. Reduced Screen Flicker

Before, the app refreshed more of the screen than it needed to. This caused the terminal to look like it was blinking or jumping around.

The fix was to reduce unnecessary redraws and reuse the existing screen when possible.

Instead of rebuilding everything all the time, the app now tries to repaint only what needs to change.

---

### 2. Faster Menu Movement

Before, moving from one menu item to another could trigger page checks immediately.

That made the menu feel slow, especially when landing on pages that checked updates, firmware, drivers, logs, or disk health.

The fix was to make normal menu movement lighter.

Now the app can move through the menu faster while still showing useful information.

---

### 3. Better Caching

Some system checks do not need to run every second.

For example:

- Operating system information does not change often.
- Hardware information does not change often.
- Storage and memory information can be reused briefly.
- Update checks should not run every time the Updates page is opened.

The app now reuses recent results when it can.

That means it spends less time asking the system for the same information over and over again.

---

### 4. Slower Checks Run Only When Needed

Some commands are naturally slower than others.

Examples include:

```bash
apt list --upgradable
fwupdmgr get-updates
ubuntu-drivers list
smartctl -H
journalctl
```

These commands can pause the interface, especially on slower systems.

The updated script avoids running these heavier checks during normal menu browsing.

For update checks, the app now expects the user to press `C` on the Updates page when they actually want to check for updates.

---

### 5. Less Repeated Command Use

Some pages were calling the same command more than once during the same page load.

For example, memory and disk information can be collected once and reused while building the page output.

This makes the page load cleaner and faster.

---

## Before and After

### Before

- Menu movement had a delay.
- The screen flickered during redraws.
- Slow checks could run just by highlighting a page.
- Some commands were repeated more than needed.
- The app worked, but felt heavy.

### After

- Menu movement feels faster.
- The screen redraws less.
- Slower checks only run when they matter.
- Recent results are reused through caching.
- The app feels smoother and less annoying to use.

---

## Why This Matters

A script can work and still need tuning.

The first goal was to make the app useful. Once that worked, the next step was making it nicer to use.

For a terminal app, speed and screen behavior matter.

If the interface flickers too much or pauses every time the user moves around, the tool feels unfinished even if the commands are correct.

This update focused on making the script feel better during actual use.

---

## How to Install

Copy the script into your Bash scripts folder:

```bash
cd /home/support/Documents/bash-shell-scripts
```

Back up the current version:

```bash
mv sysinfo-ide-v2.sh sysinfo-ide-v2.backup.$(date +%Y%m%d-%H%M%S).sh
```

Copy the updated version into place:

```bash
cp ~/Downloads/sysinfo-ide-v2-turbo.sh sysinfo-ide-v2.sh
```

Make it executable:

```bash
chmod +x sysinfo-ide-v2.sh
```

Check for syntax errors:

```bash
bash -n sysinfo-ide-v2.sh
```

Run it:

```bash
./sysinfo-ide-v2.sh
```

---

## Optional: Run It From Anywhere

If the script folder is already in your `PATH`, you can run:

```bash
sysinfo-ide-v2.sh
```

If not, you can add the folder to your path by editing your shell config file:

```bash
nano ~/.bashrc
```

Add this line:

```bash
export PATH="$PATH:/home/support/Documents/bash-shell-scripts"
```

Reload Bash:

```bash
source ~/.bashrc
```

Then run:

```bash
sysinfo-ide-v2.sh
```

---

## Notes

This script is mainly designed for Ubuntu and Debian-based systems.

Some features depend on tools such as:

- `apt`
- `systemctl`
- `fwupdmgr`
- `ubuntu-drivers`
- `smartctl`
- `sensors`
- `lspci`
- `lsusb`

The script checks for missing dependencies and can help install supported tools on Ubuntu or Debian-based systems.

---

## Revision History

| Version | Date | Notes |
| --- | --- | --- |
| v1 | Initial build | Basic system and hardware information interface |
| v2 | Updated build | Added updates, firmware, drivers, logs, rollback, and system health pages |
| v2 Fast Fix | October 2026 | Reduced flicker, improved redraw behavior, and added better caching |
| v2 Turbo | October 2026 | Reduced slow checks during menu movement and improved page loading speed |

---

## Summary

This update was not about adding flashy features.

It was about making the app feel better.

The sysinfo app already worked, but it was too slow and flickered too much. The updated version is smoother, faster, and less annoying to use.

That matters because a terminal tool should not just work. It should feel usable too.
