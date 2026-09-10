# System & Hardware Information IDE – Update Notes

This update takes the Bash System & Hardware Information tool further and turns it into more of a small Linux maintenance console.

The main changes are:

- Unicode box-drawing characters for a cleaner IDE look
- Better box padding and alignment
- Live update activity inside the same IDE
- APT progress shown at the bottom of the update panel
- Current package or update action displayed while the update runs
- Built-in update and install logs
- A Logs / Rollback section
- Best-effort rollback for package and driver changes
- Faster log browsing
- More reliable refresh behavior
- Fix for leftover log text after closing the log viewer

---

## Unicode Boxes

The IDE now uses Unicode box-drawing characters when the terminal supports UTF-8.

Examples:

```text
┌──────────────────────────┬──────────────────────────────────────────────┐
│ SYSTEM INFO              │ Processor                                    │
│                          │                                              │
│ > Overview               │ PROCESSOR                                    │
│   Operating System       │ ───────────────────────────────────────────  │
│   Processor              │ Processor        Intel Core...               │
│   Memory                 │ CPU Threads      16                          │
└──────────────────────────┴──────────────────────────────────────────────┘
```

The script can still fall back to normal ASCII characters if Unicode is not supported.

One problem with Unicode borders is that they are multi-byte characters. A method like this:

```bash
printf "%${count}s" "" | tr " " "─"
```

can break the line character.

The updated code builds the line using Bash string replacement instead:

```bash
repeat_char() {

    local char="$1"
    local count="$2"
    local output=""

    ((count < 0)) && count=0

    printf -v output '%*s' "$count" ''

    output="${output// /$char}"

    printf "%s" "$output"
}
```

This keeps Unicode horizontal borders clean.

---

## Better Box Padding

The main IDE and popup windows now use the same geometry rules.

The left menu, right information panel, and modal windows all reserve padding between text and borders.

For example, the right panel no longer writes directly beside the border.

The script calculates the available area first:

```bash
RIGHT_WIDTH=$((COLS - MENU_DIVIDER_X - 2))
```

Then content is drawn inside that area instead of using hard-coded positions.

This fixed several off-by-one alignment problems.

---

## Live Update Progress

System updates now stay inside the IDE.

The right panel becomes a live maintenance screen while updates are running.

Example:

```text
SYSTEM MAINTENANCE
────────────────────────────────────────────────────────────

Installing Ubuntu package updates...

Get:14 linux-firmware...
Preparing package...
Unpacking package...
Configuring package...

Action: Configuring package
Item:   openssl

Progress [#########################               ] 63%
```

The progress bar stays near the bottom while the current action is shown above it.

Normal command output is redirected to a log so it does not destroy the terminal interface.

```bash
"$@" </dev/null >"$logfile" 2>&1 &
```

The script watches the background process and updates only the progress area.

---

## Sudo Password Dialog

The script no longer drops out of the IDE when administrator access is required.

Instead, it displays a centered password dialog.

```text
┌──────────────────────────────────────────────────────────────┐
│                  Administrator Password                      │
│                                                              │
│   Administrator access is required to continue.              │
│                                                              │
│   Password: ******************************                    │
│                                                              │
│            ENTER Continue     ESC Cancel                     │
└──────────────────────────────────────────────────────────────┘
```

The password is masked on screen.

The script validates it with:

```bash
printf '%s\n' "$DIALOG_PASSWORD" |
    sudo -S -p '' -v
```

The password variable is removed after use:

```bash
unset DIALOG_PASSWORD
```

If sudo credentials are already cached, the dialog is skipped.

---

## Reboot Dialog

If an update requires a restart, the program now asks inside the IDE.

```text
┌──────────────────────────────────────────────────────────────┐
│                     Reboot Required                          │
│                                                              │
│   The update completed successfully.                         │
│   A restart is required to finish applying changes.          │
│                                                              │
│       [Y] Restart Now        [N] Restart Later               │
└──────────────────────────────────────────────────────────────┘
```

Choosing restart later keeps the program open.

Choosing restart now runs:

```bash
sudo systemctl reboot
```

---

## Update and Install Logs

Every update or installation can now create a dated log.

Logs are stored in:

```text
~/.local/state/sysinfo-ide/logs
```

A typical log can contain:

```text
System & Hardware Information / Maintenance IDE
Operation : system-update
Started   : 2026-09-09 22:15:41 PDT
Computer  : workstation
User      : teo
----------------------------------------------------------------
[2026-09-09 22:15:41] Captured pre-update package snapshot.
[2026-09-09 22:15:42] APT command: apt-get update
[2026-09-09 22:15:43] Hit:1 ...
[2026-09-09 22:15:44] Get:2 ...
[2026-09-09 22:15:48] APT command completed successfully.
[2026-09-09 22:15:48] APT command: apt-get upgrade -y
[2026-09-09 22:15:49] Downloading openssl
[2026-09-09 22:15:52] Unpacking openssl
[2026-09-09 22:15:54] Setting up openssl
----------------------------------------------------------------
Finished  : 2026-09-09 22:16:19 PDT
Status    : success
```

This makes it easier to see what actually happened during an update.

---

## Logs / Rollback Page

A new menu item was added:

```text
Logs / Rollback
```

The main shortcuts include:

```text
L   View logs
B   Rollback
```

The log browser lets the user choose a log and open it inside the IDE.

The viewer supports scrolling with the arrow keys.

---

## Faster Log Viewer

The first log viewer was laggy.

The problem was that every Up or Down keypress could redraw the whole IDE.

If the user entered the log viewer from the Updates page, a full redraw could also run slower checks like:

```bash
fwupdmgr
ubuntu-drivers
```

That meant simply scrolling through a text file could trigger hardware checks.

The fix was to cache the log list and redraw only the rows that changed.

Instead of:

```bash
while true; do
    draw_ui
    draw_log
    read_key
done
```

the viewer now works more like:

```bash
draw_ui_cached
render_log_window "$offset" "$visible"

while true; do

    read_key

    case "$KEY" in

        $'\e[A'|$'\eOA')
            ((offset--))
            render_log_window "$offset" "$visible"
            ;;

        $'\e[B'|$'\eOB')
            ((offset++))
            render_log_window "$offset" "$visible"
            ;;

    esac

done
```

Only the visible log rows are updated.

This makes scrolling much faster.

---

## Rollback Transactions

Transaction data is stored separately in:

```text
~/.local/state/sysinfo-ide/transactions
```

Before a package update, the script can save a package-version snapshot.

After the update, it compares the before and after states.

A transaction may look like:

```text
CHANGED    openssl          3.0.13-0ubuntu3.5    3.0.13-0ubuntu3.6
CHANGED    libssl3          3.0.13-0ubuntu3.5    3.0.13-0ubuntu3.6
INSTALLED  linux-image-...  -                    6.x.x-...
```

For changed packages, the rollback function can try to reinstall the earlier version:

```text
openssl=3.0.13-0ubuntu3.5
libssl3=3.0.13-0ubuntu3.5
```

Rollback is best effort.

It only works when the older package versions are still available through APT.

---

## Rollback Safety Check

Before changing anything, the rollback function performs an APT simulation.

The idea is simple:

```text
Rollback selected
       |
       +-- Build old package version list
       |
       +-- Run APT simulation
       |
       +-- Simulation succeeds?
              |
              +-- Yes -> ask for confirmation
              |
              +-- No  -> stop
```

If APT cannot build a valid dependency plan, the rollback stops before changing the system.

This makes rollback safer than blindly forcing old packages back onto the machine.

---

## Firmware Rollback

Firmware activity is logged, but automatic firmware rollback is intentionally not included.

Firmware can include:

- BIOS / UEFI
- SSD firmware
- docks
- USB devices
- other hardware

A bad firmware downgrade can cause much bigger problems than a normal package downgrade.

Because of that, the script records the firmware activity but does not automatically downgrade firmware.

---

## Refresh Fix

Refresh was also improved.

The earlier version cleared the right panel first and then collected new information.

That could leave the screen blank while slower commands were running.

The new order is:

```text
Collect new information
        |
        v
Store completed output
        |
        v
Clear old panel
        |
        v
Draw new information
```

The important part looks like:

```bash
mapfile -t new_info_lines < <(
    get_information 2>&1
)

INFO_LINES=("${new_info_lines[@]}")

clear_right_panel
```

The old screen stays visible until the new information is ready.

---

## Refresh Lock

The script also uses a refresh lock.

This prevents a terminal resize event from interrupting a refresh and causing two redraws at the same time.

If a resize happens while a refresh is running, the resize is delayed until the refresh is finished.

This helps prevent partial borders and mixed screen contents.

---

## Timeout for Slow Hardware Checks

The Updates page uses commands such as:

```bash
fwupdmgr
ubuntu-drivers
```

These can sometimes take a while.

The updated version limits the slow status checks so one stuck command cannot make the whole refresh appear frozen.

This makes the Updates page much more predictable.

---

## Fixing Leftover Log Text

Another bug appeared after closing the log viewer.

Some log lines stayed behind inside the left menu panel.

For example:

```text
[2026-09-09 22:24:31]
[2026-09-09 22:24:32]
Finished :
Status   :
```

The cause was that `draw_menu()` redrew only the rows containing menu choices.

The lower part of the left panel was never erased.

The fix was to add a full left-panel clear:

```bash
clear_left_panel() {

    local row

    for ((row=2; row<=CONTENT_BOTTOM; row++)); do

        tput cup "$row" 1

        printf "%${MENU_INNER_WIDTH}s" ""

    done
}
```

Then the menu redraw starts by clearing the entire inside of the left panel:

```bash
draw_menu() {

    clear_left_panel

    # Draw menu again...

}
```

Now closing the log viewer, rollback browser, or another large popup restores the complete IDE background.

---

## What the Tool Can Do Now

The Bash System & Hardware Information IDE can now:

- View operating system information
- View CPU information
- View memory usage
- View storage information
- View network information
- View graphics hardware
- View battery information
- View internal PCI hardware
- View USB devices
- View system temperatures
- Check Ubuntu updates
- Check security updates
- Check firmware
- Check hardware drivers
- Install Ubuntu updates
- Install recommended drivers
- Install supported firmware
- Show live update progress
- Display what is currently downloading or installing
- Ask for sudo passwords inside the IDE
- Ask before rebooting
- Save update and install logs
- Browse logs inside the IDE
- Save package transaction information
- Attempt package and driver rollback
- Simulate rollback before changing anything
- Handle terminal resizing
- Refresh pages without blanking the screen
- Use Unicode box-drawing characters

---

## Final Thoughts

This project started as a system information viewer.

Then I added an IDE-style interface.

Then updates.

Then password dialogs.

Then firmware and driver support.

Then logs.

Then rollback.

Then I had to fix the log viewer because scrolling through a text file somehow became a hardware-checking operation.

Then I had to fix the fix because old log text stayed behind on the screen.

That is probably the most Bash part of this whole project.

The Linux commands themselves are usually simple.

The interesting part is getting all of those commands to behave like one clean terminal application.

At this point, the project is much closer to a small Linux System Information and Maintenance IDE than the simple system-info script it started as.

And there will probably be another feature after this one.

---

## Keywords

Bash, Linux, Shell Scripting, Bash Scripting, Ubuntu, Debian, Terminal UI, TUI, Unicode Terminal, Unicode Box Drawing, System Information, Hardware Information, System Maintenance, Ubuntu Updates, Linux Updates, Security Updates, Firmware Updates, BIOS Updates, fwupd, fwupdmgr, Hardware Drivers, ubuntu-drivers, apt, apt-get, sudo, Linux Logs, Update Logs, Install Logs, Rollback, Package Rollback, Driver Rollback, APT Simulation, Linux Administration, System Administration, Progress Bar, Live Progress, Terminal Programming, Modal Dialog, Password Dialog, Reboot Dialog, Dependency Checking, Troubleshooting, Linux Automation, IT Administration, CLI, Command Line, Bash Projects
