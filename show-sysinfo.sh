#!/usr/bin/env bash

# ============================================================
# SYSTEM & HARDWARE INFORMATION / MAINTENANCE IDE
# ============================================================
#
# Controls:
#   UP / DOWN  Navigate menu
#   ENTER      Refresh current page
#   R          Refresh current page
#   Q          Quit
#
# Updates page:
#   C          Check for updates
#   U          Install Ubuntu package updates
#   F          Install supported firmware updates
#   D          Install Ubuntu-recommended hardware drivers
#
# Designed primarily for Ubuntu / Debian-based systems.
# ============================================================

# ------------------------------------------------------------
# COLORS
# ------------------------------------------------------------

RESET="\033[0m"
BOLD="\033[1m"
GREEN="\033[32m"
CYAN="\033[36m"
YELLOW="\033[33m"
RED="\033[31m"

SELECT_BG="\033[44m"
SELECT_FG="\033[97m"

# ------------------------------------------------------------
# DEPENDENCIES
# ------------------------------------------------------------

declare -A DEPENDENCIES=(
    [lspci]="pciutils"
    [lsusb]="usbutils"
    [sensors]="lm-sensors"
    [upower]="upower"
    [ip]="iproute2"
    [lsblk]="util-linux"
    [lscpu]="util-linux"
    [fwupdmgr]="fwupd"
    [ubuntu-drivers]="ubuntu-drivers-common"
)

# ------------------------------------------------------------
# PRE-IDE DEPENDENCY INSTALL ACTIVITY BAR
# ------------------------------------------------------------

progress_bar() {

    local pid="$1"
    local label="$2"

    local width=40
    local position=1

    while kill -0 "$pid" 2>/dev/null; do

        local bar=""
        local blank=""

        printf -v bar '%*s' "$position" ''
        bar="${bar// /#}"

        printf -v blank '%*s' "$((width - position))" ''

        printf "\r%-22s [" "$label"

        printf "${GREEN}%s${RESET}" "$bar"

        printf "%s]" "$blank"

        ((position++))

        if ((position > width)); then
            position=1
        fi

        sleep 0.08

    done

    local complete=""

    printf -v complete '%*s' "$width" ''
    complete="${complete// /#}"

    printf "\r%-22s [${GREEN}%s${RESET}]\n" \
        "$label" \
        "$complete"
}


run_with_progress() {

    local label="$1"

    shift

    local logfile

    logfile=$(mktemp)

    "$@" >"$logfile" 2>&1 &

    local pid=$!

    progress_bar "$pid" "$label"

    wait "$pid"

    local result=$?

    if ((result != 0)); then

        echo

        printf "${RED}[ERROR]${RESET} %s failed.\n" "$label"

        echo
        echo "Last messages:"
        echo "------------------------------------------------------------"

        tail -20 "$logfile"

        echo "------------------------------------------------------------"

        rm -f "$logfile"

        return "$result"

    fi

    rm -f "$logfile"

    return 0
}


# ------------------------------------------------------------
# DEPENDENCY CHECK
# ------------------------------------------------------------

check_dependencies() {

    local missing_commands=()
    local missing_packages=()

    local cmd
    local package
    local existing
    local already_added

    for cmd in "${!DEPENDENCIES[@]}"; do

        if ! command -v "$cmd" >/dev/null 2>&1; then
            missing_commands+=("$cmd")
        fi

    done

    for cmd in "${missing_commands[@]}"; do

        package="${DEPENDENCIES[$cmd]}"

        already_added=0

        for existing in "${missing_packages[@]}"; do

            if [[ "$existing" == "$package" ]]; then

                already_added=1
                break

            fi

        done

        if ((already_added == 0)); then
            missing_packages+=("$package")
        fi

    done

    if ((${#missing_packages[@]} == 0)); then
        return 0
    fi

    clear

    echo "+------------------------------------------------------------+"
    echo "|              SYSTEM & HARDWARE INFORMATION                 |"
    echo "|                    DEPENDENCY CHECK                        |"
    echo "+------------------------------------------------------------+"
    echo

    echo "Some system tools are missing:"
    echo

    for cmd in "${missing_commands[@]}"; do

        printf "  %-18s -> %s\n" \
            "$cmd" \
            "${DEPENDENCIES[$cmd]}"

    done

    echo

    if ! command -v apt-get >/dev/null 2>&1; then

        printf "${YELLOW}[WARNING]${RESET} "
        echo "Automatic installation currently supports Ubuntu/Debian."

        echo
        echo "Install these packages with your package manager:"

        for package in "${missing_packages[@]}"; do
            echo "  - $package"
        done

        echo

        read -rp "Press ENTER to continue..."

        return 1

    fi

    read -rp "Install missing dependencies now? [Y/n]: " answer

    answer="${answer:-Y}"

    case "$answer" in

        y|Y|yes|YES|Yes)

            echo
            echo "Administrator privileges may be required."
            echo

            if ! sudo -v; then

                echo

                printf "${RED}[ERROR]${RESET} "
                echo "Administrator authentication failed."

                read -rp "Press ENTER to continue..."

                return 1

            fi

            echo

            if ! run_with_progress \
                "Updating package list" \
                sudo apt-get update; then

                read -rp "Press ENTER to continue..."

                return 1

            fi

            echo

            if ! run_with_progress \
                "Installing tools" \
                sudo apt-get install -y "${missing_packages[@]}"; then

                read -rp "Press ENTER to continue..."

                return 1

            fi

            echo
            echo "Verifying installation..."
            echo

            local failed=0

            for cmd in "${missing_commands[@]}"; do

                if command -v "$cmd" >/dev/null 2>&1; then

                    printf "  ${GREEN}[OK]${RESET} %-18s\n" "$cmd"

                else

                    printf "  ${RED}[FAILED]${RESET} %-18s\n" "$cmd"

                    failed=1

                fi

            done

            echo

            if ((failed == 0)); then

                printf "${GREEN}All dependencies are ready.${RESET}\n"

            else

                printf "${YELLOW}"
                echo "Some optional tools are still unavailable."
                printf "${RESET}"

            fi

            sleep 1

            ;;

        *)

            echo
            echo "Dependency installation skipped."

            sleep 1

            ;;

    esac
}


# Check dependencies before entering the full-screen IDE.

check_dependencies


# ============================================================
# IDE STATE
# ============================================================

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

SELECTED=0

STATUS_MESSAGE="Ready"

# Used when firmware was installed and we know a reboot
# should be offered even if Ubuntu has not created its normal
# /var/run/reboot-required marker.

FORCE_REBOOT_REQUIRED=0

LAST_UPDATE_ERROR=""

ORIGINAL_STTY=$(stty -g 2>/dev/null)


# ------------------------------------------------------------
# CLEANUP
# ------------------------------------------------------------

cleanup() {

    printf "${RESET}"

    if [[ -n "${ORIGINAL_STTY:-}" ]]; then

        stty "$ORIGINAL_STTY" 2>/dev/null

    else

        stty echo 2>/dev/null

    fi

    tput cnorm 2>/dev/null

    tput rmcup 2>/dev/null

    clear
}


trap cleanup EXIT INT TERM


# Enter the alternate terminal screen.

tput smcup 2>/dev/null

# Hide cursor.

tput civis 2>/dev/null

# Disable terminal echo so arrow-key sequence characters
# such as A/B/C/D do not appear in the interface.

stty -echo 2>/dev/null


# ============================================================
# GENERAL HELPERS
# ============================================================

read_file() {

    local file="$1"

    if [[ -r "$file" ]]; then
        cat "$file"
    else
        echo "Unknown"
    fi
}


repeat_char() {

    local char="$1"
    local count="$2"

    if ((count < 0)); then
        count=0
    fi

    printf "%${count}s" "" |
        tr " " "$char"
}


trim_text() {

    local text="$1"
    local max="$2"

    if ((${#text} > max)); then

        printf "%s..." \
            "${text:0:$((max - 3))}"

    else

        printf "%s" "$text"

    fi
}


get_os_name() {

    if [[ -f /etc/os-release ]]; then

        (
            source /etc/os-release

            echo "${PRETTY_NAME:-Linux}"
        )

    else

        echo "Linux"

    fi
}


human_architecture() {

    case "$(uname -m)" in

        x86_64)
            echo "64-bit Intel/AMD"
            ;;

        aarch64)
            echo "64-bit ARM"
            ;;

        armv7l)
            echo "32-bit ARM"
            ;;

        i386|i686)
            echo "32-bit Intel/AMD"
            ;;

        *)
            uname -m
            ;;

    esac
}


get_cpu_model() {

    lscpu 2>/dev/null |
        awk -F: '
            /Model name/ {
                gsub(/^[ \t]+/, "", $2)
                print $2
                exit
            }
        '
}


get_cpu_cores() {

    lscpu 2>/dev/null |
        awk -F: '
            /^Core\(s\) per socket:/ {
                gsub(/[ \t]/, "", $2)
                print $2
                exit
            }
        '
}


get_cpu_sockets() {

    lscpu 2>/dev/null |
        awk -F: '
            /Socket\(s\):/ {
                gsub(/[ \t]/, "", $2)
                print $2
                exit
            }
        '
}


get_memory_percent() {

    free |
        awk '
            /Mem:/ {
                printf "%.0f", ($3 / $2) * 100
            }
        '
}


get_root_total() {

    df -h / |
        awk 'NR==2 {print $2}'
}


get_root_used() {

    df -h / |
        awk 'NR==2 {print $3}'
}


get_root_free() {

    df -h / |
        awk 'NR==2 {print $4}'
}


get_root_usage() {

    df -h / |
        awk 'NR==2 {print $5}'
}


# ------------------------------------------------------------
# HUMAN-READABLE USAGE BAR
# ------------------------------------------------------------

make_usage_bar() {

    local percent="$1"

    local width=25

    percent="${percent//%/}"

    if ! [[ "$percent" =~ ^[0-9]+$ ]]; then
        percent=0
    fi

    ((percent > 100)) && percent=100
    ((percent < 0)) && percent=0

    local filled=$((percent * width / 100))
    local empty=$((width - filled))

    local bar=""
    local blank=""

    printf -v bar '%*s' "$filled" ''
    bar="${bar// /#}"

    printf -v blank '%*s' "$empty" ''

    printf "[%s%s] %s%%" \
        "$bar" \
        "$blank" \
        "$percent"
}


# ============================================================
# OVERVIEW
# ============================================================

get_overview() {

    local manufacturer
    local model
    local cpu
    local memory
    local ip_address
    local disk_percent
    local mem_percent

    manufacturer=$(
        read_file /sys/class/dmi/id/sys_vendor
    )

    model=$(
        read_file /sys/class/dmi/id/product_name
    )

    cpu=$(
        get_cpu_model
    )

    memory=$(
        free -h |
            awk '/Mem:/ {print $2}'
    )

    ip_address=$(
        hostname -I 2>/dev/null |
            awk '{print $1}'
    )

    mem_percent=$(
        get_memory_percent
    )

    disk_percent=$(
        get_root_usage
    )

    disk_percent="${disk_percent//%/}"

    echo "COMPUTER"
    echo "------------------------------------------------------------"

    printf "%-21s %s\n" \
        "Computer Name" \
        "$(hostname)"

    printf "%-21s %s\n" \
        "Manufacturer" \
        "$manufacturer"

    printf "%-21s %s\n" \
        "Model" \
        "$model"

    echo
    echo "OPERATING SYSTEM"
    echo "------------------------------------------------------------"

    printf "%-21s %s\n" \
        "Operating System" \
        "$(get_os_name)"

    printf "%-21s %s\n" \
        "Kernel" \
        "$(uname -r)"

    printf "%-21s %s\n" \
        "System Type" \
        "$(human_architecture)"

    printf "%-21s %s\n" \
        "System Uptime" \
        "$(uptime -p 2>/dev/null | sed 's/^up //')"

    echo
    echo "HARDWARE"
    echo "------------------------------------------------------------"

    printf "%-21s %s\n" \
        "Processor" \
        "$cpu"

    printf "%-21s %s\n" \
        "CPU Threads" \
        "$(nproc)"

    printf "%-21s %s\n" \
        "Installed Memory" \
        "$memory"

    echo
    echo "CURRENT USAGE"
    echo "------------------------------------------------------------"

    printf "%-21s " "Memory"

    make_usage_bar "$mem_percent"

    echo

    printf "%-21s " "System Drive"

    make_usage_bar "$disk_percent"

    echo

    echo
    echo "NETWORK"
    echo "------------------------------------------------------------"

    printf "%-21s %s\n" \
        "Primary IP Address" \
        "${ip_address:-Not connected}"
}


# ============================================================
# OPERATING SYSTEM
# ============================================================

get_os() {

    echo "OPERATING SYSTEM"
    echo "------------------------------------------------------------"

    printf "%-22s %s\n" \
        "Operating System" \
        "$(get_os_name)"

    printf "%-22s %s\n" \
        "Computer Name" \
        "$(hostname)"

    printf "%-22s %s\n" \
        "Kernel Version" \
        "$(uname -r)"

    printf "%-22s %s\n" \
        "System Type" \
        "$(human_architecture)"

    if [[ -d /sys/firmware/efi ]]; then

        printf "%-22s %s\n" \
            "Boot Mode" \
            "UEFI"

    else

        printf "%-22s %s\n" \
            "Boot Mode" \
            "Legacy BIOS"

    fi

    printf "%-22s %s\n" \
        "Running For" \
        "$(uptime -p 2>/dev/null | sed 's/^up //')"

    echo
    echo "FIRMWARE"
    echo "------------------------------------------------------------"

    printf "%-22s %s\n" \
        "BIOS Manufacturer" \
        "$(read_file /sys/class/dmi/id/bios_vendor)"

    printf "%-22s %s\n" \
        "BIOS Version" \
        "$(read_file /sys/class/dmi/id/bios_version)"

    printf "%-22s %s\n" \
        "BIOS Date" \
        "$(read_file /sys/class/dmi/id/bios_date)"
}


# ============================================================
# PROCESSOR
# ============================================================

get_processor() {

    local model
    local sockets
    local cores
    local threads
    local physical_cores
    local cpu_mhz

    model=$(get_cpu_model)
    sockets=$(get_cpu_sockets)
    cores=$(get_cpu_cores)
    threads=$(nproc)

    if [[ "$sockets" =~ ^[0-9]+$ ]] &&
       [[ "$cores" =~ ^[0-9]+$ ]]; then

        physical_cores=$((sockets * cores))

    else

        physical_cores="Unknown"

    fi

    echo "PROCESSOR"
    echo "------------------------------------------------------------"

    printf "%-22s %s\n" \
        "Processor" \
        "$model"

    printf "%-22s %s\n" \
        "Physical Cores" \
        "$physical_cores"

    printf "%-22s %s\n" \
        "CPU Threads" \
        "$threads"

    printf "%-22s %s\n" \
        "System Type" \
        "$(human_architecture)"

    cpu_mhz=$(
        lscpu 2>/dev/null |
            awk -F: '
                /CPU max MHz/ {
                    gsub(/^[ \t]+/, "", $2)

                    if ($2 > 0) {
                        printf "%.2f GHz", $2 / 1000
                    }

                    exit
                }
            '
    )

    if [[ -n "$cpu_mhz" ]]; then

        printf "%-22s %s\n" \
            "Maximum Speed" \
            "$cpu_mhz"

    fi

    echo
    echo "CURRENT ACTIVITY"
    echo "------------------------------------------------------------"

    local load1
    local load5
    local load15

    read -r load1 load5 load15 _ < /proc/loadavg

    printf "%-22s %s\n" \
        "1 Minute Load" \
        "$load1"

    printf "%-22s %s\n" \
        "5 Minute Load" \
        "$load5"

    printf "%-22s %s\n" \
        "15 Minute Load" \
        "$load15"

    echo
    echo "Lower load usually means the processor is less busy."
}


# ============================================================
# MEMORY
# ============================================================

get_memory() {

    local total
    local used
    local available
    local swap_total
    local swap_used
    local percent

    total=$(
        free -h |
            awk '/Mem:/ {print $2}'
    )

    used=$(
        free -h |
            awk '/Mem:/ {print $3}'
    )

    available=$(
        free -h |
            awk '/Mem:/ {print $7}'
    )

    swap_total=$(
        free -h |
            awk '/Swap:/ {print $2}'
    )

    swap_used=$(
        free -h |
            awk '/Swap:/ {print $3}'
    )

    percent=$(
        get_memory_percent
    )

    echo "MEMORY"
    echo "------------------------------------------------------------"

    printf "%-22s %s\n" \
        "Installed Memory" \
        "$total"

    printf "%-22s %s\n" \
        "Currently Used" \
        "$used"

    printf "%-22s %s\n" \
        "Available Memory" \
        "$available"

    echo

    printf "%-22s " \
        "Memory Usage"

    make_usage_bar "$percent"

    echo

    echo
    echo "SWAP"
    echo "------------------------------------------------------------"

    printf "%-22s %s\n" \
        "Swap Space" \
        "$swap_total"

    printf "%-22s %s\n" \
        "Swap Used" \
        "$swap_used"

    echo
    echo "STATUS"
    echo "------------------------------------------------------------"

    if ((percent < 60)); then

        echo "Plenty of memory is currently available."

    elif ((percent < 80)); then

        echo "Memory usage is moderate."

    else

        echo "Memory usage is high."

    fi
}


# ============================================================
# STORAGE
# ============================================================

get_storage() {

    local disk_percent

    disk_percent=$(
        get_root_usage
    )

    disk_percent="${disk_percent//%/}"

    echo "SYSTEM DRIVE"
    echo "------------------------------------------------------------"

    printf "%-22s %s\n" \
        "Total Capacity" \
        "$(get_root_total)"

    printf "%-22s %s\n" \
        "Used Space" \
        "$(get_root_used)"

    printf "%-22s %s\n" \
        "Available Space" \
        "$(get_root_free)"

    echo

    printf "%-22s " \
        "Storage Usage"

    make_usage_bar "$disk_percent"

    echo

    echo
    echo "PHYSICAL DRIVES"
    echo "------------------------------------------------------------"

    lsblk -dn -o NAME,SIZE,TYPE,MODEL 2>/dev/null |
    while read -r name size type model; do

        [[ "$type" != "disk" ]] && continue

        printf "%-12s %-10s %s\n" \
            "/dev/$name" \
            "$size" \
            "${model:-Unknown drive}"

    done

    echo
    echo "MOUNTED STORAGE"
    echo "------------------------------------------------------------"

    printf "%-22s %-10s %-8s\n" \
        "Location" \
        "Size" \
        "Used"

    df -h \
        -x tmpfs \
        -x devtmpfs \
        -x squashfs 2>/dev/null |
        awk '
            NR > 1 {
                printf "%-22s %-10s %-8s\n",
                       $6,
                       $2,
                       $5
            }
        '
}


# ============================================================
# NETWORK
# ============================================================

get_network() {

    local default_interface
    local gateway
    local connection_state

    default_interface=$(
        ip route 2>/dev/null |
            awk '
                /default/ {
                    print $5
                    exit
                }
            '
    )

    gateway=$(
        ip route 2>/dev/null |
            awk '
                /default/ {
                    print $3
                    exit
                }
            '
    )

    echo "NETWORK CONNECTION"
    echo "------------------------------------------------------------"

    printf "%-22s %s\n" \
        "Computer Name" \
        "$(hostname)"

    printf "%-22s %s\n" \
        "Primary Interface" \
        "${default_interface:-Not connected}"

    printf "%-22s %s\n" \
        "Default Gateway" \
        "${gateway:-Not available}"

    if [[ -n "$default_interface" ]]; then

        connection_state=$(
            cat "/sys/class/net/$default_interface/operstate" \
                2>/dev/null
        )

        if [[ "$connection_state" == "up" ]]; then

            printf "%-22s %s\n" \
                "Connection Status" \
                "Connected"

        else

            printf "%-22s %s\n" \
                "Connection Status" \
                "Disconnected"

        fi

    fi

    echo
    echo "IP ADDRESSES"
    echo "------------------------------------------------------------"

    ip -o -4 addr show 2>/dev/null |
        awk '
            $2 != "lo" {
                split($4, address, "/")

                printf "%-18s %s\n",
                       $2,
                       address[1]
            }
        '

    echo
    echo "DNS SERVERS"
    echo "------------------------------------------------------------"

    if command -v resolvectl >/dev/null 2>&1; then

        local dns

        dns=$(
            resolvectl dns 2>/dev/null |
                head -5
        )

        if [[ -n "$dns" ]]; then
            echo "$dns"
        else
            echo "DNS information unavailable."
        fi

    else

        grep '^nameserver' \
            /etc/resolv.conf 2>/dev/null |
            awk '{print $2}'

    fi
}


# ============================================================
# GRAPHICS
# ============================================================

get_graphics() {

    echo "GRAPHICS"
    echo "------------------------------------------------------------"

    if ! command -v lspci >/dev/null 2>&1; then

        echo "PCI information tool is unavailable."

        return

    fi

    local gpu_count=0
    local gpu

    while IFS= read -r gpu; do

        [[ -z "$gpu" ]] && continue

        ((gpu_count++))

        gpu=$(
            echo "$gpu" |
                sed 's/^[^ ]* //' |
                sed 's/^[^:]*: //'
        )

        printf "%-22s %s\n" \
            "Graphics Adapter" \
            "$gpu"

    done < <(
        lspci 2>/dev/null |
            grep -Ei 'VGA|3D|Display'
    )

    if ((gpu_count == 0)); then

        echo "Graphics adapter information unavailable."

    fi

    echo
    echo "ACTIVE DRIVER"
    echo "------------------------------------------------------------"

    local driver

    driver=$(
        lspci -k 2>/dev/null |
            grep -A3 -Ei 'VGA|3D|Display' |
            awk -F: '
                /Kernel driver in use/ {
                    gsub(/^[ \t]+/, "", $2)
                    print $2
                    exit
                }
            '
    )

    printf "%-22s %s\n" \
        "Graphics Driver" \
        "${driver:-Unknown}"
}


# ============================================================
# BATTERY
# ============================================================

get_battery() {

    echo "BATTERY"
    echo "------------------------------------------------------------"

    if ! command -v upower >/dev/null 2>&1; then

        echo "Battery information tool is unavailable."

        return

    fi

    local battery

    battery=$(
        upower -e 2>/dev/null |
            grep -Ei 'battery|BAT' |
            head -1
    )

    if [[ -z "$battery" ]]; then

        echo "No battery was detected."

        echo
        echo "This is normal for desktop computers."

        return

    fi

    local info
    local model
    local vendor
    local state
    local percentage
    local capacity
    local remaining
    local time_full

    info=$(
        upower -i "$battery" 2>/dev/null
    )

    vendor=$(
        echo "$info" |
            awk -F: '
                /vendor:/ {
                    sub(/^[ \t]+/, "", $2)
                    print $2
                    exit
                }
            '
    )

    model=$(
        echo "$info" |
            awk -F: '
                /model:/ {
                    sub(/^[ \t]+/, "", $2)
                    print $2
                    exit
                }
            '
    )

    state=$(
        echo "$info" |
            awk -F: '
                /state:/ {
                    sub(/^[ \t]+/, "", $2)
                    print $2
                    exit
                }
            '
    )

    percentage=$(
        echo "$info" |
            awk -F: '
                /percentage:/ {
                    sub(/^[ \t]+/, "", $2)
                    print $2
                    exit
                }
            '
    )

    capacity=$(
        echo "$info" |
            awk -F: '
                /capacity:/ {
                    sub(/^[ \t]+/, "", $2)
                    print $2
                    exit
                }
            '
    )

    remaining=$(
        echo "$info" |
            awk -F: '
                /time to empty:/ {
                    sub(/^[ \t]+/, "", $2)
                    print $2
                    exit
                }
            '
    )

    time_full=$(
        echo "$info" |
            awk -F: '
                /time to full:/ {
                    sub(/^[ \t]+/, "", $2)
                    print $2
                    exit
                }
            '
    )

    printf "%-22s %s\n" \
        "Manufacturer" \
        "${vendor:-Unknown}"

    printf "%-22s %s\n" \
        "Battery Model" \
        "${model:-Internal Battery}"

    printf "%-22s %s\n" \
        "Status" \
        "${state:-Unknown}"

    printf "%-22s %s\n" \
        "Charge Level" \
        "${percentage:-Unknown}"

    printf "%-22s %s\n" \
        "Battery Health" \
        "${capacity:-Unknown}"

    if [[ -n "$remaining" ]]; then

        printf "%-22s %s\n" \
            "Estimated Runtime" \
            "$remaining"

    fi

    if [[ -n "$time_full" ]]; then

        printf "%-22s %s\n" \
            "Time Until Full" \
            "$time_full"

    fi

    if [[ "$percentage" =~ ^([0-9]+)%$ ]]; then

        echo

        printf "%-22s " \
            "Battery"

        make_usage_bar "${BASH_REMATCH[1]}"

        echo

    fi
}


# ============================================================
# INTERNAL HARDWARE
# ============================================================

get_internal_hardware() {

    echo "INTERNAL HARDWARE"
    echo "------------------------------------------------------------"

    if ! command -v lspci >/dev/null 2>&1; then

        echo "PCI information tool is unavailable."

        return

    fi

    echo
    echo "Graphics:"

    lspci 2>/dev/null |
        grep -Ei 'VGA|3D|Display' |
        sed -E 's/^[0-9a-fA-F:.]+ //' |
        sed 's/^/  /'

    echo
    echo "Network Hardware:"

    lspci 2>/dev/null |
        grep -Ei 'Ethernet|Network controller|Wireless' |
        sed -E 's/^[0-9a-fA-F:.]+ //' |
        sed 's/^/  /'

    echo
    echo "Audio Hardware:"

    lspci 2>/dev/null |
        grep -Ei 'Audio|Multimedia' |
        sed -E 's/^[0-9a-fA-F:.]+ //' |
        sed 's/^/  /'

    echo
    echo "Storage Controllers:"

    lspci 2>/dev/null |
        grep -Ei 'SATA|NVMe|RAID|Storage controller' |
        sed -E 's/^[0-9a-fA-F:.]+ //' |
        sed 's/^/  /'
}


# ============================================================
# USB DEVICES
# ============================================================

get_usb() {

    echo "USB DEVICES"
    echo "------------------------------------------------------------"

    if ! command -v lsusb >/dev/null 2>&1; then

        echo "USB information tool is unavailable."

        return

    fi

    local count

    count=$(
        lsusb 2>/dev/null |
            wc -l
    )

    printf "%-22s %s\n" \
        "Devices Detected" \
        "$count"

    echo
    echo "CONNECTED USB HARDWARE"
    echo "------------------------------------------------------------"

    lsusb 2>/dev/null |
        sed -E \
        's/^Bus [0-9]+ Device [0-9]+: ID [^ ]+ /  /'
}


# ============================================================
# TEMPERATURES
# ============================================================

get_temperature() {

    echo "SYSTEM TEMPERATURES"
    echo "------------------------------------------------------------"

    if ! command -v sensors >/dev/null 2>&1; then

        echo "Temperature monitoring is unavailable."

        echo
        echo "Install lm-sensors to enable it."

        return

    fi

    local output

    output=$(
        sensors 2>/dev/null |
            grep -E \
            'Package id|Core [0-9]+:|Tctl:|Tdie:|Composite:|CPU:|temp[0-9]+:' |
            sed 's/^[ \t]*//'
    )

    if [[ -n "$output" ]]; then

        echo "$output"

    else

        echo "No readable temperature sensors were detected."

    fi

    echo
    echo "TEMPERATURE GUIDE"
    echo "------------------------------------------------------------"

    echo "Below 60 C       Normal for light use"
    echo "60 - 80 C        Normal under heavier workloads"
    echo "80 - 85 C        Running warm"
    echo "Above 85 C       Worth monitoring"
}


# ============================================================
# UPDATE INFORMATION
# ============================================================

get_package_update_count() {

    if ! command -v apt >/dev/null 2>&1; then

        echo "Unknown"

        return

    fi

    local count

    count=$(
        apt list --upgradable 2>/dev/null |
            tail -n +2 |
            grep -c .
    )

    echo "${count:-0}"
}


get_security_update_count() {

    if ! command -v apt >/dev/null 2>&1; then

        echo "Unknown"

        return

    fi

    local count

    count=$(
        apt list --upgradable 2>/dev/null |
            tail -n +2 |
            grep -Ei -- '-security|security' |
            wc -l
    )

    echo "${count:-0}"
}


get_reboot_status() {

    if [[ -f /var/run/reboot-required ]] ||
       ((FORCE_REBOOT_REQUIRED == 1)); then

        echo "Yes"

    else

        echo "No"

    fi
}


get_firmware_status() {

    if ! command -v fwupdmgr >/dev/null 2>&1; then

        echo "Firmware tool unavailable"

        return

    fi

    local output
    local result

    output=$(
        fwupdmgr get-updates </dev/null 2>&1
    )

    result=$?

    if ((result == 2)); then

        echo "Up to date"

    elif echo "$output" |
        grep -qiE \
        'No updates available|No updatable devices|No upgrades'; then

        echo "Up to date"

    elif ((result == 0)); then

        echo "Updates available"

    else

        echo "Unable to check"

    fi
}


get_driver_status() {

    if ! command -v ubuntu-drivers >/dev/null 2>&1; then

        echo "Driver tool unavailable"

        return

    fi

    local drivers

    drivers=$(
        ubuntu-drivers list 2>/dev/null
    )

    if [[ -n "$drivers" ]]; then

        local first

        first=$(
            echo "$drivers" |
                head -1
        )

        echo "Available: $first"

    else

        echo "No additional drivers"

    fi
}


get_updates() {

    local package_count
    local security_count
    local firmware_status
    local driver_status
    local reboot_status

    package_count=$(
        get_package_update_count
    )

    security_count=$(
        get_security_update_count
    )

    firmware_status=$(
        get_firmware_status
    )

    driver_status=$(
        get_driver_status
    )

    reboot_status=$(
        get_reboot_status
    )

    echo "SYSTEM UPDATES"
    echo "------------------------------------------------------------"

    printf "%-25s %s\n" \
        "Package Updates" \
        "$package_count available"

    printf "%-25s %s\n" \
        "Security Updates" \
        "$security_count available"

    printf "%-25s %s\n" \
        "Reboot Required" \
        "$reboot_status"

    echo
    echo "FIRMWARE / BIOS"
    echo "------------------------------------------------------------"

    printf "%-25s %s\n" \
        "Firmware Status" \
        "$firmware_status"

    echo
    echo "HARDWARE DRIVERS"
    echo "------------------------------------------------------------"

    printf "%-25s %s\n" \
        "Driver Status" \
        "$driver_status"

    echo
    echo "MAINTENANCE OPTIONS"
    echo "------------------------------------------------------------"

    echo "C   Check for updates"
    echo "U   Install Ubuntu updates"
    echo "F   Install firmware updates"
    echo "D   Install recommended drivers"
}


# ============================================================
# SELECT INFORMATION PAGE
# ============================================================

get_information() {

    case "${MENU_ITEMS[$SELECTED]}" in

        "Overview")
            get_overview
            ;;

        "Operating System")
            get_os
            ;;

        "Processor")
            get_processor
            ;;

        "Memory")
            get_memory
            ;;

        "Storage")
            get_storage
            ;;

        "Network")
            get_network
            ;;

        "Graphics")
            get_graphics
            ;;

        "Battery")
            get_battery
            ;;

        "Internal Hardware")
            get_internal_hardware
            ;;

        "USB Devices")
            get_usb
            ;;

        "Temperatures")
            get_temperature
            ;;

        "Updates")
            get_updates
            ;;

    esac
}


# ============================================================
# TERMINAL GEOMETRY
# ============================================================

update_dimensions() {

    COLS=$(tput cols)
    LINES=$(tput lines)

    # Divider is placed at column 27.
    #
    # Border:
    # col 0     left border
    # col 1-26  menu interior
    # col 27    divider
    # col 28+   right panel

    MENU_DIVIDER_X=27

    MENU_INNER_WIDTH=$(
        echo $((MENU_DIVIDER_X - 1))
    )

    RIGHT_WIDTH=$(
        echo $((COLS - MENU_DIVIDER_X - 2))
    )

    CONTENT_BOTTOM=$(
        echo $((LINES - 4))
    )

    if ((COLS < 90 || LINES < 25)); then

        cleanup

        echo "The terminal window is too small."
        echo

        echo "Minimum recommended size: 90 x 25"
        echo "Current size: ${COLS} x ${LINES}"

        echo
        echo "Make the terminal larger and run the program again."

        exit 1

    fi
}


# ============================================================
# MAIN FRAME
# ============================================================

draw_frame() {

    update_dimensions

    # Header

    tput cup 0 0

    printf "${BOLD}${CYAN}"

    printf "%-*s" \
        "$COLS" \
        " SYSTEM & HARDWARE INFORMATION / MAINTENANCE"

    printf "${RESET}"

    # Top border

    tput cup 1 0

    printf "+"

    repeat_char "-" "$MENU_INNER_WIDTH"

    printf "+"

    repeat_char "-" "$RIGHT_WIDTH"

    printf "+"

    # Vertical borders

    local row

    for ((row=2; row<=CONTENT_BOTTOM; row++)); do

        tput cup "$row" 0
        printf "|"

        tput cup "$row" "$MENU_DIVIDER_X"
        printf "|"

        tput cup "$row" $((COLS - 1))
        printf "|"

    done

    # Bottom border

    tput cup $((LINES - 3)) 0

    printf "+"

    repeat_char "-" "$MENU_INNER_WIDTH"

    printf "+"

    repeat_char "-" "$RIGHT_WIDTH"

    printf "+"
}


# ============================================================
# LEFT MENU
# ============================================================

draw_menu() {

    tput cup 2 2

    printf "${BOLD}${CYAN}SYSTEM INFO${RESET}"

    local row=4
    local i
    local label

    for ((i=0; i<${#MENU_ITEMS[@]}; i++)); do

        tput cup "$row" 1

        # This string is exactly 26 characters wide:
        # 3 prefix + 22 text + 1 trailing space.

        if ((i == SELECTED)); then

            printf -v label \
                " > %-22s " \
                "${MENU_ITEMS[$i]}"

            printf \
                "${SELECT_BG}${SELECT_FG}${BOLD}%s${RESET}" \
                "$label"

        else

            printf -v label \
                "   %-22s " \
                "${MENU_ITEMS[$i]}"

            printf "%s" "$label"

        fi

        ((row++))

    done
}


# ============================================================
# RIGHT PANEL
# ============================================================

clear_right_panel() {

    local row

    for ((row=2; row<=CONTENT_BOTTOM; row++)); do

        tput cup \
            "$row" \
            $((MENU_DIVIDER_X + 1))

        printf "%${RIGHT_WIDTH}s" ""

    done
}


draw_information() {

    # Leave one blank character of padding after divider.

    local start_x=$((MENU_DIVIDER_X + 2))

    # Right border is at COLS - 1.
    # This leaves one character before it.

    local content_width=$(
        echo $((COLS - start_x - 1))
    )

    local row
    local line

    clear_right_panel

    tput cup 2 "$start_x"

    printf "${BOLD}${GREEN}%s${RESET}" \
        "${MENU_ITEMS[$SELECTED]}"

    mapfile -t INFO_LINES < <(
        get_information 2>&1
    )

    row=4

    for line in "${INFO_LINES[@]}"; do

        ((row > CONTENT_BOTTOM)) && break

        line="${line//$'\t'/    }"

        if ((${#line} > content_width)); then

            line="${line:0:$((content_width - 3))}..."

        fi

        tput cup \
            "$row" \
            "$start_x"

        printf "%-*s" \
            "$content_width" \
            "$line"

        ((row++))

    done
}


# ============================================================
# STATUS / SHORTCUTS
# ============================================================

draw_status() {

    tput cup $((LINES - 2)) 0

    printf "%${COLS}s" ""

    tput cup $((LINES - 2)) 0

    printf "${BOLD} STATUS:${RESET} %s" \
        "$STATUS_MESSAGE"
}


draw_shortcuts() {

    tput cup $((LINES - 1)) 0

    printf "%${COLS}s" ""

    tput cup $((LINES - 1)) 0

    printf "${CYAN}"

    if [[ "${MENU_ITEMS[$SELECTED]}" == "Updates" ]]; then

        printf \
            " [C] Check   [U] Ubuntu Update   [F] Firmware   [D] Drivers   [Q] Quit"

    else

        printf \
            " [UP/DOWN] Navigate   [ENTER] Refresh   [R] Refresh   [Q] Quit"

    fi

    printf "${RESET}"
}


draw_ui() {

    draw_frame

    draw_menu

    draw_information

    draw_status

    draw_shortcuts
}


# ============================================================
# MODAL BOX SYSTEM
# ============================================================
#
# All dialogs use this function.
#
# The box is drawn using one consistent width calculation:
#
# +--------------------------------+
# |                                |
# |          Dialog Title          |
# |                                |
# |  Content                       |
# |                                |
# +--------------------------------+
#
# This prevents uneven right/left padding.
# ============================================================

MODAL_X=0
MODAL_Y=0
MODAL_W=0
MODAL_H=0


modal_draw() {

    local title="$1"
    local width="$2"
    local height="$3"

    # Prevent dialogs from being larger than terminal.

    if ((width > COLS - 4)); then
        width=$((COLS - 4))
    fi

    if ((height > LINES - 4)); then
        height=$((LINES - 4))
    fi

    if ((width < 30)); then
        width=30
    fi

    if ((height < 7)); then
        height=7
    fi

    MODAL_W="$width"
    MODAL_H="$height"

    MODAL_X=$(
        echo $(((COLS - MODAL_W) / 2))
    )

    MODAL_Y=$(
        echo $(((LINES - MODAL_H) / 2))
    )

    local inner=$((MODAL_W - 2))
    local row

    # Top border

    tput cup \
        "$MODAL_Y" \
        "$MODAL_X"

    printf "+"

    repeat_char "-" "$inner"

    printf "+"

    # Body

    for ((row=1; row<MODAL_H-1; row++)); do

        tput cup \
            $((MODAL_Y + row)) \
            "$MODAL_X"

        printf "|"

        printf "%${inner}s" ""

        printf "|"

    done

    # Bottom border

    tput cup \
        $((MODAL_Y + MODAL_H - 1)) \
        "$MODAL_X"

    printf "+"

    repeat_char "-" "$inner"

    printf "+"

    # Centered title

    local title_max=$((inner - 4))
    local title_text

    title_text=$(
        trim_text \
            "$title" \
            "$title_max"
    )

    local title_x=$(
        echo $((MODAL_X + (MODAL_W - ${#title_text}) / 2))
    )

    tput cup \
        $((MODAL_Y + 1)) \
        "$title_x"

    printf "${BOLD}${CYAN}%s${RESET}" \
        "$title_text"
}


modal_text() {

    local relative_row="$1"
    local relative_col="$2"
    local text="$3"

    local max_width=$(
        echo $((MODAL_W - relative_col - 2))
    )

    if ((max_width < 1)); then
        return
    fi

    tput cup \
        $((MODAL_Y + relative_row)) \
        $((MODAL_X + relative_col))

    printf "%.*s" \
        "$max_width" \
        "$text"
}


modal_center_text() {

    local relative_row="$1"
    local text="$2"

    # Always leave at least three spaces on each side.

    local max_width=$(
        echo $((MODAL_W - 6))
    )

    local shown

    shown=$(
        trim_text \
            "$text" \
            "$max_width"
    )

    local x=$(
        echo $((MODAL_X + (MODAL_W - ${#shown}) / 2))
    )

    tput cup \
        $((MODAL_Y + relative_row)) \
        "$x"

    printf "%s" "$shown"
}


# ============================================================
# MESSAGE DIALOG
# ============================================================

message_dialog() {

    local title="$1"
    local line1="$2"
    local line2="${3:-}"

    draw_ui

    modal_draw \
        "$title" \
        64 \
        10

    modal_center_text \
        3 \
        "$line1"

    if [[ -n "$line2" ]]; then

        modal_center_text \
            4 \
            "$line2"

    fi

    modal_center_text \
        7 \
        "Press ENTER to continue"

    while true; do

        read_key

        case "$KEY" in

            ""|$'\n'|$'\r'|$'\e')
                break
                ;;

        esac

    done

    draw_ui
}


# ============================================================
# YES / NO CONFIRMATION DIALOG
# ============================================================

confirm_dialog() {

    local title="$1"
    local line1="$2"
    local line2="$3"
    local yes_text="$4"
    local no_text="$5"

    draw_ui

    modal_draw \
        "$title" \
        68 \
        11

    modal_center_text \
        3 \
        "$line1"

    modal_center_text \
        4 \
        "$line2"

    local buttons

    buttons="[Y] $yes_text     [N] $no_text"

    modal_center_text \
        7 \
        "$buttons"

    modal_center_text \
        8 \
        "ESC also cancels"

    while true; do

        read_key

        case "$KEY" in

            y|Y)

                draw_ui

                return 0
                ;;

            n|N|$'\e')

                draw_ui

                return 1
                ;;

        esac

    done
}


# ============================================================
# MASKED PASSWORD INPUT
# ============================================================

read_masked_password() {

    local field_x="$1"
    local field_y="$2"
    local field_width="$3"

    local char=""

    DIALOG_PASSWORD=""

    while true; do

        IFS= read -r -n1 char

        # ENTER

        if [[ -z "$char" ]]; then
            break
        fi

        case "$char" in

            # ESC cancels.

            $'\e')

                DIALOG_PASSWORD=""

                return 1
                ;;

            # Backspace

            $'\177'|$'\b')

                if [[ -n "$DIALOG_PASSWORD" ]]; then
                    DIALOG_PASSWORD="${DIALOG_PASSWORD%?}"
                fi

                ;;

            *)

                if ((${#DIALOG_PASSWORD} < field_width)); then

                    DIALOG_PASSWORD+="$char"

                fi

                ;;

        esac

        # Clear only the password field.

        tput cup \
            "$field_y" \
            "$field_x"

        printf "%-*s" \
            "$field_width" \
            ""

        # Draw asterisks.

        tput cup \
            "$field_y" \
            "$field_x"

        printf "%${#DIALOG_PASSWORD}s" "" |
            tr " " "*"

    done

    return 0
}


# ============================================================
# SUDO PASSWORD DIALOG
# ============================================================

request_sudo_dialog() {

    # If sudo credentials are already cached there is no need
    # to ask for the password again.

    if sudo -n true >/dev/null 2>&1; then
        return 0
    fi

    local attempts=0

    while ((attempts < 3)); do

        draw_ui

        modal_draw \
            "Administrator Password" \
            66 \
            12

        modal_center_text \
            3 \
            "Administrator access is required to continue."

        local label="Password:"
        local field_width=30

        local field_y=$(
            echo $((MODAL_Y + 5))
        )

        local field_x=$(
            echo $((MODAL_X + 19))
        )

        modal_text \
            5 \
            6 \
            "$label"

        # Password input line.

        tput cup \
            "$field_y" \
            "$field_x"

        printf "%${field_width}s" "" |
            tr " " "_"

        modal_center_text \
            8 \
            "ENTER Continue     ESC Cancel"

        tput cup \
            "$field_y" \
            "$field_x"

        if ! read_masked_password \
            "$field_x" \
            "$field_y" \
            "$field_width"; then

            unset DIALOG_PASSWORD

            STATUS_MESSAGE="Administrator request cancelled"

            draw_ui

            return 1

        fi

        # Send the password only to sudo's stdin.
        #
        # It is removed from the Bash variable immediately
        # afterward.

        if printf '%s\n' "$DIALOG_PASSWORD" |
            sudo -S -p '' -v >/dev/null 2>&1; then

            unset DIALOG_PASSWORD

            draw_ui

            return 0

        fi

        unset DIALOG_PASSWORD

        ((attempts++))

        draw_ui

        modal_draw \
            "Incorrect Password" \
            56 \
            9

        modal_center_text \
            3 \
            "The password was not accepted."

        if ((attempts < 3)); then

            modal_center_text \
                5 \
                "Press ENTER to try again"

        else

            modal_center_text \
                5 \
                "Maximum attempts reached"

        fi

        while true; do

            read_key

            case "$KEY" in

                ""|$'\n'|$'\r'|$'\e')
                    break
                    ;;

            esac

        done

    done

    STATUS_MESSAGE="Administrator authentication failed"

    draw_ui

    return 1
}


# ============================================================
# IDE UPDATE PROGRESS
# ============================================================

draw_update_panel_static() {

    local label="$1"
    local detail="$2"

    local start_x=$(
        echo $((MENU_DIVIDER_X + 3))
    )

    local content_width=$(
        echo $((COLS - start_x - 2))
    )

    clear_right_panel

    tput cup 2 "$start_x"

    printf "${BOLD}${GREEN}Updates${RESET}"

    tput cup 4 "$start_x"

    printf "${BOLD}SYSTEM MAINTENANCE${RESET}"

    tput cup 5 "$start_x"

    repeat_char \
        "-" \
        "$((content_width < 60 ? content_width : 60))"

    tput cup 7 "$start_x"

    printf "%.*s" \
        "$content_width" \
        "$label"

    tput cup 11 "$start_x"

    printf "%.*s" \
        "$content_width" \
        "$detail"

    tput cup 13 "$start_x"

    printf "%.*s" \
        "$content_width" \
        "Please do not close the program while this step is running."
}


draw_update_bar() {

    local filled_count="$1"
    local bar_width="$2"

    local start_x=$(
        echo $((MENU_DIVIDER_X + 3))
    )

    local empty=$(
        echo $((bar_width - filled_count))
    )

    local bar=""
    local blank=""

    printf -v bar \
        '%*s' \
        "$filled_count" \
        ''

    bar="${bar// /#}"

    printf -v blank \
        '%*s' \
        "$empty" \
        ''

    tput cup \
        9 \
        "$start_x"

    printf "[${GREEN}%s${RESET}%s]" \
        "$bar" \
        "$blank"
}


run_ide_progress() {

    local label="$1"
    local detail="$2"

    shift 2

    local logfile

    logfile=$(mktemp)

    # Redirect command output to the log so tools such as
    # apt and fwupdmgr cannot overwrite the IDE.

    "$@" \
        </dev/null \
        >"$logfile" \
        2>&1 &

    local pid=$!

    local bar_width=36
    local position=1

    # Draw the static section only once to reduce flicker.

    draw_update_panel_static \
        "$label" \
        "$detail"

    # Only the progress bar row changes during the loop.

    while kill -0 "$pid" 2>/dev/null; do

        draw_update_bar \
            "$position" \
            "$bar_width"

        ((position++))

        if ((position > bar_width)); then
            position=1
        fi

        sleep 0.10

    done

    wait "$pid"

    local result=$?

    # Complete the bar.

    draw_update_bar \
        "$bar_width" \
        "$bar_width"

    if ((result != 0)); then

        LAST_UPDATE_ERROR=$(
            tail -8 "$logfile" |
                tr '\n' ' ' |
                sed 's/[[:space:]][[:space:]]*/ /g'
        )

    else

        LAST_UPDATE_ERROR=""

    fi

    rm -f "$logfile"

    return "$result"
}


# ============================================================
# UPDATE ERROR DIALOG
# ============================================================

show_update_error() {

    local detail="${LAST_UPDATE_ERROR:-No additional details were returned.}"

    draw_ui

    modal_draw \
        "Update Error" \
        72 \
        11

    modal_center_text \
        3 \
        "The update process did not complete successfully."

    modal_center_text \
        5 \
        "$(trim_text "$detail" 60)"

    modal_center_text \
        8 \
        "Press ENTER to continue"

    while true; do

        read_key

        case "$KEY" in

            ""|$'\n'|$'\r'|$'\e')
                break
                ;;

        esac

    done

    STATUS_MESSAGE="Update failed"

    draw_ui
}


# ============================================================
# REBOOT HANDLING
# ============================================================

reboot_required() {

    # Normal Ubuntu reboot marker.

    if [[ -f /var/run/reboot-required ]]; then
        return 0
    fi

    # Firmware was installed during this program session.

    if ((FORCE_REBOOT_REQUIRED == 1)); then
        return 0
    fi

    return 1
}


maybe_offer_reboot() {

    if ! reboot_required; then

        draw_ui

        return

    fi

    if confirm_dialog \
        "Reboot Required" \
        "The update completed successfully." \
        "A restart is required to finish applying changes." \
        "Restart Now" \
        "Restart Later"; then

        if ! request_sudo_dialog; then

            STATUS_MESSAGE="Reboot required - restart later"

            draw_ui

            return

        fi

        draw_ui

        modal_draw \
            "Restarting Computer" \
            54 \
            8

        modal_center_text \
            3 \
            "The computer is restarting..."

        modal_center_text \
            5 \
            "Please wait."

        sleep 1

        if ! sudo -n systemctl reboot; then

            STATUS_MESSAGE="Restart failed"

            message_dialog \
                "Restart Failed" \
                "The restart command could not be completed." \
                "Restart the computer manually when ready."

        fi

    else

        STATUS_MESSAGE="Reboot required - restart later"

        draw_ui

    fi
}


# ============================================================
# CHECK FOR UPDATES
# ============================================================

check_for_updates() {

    if ! request_sudo_dialog; then
        return
    fi

    STATUS_MESSAGE="Checking Ubuntu package repositories..."

    draw_status

    if ! run_ide_progress \
        "Checking Ubuntu package repositories..." \
        "Refreshing the list of available packages." \
        sudo -n apt-get update; then

        show_update_error

        return

    fi

    if command -v fwupdmgr >/dev/null 2>&1; then

        STATUS_MESSAGE="Refreshing firmware metadata..."

        draw_status

        # Firmware refresh failures should not prevent normal
        # Ubuntu updates from being displayed.

        run_ide_progress \
            "Checking firmware metadata..." \
            "Refreshing firmware information from configured remotes." \
            fwupdmgr \
            --assume-yes \
            refresh || true

    fi

    STATUS_MESSAGE="Update check complete"

    draw_ui
}


# ============================================================
# UBUNTU SYSTEM UPDATE
# ============================================================

update_system_packages() {

    if ! confirm_dialog \
        "Ubuntu System Update" \
        "Install all currently available Ubuntu package updates?" \
        "A restart may be required after installation." \
        "Install Updates" \
        "Cancel"; then

        STATUS_MESSAGE="System update cancelled"

        draw_status

        return

    fi

    if ! request_sudo_dialog; then
        return
    fi

    STATUS_MESSAGE="Refreshing package information..."

    draw_status

    if ! run_ide_progress \
        "Checking Ubuntu package repositories..." \
        "Refreshing the package list before installation." \
        sudo -n apt-get update; then

        show_update_error

        return

    fi

    STATUS_MESSAGE="Installing Ubuntu updates..."

    draw_status

    if ! run_ide_progress \
        "Installing Ubuntu package updates..." \
        "Installing available software and security updates." \
        sudo -n apt-get upgrade -y; then

        show_update_error

        return

    fi

    STATUS_MESSAGE="Ubuntu update complete"

    draw_ui

    maybe_offer_reboot
}


# ============================================================
# HARDWARE DRIVER UPDATE
# ============================================================

update_hardware_drivers() {

    if ! command -v ubuntu-drivers >/dev/null 2>&1; then

        message_dialog \
            "Hardware Drivers" \
            "ubuntu-drivers is not available." \
            "Install ubuntu-drivers-common to enable this feature."

        return

    fi

    local drivers

    drivers=$(
        ubuntu-drivers list 2>/dev/null
    )

    if [[ -z "$drivers" ]]; then

        STATUS_MESSAGE="No additional drivers recommended"

        message_dialog \
            "Hardware Drivers" \
            "No additional recommended drivers were detected." \
            "Your current driver setup can be left as-is."

        return

    fi

    local first_driver

    first_driver=$(
        echo "$drivers" |
            head -1
    )

    if ! confirm_dialog \
        "Hardware Driver Update" \
        "Ubuntu found an additional supported hardware driver." \
        "Example: $first_driver" \
        "Install Driver" \
        "Cancel"; then

        STATUS_MESSAGE="Driver installation cancelled"

        draw_status

        return

    fi

    if ! request_sudo_dialog; then
        return
    fi

    STATUS_MESSAGE="Installing recommended hardware driver..."

    draw_status

    if ! run_ide_progress \
        "Installing recommended hardware driver..." \
        "Ubuntu is selecting and installing the best supported driver." \
        sudo -n ubuntu-drivers install; then

        show_update_error

        return

    fi

    STATUS_MESSAGE="Recommended driver installation complete"

    draw_ui

    maybe_offer_reboot
}


# ============================================================
# FIRMWARE UPDATE
# ============================================================

update_firmware() {

    if ! command -v fwupdmgr >/dev/null 2>&1; then

        message_dialog \
            "Firmware Updates" \
            "fwupdmgr is not available." \
            "Install the fwupd package to enable firmware updates."

        return

    fi

    local firmware_output
    local firmware_rc

    firmware_output=$(
        fwupdmgr get-updates \
            </dev/null \
            2>&1
    )

    firmware_rc=$?

    # fwupdmgr uses exit code 2 when the command completed
    # successfully but there was nothing to do.

    if ((firmware_rc == 2)) ||
       echo "$firmware_output" |
       grep -qiE \
       'No updates available|No updatable devices|No upgrades'; then

        STATUS_MESSAGE="Firmware is already up to date"

        message_dialog \
            "Firmware Updates" \
            "No supported firmware updates are currently available." \
            "Your detected firmware is up to date."

        return

    fi

    if ((firmware_rc != 0)); then

        LAST_UPDATE_ERROR=$(
            echo "$firmware_output" |
                tail -6 |
                tr '\n' ' '
        )

        show_update_error

        return

    fi

    if ! confirm_dialog \
        "Firmware Update" \
        "Supported firmware updates are available for this computer." \
        "Keep the computer connected to power during the update." \
        "Install Firmware" \
        "Cancel"; then

        STATUS_MESSAGE="Firmware update cancelled"

        draw_status

        return

    fi

    if ! request_sudo_dialog; then
        return
    fi

    STATUS_MESSAGE="Installing firmware updates..."

    draw_status

    # --assume-yes means fwupdmgr does not need to ask its
    # own confirmation questions.
    #
    # --no-reboot-check keeps fwupdmgr from displaying its
    # own restart prompt. Our IDE handles that afterward.

    if ! run_ide_progress \
        "Installing firmware updates..." \
        "Firmware is being downloaded and prepared for supported devices." \
        sudo -n \
        fwupdmgr \
        --assume-yes \
        --no-reboot-check \
        update; then

        if [[ "$LAST_UPDATE_ERROR" == *"No upgrades"* ]] ||
           [[ "$LAST_UPDATE_ERROR" == *"No updates"* ]] ||
           [[ "$LAST_UPDATE_ERROR" == *"No releases"* ]]; then

            STATUS_MESSAGE="Firmware already up to date"

            message_dialog \
                "Firmware Updates" \
                "No firmware update needed to be installed." \
                "The detected devices are already current."

            return

        fi

        show_update_error

        return

    fi

    # Firmware commonly needs a restart to activate.
    # Offer one using our own dialog.

    FORCE_REBOOT_REQUIRED=1

    STATUS_MESSAGE="Firmware update complete"

    draw_ui

    maybe_offer_reboot
}


# ============================================================
# RESIZE HANDLER
# ============================================================

handle_resize() {

    draw_ui
}


trap handle_resize WINCH


# ============================================================
# KEYBOARD READER
# ============================================================

read_key() {

    local first=""
    local second=""
    local third=""

    KEY=""

    IFS= read -r -n1 first

    # Normal key.

    if [[ "$first" != $'\e' ]]; then

        KEY="$first"

        return

    fi

    # Arrow-key escape sequence.

    IFS= read -r -n1 -t 0.20 second || true

    if [[ "$second" == "[" ||
          "$second" == "O" ]]; then

        IFS= read -r -n1 -t 0.20 third || true

        KEY="${first}${second}${third}"

    else

        KEY="${first}${second}"

    fi
}


# ============================================================
# START IDE
# ============================================================

draw_ui


# ============================================================
# MAIN INPUT LOOP
# ============================================================

while true; do

    read_key

    case "$KEY" in

        # ----------------------------------------------------
        # UP
        # ----------------------------------------------------

        $'\e[A'|$'\eOA')

            ((SELECTED--))

            if ((SELECTED < 0)); then

                SELECTED=$((
                    ${#MENU_ITEMS[@]} - 1
                ))

            fi

            STATUS_MESSAGE="Viewing ${MENU_ITEMS[$SELECTED]}"

            draw_menu
            draw_information
            draw_status
            draw_shortcuts

            ;;


        # ----------------------------------------------------
        # DOWN
        # ----------------------------------------------------

        $'\e[B'|$'\eOB')

            ((SELECTED++))

            if ((SELECTED >= ${#MENU_ITEMS[@]})); then

                SELECTED=0

            fi

            STATUS_MESSAGE="Viewing ${MENU_ITEMS[$SELECTED]}"

            draw_menu
            draw_information
            draw_status
            draw_shortcuts

            ;;


        # ----------------------------------------------------
        # ENTER
        # ----------------------------------------------------

        ""|$'\n'|$'\r')

            STATUS_MESSAGE="Refreshed $(date '+%H:%M:%S')"

            draw_information
            draw_status

            ;;


        # ----------------------------------------------------
        # R - REFRESH CURRENT PAGE
        # ----------------------------------------------------

        r|R)

            STATUS_MESSAGE="Refreshed $(date '+%H:%M:%S')"

            draw_information
            draw_status

            ;;


        # ----------------------------------------------------
        # C - CHECK FOR UPDATES
        # ----------------------------------------------------

        c|C)

            if [[ "${MENU_ITEMS[$SELECTED]}" == "Updates" ]]; then

                STATUS_MESSAGE="Checking for updates..."

                draw_status

                check_for_updates

            fi

            ;;


        # ----------------------------------------------------
        # U - UBUNTU UPDATE
        # ----------------------------------------------------

        u|U)

            if [[ "${MENU_ITEMS[$SELECTED]}" == "Updates" ]]; then

                update_system_packages

            fi

            ;;


        # ----------------------------------------------------
        # F - FIRMWARE UPDATE
        # ----------------------------------------------------

        f|F)

            if [[ "${MENU_ITEMS[$SELECTED]}" == "Updates" ]]; then

                update_firmware

            fi

            ;;


        # ----------------------------------------------------
        # D - HARDWARE DRIVER UPDATE
        # ----------------------------------------------------

        d|D)

            if [[ "${MENU_ITEMS[$SELECTED]}" == "Updates" ]]; then

                update_hardware_drivers

            fi

            ;;


        # ----------------------------------------------------
        # Q - QUIT
        # ----------------------------------------------------

        q|Q)

            STATUS_MESSAGE="Exiting..."

            draw_status

            sleep 0.1

            break

            ;;

    esac

done