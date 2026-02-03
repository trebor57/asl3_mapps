# M-App Install (Ruby)

Ruby-based multi-app installer for AllStarLink v3. Installs **AllScan**, **DVSwitch Server**, **Supermon-NG**, **SkywarnPlus-NG**, **saytime-weather-rb**, **sayip-node-utils**, and **internet-monitor** (primarily for mobile nodes).

## Requirements

- Ruby 3.x (stdlib only; no gems)
- **Run with sudo only, from a user account.** The script must be invoked as `sudo ./asl3_mapp.rb ...` while logged in as a normal user. Do **not** run it as root (e.g. after `su -` or root login), and do **not** run it as a normal user without `sudo`—it will exit with an error. This ensures installers that need a non-root user (e.g. SkywarnPlus-NG with `-w`) run correctly.

## /etc/fstab (ASL3 Trixie / RPi3)

On the **ASL3 Trixie image**, `/var/tmp` is often **tmpfs with `noexec`**, so installers cannot run under `/var/tmp/m_app_install`. The script fixes this automatically.

### When you run the script

1. **Before any install step**, the script updates `/etc/fstab`:
   - Keeps a single tmpfs for `/tmp` only (256M; options: `defaults,noatime,nosuid,nodev,mode=1777,size=256M`).
   - Comments out other tmpfs lines (`/var/tmp`, `/var/log/apache2`, `/var/log/asterisk`).
   - Backs up the original to `/etc/fstab.m_app_install.bak`.
2. The script then tries to **umount `/var/tmp`** so this run can use `/var/tmp` on disk without rebooting.

### If umount succeeds

The script continues and installs run in the same session. The new fstab is **not** applied to `/tmp` or other mounts until you reboot or run `sudo mount -a`; only `/var/tmp` was switched to disk by the umount.

### If umount fails

The script logs a warning and continues. Install steps that use `/var/tmp` may fail (noexec). **Reboot**, then run the script again; after reboot the new fstab is in effect and `/var/tmp` will be on disk.

### Full remount or reboot

- **Reboot:** Easiest. After reboot, fstab is fully in effect: `/tmp` is the only tmpfs, `/var/tmp` and the log tmpfs dirs are on disk.
- **Remount without reboot:** Run `sudo mount -a` to apply fstab. That will not change already-mounted filesystems; to get `/tmp` updated you would need to reboot or manually umount/mount `/tmp`. So **reboot is recommended** after the first run.

**Memory:** 256M is fine on a 1 GB RPi3. For 128M, edit the constant `FSTAB_TMPFS_TMP_LINE` in the script.

## Download & permissions

Download the latest script to your home directory and make it executable:

```bash
cd "$HOME"
wget -O asl3_mapp.rb "https://raw.githubusercontent.com/hardenedpenguin/asl3_mapps/refs/heads/main/asl3_mapp.rb"
chmod +x asl3_mapp.rb
```

## Usage

Run the script **with sudo** from your **user account** (not as root):

```bash
sudo ./asl3_mapp.rb -a          # AllScan only
sudo ./asl3_mapp.rb -d          # DVSwitch only
sudo ./asl3_mapp.rb -s          # Supermon-NG only
sudo ./asl3_mapp.rb -w          # SkywarnPlus-NG only (install.sh runs as you)
sudo ./asl3_mapp.rb -y          # saytime-weather-rb only
sudo ./asl3_mapp.rb -i          # sayip-node-utils (prompts for NODE_NUMBER)
sudo ./asl3_mapp.rb -m          # internet-monitor (mobile nodes; prompts for NODE_NUMBER)
sudo ./asl3_mapp.rb -a -d -s -w -y -i -m # All seven
sudo ./asl3_mapp.rb -h          # Help
```

## Options

| Option | Description |
|--------|-------------|
| `-a` | Install AllScan |
| `-d` | Install DVSwitch Server |
| `-s` | Install Supermon-NG |
| `-w` | Install SkywarnPlus-NG (must run with `sudo` so install.sh runs as your user) |
| `-y` | Install saytime-weather-rb (Ruby saytime + weather) |
| `-i` | Install sayip-node-utils (prompts for NODE_NUMBER) |
| `-m` | Install internet-monitor (mobile nodes; prompts for NODE_NUMBER) |
| `-h` | Show help |

## DVSwitch security notice (crypto policy change)

When you install **DVSwitch** (`-d`), this installer makes a **system crypto-policy override for APT/Sequoia** to extend SHA1 acceptance that some DVSwitch-related downloads/metadata may still require.

- **What it does**:
  - Creates: `/etc/crypto-policies/back-ends/` (if missing)
  - Copies (if missing): `/usr/share/apt/default-sequoia.config` → `/etc/crypto-policies/back-ends/apt-sequoia.config`
  - Ensures this line is set in `apt-sequoia.config`:
    - `sha1.second_preimage_resistance = 2026-06-01`

- **Security impact**: this is a deliberate **weakening of SHA1-related policy** for APT’s Sequoia backend. It’s done only when `-d` is requested, but the resulting config file is **system-wide** until you revert it.

- **How to revert** (if you don’t want this after DVSwitch install):
  - Remove the override file: `sudo rm -f /etc/crypto-policies/back-ends/apt-sequoia.config`
  - (Optional) reboot or restart relevant services / rerun your distro’s crypto-policy tooling if applicable.

## Paths

- Log: `/var/log/m_app_install.log`
- Temp: `/var/tmp/m_app_install` (removed after run)

## License

GPL-3.0-or-later (see script header).
