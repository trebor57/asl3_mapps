# M-App Install (Ruby)

Ruby-based multi-app installer for AllStarLink v3. Installs **AllScan**, **DVSwitch Server**, **Supermon-NG**, **SkywarnPlus-NG**, **saytime-weather-rb**, **sayip-node-utils**, and **internet-monitor** (primarily for mobile nodes).

## Requirements

- Ruby 3.x (stdlib only; no gems)
- **Run with sudo only, from a user account.** The script must be invoked as `sudo ./asl3_mapp.rb ...` while logged in as a normal user. Do **not** run it as root (e.g. after `su -` or root login), and do **not** run it as a normal user without `sudo`—it will exit with an error. This ensures installers that need a non-root user (e.g. SkywarnPlus-NG with `-w`) run correctly.

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

## DVSwitch (Trixie / Bookworm)

DVSwitch is installed using the official scripts from [dvswitch.org](http://dvswitch.org/trixie): **Trixie** or **Bookworm** is chosen automatically from your system’s distro codename. The DVSwitch repository is SHA-256 compliant.


## Paths

- Log: `/var/log/m_app_install.log`
- Temp: `/var/tmp/m_app_install` (removed after run)

## License

GPL-3.0-or-later (see script header).
