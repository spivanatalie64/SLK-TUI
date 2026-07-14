#!/usr/bin/env bash
# slk-tui.sh — SLK Interactive Kernel Configurator
# A friendly TUI for modifying Linux kernel configs.
#
# Usage: slk-tui.sh [path-to-config]
#   If no config path is given, looks for .config in current dir.
set -euo pipefail

CONFIG_FILE="${1:-.config}"
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
LIBDIR="${SCRIPT_DIR}/lib"
SHAREDIR="${SCRIPT_DIR}/share"

# ── Detect TUI backend ────────────────────────────────────────────────────
if command -v whiptail &>/dev/null; then
    TUI="whiptail"
elif command -v dialog &>/dev/null; then
    TUI="dialog"
else
    echo "SLK-TUI requires 'whiptail' or 'dialog'. Install one:"
    echo "  sudo pacman -S libnewt    (for whiptail)"
    echo "  sudo pacman -S dialog     (for dialog)"
    exit 1
fi

# ── Colors (for raw output) ───────────────────────────────────────────────
R=$(tput setaf 1 2>/dev/null || echo "")
G=$(tput setaf 2 2>/dev/null || echo "")
Y=$(tput setaf 3 2>/dev/null || echo "")
B=$(tput setaf 4 2>/dev/null || echo "")
N=$(tput sgr0 2>/dev/null || echo "")

# ── Helpers ───────────────────────────────────────────────────────────────
msgbox()   { $TUI --title "$1" --msgbox "$2" 20 60; }
yesno()    { $TUI --title "$1" --yesno "$2" 12 60; }
inputbox() { $TUI --title "$1" --inputbox "$2" 10 60 "$3" 3>&1 1>&2 2>&3; }
menu()     { $TUI --title "$1" --menu "$2" 22 76 12 "$@"; }
checklist(){ $TUI --title "$1" --checklist "$2" 22 76 10 "$@"; }

# ── Load config ───────────────────────────────────────────────────────────
load_config() {
    if [ ! -f "$CONFIG_FILE" ]; then
        msgbox "Config Not Found" "No config found at:\n\n  $CONFIG_FILE\n\nPlace a kernel .config file or specify one:\n  slk-tui.sh /path/to/config"
        exit 1
    fi
    # Parse config into associative arrays
    declare -gA CONFIG_VALS CONFIG_DESCS
    while IFS='=' read -r key val; do
        [[ "$key" =~ ^# ]] && continue
        [[ -z "$key" ]] && continue
        CONFIG_VALS["$key"]="$val"
    done < "$CONFIG_FILE"
}

save_config() {
    local tmpf=$(mktemp)
    for key in "${!CONFIG_VALS[@]}"; do
        if grep -q "^${key}=" "$CONFIG_FILE"; then
            sed -i "s/^${key}=.*/${key}=${CONFIG_VALS[$key]}/" "$CONFIG_FILE"
        elif grep -q "^# ${key} is not set" "$CONFIG_FILE"; then
            sed -i "s/^# ${key} is not set/${key}=${CONFIG_VALS[$key]}/" "$CONFIG_FILE"
        else
            echo "${key}=${CONFIG_VALS[$key]}" >> "$CONFIG_FILE"
        fi
    done
    msgbox "Saved" "Config saved to $CONFIG_FILE\n\nRun olddefconfig to resolve dependencies:\n  make olddefconfig"
}

check_config() {
    local k="$1"
    local v="${CONFIG_VALS[$k]:-}"
    if [ "$v" = "y" ]; then
        echo "ON"
    elif [ "$v" = "m" ]; then
        echo "MOD"
    elif [ "$v" = "n" ] || [ -z "$v" ]; then
        echo "OFF"
    else
        echo "$v"
    fi
}

toggle_config() {
    local k="$1"
    local cur="${CONFIG_VALS[$k]:-}"
    case "$cur" in
        y)  CONFIG_VALS["$k"]="n" ;;
        m)  CONFIG_VALS["$k"]="y" ;;
        n)  CONFIG_VALS["$k"]="m" ;;
        "") CONFIG_VALS["$k"]="y" ;;
        *)  CONFIG_VALS["$k"]="y" ;;
    esac
}

set_config() {
    local k="$1" v="$2"
    CONFIG_VALS["$k"]="$v"
}

# ── Category definitions ──────────────────────────────────────────────────
declare -A CATEGORIES
CATEGORIES["CPU / Microarchitecture"]="MCORE2 GENERIC_CPU NR_CPUS NUMA SCHED_MC SCHED_SMT SCHED_MC_PRIO"
CATEGORIES["Preemption / Timer"]="PREEMPT PREEMPT_VOLUNTARY PREEMPT_RT HZ_1000 HZ_250 HZ_300 NO_HZ_FULL NO_HZ_IDLE HZ_PERIODIC"
CATEGORIES["Power Management"]="CPU_FREQ CPU_FREQ_DEFAULT_GOV_SCHEDUTIL CPU_FREQ_DEFAULT_GOV_PERFORMANCE X86_INTEL_PSTATE INTEL_IDLE ACPI_PROCESSOR ACPI_PROCESSOR_IDLE"
CATEGORIES["Graphics"]="DRM DRM_RADEON DRM_AMDGPU DRM_I915 FB_RADEON AGP_INTEL FRAMEBUFFER_CONSOLE"
CATEGORIES["HP ProLiant"]="HP_ILO HP_WDT HP_SDC"
CATEGORIES["Storage"]="SCSI_HPSA SATA_AHCI BLK_DEV_NVME DM_SNAPSHOT DM_CRYPT DM_THIN_PROVISIONING MD_RAID456"
CATEGORIES["Network"]="TIGON3 TCP_CONG_BBR IPV6 BRIDGE VLAN_8021Q NETFILTER IP_NF_FILTER IP_NF_NAT WLAN BT NFC"
CATEGORIES["Filesystems"]="EXT4_FS BTRFS_FS XFS_FS F2FS_FS HUGETLBFS"
CATEGORIES["Memory / Swap"]="TRANSPARENT_HUGEPAGE ZSWAP ZSMALLOC ZRAM"
CATEGORIES["Security"]="SECURITY SECURITY_YAMA SECURITY_APPARMOR SECURITY_SELINUX LSM"
CATEGORIES["Build / Debug"]="DEBUG_INFO DEBUG_KERNEL STACK_VALIDATION CC_OPTIMIZE_FOR_PERFORMANCE LOCALVERSION"

# ── Descriptions ──────────────────────────────────────────────────────────
declare -A DESCS
DESCS["CPU / Microarchitecture"]="CPU type, number of cores, NUMA, scheduling topology"
DESCS["Preemption / Timer"]="Latency model, timer frequency, adaptive tick"
DESCS["Power Management"]="CPU frequency scaling, idle states, ACPI processor"
DESCS["Graphics"]="Display drivers, GPU acceleration, framebuffer"
DESCS["HP ProLiant"]="Integrated Lights-Out, watchdog, system display"
DESCS["Storage"]="Host bus adapters, SATA, NVMe, device mapper, RAID"
DESCS["Network"]="NIC drivers, TCP congestion, firewall, VLAN"
DESCS["Filesystems"]="On-disk filesystem support (ext4, btrfs, xfs, etc.)"
DESCS["Memory / Swap"]="Huge pages, compressed swap, zram, zswap"
DESCS["Security"]="LSM framework, Yama, AppArmor, SELinux"
DESCS["Build / Debug"]="Debug symbols, optimization flags, local version string"

# ── Category full descriptions ────────────────────────────────────────────
declare -A OPT_DESCS
OPT_DESCS["MCORE2"]="Optimize for Intel Core 2 / Westmere / older Intel"
OPT_DESCS["GENERIC_CPU"]="Generic x86-64 (use with MCORE2=n for specific tuning)"
OPT_DESCS["NR_CPUS"]="Maximum number of CPUs (set to your thread count + headroom)"
OPT_DESCS["NUMA"]="Non-Uniform Memory Access (enable for multi-socket systems)"
OPT_DESCS["SCHED_MC"]="Multi-core scheduler balancing"
OPT_DESCS["SCHED_SMT"]="Simultaneous Multi-Threading scheduler (Hyper-Threading)"
OPT_DESCS["SCHED_MC_PRIO"]="Prioritize scheduling on same core before same socket"
OPT_DESCS["PREEMPT"]="Full preemption (lowest latency, highest overhead)"
OPT_DESCS["PREEMPT_VOLUNTARY"]="Voluntary preemption (balanced for desktop/server)"
OPT_DESCS["PREEMPT_RT"]="Real-time preemption (for audio/industrial use)"
OPT_DESCS["HZ_1000"]="1000 Hz timer (smooth mouse, more overhead)"
OPT_DESCS["HZ_250"]="250 Hz timer (balanced)"
OPT_DESCS["HZ_300"]="300 Hz timer (balanced, some distros)"
OPT_DESCS["NO_HZ_FULL"]="Full adaptive tick (no timer interrupts on idle CPUs)"
OPT_DESCS["NO_HZ_IDLE"]="Adaptive tick only when idle"
OPT_DESCS["HZ_PERIODIC"]="Periodic timer ticks (always-on, predictable)"
OPT_DESCS["CPU_FREQ"]="CPU frequency scaling subsystem"
OPT_DESCS["CPU_FREQ_DEFAULT_GOV_SCHEDUTIL"]="Default governor: schedutil (modern, scheduler-driven)"
OPT_DESCS["CPU_FREQ_DEFAULT_GOV_PERFORMANCE"]="Default governor: performance (max freq always)"
OPT_DESCS["X86_INTEL_PSTATE"]="Intel P-state driver (Sandy Bridge and newer)"
OPT_DESCS["INTEL_IDLE"]="Intel idle driver (native C-state control)"
OPT_DESCS["ACPI_PROCESSOR"]="ACPI processor support"
OPT_DESCS["ACPI_PROCESSOR_IDLE"]="ACPI processor idle states"
OPT_DESCS["DRM"]="Direct Rendering Manager (graphics subsystem)"
OPT_DESCS["DRM_RADEON"]="Radeon DRM driver (R100-R700, ES1000, older GPUs)"
OPT_DESCS["DRM_AMDGPU"]="AMDGPU DRM driver (GCN and newer AMD GPUs)"
OPT_DESCS["DRM_I915"]="Intel integrated graphics (i810 through current)"
OPT_DESCS["FB_RADEON"]="Radeon framebuffer (fallback when KMS unavailable)"
OPT_DESCS["AGP_INTEL"]="Intel AGP support (needed for ES1000 on 5520 chipset)"
OPT_DESCS["FRAMEBUFFER_CONSOLE"]="Text console on framebuffer"
OPT_DESCS["HP_ILO"]="HP Integrated Lights-Out management processor"
OPT_DESCS["HP_WDT"]="HP watchdog timer (for iLO system reset)"
OPT_DESCS["HP_SDC"]="HP System Display Controller (front panel)"
OPT_DESCS["SCSI_HPSA"]="HP Smart Array SCSI driver (P410i/P420i/P430i)"
OPT_DESCS["SATA_AHCI"]="AHCI SATA support"
OPT_DESCS["BLK_DEV_NVME"]="NVMe SSD support"
OPT_DESCS["DM_SNAPSHOT"]="LVM snapshot target"
OPT_DESCS["DM_CRYPT"]="LVM encryption target (dm-crypt)"
OPT_DESCS["DM_THIN_PROVISIONING"]="LVM thin provisioning"
OPT_DESCS["MD_RAID456"]="MD RAID 4/5/6 levels"
OPT_DESCS["TIGON3"]="Broadcom Tigon3 gigabit Ethernet (HP NC382i)"
OPT_DESCS["TCP_CONG_BBR"]="BBR congestion control (best for high-latency links)"
OPT_DESCS["IPV6"]="IPv6 protocol support"
OPT_DESCS["BRIDGE"]="Ethernet bridging (for VMs/containers)"
OPT_DESCS["VLAN_8021Q"]="VLAN tagging"
OPT_DESCS["NETFILTER"]="Network packet filtering framework"
OPT_DESCS["IP_NF_FILTER"]="iptables filter table"
OPT_DESCS["IP_NF_NAT"]="iptables NAT"
OPT_DESCS["WLAN"]="Wireless LAN (WiFi) support"
OPT_DESCS["BT"]="Bluetooth support"
OPT_DESCS["NFC"]="Near Field Communication"
OPT_DESCS["EXT4_FS"]="ext4 journaling filesystem"
OPT_DESCS["BTRFS_FS"]="Btrfs copy-on-write filesystem"
OPT_DESCS["XFS_FS"]="XFS journaling filesystem"
OPT_DESCS["F2FS_FS"]="F2FS flash-friendly filesystem"
OPT_DESCS["HUGETLBFS"]="HugeTLB filesystem (large page support)"
OPT_DESCS["TRANSPARENT_HUGEPAGE"]="Transparent Hugepages"
OPT_DESCS["ZSWAP"]="Compressed swap cache"
OPT_DESCS["ZSMALLOC"]="Slab allocator for zswap/zram"
OPT_DESCS["ZRAM"]="Compressed RAM block device (swap on RAM)"
OPT_DESCS["SECURITY"]="Linux Security Module framework"
OPT_DESCS["SECURITY_YAMA"]="Yama LSM (ptrace restrictions)"
OPT_DESCS["SECURITY_APPARMOR"]="AppArmor mandatory access control"
OPT_DESCS["SECURITY_SELINUX"]="SELinux mandatory access control"
OPT_DESCS["LSM"]="LSM ordering (comma-separated list)"
OPT_DESCS["DEBUG_INFO"]="Kernel debug symbols (DO NOT ENABLE FOR PRODUCTION)"
OPT_DESCS["DEBUG_KERNEL"]="Kernel debugging (DO NOT ENABLE FOR PRODUCTION)"
OPT_DESCS["STACK_VALIDATION"]="Stack validation at build time (slows build)"
OPT_DESCS["CC_OPTIMIZE_FOR_PERFORMANCE"]="Optimize for performance (-O2)"
OPT_DESCS["LOCALVERSION"]="Local version string (appended to uname -r)"

# ── Render config value for display ──────────────────────────────────────
val_display() {
    local v="${CONFIG_VALS[$1]:-}"
    case "$v" in
        y)  echo "${G}ON ${N}" ;;
        m)  echo "${Y}MOD${N}" ;;
        n|"") echo "${R}OFF${N}" ;;
        *)  echo "${B}${v}${N}" ;;
    esac
}

val_for_tui() {
    local v="${CONFIG_VALS[$1]:-}"
    case "$v" in
        y)  echo "ON " ;;
        m)  echo "MOD" ;;
        n|"") echo "OFF" ;;
        *)  echo "=$v" ;;
    esac
}

# ── Show hardware info ────────────────────────────────────────────────────
show_hardware() {
    local info=""
    info+="CPU:        $(grep 'model name' /proc/cpuinfo | head -1 | cut -d: -f2 | xargs)\n"
    info+="Cores:      $(nproc) logical\n"
    info+="RAM:        $(free -h | grep Mem | awk '{print $2}')\n"
    info+="GPU:        $(lspci 2>/dev/null | grep -i 'vga\|display\|3d' | head -1 | cut -d: -f3- | xargs || echo 'Unknown')\n"
    info+="Storage:    $(lsblk -d 2>/dev/null | grep -v NAME | awk '{print $1, $4}' | head -3 | tr '\n' ' ')\n"
    info+="Network:    $(ip link 2>/dev/null | grep -v lo | grep 'state UP' | awk -F': ' '{print $2}' | tr '\n' ' ' || echo 'N/A')\n"
    info+="\nConfig:     $CONFIG_FILE"
    msgbox "System Hardware" "$info"
}

# ── Apply a hardware profile ──────────────────────────────────────────────
apply_profile() {
    local profile="$1"
    local profile_file="${SHAREDIR}/profiles/${profile}.txt"
    if [ ! -f "$profile_file" ]; then
        msgbox "Profile Not Found" "Profile not found: $profile"
        return
    fi
    while read -r line; do
        [[ "$line" =~ ^# ]] && continue
        [[ -z "$line" ]] && continue
        if [[ "$line" =~ "=" ]]; then
            local key="${line%%=*}"
            local val="${line#*=}"
            set_config "$key" "$val"
        elif [[ "$line" =~ ^- ]]; then
            local key="${line#-}"
            set_config "$key" "n"
        fi
    done < "$profile_file"
    msgbox "Profile Applied" "Hardware profile loaded:\n\n  $profile\n\nReview and save changes."
}

# ── Hardware profile selector ─────────────────────────────────────────────
hardware_profiles_menu() {
    local items=()
    items+=("server-hp-dl380-g7" "HP ProLiant DL380 G7 (Xeon E5649, ES1000)")
    items+=("server-dell-poweredge-r730" "Dell PowerEdge R730 (E5-26xx, iDRAC)")
    items+=("server-generic" "Generic Server (minimal, no GPU)")
    items+=("laptop-generic" "Generic Laptop (ACPI, battery, WiFi)")
    items+=("desktop-generic" "Generic Desktop (GPU, audio, USB)")
    items+=("raspberry-pi-4" "Raspberry Pi 4 (BCM2711)")
    items+=("raspberry-pi-5" "Raspberry Pi 5 (BCM2712)")
    items+=("rockchip-rk3588" "Rockchip RK3588 (Orange Pi 5, etc.)")
    items+=("allwinner-h3" "Allwinner H3 (Orange Pi Zero, etc.)")
    items+=("reset" "Reset to current distro config")

    local choice
    choice=$($TUI --title "Hardware Profiles" --menu "Select a hardware profile to auto-configure the kernel:" 22 76 10 "${items[@]}" 3>&1 1>&2 2>&3)
    [ -z "$choice" ] && return
    if [ "$choice" = "reset" ]; then
        if [ -f /proc/config.gz ]; then
            zcat /proc/config.gz > "$CONFIG_FILE"
            load_config
            msgbox "Reset" "Config reset to current running kernel's config."
        else
            msgbox "No Source" "No /proc/config.gz available to reset from."
        fi
        return
    fi
    apply_profile "$choice"
}

# ── Search config options ─────────────────────────────────────────────────
search_config() {
    local query
    query=$(inputbox "Search" "Enter search term (e.g. NVMe, GPU, HP, Intel):" "")
    [ -z "$query" ] && return
    query=$(echo "$query" | tr '[:lower:]' '[:upper:]')

    local results=()
    local items=()
    local i=0
    while IFS='=' read -r key val; do
        [[ "$key" =~ ^# ]] && continue
        [[ -z "$key" ]] && continue
        if echo "$key" | grep -q "$query" || echo "${OPT_DESCS[$key]:-}" | grep -qi "$query"; then
            local display_val
            case "${CONFIG_VALS[$key]:-}" in
                y) display_val="ON " ;;
                m) display_val="MOD" ;;
                n|"") display_val="OFF" ;;
                *) display_val="=${CONFIG_VALS[$key]}" ;;
            esac
            results+=("$key")
            items+=("$key" "[$display_val] ${OPT_DESCS[$key]:-No description}")
            ((i++))
        fi
    done < <(grep '=' "$CONFIG_FILE" | head -100)

    if [ ${#items[@]} -eq 0 ]; then
        msgbox "No Results" "No config options match '$query'."
        return
    fi

    local choice
    choice=$($TUI --title "Search: $query" --menu "Found ${#results[@]} results. Select to toggle:" 22 76 12 "${items[@]}" 3>&1 1>&2 2>&3)
    [ -z "$choice" ] && return
    toggle_config "$choice"
}

# ── Category view ─────────────────────────────────────────────────────────
category_menu() {
    local items=()
    for cat in "${!CATEGORIES[@]}"; do
        items+=("$cat" "${DESCS[$cat]:-}")
    done

    local choice
    choice=$($TUI --title "SLK Configurator — Select Category" --menu "Choose a config category to tune:" 22 76 12 "${items[@]}" 3>&1 1>&2 2>&3)
    [ -z "$choice" ] && return
    category_edit "$choice"
}

category_edit() {
    local cat="$1"
    local opts="${CATEGORIES[$cat]}"
    local items=()
    local arr=($opts)

    for opt in "${arr[@]}"; do
        local v=$(val_for_tui "$opt")
        local desc="${OPT_DESCS[$opt]:-}"
        items+=("$opt" "[$v] $desc")
    done

    items+=("_BACK" "Back to category list")
    items+=("_SAVE" "Save changes to config")

    local choice
    choice=$($TUI --title "Editing: $cat" --menu "Toggle options with Enter:" 24 78 15 "${items[@]}" 3>&1 1>&2 2>&3)
    [ -z "$choice" ] && return
    case "$choice" in
        _BACK) category_menu ;;
        _SAVE) save_config ;;
        *)
            toggle_config "$choice"
            category_edit "$cat"
            ;;
    esac
}

# ── Main menu ─────────────────────────────────────────────────────────────
main_menu() {
    local choice
    local stat_line="Config: $(basename $CONFIG_FILE) | Options: $(grep -c '=y\|=m' "$CONFIG_FILE") enabled"

    choice=$($TUI --title "SLK — Sprungles' Linux Kernel Configurator" --menu "$stat_line" 24 78 12 \
        "category"   "Browse config categories" \
        "search"     "Search by option name or description" \
        "profile"    "Load a hardware-specific profile" \
        "hardware"   "Show detected system hardware" \
        "save"       "Save config and exit" \
        "exit"       "Exit without saving" 3>&1 1>&2 2>&3)

    case "$choice" in
        category)   category_menu ;;
        search)     search_config ;;
        profile)    hardware_profiles_menu ;;
        hardware)   show_hardware ;;
        save)       save_config ; exit 0 ;;
        exit)       exit 0 ;;
        *)          exit 0 ;;
    esac
    main_menu
}

# ── Start ─────────────────────────────────────────────────────────────────
load_config
main_menu
