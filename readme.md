# Dual Boot Bluetooth Pairing Script

This Bash script automates the process of syncing Bluetooth link keys between Windows and Linux on dual-boot systems. It reads the trusted Bluetooth devices from Windows, extracts their keys, and updates the Linux Bluetooth database, allowing seamless pairing across both operating systems.

---

## Requirements

- Linux system with `bluetoothctl` installed.
- Windows partition accessible and not hibernated ([Fast Startup disabled](https://www.xda-developers.com/disable-fast-startup-in-windows-11/)).
- `chntpw` installed to read the Windows registry.

Supported package managers for automatic installation of `chntpw`:
- `apt`
- `pacman`

---

## Usage
1.Pair the device in Linux first.

2.Boot into Windows and re-pair the device.

3.Boot back into your Linux distribution

4.Clone this repository using

```bash
git clone https://github.com/addev2906/dualboot-bluetooth-pairing
```

5. Make the script executable:

```bash
chmod +x btpair.sh
```

6. Run the script with root privileges:

```bash
sudo ./btpair.sh
```

7. Follow the prompts:

- Select a trusted Bluetooth device from the list.
- Enter the Windows system partition (e.g., `nvme0n1p3`).

8. The script will automatically:

- Mount the Windows partition.
- Extract the link key for the selected Bluetooth device.
- Update the Linux Bluetooth database with the extracted key.
- Safely unmount the Windows partition.

---

## Notes

- Windows must **fully shut down** and not be hibernated. Fast Startup must be disabled, or the script cannot read the link key safely.
- The script uses a `trap` to ensure the Windows partition is always unmounted even if the script fails or is interrupted.

---

## Disclaimer

Use this script at your own risk. Modifying system partitions and Bluetooth databases can cause loss of data or device mispairing if used incorrectly. Always backup important data before running the script.
