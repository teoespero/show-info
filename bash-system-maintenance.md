# Adding System Updates and Maintenance Tools to My Bash Hardware Info App

In my last Bash project, I built a System and Hardware Information tool with an IDE-style terminal interface.

It could show things like:

- Operating system
- CPU
- Memory
- Storage
- Network
- Graphics
- Battery
- USB devices
- Temperatures

At first, the tool was mostly for looking at information.

This time, I wanted to make it actually do something too.

So I added a new **Updates** section.

Now the same Bash program can check for system updates, install Ubuntu updates, check firmware, look for recommended hardware drivers, and tell me when the computer needs to restart.

The main thing I wanted was to keep everything inside the same terminal interface.

I did not want the program to suddenly drop back to a normal shell every time `sudo`, `apt`, or `fwupdmgr` needed something.

That turned out to be the interesting part.

---

## Adding an Updates Page

The first change was adding another item to the menu.

```bash
MENU_ITEMS=(
    "Overview"
    "Operating System"
    "Processor"
    "Memory"
    "Storage"
    "Network"
    "Graphics"
    "Battery"
    "Internal Hardware"
    "USB Devices"
    "Temperatures"
    "Updates"
)
```

When the user highlights **Updates**, the right side of the screen shows something like:

```text
SYSTEM UPDATES
------------------------------------------------------------

Package Updates           12 available
Security Updates          3 available
Reboot Required           No

FIRMWARE / BIOS
------------------------------------------------------------

Firmware Status           Up to date

HARDWARE DRIVERS
------------------------------------------------------------

Driver Status             No additional drivers

MAINTENANCE OPTIONS
------------------------------------------------------------

C   Check for updates
U   Install Ubuntu updates
F   Install firmware updates
D   Install recommended drivers
```

The keyboard shortcuts also change when the Updates page is selected.

```text
[C] Check   [U] Ubuntu Update   [F] Firmware   [D] Drivers   [Q] Quit
```

That made the maintenance section feel like part of the same app instead of a separate script.

---

## Checking for Ubuntu Updates

For normal system updates, I use `apt`.

To count available updates:

```bash
get_package_update_count() {

    local count

    count=$(
        apt list --upgradable 2>/dev/null |
            tail -n +2 |
            grep -c .
    )

    echo "${count:-0}"
}
```

This runs:

```bash
apt list --upgradable
```

and counts how many packages are available.

For security updates, I filter the list:

```bash
get_security_update_count() {

    local count

    count=$(
        apt list --upgradable 2>/dev/null |
            tail -n +2 |
            grep -Ei -- '-security|security' |
            wc -l
    )

    echo "${count:-0}"
}
```

This gives me a quick idea of how many updates are regular software updates and how many are related to security.

---

## Checking if a Reboot Is Required

Ubuntu creates this file when a restart is needed:

```text
/var/run/reboot-required
```

So checking for a reboot is simple:

```bash
get_reboot_status() {

    if [[ -f /var/run/reboot-required ]]; then
        echo "Yes"
    else
        echo "No"
    fi
}
```

This lets the Updates page show:

```text
Reboot Required           Yes
```

instead of making the user guess.

---

## Adding Firmware Update Checking

I also wanted to check BIOS and device firmware.

For that, I added:

```bash
fwupdmgr
```

which comes from:

```text
fwupd
```

The script checks for firmware updates with:

```bash
fwupdmgr get-updates
```

Then I look at the result and display something simple:

```text
Firmware Status           Updates available
```

or:

```text
Firmware Status           Up to date
```

I did not want to dump the entire `fwupdmgr` output into the normal screen because the goal of this project is still to keep things readable.

---

## Checking Hardware Drivers

For Ubuntu-supported drivers, I added:

```bash
ubuntu-drivers
```

The script can check for recommended hardware drivers with:

```bash
ubuntu-drivers list
```

If something is available, the program can show:

```text
Driver Status             Available: nvidia-driver-xxx
```

If nothing extra is needed:

```text
Driver Status             No additional drivers
```

This was especially useful because driver information can get messy if you just run everything manually.

---

## Keeping Updates Inside the IDE

This was probably the biggest improvement.

At first, I had the update process leave the IDE and go back to a normal terminal.

That worked, but it did not feel right.

The program would look like a terminal app, then suddenly become normal command output.

So I changed it.

Now the update process stays inside the right panel.

It looks something like:

```text
SYSTEM MAINTENANCE
------------------------------------------------------------

Installing Ubuntu package updates...

[##########################          ]

Installing available software and security updates.

Please do not close the program while this step is running.
```

The update command itself still runs normally.

For example:

```bash
sudo apt-get upgrade -y
```

But the output is redirected to a temporary log file:

```bash
"$@" </dev/null >"$logfile" 2>&1 &
```

Then the program watches the background process.

```bash
while kill -0 "$pid" 2>/dev/null; do
    draw_update_bar "$position" "$bar_width"
done
```

That way `apt` does not destroy the interface.

---

## Issue: Package Output Was Breaking the Screen

One of the problems I ran into was that command output could mess up the IDE borders.

Commands like:

```bash
apt-get
```

can print a lot of information.

If that output appears directly in the terminal, it can overwrite the menu, status bar, or borders.

The fix was redirecting the output:

```bash
> "$logfile" 2>&1
```

Now the command runs quietly in the background while the IDE shows its own progress display.

If something fails, I can still read the end of the log.

```bash
tail -8 "$logfile"
```

So I get a clean interface without hiding the error completely.

---

## Adding a Sudo Password Dialog

The next problem was `sudo`.

Normally, Linux would show something like:

```text
[sudo] password for user:
```

That would appear outside the layout and ruin the interface.

So instead, I made my own password dialog.

It looks like:

```text
+--------------------------------------------------------------+
|                    Administrator Password                    |
|                                                              |
|       Administrator access is required to continue.          |
|                                                              |
|       Password: ************************                     |
|                                                              |
|            ENTER Continue     ESC Cancel                     |
|                                                              |
+--------------------------------------------------------------+
```

The password is masked with `*`.

The input function reads one character at a time:

```bash
IFS= read -r -n1 char
```

Then it builds the password in memory.

```bash
DIALOG_PASSWORD+="$char"
```

But on the screen, I only show:

```text
********
```

instead of the real password.

---

## Using the Password With Sudo

Once the user enters the password, I send it to `sudo` through standard input.

```bash
printf '%s\n' "$DIALOG_PASSWORD" |
    sudo -S -p '' -v
```

After that, I remove the variable:

```bash
unset DIALOG_PASSWORD
```

I also check first if sudo credentials are already cached:

```bash
sudo -n true
```

If that works, the password dialog does not appear again.

That makes the tool a lot less annoying when several maintenance tasks are run one after another.

---

## Issue: Password Dialog Padding

Another thing that took some work was the box alignment.

Bash terminal interfaces are very easy to make ugly.

If the width calculation is off by even one character, you get something like:

```text
+----------------------+
| Password: ******      |
|                       |
+-----------------------+
```

The right side stops lining up.

The fix was to make every dialog use the same box-drawing function.

```bash
modal_draw() {

    local title="$1"
    local width="$2"
    local height="$3"

    MODAL_X=$(((COLS - width) / 2))
    MODAL_Y=$(((LINES - height) / 2))

    ...
}
```

Then every message, password box, reboot dialog, and error dialog uses the same calculations.

That helped fix the uneven padding.

---

## Centering Dialog Text

I also made a helper for centered text.

```bash
modal_center_text() {

    local relative_row="$1"
    local text="$2"

    local x=$(
        echo $((MODAL_X + (MODAL_W - ${#text}) / 2))
    )

    tput cup \
        $((MODAL_Y + relative_row)) \
        "$x"

    printf "%s" "$text"
}
```

That means I no longer have to guess how many spaces should go before a message.

The program calculates it.

This is a small thing, but it made the dialogs look much better.

---

## Adding Confirmation Dialogs

For updates, I did not want one keypress to immediately start changing the computer.

So I added confirmation boxes.

For example:

```text
+------------------------------------------------------------------+
|                      Ubuntu System Update                        |
|                                                                  |
|       Install all currently available Ubuntu updates?            |
|       A restart may be required after installation.              |
|                                                                  |
|          [Y] Install Updates     [N] Cancel                      |
|                                                                  |
+------------------------------------------------------------------+
```

The same function can be reused for:

- Ubuntu updates
- Driver installation
- Firmware updates
- Reboot confirmation

That made the code easier to manage.

---

## Installing Ubuntu Updates

The Ubuntu update process now works like this:

```text
Press U
   |
   +-- Confirmation dialog
          |
          +-- Sudo password dialog
                 |
                 +-- apt update
                 |
                 +-- apt upgrade
                 |
                 +-- Reboot check
```

The update commands are still simple:

```bash
sudo apt-get update
```

and:

```bash
sudo apt-get upgrade -y
```

The difference is the user does not see raw command output.

The IDE handles the display.

---

## Adding Driver Installation

For hardware drivers, pressing:

```text
D
```

first checks if Ubuntu recommends anything.

If no driver is needed:

```text
No additional recommended drivers were detected.
```

If one is available, the program asks before installing.

The command used is:

```bash
sudo ubuntu-drivers install
```

Again, the install stays inside the IDE with the same progress bar.

---

## Firmware Needed More Care

Firmware is a little different.

Installing a normal software update is one thing.

Updating BIOS or device firmware is more serious.

So I made the firmware option require confirmation.

The program also shows a warning:

```text
Keep the computer connected to power during the update.
```

Then it runs:

```bash
fwupdmgr update
```

with options that let my Bash interface handle the confirmation and restart message instead of letting `fwupdmgr` create its own prompts.

The goal was to keep the workflow consistent.

---

## Adding a Reboot Dialog

After an update, the script checks if the system needs to restart.

If it does, a popup appears:

```text
+--------------------------------------------------------------+
|                     Reboot Required                          |
|                                                              |
|       The update completed successfully.                     |
|       A restart is required to finish applying changes.      |
|                                                              |
|          [Y] Restart Now     [N] Restart Later               |
|                                                              |
+--------------------------------------------------------------+
```

If the user chooses restart later, the app stays open.

The status bar changes to:

```text
STATUS: Reboot required - restart later
```

If the user chooses restart now, the program runs:

```bash
sudo systemctl reboot
```

I like this much better than automatically restarting the computer.

---

## Issue: Firmware Reboots

Normal Ubuntu package updates can create:

```text
/var/run/reboot-required
```

But firmware updates may not always behave exactly the same way.

So I added another flag:

```bash
FORCE_REBOOT_REQUIRED=1
```

After a firmware update succeeds, the program treats the machine as needing a restart.

Then the same reboot dialog appears.

This keeps the behavior simple for the user.

---

## Fixing the Main Box Padding

I also went back and cleaned up the main IDE layout.

The left menu, divider, and right panel all use fixed geometry.

For example:

```bash
MENU_DIVIDER_X=27
```

The script then calculates:

```bash
MENU_INNER_WIDTH=$((MENU_DIVIDER_X - 1))
```

and:

```bash
RIGHT_WIDTH=$((COLS - MENU_DIVIDER_X - 2))
```

That means the program does not just guess the size of the borders.

The left panel knows exactly where it ends.

The right panel knows exactly how much space it has.

The result is cleaner alignment when the terminal changes size.

---

## Why I Kept ASCII Borders

I stayed with regular characters:

```text
+
-
|
```

instead of Unicode box characters.

It is not as fancy, but it works well across different terminals.

For a Bash project like this, I would rather have:

```text
+------------------------+
|       SYSTEM INFO      |
+------------------------+
```

work everywhere than spend time fixing terminal font problems.

---

## What This Project Became

Originally, this was just a system information viewer.

Now it is closer to a small maintenance console.

It can:

- View system information
- View hardware information
- Check Ubuntu updates
- Count security updates
- Check firmware
- Check recommended drivers
- Install software updates
- Install supported drivers
- Install firmware updates
- Ask for sudo passwords inside the UI
- Show installation progress
- Detect reboot requirements
- Ask before restarting

That is a lot more than where the project started.

---

## What I Learned This Time

The update features taught me a few new things.

I worked with:

- `apt`
- `sudo`
- `fwupdmgr`
- `ubuntu-drivers`
- background processes
- exit codes
- temporary log files
- masked keyboard input
- reusable confirmation dialogs
- reboot detection
- terminal layout calculations
- modal windows in Bash
- keeping command output inside a TUI

The biggest lesson was that the actual Linux commands are usually the easy part.

Running:

```bash
sudo apt-get upgrade -y
```

is simple.

Making it fit inside a terminal interface, asking for the password cleanly, handling failures, keeping the borders aligned, and asking about the reboot is where most of the work happens.

That is also the part I enjoy.

Take a normal Linux command.

Wrap it in Bash.

Add an interface.

Break the interface.

Fix the interface.

Then add one more feature and break it again.

That seems to be the process.

For now, my Bash System Information tool has officially turned into a System Information and Maintenance IDE.

And yes, I could just use the normal Ubuntu updater.

But again, where is the fun in that?

---

## Keywords

Bash, Linux, Shell Scripting, Bash Scripting, Ubuntu, Debian, System Administration, Linux Administration, Terminal UI, TUI, System Maintenance, System Updates, Ubuntu Updates, Security Updates, Firmware Updates, BIOS Updates, fwupd, fwupdmgr, Hardware Drivers, ubuntu-drivers, sudo, apt, apt-get, Reboot Detection, Reboot Required, Password Dialog, Modal Dialog, ASCII Interface, Terminal Interface, Progress Bar, Dependency Checking, Hardware Information, System Information, CPU Information, Memory Usage, Storage Information, Network Information, USB Devices, Battery Information, Linux Automation, Command Line, CLI, IT Administration, Linux Projects, Bash Projects, Troubleshooting, Terminal Programming, Learning Bash, System Tools, Software Updates, Driver Updates, Firmware Management
