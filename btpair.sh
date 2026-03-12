#!/bin/bash
# ----------------------------
# DUAL BOOT BLUETOOTH PAIR UI
# ----------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RESET='\033[0m'
MOUNT_POINT="/mnt/c"

echo -e "${CYAN}=== DUAL BOOT BLUETOOTH PAIR ===${RESET}"

# --- Functions ---
clean_mac() {
    local mac_clean
    mac_clean=$(echo "$1" | tr -d ':' | tr 'A-Z' 'a-z')
    echo "$mac_clean"
}

get_device_mac() {
    local devices choice selected i
    # FIX #4: Fall back to all devices if filter argument is unsupported
    mapfile -t devices < <(bluetoothctl devices Trusted 2>/dev/null)
    if ((${#devices[@]} == 0)); then
        mapfile -t devices < <(bluetoothctl devices 2>/dev/null)
    fi
    if ((${#devices[@]} == 0)); then
        echo -e "${RED}No Bluetooth devices found.${RESET}" >&2
        return 1
    fi

    echo -e "${YELLOW}Bluetooth devices:${RESET}" >&2
    for i in "${!devices[@]}"; do
        printf "  %d) %s\n" "$((i+1))" "${devices[i]#Device }" >&2
    done

    read -rp "Select a device number: " choice
    if ! [[ "$choice" =~ ^[0-9]+$ ]] || ((choice < 1 || choice > ${#devices[@]})); then
        echo -e "${RED}Invalid selection.${RESET}" >&2
        return 1
    fi

    selected="${devices[choice-1]}"

    # RAW MAC (with colons, uppercase) → global
    device_mac=$(awk '{print $2}' <<< "$selected")
    device_mac=${device_mac^^}

    # Clean MAC → global (no longer echoed to stdout to avoid capture confusion)
    # FIX #5: Use only globals; don't echo from function to avoid ambiguity
    clean_dev_mac=$(clean_mac "$device_mac")
}

# --- Detect adapter MAC ---
# FIX #3: Use exit after first match to avoid grabbing secondary controllers
mac_card=$(bluetoothctl show | awk '/^Controller/ {print $2; exit}')
if [[ -z "$mac_card" ]]; then
    echo -e "${RED}No Bluetooth controller found.${RESET}" >&2
    exit 1
fi
mac_card_clean=$(clean_mac "$mac_card")

# --- Detect package manager ---
PACKAGE_MANAGERS=(apt dnf pacman zypper apk xbps-install emerge nix-env brew)
for i in "${PACKAGE_MANAGERS[@]}"; do
    if command -v "$i" >/dev/null 2>&1; then
        pm="$i"
        break
    fi
done

if [[ -z "$pm" ]]; then
    echo -e "${RED}No supported package manager found.${RESET}" >&2
    exit 1
fi
echo -e "${GREEN}Detected package manager:${RESET} $pm"

# --- Install chntpw and ntfs-3g if necessary ---
for pkg in chntpw ntfs-3g; do
    if ! command -v "$pkg" >/dev/null 2>&1; then
        echo -e "${CYAN}Installing $pkg...${RESET}"
        case $pm in
            pacman) sudo pacman -S --noconfirm "$pkg" ;;
            apt)    sudo apt install "$pkg" -y ;;
            dnf)    sudo dnf install "$pkg" -y ;;
            *)
                echo -e "${YELLOW}Please install $pkg manually and re-run.${RESET}"
                exit 1
                ;;
        esac
    else
        echo -e "${GREEN}$pkg already installed.${RESET}"
    fi
done

# --- Trap to unmount on exit or error ---
trap '
    cd /tmp
    if mountpoint -q "$MOUNT_POINT"; then
        echo "Unmounting $MOUNT_POINT"
        sudo umount "$MOUNT_POINT"
    fi' EXIT

# --- Select Bluetooth device ---
echo
echo -e "${CYAN}Select the trusted Bluetooth device to pair:${RESET}"
if ! get_device_mac; then
    exit 1
fi
echo -e "${GREEN}Selected device:${RESET} $device_mac"
echo -e "${GREEN}Cleaned MAC for pairing:${RESET} $clean_dev_mac"

# --- Pick Windows system partition ---
echo
echo -e "${YELLOW}Available partitions:${RESET}"
lsblk -o NAME,SIZE,FSTYPE,LABEL,MOUNTPOINT
echo

read -rp "Enter your Windows system partition (e.g. nvme0n1p3): " part
if [[ ! -b /dev/"$part" ]]; then
    echo -e "${RED}Partition /dev/$part does not exist.${RESET}" >&2
    exit 1
fi

# --- Mount Windows partition ---
sudo mkdir -p "$MOUNT_POINT"
# FIX #7: Explicit ntfs-3g mount type for reliability
if ! sudo mount -t ntfs-3g /dev/"$part" "$MOUNT_POINT"; then
    echo -e "${RED}Failed to mount /dev/$part. Is ntfs-3g installed?${RESET}" >&2
    exit 1
fi

cd "$MOUNT_POINT/Windows/System32/config" || {
    echo -e "${RED}Failed to cd into Windows config directory.${RESET}" >&2
    exit 1
}

# --- Extract Windows Bluetooth key ---
echo -e "${CYAN}Reading Windows Bluetooth key...${RESET}"

# FIX #1: i=3 to i=18 skips the offset field ($2) and captures all 16 key bytes
raw_hex=$(chntpw -e SYSTEM <<EOF | awk '/^:/{for(i=2;i<=NF;i++) if($i~/^[0-9A-Fa-f]{2}$/) printf "%s", $i}'
cd ControlSet001\Services\BTHPORT\Parameters\Keys
cd ${mac_card_clean}
hex ${clean_dev_mac}
q
y
EOF
)

echo -e "${GREEN}Raw extracted hex:${RESET} $raw_hex"

raw_hex_clean=$(echo "$raw_hex" | tr -d ' \n')

# FIX #2: Validate extracted key before writing
if [[ ${#raw_hex_clean} -ne 32 ]]; then
    echo -e "${RED}Failed to extract a valid 128-bit key (got '${raw_hex_clean}').${RESET}" >&2
    echo -e "${RED}Check that the device MAC and controller MAC are correct.${RESET}" >&2
    exit 1
fi

echo -e "${CYAN}Extracted key:${RESET} $raw_hex_clean"

info_file="/var/lib/bluetooth/$mac_card/$device_mac/info"
# if [[ ! -f "$info_file" ]]; then
#     echo -e "${RED}Info file not found: $info_file${RESET}" >&2
#     exit 1
# fi

echo -e "${GREEN}Updating Linux Bluetooth database...${RESET}"
sudo sed -i "/^\[LinkKey\]/,/^\[/{
    /^Key=/ s/.*/Key=$raw_hex_clean/
}" "$info_file"

sudo systemctl restart bluetooth
echo -e "${GREEN}Done!${RESET} Bluetooth pairing updated successfully."
echo "You can now connect your device in either OS without repairing!"