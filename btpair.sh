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
clean_mac(){
    local mac_clean
    mac_clean=$(echo "$1" | tr -d ':' | tr 'A-F' 'a-f')
    echo "$mac_clean"
}

get_device_mac() {
    local devices choice selected i

    mapfile -t devices < <(bluetoothctl devices Trusted)
    if ((${#devices[@]} == 0)); then
        echo -e "${RED}No trusted Bluetooth devices found.${RESET}" >&2
        return 1
    fi

    echo -e "${YELLOW}Trusted Bluetooth devices:${RESET}" >&2
    for i in "${!devices[@]}"; do
        printf "  %d) %s\n" "$((i+1))" "${devices[i]#Device }" >&2
    done

    read -rp "Select a device number: " choice >&2
    if ! [[ "$choice" =~ ^[0-9]+$ ]] || ((choice < 1 || choice > ${#devices[@]})); then
        echo -e "${RED}Invalid selection.${RESET}" >&2
        return 1
    fi

    selected="${devices[choice-1]}"

    # RAW MAC (with colons, uppercase) → global
    device_mac=$(awk '{print $2}' <<< "$selected")
    device_mac=${device_mac^^}

    # Clean MAC → function output
    clean_dev_mac=$(echo "$device_mac" | tr -d ':' | tr 'A-Z' 'a-z')
    echo "$clean_dev_mac"
}

# --- Detect adapter MAC ---
mac_card=$(bluetoothctl show | awk '/Controller/ {print $2}')
mac_card_clean=$(clean_mac "$mac_card")

# --- Detect package manager ---
PACKAGE_MANAGERS=(apt dnf pacman zypper apk xbps-install emerge nix-env brew)
for i in "${PACKAGE_MANAGERS[@]}"; do
    if command -v "$i" >/dev/null 2>&1; then
        pm="$i"
        break
    fi
done
echo -e "${GREEN}Detected package manager:${RESET} $pm"

# --- Install chntpw if necessary ---
case $pm in
    pacman)
        echo -e "${CYAN}Installing chntpw...${RESET}"
        sudo pacman -S chntpw
        ;;
    apt)
        echo -e "${CYAN}Installing chntpw...${RESET}"
        sudo apt install chntpw -y
        ;;
    *)
        echo Install chntpw with your package manager and continue...
        ;;
esac

# --- Trap to unmount on exit or error ---
trap '
    cd /tmp
    if mountpoint -q "$MOUNT_POINT"; then echo "Unmounting $MOUNT_POINT"; sudo umount "$MOUNT_POINT"; fi' EXIT

# --- Select Bluetooth device ---
echo
echo -e "${CYAN}Select the trusted Bluetooth device to pair:${RESET}"
get_device_mac

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
sudo mount /dev/"$part" "$MOUNT_POINT"
cd "$MOUNT_POINT/Windows/System32/config" || { echo "Failed to cd into Windows config"; exit 1; }

# --- Extract Windows Bluetooth key ---
echo -e "${CYAN}Reading Windows Bluetooth key...${RESET}"
raw_hex=$(chntpw -e SYSTEM <<EOF | awk '/^:/{for(i=2;i<=17;i++) printf "%s ", $i; print ""}'
cd ControlSet001\Services\BTHPORT\Parameters\Keys
cd ${mac_card_clean}
hex $clean_dev_mac
q
y
EOF
)

raw_hex_clean=$(echo "$raw_hex" | tr -d " ")

echo -e "${GREEN}Updating Linux Bluetooth database...${RESET}"
sudo sed -i "/^\[LinkKey\]/,/^\[/{ 
    /^Key=/ s/.*/Key=$raw_hex_clean/
}" "/var/lib/bluetooth/$mac_card/$device_mac/info"

# --- Cleanup handled by trap ---
sudo systemctl restart bluetooth
echo -e "${GREEN}Done!${RESET} Bluetooth pairing updated successfully."
echo "You can now connect your device in either OS without repairing!"