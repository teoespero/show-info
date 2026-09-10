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
# BOX DRAWING CHARACTERS
# ------------------------------------------------------------
# Use Unicode box drawing when the terminal is UTF-8.
# Fall back to ASCII on older/non-UTF-8 terminals so the
# interface does not become misaligned.

if locale charmap 2>/dev/null | grep -qiE 'UTF-?8'; then
    BOX_TL="┌"
    BOX_TR="┐"
    BOX_BL="└"
    BOX_BR="┘"
    BOX_H="─"
    BOX_V="│"
    BOX_TDOWN="┬"
    BOX_TUP="┴"
else
    BOX_TL="+"
    BOX_TR="+"
    BOX_BL="+"
    BOX_BR="+"
    BOX_H="-"
    BOX_V="|"
    BOX_TDOWN="+"
    BOX_TUP="+"
fi

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
        local bar="" blank=""
        printf -v bar '%*s' "$position" ''
        bar="${bar// /#}"
        printf -v blank '%*s' "$((width - position))" ''

        printf "\r%-22s [" "$label"
        printf "${GREEN}%s${RESET}" "$bar"
        printf "%s]" "$blank"

        ((position++))
        ((position > width)) && position=1
        sleep 0.08
    done

    local complete=""
    printf -v complete '%*s' "$width" ''
    complete="${complete// /#}"
    printf "\r%-22s [${GREEN}%s${RESET}]\n" "$label" "$complete"
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

check_dependencies() {
    local missing_commands=()
    local missing_packages=()
    local cmd package existing already_added

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
        ((already_added == 0)) && missing_packages+=("$package")
    done

    ((${#missing_packages[@]} == 0)) && return 0

    clear
    echo "+------------------------------------------------------------+"
    echo "|              SYSTEM & HARDWARE INFORMATION                 |"
    echo "|                    DEPENDENCY CHECK                        |"
    echo "+------------------------------------------------------------+"
    echo
    echo "Some system tools are missing:"
    echo

    for cmd in "${missing_commands[@]}"; do
        printf "  %-18s -> %s\n" "$cmd" "${DEPENDENCIES[$cmd]}"
    done

    echo

    if ! command -v apt-get >/dev/null 2>&1; then
        printf "${YELLOW}[WARNING]${RESET} Automatic installation currently supports Ubuntu/Debian.\n"
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
                printf "${RED}[ERROR]${RESET} Administrator authentication failed.\n"
                read -rp "Press ENTER to continue..."
                return 1
            fi

            echo
            if ! run_with_progress "Updating package list" sudo apt-get update; then
                read -rp "Press ENTER to continue..."
                return 1
            fi

            echo
            if ! run_with_progress "Installing tools" sudo apt-get install -y "${missing_packages[@]}"; then
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
                printf "${YELLOW}Some optional tools are still unavailable.${RESET}\n"
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

check_dependencies

# ------------------------------------------------------------
# IDE STATE
# ------------------------------------------------------------
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
    "Logs / Rollback"
)

SELECTED=0
STATUS_MESSAGE="Ready"
FORCE_REBOOT_REQUIRED=0
LAST_UPDATE_ERROR=""

# Refresh/redraw state. These keep a resize signal from drawing
# over a page while fresh information is still being collected.
UI_BUSY=0
PENDING_RESIZE=0

ORIGINAL_STTY=$(stty -g 2>/dev/null)

# Persistent update/install logs and rollback transaction records.
APP_STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/sysinfo-ide"
LOG_DIR="$APP_STATE_DIR/logs"
TXN_DIR="$APP_STATE_DIR/transactions"

mkdir -p "$LOG_DIR" "$TXN_DIR" 2>/dev/null
chmod 700 "$APP_STATE_DIR" "$LOG_DIR" "$TXN_DIR" 2>/dev/null || true

CURRENT_LOG_FILE=""
CURRENT_OPERATION=""
CURRENT_TXN_DIR=""

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

tput smcup 2>/dev/null
tput civis 2>/dev/null
stty -echo 2>/dev/null

# ------------------------------------------------------------
# GENERAL HELPERS
# ------------------------------------------------------------
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
    local output=""

    ((count < 0)) && count=0

    # Bash substitution preserves multi-byte UTF-8 characters.
    # GNU tr can break characters such as the Unicode horizontal
    # line by repeating only one byte of the character.
    printf -v output '%*s' "$count" ''
    output="${output// /$char}"
    printf "%s" "$output"
}

trim_text() {
    local text="$1"
    local max="$2"
    if ((${#text} > max)); then
        printf "%s..." "${text:0:$((max - 3))}"
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
        x86_64) echo "64-bit Intel/AMD" ;;
        aarch64) echo "64-bit ARM" ;;
        armv7l) echo "32-bit ARM" ;;
        i386|i686) echo "32-bit Intel/AMD" ;;
        *) uname -m ;;
    esac
}

get_cpu_model() {
    lscpu 2>/dev/null | awk -F: '/Model name/ {gsub(/^[ \t]+/, "", $2); print $2; exit}'
}

get_cpu_cores() {
    lscpu 2>/dev/null | awk -F: '/^Core\(s\) per socket:/ {gsub(/[ \t]/, "", $2); print $2; exit}'
}

get_cpu_sockets() {
    lscpu 2>/dev/null | awk -F: '/Socket\(s\):/ {gsub(/[ \t]/, "", $2); print $2; exit}'
}

get_memory_percent() {
    free | awk '/Mem:/ {printf "%.0f", ($3 / $2) * 100}'
}

get_root_total() { df -h / | awk 'NR==2 {print $2}'; }
get_root_used()  { df -h / | awk 'NR==2 {print $3}'; }
get_root_free()  { df -h / | awk 'NR==2 {print $4}'; }
get_root_usage() { df -h / | awk 'NR==2 {print $5}'; }

make_usage_bar() {
    local percent="$1"
    local width=25
    percent="${percent//%/}"

    [[ "$percent" =~ ^[0-9]+$ ]] || percent=0
    ((percent > 100)) && percent=100
    ((percent < 0)) && percent=0

    local filled=$((percent * width / 100))
    local empty=$((width - filled))
    local bar="" blank=""

    printf -v bar '%*s' "$filled" ''
    bar="${bar// /#}"
    printf -v blank '%*s' "$empty" ''
    printf "[%s%s] %s%%" "$bar" "$blank" "$percent"
}

# ------------------------------------------------------------
# SYSTEM INFORMATION PAGES
# ------------------------------------------------------------
get_overview() {
    local manufacturer model cpu memory ip_address disk_percent mem_percent

    manufacturer=$(read_file /sys/class/dmi/id/sys_vendor)
    model=$(read_file /sys/class/dmi/id/product_name)
    cpu=$(get_cpu_model)
    memory=$(free -h | awk '/Mem:/ {print $2}')
    ip_address=$(hostname -I 2>/dev/null | awk '{print $1}')
    mem_percent=$(get_memory_percent)
    disk_percent=$(get_root_usage)
    disk_percent="${disk_percent//%/}"

    echo "COMPUTER"
    echo "------------------------------------------------------------"
    printf "%-21s %s\n" "Computer Name" "$(hostname)"
    printf "%-21s %s\n" "Manufacturer" "$manufacturer"
    printf "%-21s %s\n" "Model" "$model"

    echo
    echo "OPERATING SYSTEM"
    echo "------------------------------------------------------------"
    printf "%-21s %s\n" "Operating System" "$(get_os_name)"
    printf "%-21s %s\n" "Kernel" "$(uname -r)"
    printf "%-21s %s\n" "System Type" "$(human_architecture)"
    printf "%-21s %s\n" "System Uptime" "$(uptime -p 2>/dev/null | sed 's/^up //')"

    echo
    echo "HARDWARE"
    echo "------------------------------------------------------------"
    printf "%-21s %s\n" "Processor" "$cpu"
    printf "%-21s %s\n" "CPU Threads" "$(nproc)"
    printf "%-21s %s\n" "Installed Memory" "$memory"

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
    printf "%-21s %s\n" "Primary IP Address" "${ip_address:-Not connected}"
}

get_os() {
    echo "OPERATING SYSTEM"
    echo "------------------------------------------------------------"
    printf "%-22s %s\n" "Operating System" "$(get_os_name)"
    printf "%-22s %s\n" "Computer Name" "$(hostname)"
    printf "%-22s %s\n" "Kernel Version" "$(uname -r)"
    printf "%-22s %s\n" "System Type" "$(human_architecture)"

    if [[ -d /sys/firmware/efi ]]; then
        printf "%-22s %s\n" "Boot Mode" "UEFI"
    else
        printf "%-22s %s\n" "Boot Mode" "Legacy BIOS"
    fi

    printf "%-22s %s\n" "Running For" "$(uptime -p 2>/dev/null | sed 's/^up //')"

    echo
    echo "FIRMWARE"
    echo "------------------------------------------------------------"
    printf "%-22s %s\n" "BIOS Manufacturer" "$(read_file /sys/class/dmi/id/bios_vendor)"
    printf "%-22s %s\n" "BIOS Version" "$(read_file /sys/class/dmi/id/bios_version)"
    printf "%-22s %s\n" "BIOS Date" "$(read_file /sys/class/dmi/id/bios_date)"
}

get_processor() {
    local model sockets cores threads physical_cores cpu_mhz

    model=$(get_cpu_model)
    sockets=$(get_cpu_sockets)
    cores=$(get_cpu_cores)
    threads=$(nproc)

    if [[ "$sockets" =~ ^[0-9]+$ ]] && [[ "$cores" =~ ^[0-9]+$ ]]; then
        physical_cores=$((sockets * cores))
    else
        physical_cores="Unknown"
    fi

    echo "PROCESSOR"
    echo "------------------------------------------------------------"
    printf "%-22s %s\n" "Processor" "$model"
    printf "%-22s %s\n" "Physical Cores" "$physical_cores"
    printf "%-22s %s\n" "CPU Threads" "$threads"
    printf "%-22s %s\n" "System Type" "$(human_architecture)"

    cpu_mhz=$(lscpu 2>/dev/null | awk -F: '/CPU max MHz/ {gsub(/^[ \t]+/, "", $2); if ($2 > 0) printf "%.2f GHz", $2 / 1000; exit}')
    [[ -n "$cpu_mhz" ]] && printf "%-22s %s\n" "Maximum Speed" "$cpu_mhz"

    echo
    echo "CURRENT ACTIVITY"
    echo "------------------------------------------------------------"

    local load1 load5 load15
    read -r load1 load5 load15 _ < /proc/loadavg
    printf "%-22s %s\n" "1 Minute Load" "$load1"
    printf "%-22s %s\n" "5 Minute Load" "$load5"
    printf "%-22s %s\n" "15 Minute Load" "$load15"
    echo
    echo "Lower load usually means the processor is less busy."
}

get_memory() {
    local total used available swap_total swap_used percent

    total=$(free -h | awk '/Mem:/ {print $2}')
    used=$(free -h | awk '/Mem:/ {print $3}')
    available=$(free -h | awk '/Mem:/ {print $7}')
    swap_total=$(free -h | awk '/Swap:/ {print $2}')
    swap_used=$(free -h | awk '/Swap:/ {print $3}')
    percent=$(get_memory_percent)

    echo "MEMORY"
    echo "------------------------------------------------------------"
    printf "%-22s %s\n" "Installed Memory" "$total"
    printf "%-22s %s\n" "Currently Used" "$used"
    printf "%-22s %s\n" "Available Memory" "$available"
    echo
    printf "%-22s " "Memory Usage"
    make_usage_bar "$percent"
    echo

    echo
    echo "SWAP"
    echo "------------------------------------------------------------"
    printf "%-22s %s\n" "Swap Space" "$swap_total"
    printf "%-22s %s\n" "Swap Used" "$swap_used"

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

get_storage() {
    local disk_percent
    disk_percent=$(get_root_usage)
    disk_percent="${disk_percent//%/}"

    echo "SYSTEM DRIVE"
    echo "------------------------------------------------------------"
    printf "%-22s %s\n" "Total Capacity" "$(get_root_total)"
    printf "%-22s %s\n" "Used Space" "$(get_root_used)"
    printf "%-22s %s\n" "Available Space" "$(get_root_free)"
    echo
    printf "%-22s " "Storage Usage"
    make_usage_bar "$disk_percent"
    echo

    echo
    echo "PHYSICAL DRIVES"
    echo "------------------------------------------------------------"
    lsblk -dn -o NAME,SIZE,TYPE,MODEL 2>/dev/null |
    while read -r name size type model; do
        [[ "$type" != "disk" ]] && continue
        printf "%-12s %-10s %s\n" "/dev/$name" "$size" "${model:-Unknown drive}"
    done

    echo
    echo "MOUNTED STORAGE"
    echo "------------------------------------------------------------"
    printf "%-22s %-10s %-8s\n" "Location" "Size" "Used"
    df -h -x tmpfs -x devtmpfs -x squashfs 2>/dev/null |
        awk 'NR > 1 {printf "%-22s %-10s %-8s\n", $6, $2, $5}'
}

get_network() {
    local default_interface gateway connection_state

    default_interface=$(ip route 2>/dev/null | awk '/default/ {print $5; exit}')
    gateway=$(ip route 2>/dev/null | awk '/default/ {print $3; exit}')

    echo "NETWORK CONNECTION"
    echo "------------------------------------------------------------"
    printf "%-22s %s\n" "Computer Name" "$(hostname)"
    printf "%-22s %s\n" "Primary Interface" "${default_interface:-Not connected}"
    printf "%-22s %s\n" "Default Gateway" "${gateway:-Not available}"

    if [[ -n "$default_interface" ]]; then
        connection_state=$(cat "/sys/class/net/$default_interface/operstate" 2>/dev/null)
        if [[ "$connection_state" == "up" ]]; then
            printf "%-22s %s\n" "Connection Status" "Connected"
        else
            printf "%-22s %s\n" "Connection Status" "Disconnected"
        fi
    fi

    echo
    echo "IP ADDRESSES"
    echo "------------------------------------------------------------"
    ip -o -4 addr show 2>/dev/null |
        awk '$2 != "lo" {split($4, address, "/"); printf "%-18s %s\n", $2, address[1]}'

    echo
    echo "DNS SERVERS"
    echo "------------------------------------------------------------"
    if command -v resolvectl >/dev/null 2>&1; then
        local dns
        dns=$(resolvectl dns 2>/dev/null | head -5)
        [[ -n "$dns" ]] && echo "$dns" || echo "DNS information unavailable."
    else
        grep '^nameserver' /etc/resolv.conf 2>/dev/null | awk '{print $2}'
    fi
}

get_graphics() {
    echo "GRAPHICS"
    echo "------------------------------------------------------------"

    if ! command -v lspci >/dev/null 2>&1; then
        echo "PCI information tool is unavailable."
        return
    fi

    local gpu_count=0 gpu
    while IFS= read -r gpu; do
        [[ -z "$gpu" ]] && continue
        ((gpu_count++))
        gpu=$(echo "$gpu" | sed 's/^[^ ]* //' | sed 's/^[^:]*: //')
        printf "%-22s %s\n" "Graphics Adapter" "$gpu"
    done < <(lspci 2>/dev/null | grep -Ei 'VGA|3D|Display')

    ((gpu_count == 0)) && echo "Graphics adapter information unavailable."

    echo
    echo "ACTIVE DRIVER"
    echo "------------------------------------------------------------"

    local driver
    driver=$(lspci -k 2>/dev/null | grep -A3 -Ei 'VGA|3D|Display' |
        awk -F: '/Kernel driver in use/ {gsub(/^[ \t]+/, "", $2); print $2; exit}')
    printf "%-22s %s\n" "Graphics Driver" "${driver:-Unknown}"
}

get_battery() {
    echo "BATTERY"
    echo "------------------------------------------------------------"

    if ! command -v upower >/dev/null 2>&1; then
        echo "Battery information tool is unavailable."
        return
    fi

    local battery
    battery=$(upower -e 2>/dev/null | grep -Ei 'battery|BAT' | head -1)

    if [[ -z "$battery" ]]; then
        echo "No battery was detected."
        echo
        echo "This is normal for desktop computers."
        return
    fi

    local info model vendor state percentage capacity remaining time_full
    info=$(upower -i "$battery" 2>/dev/null)
    vendor=$(echo "$info" | awk -F: '/vendor:/ {sub(/^[ \t]+/, "", $2); print $2; exit}')
    model=$(echo "$info" | awk -F: '/model:/ {sub(/^[ \t]+/, "", $2); print $2; exit}')
    state=$(echo "$info" | awk -F: '/state:/ {sub(/^[ \t]+/, "", $2); print $2; exit}')
    percentage=$(echo "$info" | awk -F: '/percentage:/ {sub(/^[ \t]+/, "", $2); print $2; exit}')
    capacity=$(echo "$info" | awk -F: '/capacity:/ {sub(/^[ \t]+/, "", $2); print $2; exit}')
    remaining=$(echo "$info" | awk -F: '/time to empty:/ {sub(/^[ \t]+/, "", $2); print $2; exit}')
    time_full=$(echo "$info" | awk -F: '/time to full:/ {sub(/^[ \t]+/, "", $2); print $2; exit}')

    printf "%-22s %s\n" "Manufacturer" "${vendor:-Unknown}"
    printf "%-22s %s\n" "Battery Model" "${model:-Internal Battery}"
    printf "%-22s %s\n" "Status" "${state:-Unknown}"
    printf "%-22s %s\n" "Charge Level" "${percentage:-Unknown}"
    printf "%-22s %s\n" "Battery Health" "${capacity:-Unknown}"
    [[ -n "$remaining" ]] && printf "%-22s %s\n" "Estimated Runtime" "$remaining"
    [[ -n "$time_full" ]] && printf "%-22s %s\n" "Time Until Full" "$time_full"

    if [[ "$percentage" =~ ^([0-9]+)%$ ]]; then
        echo
        printf "%-22s " "Battery"
        make_usage_bar "${BASH_REMATCH[1]}"
        echo
    fi
}

get_internal_hardware() {
    echo "INTERNAL HARDWARE"
    echo "------------------------------------------------------------"

    if ! command -v lspci >/dev/null 2>&1; then
        echo "PCI information tool is unavailable."
        return
    fi

    echo
    echo "Graphics:"
    lspci 2>/dev/null | grep -Ei 'VGA|3D|Display' | sed -E 's/^[0-9a-fA-F:.]+ //' | sed 's/^/  /'

    echo
    echo "Network Hardware:"
    lspci 2>/dev/null | grep -Ei 'Ethernet|Network controller|Wireless' | sed -E 's/^[0-9a-fA-F:.]+ //' | sed 's/^/  /'

    echo
    echo "Audio Hardware:"
    lspci 2>/dev/null | grep -Ei 'Audio|Multimedia' | sed -E 's/^[0-9a-fA-F:.]+ //' | sed 's/^/  /'

    echo
    echo "Storage Controllers:"
    lspci 2>/dev/null | grep -Ei 'SATA|NVMe|RAID|Storage controller' | sed -E 's/^[0-9a-fA-F:.]+ //' | sed 's/^/  /'
}

get_usb() {
    echo "USB DEVICES"
    echo "------------------------------------------------------------"

    if ! command -v lsusb >/dev/null 2>&1; then
        echo "USB information tool is unavailable."
        return
    fi

    local count
    count=$(lsusb 2>/dev/null | wc -l)
    printf "%-22s %s\n" "Devices Detected" "$count"

    echo
    echo "CONNECTED USB HARDWARE"
    echo "------------------------------------------------------------"
    lsusb 2>/dev/null | sed -E 's/^Bus [0-9]+ Device [0-9]+: ID [^ ]+ /  /'
}

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
    output=$(sensors 2>/dev/null |
        grep -E 'Package id|Core [0-9]+:|Tctl:|Tdie:|Composite:|CPU:|temp[0-9]+:' |
        sed 's/^[ \t]*//')

    [[ -n "$output" ]] && echo "$output" || echo "No readable temperature sensors were detected."

    echo
    echo "TEMPERATURE GUIDE"
    echo "------------------------------------------------------------"
    echo "Below 60 C       Normal for light use"
    echo "60 - 80 C        Normal under heavier workloads"
    echo "80 - 85 C        Running warm"
    echo "Above 85 C       Worth monitoring"
}

# ============================================================
# PERSISTENT UPDATE LOGS / TRANSACTIONS
# ============================================================

safe_filename_component() {
    local text="$1"
    text="${text// /-}"
    text="${text//\//-}"
    text="${text//:/-}"
    printf "%s" "$text" | tr -cd 'A-Za-z0-9._-'
}

begin_operation_log() {
    local operation="$1"
    local stamp

    stamp=$(date '+%Y%m%d_%H%M%S')
    operation=$(safe_filename_component "$operation")

    CURRENT_OPERATION="$operation"
    CURRENT_LOG_FILE="$LOG_DIR/${stamp}_${operation}.log"

    : > "$CURRENT_LOG_FILE"
    chmod 600 "$CURRENT_LOG_FILE" 2>/dev/null || true

    {
        printf "System & Hardware Information / Maintenance IDE\n"
        printf "Operation : %s\n" "$operation"
        printf "Started   : %s\n" "$(date '+%Y-%m-%d %H:%M:%S %Z')"
        printf "Computer  : %s\n" "$(hostname)"
        printf "User      : %s\n" "${USER:-unknown}"
        printf '%s\n' "----------------------------------------------------------------"
    } >> "$CURRENT_LOG_FILE"
}

log_append() {
    [[ -n "$CURRENT_LOG_FILE" ]] || return 0

    local text="$*"
    text="${text//$'\r'/}"
    text=$(printf '%s' "$text" | tr -d '\000-\010\013\014\016-\037\177')

    printf '[%s] %s\n' \
        "$(date '+%Y-%m-%d %H:%M:%S')" \
        "$text" >> "$CURRENT_LOG_FILE"
}

end_operation_log() {
    local status="$1"

    [[ -n "$CURRENT_LOG_FILE" ]] || return 0

    {
        printf '%s\n' "----------------------------------------------------------------"
        printf "Finished  : %s\n" "$(date '+%Y-%m-%d %H:%M:%S %Z')"
        printf "Status    : %s\n" "$status"
    } >> "$CURRENT_LOG_FILE"
}

snapshot_installed_packages() {
    local outfile="$1"

    dpkg-query -W \
        -f='${binary:Package}\t${Version}\n' \
        2>/dev/null | LC_ALL=C sort > "$outfile"
}

compare_package_snapshots() {
    local before="$1"
    local after="$2"
    local outfile="$3"

    awk -F '\t' '
        NR == FNR {
            old[$1] = $2
            next
        }
        {
            new[$1] = $2

            if (!($1 in old)) {
                print "INSTALLED\t" $1 "\t-\t" $2
            }
            else if (old[$1] != $2) {
                print "CHANGED\t" $1 "\t" old[$1] "\t" $2
            }
        }
        END {
            for (pkg in old) {
                if (!(pkg in new)) {
                    print "REMOVED\t" pkg "\t" old[pkg] "\t-"
                }
            }
        }
    ' "$before" "$after" | LC_ALL=C sort > "$outfile"
}

begin_transaction() {
    local type="$1"
    local stamp

    stamp=$(date '+%Y%m%d_%H%M%S')
    type=$(safe_filename_component "$type")

    CURRENT_TXN_DIR="$TXN_DIR/${stamp}_${type}_$$"
    mkdir -p "$CURRENT_TXN_DIR"
    chmod 700 "$CURRENT_TXN_DIR" 2>/dev/null || true

    snapshot_installed_packages "$CURRENT_TXN_DIR/before.tsv"

    {
        printf "type=%s\n" "$type"
        printf "started=%s\n" "$(date '+%Y-%m-%d %H:%M:%S %Z')"
        printf "status=running\n"
        printf "rollback_supported=no\n"
        printf "log=%s\n" "$CURRENT_LOG_FILE"
    } > "$CURRENT_TXN_DIR/meta"
}

transaction_meta_append() {
    local key="$1"
    local value="$2"

    [[ -n "$CURRENT_TXN_DIR" && -d "$CURRENT_TXN_DIR" ]] || return 0
    printf '%s=%s\n' "$key" "$value" >> "$CURRENT_TXN_DIR/meta"
}

finish_transaction() {
    local status="$1"
    local rollback_supported="$2"

    [[ -n "$CURRENT_TXN_DIR" && -d "$CURRENT_TXN_DIR" ]] || return 0

    snapshot_installed_packages "$CURRENT_TXN_DIR/after.tsv"
    compare_package_snapshots \
        "$CURRENT_TXN_DIR/before.tsv" \
        "$CURRENT_TXN_DIR/after.tsv" \
        "$CURRENT_TXN_DIR/changes.tsv"

    {
        printf "finished=%s\n" "$(date '+%Y-%m-%d %H:%M:%S %Z')"
        printf "final_status=%s\n" "$status"
        printf "final_rollback_supported=%s\n" "$rollback_supported"
    } >> "$CURRENT_TXN_DIR/meta"
}

meta_value() {
    local meta="$1"
    local key="$2"

    awk -F= -v key="$key" '
        $1 == key {
            value = substr($0, index($0, "=") + 1)
        }
        END {
            print value
        }
    ' "$meta" 2>/dev/null
}

latest_log_file() {
    find "$LOG_DIR" -maxdepth 1 -type f -name '*.log' \
        -printf '%T@\t%p\n' 2>/dev/null | \
        sort -nr | head -1 | cut -f2-
}

log_count() {
    find "$LOG_DIR" -maxdepth 1 -type f -name '*.log' \
        2>/dev/null | wc -l
}

rollback_transaction_count() {
    local count=0
    local dir meta status rollback changes

    while IFS= read -r dir; do
        [[ -n "$dir" ]] || continue
        meta="$dir/meta"
        [[ -f "$meta" ]] || continue

        status=$(meta_value "$meta" final_status)
        rollback=$(meta_value "$meta" final_rollback_supported)
        changes="$dir/changes.tsv"

        if [[ ("$status" == "success" || "$status" == "failed") &&
              "$rollback" == "yes" && -s "$changes" ]]; then
            ((count++))
        fi
    done < <(
        find "$TXN_DIR" -mindepth 1 -maxdepth 1 -type d \
            -printf '%p\n' 2>/dev/null
    )

    echo "$count"
}

get_logs_rollback() {
    local latest count rollbacks latest_name

    latest=$(latest_log_file)
    count=$(log_count)
    rollbacks=$(rollback_transaction_count)

    if [[ -n "$latest" ]]; then
        latest_name=$(basename "$latest")
    else
        latest_name="No logs created yet"
    fi

    echo "UPDATE / INSTALL LOGS"
    echo "------------------------------------------------------------"
    printf "%-24s %s\n" "Saved Logs" "$count"
    printf "%-24s %s\n" "Latest Log" "$latest_name"
    printf "%-24s %s\n" "Log Folder" "$LOG_DIR"

    echo
    echo "ROLLBACK"
    echo "------------------------------------------------------------"
    printf "%-24s %s\n" "Rollback Transactions" "$rollbacks"
    echo "Package rollback is best effort."
    echo "Previous package versions must still be available."
    echo
    echo "Firmware rollback is not performed automatically."

    echo
    echo "OPTIONS"
    echo "------------------------------------------------------------"
    echo "L   Browse and view saved logs"
    echo "B   Browse rollback transactions"
}

# ------------------------------------------------------------
# UPDATE INFORMATION
# ------------------------------------------------------------
get_package_update_count() {
    command -v apt >/dev/null 2>&1 || { echo "Unknown"; return; }
    local count
    count=$(apt list --upgradable 2>/dev/null | tail -n +2 | grep -c .)
    echo "${count:-0}"
}

get_security_update_count() {
    command -v apt >/dev/null 2>&1 || { echo "Unknown"; return; }
    local count
    count=$(apt list --upgradable 2>/dev/null | tail -n +2 | grep -Ei -- '-security|security' | wc -l)
    echo "${count:-0}"
}

get_reboot_status() {
    if [[ -f /var/run/reboot-required ]] || ((FORCE_REBOOT_REQUIRED == 1)); then
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

    local output result
    output=$(timeout 8s fwupdmgr get-updates </dev/null 2>&1)
    result=$?

    if ((result == 2)); then
        echo "Up to date"
    elif echo "$output" | grep -qiE 'No updates available|No updatable devices|No upgrades'; then
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
    drivers=$(timeout 8s ubuntu-drivers list 2>/dev/null)

    if [[ -n "$drivers" ]]; then
        local first
        first=$(echo "$drivers" | head -1)
        echo "Available: $first"
    else
        echo "No additional drivers"
    fi
}

get_updates() {
    local package_count security_count firmware_status driver_status reboot_status
    package_count=$(get_package_update_count)
    security_count=$(get_security_update_count)
    firmware_status=$(get_firmware_status)
    driver_status=$(get_driver_status)
    reboot_status=$(get_reboot_status)

    echo "SYSTEM UPDATES"
    echo "------------------------------------------------------------"
    printf "%-25s %s\n" "Package Updates" "$package_count available"
    printf "%-25s %s\n" "Security Updates" "$security_count available"
    printf "%-25s %s\n" "Reboot Required" "$reboot_status"

    echo
    echo "FIRMWARE / BIOS"
    echo "------------------------------------------------------------"
    printf "%-25s %s\n" "Firmware Status" "$firmware_status"

    echo
    echo "HARDWARE DRIVERS"
    echo "------------------------------------------------------------"
    printf "%-25s %s\n" "Driver Status" "$driver_status"

    echo
    echo "MAINTENANCE OPTIONS"
    echo "------------------------------------------------------------"
    echo "C   Check for updates"
    echo "U   Install Ubuntu updates"
    echo "F   Install firmware updates"
    echo "D   Install recommended drivers"
    echo "L   Open update/install logs"
    echo "B   Open rollback transactions"
}

get_information() {
    case "${MENU_ITEMS[$SELECTED]}" in
        "Overview") get_overview ;;
        "Operating System") get_os ;;
        "Processor") get_processor ;;
        "Memory") get_memory ;;
        "Storage") get_storage ;;
        "Network") get_network ;;
        "Graphics") get_graphics ;;
        "Battery") get_battery ;;
        "Internal Hardware") get_internal_hardware ;;
        "USB Devices") get_usb ;;
        "Temperatures") get_temperature ;;
        "Updates") get_updates ;;
        "Logs / Rollback") get_logs_rollback ;;
    esac
}

# ------------------------------------------------------------
# TERMINAL GEOMETRY
# ------------------------------------------------------------
update_dimensions() {
    COLS=$(tput cols)
    LINES=$(tput lines)

    # Main-frame geometry.
    #
    # Column 0                 = left border
    # Columns 1..26           = menu interior
    # Column 27                = center divider
    # Columns 28..COLS-2      = right-panel interior
    # Column COLS-1            = right border
    #
    # Both panels reserve one completely blank padding cell on
    # the left and right. Text never touches a vertical border.

    MENU_DIVIDER_X=27
    MENU_INNER_WIDTH=$((MENU_DIVIDER_X - 1))
    RIGHT_WIDTH=$((COLS - MENU_DIVIDER_X - 2))

    MENU_PAD=1
    RIGHT_PAD=1

    MENU_CONTENT_X=$((1 + MENU_PAD))
    MENU_CONTENT_WIDTH=$((MENU_INNER_WIDTH - (MENU_PAD * 2)))

    RIGHT_INNER_X=$((MENU_DIVIDER_X + 1))
    RIGHT_CONTENT_X=$((RIGHT_INNER_X + RIGHT_PAD))
    RIGHT_CONTENT_WIDTH=$((RIGHT_WIDTH - (RIGHT_PAD * 2)))

    CONTENT_BOTTOM=$((LINES - 4))

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

# ------------------------------------------------------------
# MAIN FRAME
# ------------------------------------------------------------
draw_frame() {
    update_dimensions

    tput cup 0 0
    printf "${BOLD}${CYAN}"
    printf "%-*s" "$COLS" " SYSTEM & HARDWARE INFORMATION / MAINTENANCE"
    printf "${RESET}"

    # Unicode frame:
    # ┌──────────────────────────┬──────────────────────────────┐

    tput cup 1 0
    printf "%s" "$BOX_TL"
    repeat_char "$BOX_H" "$MENU_INNER_WIDTH"
    printf "%s" "$BOX_TDOWN"
    repeat_char "$BOX_H" "$RIGHT_WIDTH"
    printf "%s" "$BOX_TR"

    local row

    for ((row=2; row<=CONTENT_BOTTOM; row++)); do
        tput cup "$row" 0
        printf "%s" "$BOX_V"

        tput cup "$row" "$MENU_DIVIDER_X"
        printf "%s" "$BOX_V"

        tput cup "$row" $((COLS - 1))
        printf "%s" "$BOX_V"
    done

    # Bottom frame:
    # └──────────────────────────┴──────────────────────────────┘

    tput cup $((LINES - 3)) 0
    printf "%s" "$BOX_BL"
    repeat_char "$BOX_H" "$MENU_INNER_WIDTH"
    printf "%s" "$BOX_TUP"
    repeat_char "$BOX_H" "$RIGHT_WIDTH"
    printf "%s" "$BOX_BR"
}

clear_left_panel() {
    local row

    # Clear the ENTIRE interior of the left panel before redrawing it.
    # Large modal windows such as the log viewer and rollback browser can
    # temporarily cover this area. Clearing only the individual menu rows
    # leaves pieces of the modal behind below the last menu item.
    #
    # Columns 0 and MENU_DIVIDER_X are borders, so only columns 1 through
    # MENU_DIVIDER_X-1 are erased here.
    for ((row=2; row<=CONTENT_BOTTOM; row++)); do
        tput cup "$row" 1
        printf "%${MENU_INNER_WIDTH}s" ""
    done
}


draw_menu() {
    # Always restore the complete panel, not just the rows occupied by menu
    # entries. This makes draw_ui() and draw_ui_cached() safe after any modal.
    clear_left_panel

    tput cup 2 "$MENU_CONTENT_X"
    printf "${BOLD}${CYAN}SYSTEM INFO${RESET}"

    local row=4 i label

    for ((i=0; i<${#MENU_ITEMS[@]}; i++)); do

        # Clear the complete menu interior first. This preserves
        # exactly one blank cell next to both vertical borders.
        tput cup "$row" 1
        printf "%${MENU_INNER_WIDTH}s" ""

        if ((i == SELECTED)); then
            label=" > ${MENU_ITEMS[$i]}"
            printf -v label "%-*.*s" \
                "$MENU_CONTENT_WIDTH" \
                "$MENU_CONTENT_WIDTH" \
                "$label"

            tput cup "$row" "$MENU_CONTENT_X"
            printf "${SELECT_BG}${SELECT_FG}${BOLD}%s${RESET}" "$label"
        else
            label="   ${MENU_ITEMS[$i]}"
            printf -v label "%-*.*s" \
                "$MENU_CONTENT_WIDTH" \
                "$MENU_CONTENT_WIDTH" \
                "$label"

            tput cup "$row" "$MENU_CONTENT_X"
            printf "%s" "$label"
        fi

        ((row++))
    done
}

clear_right_panel() {
    local row
    for ((row=2; row<=CONTENT_BOTTOM; row++)); do
        tput cup "$row" $((MENU_DIVIDER_X + 1))
        printf "%${RIGHT_WIDTH}s" ""
    done
}

draw_information() {
    local start_x="$RIGHT_CONTENT_X"
    local content_width="$RIGHT_CONTENT_WIDTH"
    local row line
    local page_title="${MENU_ITEMS[$SELECTED]}"
    local -a new_info_lines=()

    # Collect the new data BEFORE clearing the panel. Some commands,
    # especially fwupdmgr and ubuntu-drivers, can take a moment.
    # Keeping the old page visible prevents blank/flickering refreshes.
    mapfile -t new_info_lines < <(get_information 2>&1)

    # Swap in the completed data only after collection finishes.
    INFO_LINES=("${new_info_lines[@]}")

    clear_right_panel

    tput cup 2 "$start_x"
    printf "${BOLD}${GREEN}%s${RESET}" "$page_title"

    row=4
    for line in "${INFO_LINES[@]}"; do
        ((row > CONTENT_BOTTOM)) && break
        line="${line//$'\t'/    }"
        if ((${#line} > content_width)); then
            line="${line:0:$((content_width - 3))}..."
        fi
        tput cup "$row" "$start_x"
        printf "%-*s" "$content_width" "$line"
        ((row++))
    done
}

refresh_current_page() {
    local page="${MENU_ITEMS[$SELECTED]}"

    if ((UI_BUSY == 1)); then
        STATUS_MESSAGE="Refresh already in progress"
        draw_status
        return
    fi

    UI_BUSY=1
    STATUS_MESSAGE="Refreshing ${page}..."
    draw_status
    tput civis 2>/dev/null

    draw_information

    STATUS_MESSAGE="Refreshed ${page} at $(date '+%H:%M:%S')"
    draw_status
    draw_shortcuts
    UI_BUSY=0

    # If SIGWINCH arrived while data was being collected, redraw once
    # after the refresh instead of letting the resize interrupt it.
    if ((PENDING_RESIZE == 1)); then
        PENDING_RESIZE=0
        draw_ui
    fi
}

draw_status() {
    tput cup $((LINES - 2)) 0
    printf "%${COLS}s" ""
    tput cup $((LINES - 2)) 0
    printf "${BOLD} STATUS:${RESET} %s" "$STATUS_MESSAGE"
}

draw_shortcuts() {
    tput cup $((LINES - 1)) 0
    printf "%${COLS}s" ""
    tput cup $((LINES - 1)) 0
    printf "${CYAN}"
    if [[ "${MENU_ITEMS[$SELECTED]}" == "Updates" ]]; then
        printf " [C] Check   [U] Update   [F] Firmware   [D] Drivers   [L] Logs   [B] Rollback"
    elif [[ "${MENU_ITEMS[$SELECTED]}" == "Logs / Rollback" ]]; then
        printf " [L] View Logs   [B] Rollback   [ENTER] Refresh   [Q] Quit"
    else
        printf " [UP/DOWN] Navigate   [ENTER] Refresh   [R] Refresh   [Q] Quit"
    fi
    printf "${RESET}"
}

draw_information_cached() {
    # Redraw the right panel from the last completed information snapshot.
    # This is used behind modal browsers so opening/scrolling logs does not
    # rerun slow probes such as fwupdmgr or ubuntu-drivers.
    local start_x="$RIGHT_CONTENT_X"
    local content_width="$RIGHT_CONTENT_WIDTH"
    local row line
    local page_title="${MENU_ITEMS[$SELECTED]}"

    clear_right_panel

    tput cup 2 "$start_x"
    printf "${BOLD}${GREEN}%s${RESET}" "$page_title"

    row=4
    for line in "${INFO_LINES[@]:-}"; do
        ((row > CONTENT_BOTTOM)) && break
        line="${line//$'\t'/    }"
        if ((${#line} > content_width)); then
            line="${line:0:$((content_width - 3))}..."
        fi
        tput cup "$row" "$start_x"
        printf "%-*s" "$content_width" "$line"
        ((row++))
    done
}

draw_ui_cached() {
    draw_frame
    draw_menu
    draw_information_cached
    draw_status
    draw_shortcuts
}

draw_ui() {
    draw_frame
    draw_menu
    draw_information
    draw_status
    draw_shortcuts
}

# ------------------------------------------------------------
# MODAL BOX SYSTEM
# ------------------------------------------------------------
MODAL_X=0
MODAL_Y=0
MODAL_W=0
MODAL_H=0

modal_draw() {
    local title="$1"
    local width="$2"
    local height="$3"

    ((width > COLS - 4)) && width=$((COLS - 4))
    ((height > LINES - 4)) && height=$((LINES - 4))
    ((width < 30)) && width=30
    ((height < 7)) && height=7

    MODAL_W=$width
    MODAL_H=$height
    MODAL_X=$(((COLS - MODAL_W) / 2))
    MODAL_Y=$(((LINES - MODAL_H) / 2))

    local inner=$((MODAL_W - 2))
    local row

    # Dialog content always has three blank cells between text
    # and each vertical border. All dialog helpers use these same
    # bounds so titles, messages, buttons and fields line up.
    MODAL_PAD=3
    MODAL_CONTENT_X=$((MODAL_X + 1 + MODAL_PAD))
    MODAL_CONTENT_WIDTH=$((inner - (MODAL_PAD * 2)))

    ((MODAL_CONTENT_WIDTH < 1)) && MODAL_CONTENT_WIDTH=1

    # Top border.
    tput cup "$MODAL_Y" "$MODAL_X"
    printf "%s" "$BOX_TL"
    repeat_char "$BOX_H" "$inner"
    printf "%s" "$BOX_TR"

    # Body. Every row is exactly MODAL_W display cells wide:
    # one border + inner spaces + one border.
    for ((row=1; row<MODAL_H-1; row++)); do
        tput cup $((MODAL_Y + row)) "$MODAL_X"
        printf "%s" "$BOX_V"
        printf "%${inner}s" ""
        printf "%s" "$BOX_V"
    done

    # Bottom border.
    tput cup $((MODAL_Y + MODAL_H - 1)) "$MODAL_X"
    printf "%s" "$BOX_BL"
    repeat_char "$BOX_H" "$inner"
    printf "%s" "$BOX_BR"

    # Center the title inside the padded content area, not across
    # the border cells themselves.
    local title_text
    title_text=$(trim_text "$title" "$MODAL_CONTENT_WIDTH")

    local title_x=$((
        MODAL_CONTENT_X +
        (MODAL_CONTENT_WIDTH - ${#title_text}) / 2
    ))

    tput cup $((MODAL_Y + 1)) "$title_x"
    printf "${BOLD}${CYAN}%s${RESET}" "$title_text"
}

modal_text() {
    local relative_row="$1"
    local relative_col="$2"
    local text="$3"

    # relative_col is relative to the padded content area.
    ((relative_col < 0)) && relative_col=0
    ((relative_col >= MODAL_CONTENT_WIDTH)) && return

    local max_width=$((MODAL_CONTENT_WIDTH - relative_col))
    local shown
    shown=$(trim_text "$text" "$max_width")

    tput cup \
        $((MODAL_Y + relative_row)) \
        $((MODAL_CONTENT_X + relative_col))

    printf "%s" "$shown"
}

modal_center_text() {
    local relative_row="$1"
    local text="$2"

    local shown
    shown=$(trim_text "$text" "$MODAL_CONTENT_WIDTH")

    local x=$((
        MODAL_CONTENT_X +
        (MODAL_CONTENT_WIDTH - ${#shown}) / 2
    ))

    tput cup $((MODAL_Y + relative_row)) "$x"
    printf "%s" "$shown"
}

message_dialog() {
    local title="$1"
    local line1="$2"
    local line2="${3:-}"

    draw_ui
    modal_draw "$title" 64 10
    modal_center_text 3 "$line1"
    [[ -n "$line2" ]] && modal_center_text 4 "$line2"
    modal_center_text 7 "Press ENTER to continue"

    while true; do
        read_key
        case "$KEY" in
            ""|$'\n'|$'\r'|$'\e') break ;;
        esac
    done

    draw_ui
}

confirm_dialog() {
    local title="$1"
    local line1="$2"
    local line2="$3"
    local yes_text="$4"
    local no_text="$5"

    draw_ui
    modal_draw "$title" 68 11
    modal_center_text 3 "$line1"
    modal_center_text 4 "$line2"

    local buttons="[Y] $yes_text     [N] $no_text"
    modal_center_text 7 "$buttons"
    modal_center_text 8 "ESC also cancels"

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

read_masked_password() {
    local field_x="$1"
    local field_y="$2"
    local field_width="$3"
    local char=""

    DIALOG_PASSWORD=""

    while true; do
        IFS= read -r -n1 char

        if [[ -z "$char" ]]; then
            break
        fi

        case "$char" in
            $'\e')
                DIALOG_PASSWORD=""
                return 1
                ;;
            $'\177'|$'\b')
                [[ -n "$DIALOG_PASSWORD" ]] && DIALOG_PASSWORD="${DIALOG_PASSWORD%?}"
                ;;
            *)
                ((${#DIALOG_PASSWORD} < field_width)) && DIALOG_PASSWORD+="$char"
                ;;
        esac

        tput cup "$field_y" "$field_x"
        printf "%-*s" "$field_width" ""
        tput cup "$field_y" "$field_x"
        printf "%${#DIALOG_PASSWORD}s" "" | tr " " "*"
    done

    return 0
}

request_sudo_dialog() {
    if sudo -n true >/dev/null 2>&1; then
        return 0
    fi

    local attempts=0

    while ((attempts < 3)); do
        draw_ui
        modal_draw "Administrator Password" 66 12
        modal_center_text 3 "Administrator access is required to continue."

        local label="Password:"
        local field_width=30
        local field_y=$((MODAL_Y + 5))
        local field_x=$((MODAL_CONTENT_X + 13))

        # Label begins at the left edge of the padded content area.
        modal_text 5 0 "$label"
        # Keep the password field inside the modal's padded area.
        local max_field_width=$((
            MODAL_CONTENT_X + MODAL_CONTENT_WIDTH - field_x
        ))

        ((field_width > max_field_width)) && field_width=$max_field_width
        ((field_width < 8)) && field_width=8

        tput cup "$field_y" "$field_x"
        printf "%${field_width}s" "" | tr " " "_"

        modal_center_text 8 "ENTER Continue     ESC Cancel"
        tput cup "$field_y" "$field_x"

        if ! read_masked_password "$field_x" "$field_y" "$field_width"; then
            unset DIALOG_PASSWORD
            STATUS_MESSAGE="Administrator request cancelled"
            draw_ui
            return 1
        fi

        if printf '%s\n' "$DIALOG_PASSWORD" | sudo -S -p '' -v >/dev/null 2>&1; then
            unset DIALOG_PASSWORD
            draw_ui
            return 0
        fi

        unset DIALOG_PASSWORD
        ((attempts++))

        draw_ui
        modal_draw "Incorrect Password" 56 9
        modal_center_text 3 "The password was not accepted."
        if ((attempts < 3)); then
            modal_center_text 5 "Press ENTER to try again"
        else
            modal_center_text 5 "Maximum attempts reached"
        fi

        while true; do
            read_key
            case "$KEY" in
                ""|$'\n'|$'\r'|$'\e') break ;;
            esac
        done
    done

    STATUS_MESSAGE="Administrator authentication failed"
    draw_ui
    return 1
}

# ------------------------------------------------------------
# IDE UPDATE PROGRESS
# ------------------------------------------------------------
#
# The right panel becomes a live update console. Recent package
# activity is displayed in the upper part of the panel. The
# current package/action is fixed near the bottom and the
# progress bar always stays on the final row inside the IDE.
#
# APT-specific operations use APT::Status-Fd so the percentage
# is APT's real 0-100 progress value instead of a fake timer.
# ------------------------------------------------------------

UPDATE_HISTORY=()
UPDATE_CURRENT_ACTION="Waiting..."
UPDATE_CURRENT_ITEM=""
UPDATE_PERCENT=0
UPDATE_LAST_EVENT=""

update_history_clear() {
    UPDATE_HISTORY=()
    UPDATE_LAST_EVENT=""
}

update_history_add() {
    local text="$1"
    local max_lines="$2"

    # Remove carriage returns and collapse repeated whitespace.
    text="${text//$'\r'/}"
    text=$(printf '%s' "$text" | sed 's/[[:space:]][[:space:]]*/ /g')

    [[ -z "$text" ]] && return
    [[ "$text" == "$UPDATE_LAST_EVENT" ]] && return

    UPDATE_LAST_EVENT="$text"
    UPDATE_HISTORY+=("$text")

    while ((${#UPDATE_HISTORY[@]} > max_lines)); do
        UPDATE_HISTORY=("${UPDATE_HISTORY[@]:1}")
    done
}

update_console_geometry() {
    # Use the exact same left/right padding as the normal right
    # information panel so update screens never shift horizontally.
    UPDATE_START_X="$RIGHT_CONTENT_X"
    UPDATE_CONTENT_WIDTH="$RIGHT_CONTENT_WIDTH"

    UPDATE_PROGRESS_Y=$CONTENT_BOTTOM
    UPDATE_DETAIL_Y=$((CONTENT_BOTTOM - 2))
    UPDATE_ITEM_Y=$((CONTENT_BOTTOM - 3))
    UPDATE_ACTION_Y=$((CONTENT_BOTTOM - 4))
    UPDATE_SEPARATOR_Y=$((CONTENT_BOTTOM - 5))

    UPDATE_HISTORY_TOP=7
    UPDATE_HISTORY_BOTTOM=$((UPDATE_SEPARATOR_Y - 1))
    UPDATE_HISTORY_ROWS=$((UPDATE_HISTORY_BOTTOM - UPDATE_HISTORY_TOP + 1))

    ((UPDATE_HISTORY_ROWS < 1)) && UPDATE_HISTORY_ROWS=1
}

draw_update_panel_static() {
    local label="$1"
    local detail="$2"

    update_console_geometry
    clear_right_panel

    tput cup 2 "$UPDATE_START_X"
    printf "${BOLD}${GREEN}Updates${RESET}"

    tput cup 4 "$UPDATE_START_X"
    printf "${BOLD}%.*s${RESET}" \
        "$UPDATE_CONTENT_WIDTH" \
        "$label"

    tput cup 5 "$UPDATE_START_X"
    repeat_char "$BOX_H" \
        "$((UPDATE_CONTENT_WIDTH < 60 ? UPDATE_CONTENT_WIDTH : 60))"

    # Keep the explanation short and fixed below the title.
    tput cup 6 "$UPDATE_START_X"
    printf "%-*.*s" \
        "$UPDATE_CONTENT_WIDTH" \
        "$UPDATE_CONTENT_WIDTH" \
        "$detail"

    tput cup "$UPDATE_SEPARATOR_Y" "$UPDATE_START_X"
    repeat_char "$BOX_H" "$UPDATE_CONTENT_WIDTH"
}

draw_update_history() {
    update_console_geometry

    local row=$UPDATE_HISTORY_TOP
    local i
    local line

    # Clear only the live-history area.
    for ((i=UPDATE_HISTORY_TOP; i<=UPDATE_HISTORY_BOTTOM; i++)); do
        tput cup "$i" "$UPDATE_START_X"
        printf "%-*s" "$UPDATE_CONTENT_WIDTH" ""
    done

    for line in "${UPDATE_HISTORY[@]}"; do
        ((row > UPDATE_HISTORY_BOTTOM)) && break

        tput cup "$row" "$UPDATE_START_X"
        printf "%-*.*s" \
            "$UPDATE_CONTENT_WIDTH" \
            "$UPDATE_CONTENT_WIDTH" \
            "$line"

        ((row++))
    done
}

draw_update_current() {
    update_console_geometry

    local action="Action: ${UPDATE_CURRENT_ACTION:-Working...}"
    local item="Item:   ${UPDATE_CURRENT_ITEM:-Waiting for package information...}"

    tput cup "$UPDATE_ACTION_Y" "$UPDATE_START_X"
    printf "%-*.*s" \
        "$UPDATE_CONTENT_WIDTH" \
        "$UPDATE_CONTENT_WIDTH" \
        "$action"

    tput cup "$UPDATE_ITEM_Y" "$UPDATE_START_X"
    printf "%-*.*s" \
        "$UPDATE_CONTENT_WIDTH" \
        "$UPDATE_CONTENT_WIDTH" \
        "$item"

    tput cup "$UPDATE_DETAIL_Y" "$UPDATE_START_X"
    printf "%-*.*s" \
        "$UPDATE_CONTENT_WIDTH" \
        "$UPDATE_CONTENT_WIDTH" \
        "Please do not close the program while this step is running."
}

draw_update_percent_bar() {
    local percent="$1"

    update_console_geometry

    percent="${percent//%/}"
    percent="${percent%%.*}"

    [[ "$percent" =~ ^[0-9]+$ ]] || percent=0

    ((percent < 0)) && percent=0
    ((percent > 100)) && percent=100

    # Reserve space for "Progress ", brackets and " 100%".
    local bar_width=$((UPDATE_CONTENT_WIDTH - 18))
    ((bar_width < 12)) && bar_width=12

    local filled=$((percent * bar_width / 100))
    local empty=$((bar_width - filled))
    local bar=""
    local blank=""

    printf -v bar '%*s' "$filled" ''
    bar="${bar// /#}"

    printf -v blank '%*s' "$empty" ''

    tput cup "$UPDATE_PROGRESS_Y" "$UPDATE_START_X"

    printf "%-*s" "$UPDATE_CONTENT_WIDTH" ""

    tput cup "$UPDATE_PROGRESS_Y" "$UPDATE_START_X"

    printf "Progress [${GREEN}%s${RESET}%s] %3d%%" \
        "$bar" \
        "$blank" \
        "$percent"
}

draw_update_activity_bar() {
    local position="$1"

    update_console_geometry

    local bar_width=$((UPDATE_CONTENT_WIDTH - 18))
    ((bar_width < 12)) && bar_width=12

    ((position < 1)) && position=1
    ((position > bar_width)) && position=bar_width

    local bar=""
    local blank=""

    printf -v bar '%*s' "$position" ''
    bar="${bar// /#}"

    printf -v blank '%*s' "$((bar_width - position))" ''

    tput cup "$UPDATE_PROGRESS_Y" "$UPDATE_START_X"
    printf "%-*s" "$UPDATE_CONTENT_WIDTH" ""

    tput cup "$UPDATE_PROGRESS_Y" "$UPDATE_START_X"
    printf "Working  [${GREEN}%s${RESET}%s]" "$bar" "$blank"
}

parse_apt_progress_line() {
    local line="$1"

    line="${line//$'\r'/}"

    local kind field percent description

    case "$line" in
        pmstatus:*|dlstatus:*|pmerror:*|pmconffile:*)
            IFS=':' read -r kind field percent description <<< "$line"

            percent="${percent//%/}"
            percent="${percent%%.*}"
            [[ "$percent" =~ ^[0-9]+$ ]] || percent=0

            UPDATE_PERCENT="$percent"

            case "$kind" in
                pmstatus)
                    UPDATE_CURRENT_ITEM="$field"
                    UPDATE_CURRENT_ACTION="${description:-Updating package}"
                    ;;
                dlstatus)
                    UPDATE_CURRENT_ACTION="${description:-Downloading packages}"
                    ;;
                pmerror)
                    UPDATE_CURRENT_ITEM="$field"
                    UPDATE_CURRENT_ACTION="Package manager error"
                    ;;
                pmconffile)
                    UPDATE_CURRENT_ITEM="$field"
                    UPDATE_CURRENT_ACTION="Configuration file requires attention"
                    ;;
            esac

            update_history_add \
                "${description:-$line}" \
                "$UPDATE_HISTORY_ROWS"
            ;;

        Get:*|Hit:*|Ign:*|Err:*|Fetched*|Reading\ package*|Building\ dependency*|Calculating\ upgrade*|Preparing\ to\ unpack*|Unpacking*|Setting\ up*|Processing\ triggers*)
            # Human APT output is useful because Get:/Hit: lines show
            # the repository/package that is currently being fetched.
            UPDATE_CURRENT_ITEM="$line"

            case "$line" in
                Get:*) UPDATE_CURRENT_ACTION="Downloading" ;;
                Hit:*) UPDATE_CURRENT_ACTION="Repository current" ;;
                Ign:*) UPDATE_CURRENT_ACTION="Repository item ignored" ;;
                Err:*) UPDATE_CURRENT_ACTION="Repository error" ;;
                Fetched*) UPDATE_CURRENT_ACTION="Download complete" ;;
                Reading\ package*) UPDATE_CURRENT_ACTION="Reading package lists" ;;
                Building\ dependency*) UPDATE_CURRENT_ACTION="Building dependency tree" ;;
                Calculating\ upgrade*) UPDATE_CURRENT_ACTION="Calculating upgrade" ;;
                Preparing\ to\ unpack*) UPDATE_CURRENT_ACTION="Preparing package" ;;
                Unpacking*) UPDATE_CURRENT_ACTION="Unpacking package" ;;
                Setting\ up*) UPDATE_CURRENT_ACTION="Configuring package" ;;
                Processing\ triggers*) UPDATE_CURRENT_ACTION="Processing triggers" ;;
            esac

            update_history_add \
                "$line" \
                "$UPDATE_HISTORY_ROWS"
            ;;
    esac
}

# ------------------------------------------------------------
# APT UPDATE/UPGRADE WITH REAL PROGRESS
# ------------------------------------------------------------
run_apt_ide_progress() {
    local label="$1"
    local detail="$2"

    shift 2

    local tempdir
    local pipe
    local logfile

    tempdir=$(mktemp -d)
    pipe="$tempdir/progress.pipe"
    logfile="$tempdir/apt-error.log"
    mkfifo "$pipe"

    update_history_clear
    UPDATE_CURRENT_ACTION="Starting APT..."
    UPDATE_CURRENT_ITEM="Waiting for package information..."
    UPDATE_PERCENT=0

    draw_update_panel_static "$label" "$detail"
    draw_update_current
    draw_update_percent_bar 0

    # Open the FIFO read/write so the Bash reader never blocks while
    # waiting for apt-get to open or close its end of the pipe.
    exec 8<>"$pipe"

    # APT::Status-Fd produces pmstatus/dlstatus records containing a
    # real total percentage plus a human-readable current action.
    # We use stdout (fd 1), which avoids sudo closing a custom fd > 2.
    log_append "APT command: apt-get $*"

    sudo -n apt-get \
        -o APT::Status-Fd=1 \
        -o Dpkg::Progress-Fancy=0 \
        -o Dpkg::Use-Pty=0 \
        "$@" \
        </dev/null \
        >"$pipe" \
        2>"$logfile" &

    local pid=$!
    local line=""

    while kill -0 "$pid" 2>/dev/null; do

        if IFS= read -r -t 0.10 line <&8; then
            log_append "$line"
            parse_apt_progress_line "$line"
            draw_update_history
            draw_update_current
            draw_update_percent_bar "$UPDATE_PERCENT"
        fi

    done

    # Drain any final lines written just before apt exited.
    while IFS= read -r -t 0.02 line <&8; do
        log_append "$line"
        parse_apt_progress_line "$line"
    done

    wait "$pid"
    local result=$?

    exec 8>&-

    draw_update_history
    draw_update_current

    if [[ -s "$logfile" ]]; then
        while IFS= read -r line; do
            log_append "stderr: $line"
        done < "$logfile"
    fi

    if ((result == 0)); then
        UPDATE_PERCENT=100
        draw_update_percent_bar 100
        LAST_UPDATE_ERROR=""
        log_append "APT command completed successfully."
    else
        LAST_UPDATE_ERROR=$(tail -8 "$logfile" | tr '\n' ' ' | sed 's/[[:space:]][[:space:]]*/ /g')

        if [[ -z "$LAST_UPDATE_ERROR" && ${#UPDATE_HISTORY[@]} -gt 0 ]]; then
            LAST_UPDATE_ERROR="${UPDATE_HISTORY[-1]}"
        fi
        log_append "APT command failed with exit code $result."
    fi

    rm -rf "$tempdir"

    return "$result"
}

# ------------------------------------------------------------
# GENERIC LIVE IDE PROGRESS
# ------------------------------------------------------------
# Used for fwupdmgr and ubuntu-drivers. These tools do not expose
# the same APT status stream directly to this script, so their
# current output is shown live while the bottom bar acts as an
# activity indicator.
run_ide_progress() {
    local label="$1"
    local detail="$2"

    shift 2

    local tempdir
    local pipe

    tempdir=$(mktemp -d)
    pipe="$tempdir/progress.pipe"
    mkfifo "$pipe"

    update_history_clear
    UPDATE_CURRENT_ACTION="Starting..."
    UPDATE_CURRENT_ITEM="Waiting for activity..."

    draw_update_panel_static "$label" "$detail"
    draw_update_current

    exec 8<>"$pipe"

    log_append "Command: $*"

    "$@" \
        </dev/null \
        >"$pipe" \
        2>&1 &

    local pid=$!
    local line=""
    local position=1
    local bar_width=$((UPDATE_CONTENT_WIDTH - 18))

    ((bar_width < 12)) && bar_width=12

    while kill -0 "$pid" 2>/dev/null; do

        if IFS= read -r -t 0.08 line <&8; then
            line="${line//$'\r'/}"

            if [[ -n "$line" ]]; then
                log_append "$line"
                UPDATE_CURRENT_ACTION="Working"
                UPDATE_CURRENT_ITEM="$line"
                update_history_add "$line" "$UPDATE_HISTORY_ROWS"
                draw_update_history
                draw_update_current
            fi
        fi

        draw_update_activity_bar "$position"

        ((position++))
        ((position > bar_width)) && position=1

    done

    while IFS= read -r -t 0.02 line <&8; do
        line="${line//$'\r'/}"
        [[ -z "$line" ]] && continue
        log_append "$line"
        UPDATE_CURRENT_ITEM="$line"
        update_history_add "$line" "$UPDATE_HISTORY_ROWS"
    done

    wait "$pid"
    local result=$?

    exec 8>&-

    draw_update_history
    draw_update_current

    if ((result == 0)); then
        draw_update_percent_bar 100
        LAST_UPDATE_ERROR=""
        log_append "Command completed successfully."
    else
        LAST_UPDATE_ERROR="${UPDATE_HISTORY[-1]:-The command did not complete successfully.}"
        log_append "Command failed with exit code $result."
    fi

    rm -rf "$tempdir"

    return "$result"
}

# ============================================================
# LOG VIEWER
# ============================================================

modal_clear_row() {
    local relative_row="$1"

    tput cup \
        $((MODAL_Y + relative_row)) \
        "$MODAL_CONTENT_X"

    printf "%-*s" "$MODAL_CONTENT_WIDTH" ""
}

load_log_lines() {
    local file="$1"

    # Sanitize the whole file once instead of launching `tr` for every
    # visible line on every keypress. LC_ALL=C removes only ASCII control
    # bytes while leaving UTF-8 text intact.
    mapfile -t LOG_VIEW_LINES < <(
        LC_ALL=C tr -d '\000-\010\013\014\016-\037\177' < "$file"
    )

    if ((${#LOG_VIEW_LINES[@]} == 0)); then
        LOG_VIEW_LINES=("Log file is empty.")
    fi
}

render_log_window() {
    local offset="$1"
    local visible="$2"
    local i row line

    # Redraw only the log-content rows. The frame, title and underlying IDE
    # stay untouched, which removes most of the lag while scrolling.
    for ((i=0; i<visible; i++)); do
        modal_clear_row $((3 + i))

        row=$((offset + i))
        ((row >= ${#LOG_VIEW_LINES[@]})) && continue

        line="${LOG_VIEW_LINES[$row]}"
        modal_text $((3 + i)) 0 "$line"
    done

    modal_clear_row $((MODAL_H - 2))
    modal_center_text $((MODAL_H - 2)) \
        "UP/DOWN Scroll    ENTER/ESC Close    Line $((offset + 1))/${#LOG_VIEW_LINES[@]}"
}

view_log_file() {
    local file="$1"
    [[ -f "$file" ]] || return 1

    load_log_lines "$file"

    local offset=0
    local visible max_offset

    # Repaint from cached data only. In particular, do not re-run the
    # Updates-page firmware/driver checks just to open a log.
    draw_ui_cached
    modal_draw "Log Viewer - $(basename "$file")" $((COLS - 4)) $((LINES - 4))

    visible=$((MODAL_H - 6))
    ((visible < 1)) && visible=1

    max_offset=$((${#LOG_VIEW_LINES[@]} - visible))
    ((max_offset < 0)) && max_offset=0

    render_log_window "$offset" "$visible"

    while true; do
        read_key

        case "$KEY" in
            $'\e[A'|$'\eOA')
                if ((offset > 0)); then
                    ((offset--))
                    render_log_window "$offset" "$visible"
                fi
                ;;
            $'\e[B'|$'\eOB')
                if ((offset < max_offset)); then
                    ((offset++))
                    render_log_window "$offset" "$visible"
                fi
                ;;
            ""|$'\n'|$'\r'|$'\e')
                return 0
                ;;
        esac
    done
}

render_log_browser_frame() {
    modal_draw "Saved Update / Install Logs" 78 16
    modal_text 3 0 "Select a log and press ENTER to view it."
    modal_center_text 14 "UP/DOWN Select    ENTER View    ESC Close"
}

render_log_browser_rows() {
    local top="$1"
    local selected="$2"
    local visible="$3"
    local i index label

    for ((i=0; i<visible; i++)); do
        modal_clear_row $((5 + i))

        index=$((top + i))
        ((index >= ${#LOG_BROWSER_FILES[@]})) && continue

        label="${LOG_BROWSER_LABELS[$index]}"

        if ((index == selected)); then
            modal_text $((5 + i)) 0 "> $label"
        else
            modal_text $((5 + i)) 0 "  $label"
        fi
    done
}

browse_logs() {
    LOG_BROWSER_FILES=()
    LOG_BROWSER_LABELS=()

    local selected=0
    local top=0
    local visible=8
    local file

    mapfile -t LOG_BROWSER_FILES < <(
        find "$LOG_DIR" -maxdepth 1 -type f -name '*.log' \
            -printf '%T@\t%p\n' 2>/dev/null | \
            sort -nr | cut -f2-
    )

    if ((${#LOG_BROWSER_FILES[@]} == 0)); then
        message_dialog \
            "Update Logs" \
            "No saved update or installation logs were found." \
            "$LOG_DIR"
        return
    fi

    # Cache labels once. basename used to run again on every redraw.
    for file in "${LOG_BROWSER_FILES[@]}"; do
        LOG_BROWSER_LABELS+=("$(basename "$file")")
    done

    # The existing IDE is already on screen when L is pressed. Draw only the
    # modal rather than refreshing the entire page behind it.
    render_log_browser_frame
    render_log_browser_rows "$top" "$selected" "$visible"

    while true; do
        read_key

        case "$KEY" in
            $'\e[A'|$'\eOA')
                if ((selected > 0)); then
                    ((selected--))
                    ((selected < top)) && top=$selected
                    render_log_browser_rows "$top" "$selected" "$visible"
                fi
                ;;
            $'\e[B'|$'\eOB')
                if ((selected < ${#LOG_BROWSER_FILES[@]} - 1)); then
                    ((selected++))
                    ((selected >= top + visible)) && top=$((selected - visible + 1))
                    render_log_browser_rows "$top" "$selected" "$visible"
                fi
                ;;
            ""|$'\n'|$'\r')
                view_log_file "${LOG_BROWSER_FILES[$selected]}"

                # Restore the browser from cached IDE data. This avoids slow
                # status probes after closing every log.
                draw_ui_cached
                render_log_browser_frame
                render_log_browser_rows "$top" "$selected" "$visible"
                ;;
            $'\e')
                draw_ui_cached
                return
                ;;
        esac
    done
}

# ============================================================
# PACKAGE / DRIVER ROLLBACK
# ============================================================

version_available() {
    local package="$1"
    local version="$2"

    apt-cache madison "$package" 2>/dev/null | \
        awk '{print $3}' | grep -Fxq -- "$version"
}

rollback_system_transaction() {
    local dir="$1"
    local changes="$dir/changes.tsv"
    local -a install_specs=()
    local -a unavailable=()
    local kind pkg oldver newver

    while IFS=$'\t' read -r kind pkg oldver newver; do
        [[ -n "$kind" && -n "$pkg" ]] || continue

        case "$kind" in
            CHANGED|REMOVED)
                if [[ "$oldver" != "-" ]] && version_available "$pkg" "$oldver"; then
                    install_specs+=("$pkg=$oldver")
                else
                    unavailable+=("$pkg=$oldver")
                fi
                ;;
            INSTALLED)
                # Newly introduced dependencies are deliberately left installed.
                # Blindly removing them can remove software that now depends on them.
                ;;
        esac
    done < "$changes"

    if ((${#install_specs[@]} == 0)); then
        local msg="No previous package versions are currently available."
        if ((${#unavailable[@]} > 0)); then
            msg="Previous versions for ${#unavailable[@]} package(s) are no longer available."
        fi
        message_dialog "Rollback Not Available" "$msg" "Nothing was changed."
        return 1
    fi

    # Ask APT to simulate the rollback first.  This catches broken
    # dependency plans before anything is changed on the computer.
    local simulation_log
    simulation_log=$(mktemp)

    if ! apt-get -s install --allow-downgrades "${install_specs[@]}"         >"$simulation_log" 2>&1; then
        LAST_UPDATE_ERROR=$(tail -8 "$simulation_log" | tr '\n' ' ')
        rm -f "$simulation_log"
        message_dialog             "Rollback Simulation Failed"             "APT could not build a safe rollback dependency plan."             "No packages were changed."
        return 1
    fi

    rm -f "$simulation_log"

    if ! request_sudo_dialog; then
        return 1
    fi

    begin_operation_log "rollback-system"
    log_append "Rollback source transaction: $(basename "$dir")"
    log_append "Packages scheduled for previous versions: ${#install_specs[@]}"
    log_append "Unavailable previous versions: ${#unavailable[@]}"

    if ! run_apt_ide_progress \
        "Rolling back package versions..." \
        "Reinstalling previous package versions that are still available." \
        install --allow-downgrades -y "${install_specs[@]}"; then
        end_operation_log "failed"
        show_update_error
        return 1
    fi

    end_operation_log "success"
    printf '%s\n' "$(date '+%Y-%m-%d %H:%M:%S %Z')" > "$dir/rollback-performed"

    STATUS_MESSAGE="Rollback completed - reboot may be required"
    draw_ui
    maybe_offer_reboot
    return 0
}

rollback_driver_transaction() {
    local dir="$1"
    local meta="$dir/meta"
    local packages
    local -a remove_packages=()
    local pkg

    packages=$(meta_value "$meta" driver_packages)

    for pkg in $packages; do
        if dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | \
            grep -q 'install ok installed'; then
            remove_packages+=("$pkg")
        fi
    done

    if ((${#remove_packages[@]} == 0)); then
        message_dialog \
            "Driver Rollback" \
            "The driver packages from this transaction are no longer installed." \
            "Nothing was changed."
        return 1
    fi

    local simulation_log
    simulation_log=$(mktemp)

    if ! apt-get -s remove "${remove_packages[@]}"         >"$simulation_log" 2>&1; then
        rm -f "$simulation_log"
        message_dialog             "Driver Rollback Simulation Failed"             "APT could not build a safe driver-removal plan."             "No packages were changed."
        return 1
    fi

    rm -f "$simulation_log"

    if ! request_sudo_dialog; then
        return 1
    fi

    begin_operation_log "rollback-driver"
    log_append "Rollback source transaction: $(basename "$dir")"
    log_append "Removing driver packages: ${remove_packages[*]}"

    if ! run_apt_ide_progress \
        "Removing installed driver packages..." \
        "Removing the driver packages installed by the selected transaction." \
        remove -y "${remove_packages[@]}"; then
        end_operation_log "failed"
        show_update_error
        return 1
    fi

    end_operation_log "success"
    printf '%s\n' "$(date '+%Y-%m-%d %H:%M:%S %Z')" > "$dir/rollback-performed"

    STATUS_MESSAGE="Driver rollback completed"
    draw_ui
    maybe_offer_reboot
    return 0
}

rollback_transaction() {
    local dir="$1"
    local meta="$dir/meta"
    local type started changes_count

    type=$(meta_value "$meta" type)
    started=$(meta_value "$meta" started)
    changes_count=$(wc -l < "$dir/changes.tsv" 2>/dev/null || echo 0)

    if [[ -f "$dir/rollback-performed" ]]; then
        message_dialog \
            "Rollback" \
            "This transaction has already been rolled back once." \
            "No additional rollback was started."
        return
    fi

    if ! confirm_dialog \
        "Rollback Transaction" \
        "Rollback $type from $started?" \
        "$changes_count package change(s) were recorded. This is best effort." \
        "Rollback" \
        "Cancel"; then
        return
    fi

    case "$type" in
        system-update)
            rollback_system_transaction "$dir"
            ;;
        driver-install)
            rollback_driver_transaction "$dir"
            ;;
        *)
            message_dialog \
                "Rollback Unsupported" \
                "Automatic rollback is not supported for this transaction type." \
                "Firmware downgrade is intentionally not automated."
            ;;
    esac
}

browse_rollbacks() {
    local -a dirs=()
    local selected=0
    local top=0
    local visible=7
    local dir meta type started status rollback count label
    local i index

    while IFS= read -r dir; do
        [[ -n "$dir" ]] || continue
        meta="$dir/meta"
        [[ -f "$meta" ]] || continue

        status=$(meta_value "$meta" final_status)
        rollback=$(meta_value "$meta" final_rollback_supported)

        if [[ ("$status" == "success" || "$status" == "failed") &&
              "$rollback" == "yes" && -s "$dir/changes.tsv" ]]; then
            dirs+=("$dir")
        fi
    done < <(
        find "$TXN_DIR" -mindepth 1 -maxdepth 1 -type d \
            -printf '%T@\t%p\n' 2>/dev/null | \
            sort -nr | cut -f2-
    )

    if ((${#dirs[@]} == 0)); then
        message_dialog \
            "Rollback" \
            "No rollback-capable update or driver transactions were found." \
            "Firmware transactions are log-only."
        return
    fi

    while true; do
        ((selected < top)) && top=$selected
        ((selected >= top + visible)) && top=$((selected - visible + 1))

        draw_ui
        modal_draw "Rollback Transactions" 82 16
        modal_text 3 0 "Select a saved package transaction."

        for ((i=0; i<visible; i++)); do
            index=$((top + i))
            ((index >= ${#dirs[@]})) && break

            dir="${dirs[$index]}"
            meta="$dir/meta"
            type=$(meta_value "$meta" type)
            started=$(meta_value "$meta" started)
            count=$(wc -l < "$dir/changes.tsv" 2>/dev/null || echo 0)

            label="$type | $started | $count change(s)"

            if [[ -f "$dir/rollback-performed" ]]; then
                label="$label | already rolled back"
            fi

            if ((index == selected)); then
                modal_text $((5 + i)) 0 "> $label"
            else
                modal_text $((5 + i)) 0 "  $label"
            fi
        done

        modal_center_text 14 "UP/DOWN Select    ENTER Rollback    ESC Close"

        read_key

        case "$KEY" in
            $'\e[A'|$'\eOA')
                ((selected > 0)) && ((selected--))
                ;;
            $'\e[B'|$'\eOB')
                ((selected < ${#dirs[@]} - 1)) && ((selected++))
                ;;
            ""|$'\n'|$'\r')
                rollback_transaction "${dirs[$selected]}"
                ;;
            $'\e')
                draw_ui
                return
                ;;
        esac
    done
}

show_update_error() {
    local detail="${LAST_UPDATE_ERROR:-No additional details were returned.}"
    draw_ui
    modal_draw "Update Error" 72 11
    modal_center_text 3 "The update process did not complete successfully."
    modal_center_text 5 "$(trim_text "$detail" 60)"
    modal_center_text 8 "Press ENTER to continue"

    while true; do
        read_key
        case "$KEY" in
            ""|$'\n'|$'\r'|$'\e') break ;;
        esac
    done

    STATUS_MESSAGE="Update failed"
    draw_ui
}

# ------------------------------------------------------------
# REBOOT HANDLING
# ------------------------------------------------------------
reboot_required() {
    [[ -f /var/run/reboot-required ]] && return 0
    ((FORCE_REBOOT_REQUIRED == 1)) && return 0

    return 1
}

maybe_offer_reboot() {
    reboot_required || { draw_ui; return; }

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
        modal_draw "Restarting Computer" 54 8
        modal_center_text 3 "The computer is restarting..."
        modal_center_text 5 "Please wait."
        sleep 1

        if ! sudo -n systemctl reboot; then
            STATUS_MESSAGE="Restart failed"
            message_dialog "Restart Failed" "The restart command could not be completed." "Restart the computer manually when ready."
        fi
    else
        STATUS_MESSAGE="Reboot required - restart later"
        draw_ui
    fi
}

# ------------------------------------------------------------
# UPDATE ACTIONS
# ------------------------------------------------------------
check_for_updates() {
    if ! request_sudo_dialog; then
        return
    fi

    begin_operation_log "check-updates"
    log_append "Beginning update check."

    STATUS_MESSAGE="Checking Ubuntu package repositories..."
    draw_status

    if ! run_apt_ide_progress \
        "Checking Ubuntu package repositories..." \
        "Refreshing the list of available packages." \
        update; then
        end_operation_log "failed"
        show_update_error
        return
    fi

    if command -v fwupdmgr >/dev/null 2>&1; then
        STATUS_MESSAGE="Refreshing firmware metadata..."
        draw_status

        run_ide_progress \
            "Checking firmware metadata..." \
            "Refreshing firmware information from configured remotes." \
            fwupdmgr --assume-yes refresh || true
    fi

    log_append "Available package updates: $(get_package_update_count)"
    log_append "Security updates: $(get_security_update_count)"
    log_append "Firmware status: $(get_firmware_status)"
    log_append "Driver status: $(get_driver_status)"
    end_operation_log "success"

    STATUS_MESSAGE="Update check complete - log saved"
    draw_ui
}

update_system_packages() {
    if ! confirm_dialog \
        "Ubuntu System Update" \
        "Install all currently available Ubuntu package updates?" \
        "A transaction snapshot and full log will be saved first." \
        "Install Updates" \
        "Cancel"; then
        STATUS_MESSAGE="System update cancelled"
        draw_status
        return
    fi

    if ! request_sudo_dialog; then
        return
    fi

    begin_operation_log "system-update"
    begin_transaction "system-update"
    log_append "Captured pre-update package snapshot."

    STATUS_MESSAGE="Refreshing package information..."
    draw_status

    if ! run_apt_ide_progress \
        "Checking Ubuntu package repositories..." \
        "Refreshing the package list before installation." \
        update; then
        finish_transaction "failed" "no"
        end_operation_log "failed"
        show_update_error
        return
    fi

    STATUS_MESSAGE="Installing Ubuntu updates..."
    draw_status

    if ! run_apt_ide_progress \
        "Installing Ubuntu package updates..." \
        "Downloading, unpacking and configuring available updates." \
        upgrade -y; then
        finish_transaction "failed" "yes"
        end_operation_log "failed"
        show_update_error
        return
    fi

    finish_transaction "success" "yes"
    log_append "Package changes recorded: $(wc -l < "$CURRENT_TXN_DIR/changes.tsv" 2>/dev/null || echo 0)"
    end_operation_log "success"

    STATUS_MESSAGE="Ubuntu update complete - log and rollback snapshot saved"
    draw_ui
    maybe_offer_reboot
}

update_hardware_drivers() {
    if ! command -v ubuntu-drivers >/dev/null 2>&1; then
        message_dialog "Hardware Drivers" "ubuntu-drivers is not available." "Install ubuntu-drivers-common to enable this feature."
        return
    fi

    local drivers
    drivers=$(ubuntu-drivers list 2>/dev/null)

    if [[ -z "$drivers" ]]; then
        STATUS_MESSAGE="No additional drivers recommended"
        message_dialog "Hardware Drivers" "No additional recommended drivers were detected." "Your current driver setup can be left as-is."
        return
    fi

    if ! confirm_dialog \
        "Hardware Driver Update" \
        "Ubuntu found additional supported hardware driver packages." \
        "A log and rollback transaction will be saved before installation." \
        "Install Driver" \
        "Cancel"; then
        STATUS_MESSAGE="Driver installation cancelled"
        draw_status
        return
    fi

    if ! request_sudo_dialog; then
        return
    fi

    begin_operation_log "driver-install"
    begin_transaction "driver-install"
    transaction_meta_append "driver_packages" "$(echo "$drivers" | tr '\n' ' ')"
    log_append "Ubuntu driver candidates: $(echo "$drivers" | tr '\n' ' ')"

    STATUS_MESSAGE="Installing recommended hardware driver..."
    draw_status

    if ! run_ide_progress \
        "Installing recommended hardware driver..." \
        "Ubuntu is selecting and installing the best supported driver." \
        sudo -n ubuntu-drivers install; then
        finish_transaction "failed" "yes"
        end_operation_log "failed"
        show_update_error
        return
    fi

    finish_transaction "success" "yes"
    log_append "Package changes recorded: $(wc -l < "$CURRENT_TXN_DIR/changes.tsv" 2>/dev/null || echo 0)"
    end_operation_log "success"

    STATUS_MESSAGE="Driver installation complete - rollback snapshot saved"
    draw_ui
    maybe_offer_reboot
}

update_firmware() {
    if ! command -v fwupdmgr >/dev/null 2>&1; then
        message_dialog "Firmware Updates" "fwupdmgr is not available." "Install the fwupd package to enable firmware updates."
        return
    fi

    local firmware_output firmware_rc
    firmware_output=$(fwupdmgr get-updates </dev/null 2>&1)
    firmware_rc=$?

    if ((firmware_rc == 2)) || echo "$firmware_output" | grep -qiE 'No updates available|No updatable devices|No upgrades'; then
        STATUS_MESSAGE="Firmware is already up to date"
        message_dialog "Firmware Updates" "No supported firmware updates are currently available." "Your detected firmware is up to date."
        return
    fi

    if ((firmware_rc != 0)); then
        LAST_UPDATE_ERROR=$(echo "$firmware_output" | tail -6 | tr '\n' ' ')
        show_update_error
        return
    fi

    if ! confirm_dialog \
        "Firmware Update" \
        "Supported firmware updates are available for this computer." \
        "Firmware is logged, but automatic firmware rollback is disabled." \
        "Install Firmware" \
        "Cancel"; then
        STATUS_MESSAGE="Firmware update cancelled"
        draw_status
        return
    fi

    if ! request_sudo_dialog; then
        return
    fi

    begin_operation_log "firmware-update"
    begin_transaction "firmware-update"
    transaction_meta_append "firmware_rollback" "manual-only"
    log_append "Firmware update started. Automatic firmware rollback is intentionally disabled."
    log_append "Available firmware information: $(echo "$firmware_output" | tr '\n' ' ' | tr -s ' ')"

    STATUS_MESSAGE="Installing firmware updates..."
    draw_status

    if ! run_ide_progress \
        "Installing firmware updates..." \
        "Firmware is being downloaded and prepared for supported devices." \
        sudo -n fwupdmgr --assume-yes --no-reboot-check update; then

        if [[ "$LAST_UPDATE_ERROR" == *"No upgrades"* ]] ||
           [[ "$LAST_UPDATE_ERROR" == *"No updates"* ]] ||
           [[ "$LAST_UPDATE_ERROR" == *"No releases"* ]]; then
            finish_transaction "success" "no"
            end_operation_log "success-no-change"
            STATUS_MESSAGE="Firmware already up to date"
            message_dialog "Firmware Updates" "No firmware update needed to be installed." "The detected devices are already current."
            return
        fi

        finish_transaction "failed" "no"
        end_operation_log "failed"
        show_update_error
        return
    fi

    finish_transaction "success" "no"
    end_operation_log "success"

    FORCE_REBOOT_REQUIRED=1
    STATUS_MESSAGE="Firmware update complete - log saved"
    draw_ui
    maybe_offer_reboot
}

# ------------------------------------------------------------
# RESIZE + KEYBOARD
# ------------------------------------------------------------
handle_resize() {
    if ((UI_BUSY == 1)); then
        PENDING_RESIZE=1
        return
    fi

    draw_ui
}

trap handle_resize WINCH

read_key() {
    local first="" second="" third=""
    KEY=""

    IFS= read -r -n1 first

    if [[ "$first" != $'\e' ]]; then
        KEY="$first"
        return
    fi

    IFS= read -r -n1 -t 0.20 second || true

    if [[ "$second" == "[" || "$second" == "O" ]]; then
        IFS= read -r -n1 -t 0.20 third || true
        KEY="${first}${second}${third}"
    else
        KEY="${first}${second}"
    fi
}

# ------------------------------------------------------------
# START
# ------------------------------------------------------------
draw_ui

while true; do
    read_key

    case "$KEY" in
        $'\e[A'|$'\eOA')
            ((SELECTED--))
            if ((SELECTED < 0)); then
                SELECTED=$((${#MENU_ITEMS[@]} - 1))
            fi
            STATUS_MESSAGE="Viewing ${MENU_ITEMS[$SELECTED]}"
            draw_menu
            draw_information
            draw_status
            draw_shortcuts
            ;;

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

        ""|$'\n'|$'\r')
            refresh_current_page
            ;;

        r|R)
            refresh_current_page
            ;;

        c|C)
            if [[ "${MENU_ITEMS[$SELECTED]}" == "Updates" ]]; then
                STATUS_MESSAGE="Checking for updates..."
                draw_status
                check_for_updates
            fi
            ;;

        u|U)
            if [[ "${MENU_ITEMS[$SELECTED]}" == "Updates" ]]; then
                update_system_packages
            fi
            ;;

        f|F)
            if [[ "${MENU_ITEMS[$SELECTED]}" == "Updates" ]]; then
                update_firmware
            fi
            ;;

        d|D)
            if [[ "${MENU_ITEMS[$SELECTED]}" == "Updates" ]]; then
                update_hardware_drivers
            fi
            ;;

        l|L)
            if [[ "${MENU_ITEMS[$SELECTED]}" == "Updates" ||
                  "${MENU_ITEMS[$SELECTED]}" == "Logs / Rollback" ]]; then
                browse_logs
            fi
            ;;

        b|B)
            if [[ "${MENU_ITEMS[$SELECTED]}" == "Updates" ||
                  "${MENU_ITEMS[$SELECTED]}" == "Logs / Rollback" ]]; then
                browse_rollbacks
            fi
            ;;

        q|Q)
            STATUS_MESSAGE="Exiting..."
            draw_status
            sleep 0.1
            break
            ;;
    esac
done
