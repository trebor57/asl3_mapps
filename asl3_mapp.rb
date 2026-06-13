#!/usr/bin/env ruby
# frozen_string_literal: true

# This script assists with the new install of AllStarLink version 3.
# It installs AllScan Dashboard, DVSwitch Server, Supermon-NG, SkywarnPlus-NG,
# saytime-weather-rb, sayip-node-utils, and internet-monitor (mobile nodes).
#
# Copyright (C) 2026 Jory A. Pratt - W5GLE <geekypenguin@gmail.com>
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <https://www.gnu.org/licenses/>.

require 'fileutils'
require 'open-uri'
require 'optparse'
require 'open3'
require 'shellwords'

# Configuration
LOG_FILE = '/var/log/m_app_install.log'
TEMP_DIR = '/var/tmp/m_app_install'
DVSWITCH_CONFIG = '/usr/share/dvswitch/include/config.php'
HARDENEDPENGUIN_APT_KEYRING_URL = 'https://hardenedpenguin.github.io/hardenedpenguin-apt/pool/main/h/hardenedpenguin-archive-keyring/hardenedpenguin-archive-keyring_1.0_all.deb'
HARDENEDPENGUIN_APT_KEYRING_DEB = 'hardenedpenguin-archive-keyring_1.0_all.deb'
HARDENEDPENGUIN_APT_SOURCE = '/etc/apt/sources.list.d/hardenedpenguin.list'
INTERNET_MONITOR_CONF = '/etc/internet-monitor.conf'
FSTAB = '/etc/fstab'
FSTAB_TMPFS_TMP_LINE = "tmpfs           /tmp            tmpfs   defaults,noatime,nosuid,nodev,mode=1777,size=256M 0 0"

# Colors
RED = "\033[0;31m"
GREEN = "\033[0;32m"
YELLOW = "\033[1;33m"
NC = "\033[0m"

def log(level, message)
  timestamp = Time.now.strftime('%Y-%m-%d %H:%M:%S')
  case level
  when :info
    puts "#{GREEN}[INFO]#{NC} #{message}"
  when :warn
    puts "#{YELLOW}[WARN]#{NC} #{message}"
  when :error
    puts "#{RED}[ERROR]#{NC} #{message}"
  end
  File.open(LOG_FILE, 'a') { |f| f.puts "[#{timestamp}] [#{level.to_s.upcase}] #{message}" }
end

def error_exit(message)
  log(:error, message)
  exit 1
end

def run(cmd, **opts)
  stdout, stderr, status = Open3.capture3(cmd, **opts)
  [status.success?, stdout, stderr]
end

def run!(cmd)
  ok, _stdout, stderr = run(cmd)
  return if ok
  error_exit("Command failed: #{cmd}\n#{stderr}".strip)
end

def deb_package_installed?(name)
  ok, _stdout, _stderr = run("dpkg -s #{Shellwords.escape(name)} 2>/dev/null")
  ok
end

def hardenedpenguin_apt_configured?
  File.file?(HARDENEDPENGUIN_APT_SOURCE) || deb_package_installed?('hardenedpenguin-archive-keyring')
end

def ensure_hardenedpenguin_apt!
  return if hardenedpenguin_apt_configured?

  log(:info, 'Setting up hardenedpenguin APT repository...')
  FileUtils.cd(TEMP_DIR) do
    safe_download(HARDENEDPENGUIN_APT_KEYRING_URL, HARDENEDPENGUIN_APT_KEYRING_DEB)
    run!("apt install -y ./#{HARDENEDPENGUIN_APT_KEYRING_DEB}")
    FileUtils.rm_f(HARDENEDPENGUIN_APT_KEYRING_DEB)
  end
  run!('apt update')
  log(:info, 'hardenedpenguin APT repository configured.')
end

def apt_install_package!(package_name)
  ensure_hardenedpenguin_apt!
  if deb_package_installed?(package_name)
    run!("apt install --reinstall -y #{Shellwords.escape(package_name)}")
  else
    run!("apt install -y #{Shellwords.escape(package_name)}")
  end
end

def run_interactive!(cmd)
  log(:info, "Running: #{cmd}")
  ok = system(cmd)
  return if ok
  error_exit("Command failed: #{cmd}")
end

def safe_download(url, output_path, max_retries: 3)
  retries = 0
  while retries < max_retries
    begin
      URI.open(url, read_timeout: 30, open_timeout: 30) do |io|
        File.binwrite(output_path, io.read)
      end
      return true
    rescue => e
      retries += 1
      log(:warn, "Download failed for #{url} (attempt #{retries}/#{max_retries}): #{e.message}")
      sleep 2 if retries < max_retries
    end
  end
  error_exit("Failed to download #{url} after #{max_retries} attempts")
end

def prompt_node_number
  unless $stdin.tty?
    error_exit('NODE_NUMBER is required. Please run interactively in a terminal.')
  end

  print 'Enter your AllStar node number (NODE_NUMBER): '
  node = $stdin.gets&.strip
  error_exit('No node number provided.') if node.nil? || node.empty?
  error_exit('Invalid node number. Use digits only.') unless node.match?(/\A\d+\z/)
  node
end

def ensure_fstab_tmpfs!
  return unless File.file?(FSTAB) && File.readable?(FSTAB) && File.writable?(FSTAB)

  lines = File.read(FSTAB).lines
  new_lines = []
  tmp_line_added = false

  lines.each do |line|
    if line.match?(/^\s*#/) || line.match?(/^\s*$/)
      new_lines << line
      next
    end

    parts = line.split(/\s+/, 6)
    if parts.size >= 4 && parts[0] == 'tmpfs' && parts[2] == 'tmpfs'
      mount_point = parts[1]
      if mount_point == '/tmp'
        new_lines << "#{FSTAB_TMPFS_TMP_LINE}\n"
        tmp_line_added = true
      else
        new_lines << "# #{line}"
      end
    else
      new_lines << line
    end
  end

  new_lines << "#{FSTAB_TMPFS_TMP_LINE}\n" unless tmp_line_added

  new_content = new_lines.join
  return if new_content == lines.join

  FileUtils.cp(FSTAB, "#{FSTAB}.m_app_install.bak")
  File.write(FSTAB, new_content)
  log(:info, "Updated #{FSTAB}: single tmpfs for /tmp, other tmpfs entries commented out. Backup: #{FSTAB}.m_app_install.bak")

  log(:warn, 'fstab was modified. Reboot before continuing so /tmp and mounts match fstab and installs avoid failures.')

  loop do
    puts
    puts 'Choose what to do next:'
    puts "  #{YELLOW}r#{NC} then Enter — reboot now (recommended); run this script again after the system comes back"
    puts "  #{YELLOW}Enter only#{NC} — continue without rebooting (may cause install failures)"
    $stdout.write('Your choice (r + Enter, or Enter alone): ')
    $stdout.flush
    line = $stdin.gets
    break if line.nil?

    choice = line.strip.downcase
    if choice.empty?
      log(:warn, 'Continuing without reboot at your request.')
      break
    elsif choice == 'r'
      log(:info, 'Rebooting now…')
      unless system('shutdown', '-r', 'now')
        error_exit('Could not start reboot. Run: sudo reboot — then re-run this script.')
      end
      exit 0
    else
      puts "#{YELLOW}Type r and press Enter to reboot, or press Enter alone to continue.#{NC}"
    end
  end

  # Only unmount if /var/tmp is currently a mount point (e.g. tmpfs).
  mounted, = run('mountpoint -q /var/tmp')
  if mounted
    ok, = run('umount /var/tmp')
    if ok
      log(:info, '/var/tmp is now on disk; this run can proceed without reboot.')
    else
      log(:warn, 'Could not umount /var/tmp (in use?); reboot and run again for installs to use disk.')
    end
  else
    log(:info, '/var/tmp is not mounted; already on disk. This run can proceed.')
  end
end

def set_kv_line(path, key, value)
  line = "#{key}=#{value}"

  if File.exist?(path)
    updated = false
    out = File.read(path).lines.map do |l|
      if l.match?(/^\s*#{Regexp.escape(key)}\s*=/)
        updated = true
        "#{line}\n"
      else
        l
      end
    end

    out << "#{line}\n" unless updated
    File.write(path, out.join)
  else
    File.write(path, "#{line}\n")
  end
end

def distro_codename
  codename = nil
  if File.readable?('/etc/os-release')
    File.foreach('/etc/os-release') do |line|
      if line.strip =~ /\AVERSION_CODENAME=(.+)\z/
        codename = Regexp.last_match(1).strip
        break
      end
    end
  end
  codename ||= (run('lsb_release -sc')[1]&.strip) if codename.nil? || codename.empty?
  codename.to_s.empty? ? 'bookworm' : codename
end

def install_allscan
  log(:info, 'Installing AllScan...')

  run!('apt install -y php unzip asl3-tts')

  FileUtils.cd(TEMP_DIR) do
    installer = 'AllScanInstallUpdate.php'
    safe_download('https://raw.githubusercontent.com/davidgsd/AllScan/main/AllScanInstallUpdate.php', installer)
    File.chmod(0o755, installer)

    log(:info, 'Running AllScan installer (may prompt for input)...')
    log_offset = File.size?(LOG_FILE) || 0
    run_interactive!("php #{installer}")
    log(:info, 'AllScan installation completed successfully')

    FileUtils.rm_f(installer)

    # After the interactive installer finishes, clear the screen and show only our log output
    # from this run (not the installer's interactive prompts).
    if $stdout.tty?
      system('clear')
      File.open(LOG_FILE, 'r') do |f|
        f.seek(log_offset)
        print f.read
      end
    end
  end
end

def install_dvswitch
  log(:info, 'Installing DVSwitch Server...')

  run!('apt install -y php-cgi libapache2-mod-php')

  codename = distro_codename
  installer_url = codename == 'trixie' ? 'http://dvswitch.org/trixie' : 'http://dvswitch.org/bookworm'
  installer = codename == 'trixie' ? 'trixie' : 'bookworm'

  FileUtils.cd(TEMP_DIR) do
    safe_download(installer_url, installer)
    File.chmod(0o755, installer)

    log(:info, 'Running DVSwitch installer...')
    ok, _, stderr = run("./#{installer}")
    if ok
      log(:info, 'DVSwitch installer completed')
    else
      error_exit("DVSwitch installer failed: #{stderr}")
    end

    FileUtils.rm_f(installer)
  end

  run!('apt update')
  run!('apt install -y dvswitch-server')

  if File.file?(DVSWITCH_CONFIG)
    content = File.read(DVSWITCH_CONFIG)
    if content.include?('31001')
      content = content.gsub('31001', '34001')
      File.write(DVSWITCH_CONFIG, content)
      log(:info, 'Updated USRP port from 31001 to 34001')
    else
      log(:warn, 'USRP port 31001 not found in config; no change made')
    end
  else
    log(:warn, "DVSwitch config file not found: #{DVSWITCH_CONFIG}")
  end

  log(:info, 'DVSwitch Server installation completed successfully')
end

def install_supermon_ng
  if deb_package_installed?('supermon-ng')
    log(:info, 'Supermon-NG is already installed; skipping installation.')
    return
  end

  log(:info, 'Installing Supermon-NG...')
  apt_install_package!('supermon-ng')
  log(:info, 'Supermon-NG installation completed successfully')
end

def install_skywarnplus_ng
  if deb_package_installed?('skywarnplus-ng-all') || deb_package_installed?('skywarnplus-ng')
    log(:info, 'SkywarnPlus-NG is already installed; skipping installation.')
    return
  end

  log(:info, 'Installing SkywarnPlus-NG (skywarnplus-ng-all)...')
  apt_install_package!('skywarnplus-ng-all')
  run!('systemctl enable skywarnplus-ng')
  run!('systemctl start skywarnplus-ng')
  log(:info, 'SkywarnPlus-NG service enabled and started. Dashboard: http://localhost:8100 (default: admin / skywarn123)')
  log(:info, 'If accessing the dashboard from another machine, open port 8100 in your firewall manually (e.g. sudo ufw allow 8100/tcp).')
end

def install_saytime_weather_rb
  if deb_package_installed?('saytime-weather-rb')
    log(:info, 'saytime-weather-rb is already installed; skipping installation.')
    return
  end

  log(:info, 'Installing saytime-weather-rb...')
  log(:warn, 'Do not install this alongside other saytime_weather implementations; it is a replacement.')
  apt_install_package!('saytime-weather-rb')
  log(:info, 'saytime-weather-rb installation completed successfully')
end

def install_sayip_node_utils
  if deb_package_installed?('sayip-node-utils')
    log(:info, 'sayip-node-utils is already installed; skipping installation.')
    return
  end

  log(:info, 'Installing sayip-node-utils (SayIP/reboot/halt/public IP)...')
  node_number = prompt_node_number
  ensure_hardenedpenguin_apt!
  run!("NODE_NUMBER=#{Shellwords.escape(node_number)} apt install -y sayip-node-utils")
  log(:info, 'Post-install: you may need `sudo asterisk -rx "rpt reload"` (and/or restart asterisk) for new DTMF config to load.')
end

def install_internet_monitor
  if deb_package_installed?('internet-monitor')
    log(:info, 'internet-monitor is already installed; skipping installation.')
    return
  end

  log(:info, 'Installing internet-monitor (primarily for mobile nodes)...')
  node_number = prompt_node_number
  ensure_hardenedpenguin_apt!
  run!("NODE_NUMBER=#{Shellwords.escape(node_number)} apt install -y internet-monitor")

  log(:info, "Writing NODE_NUMBER=#{node_number} to #{INTERNET_MONITOR_CONF}...")
  set_kv_line(INTERNET_MONITOR_CONF, 'NODE_NUMBER', node_number)

  log(:info, 'Enabling and starting internet-monitor service...')
  run!('systemctl enable internet-monitor')
  run!('systemctl start internet-monitor')
end

def usage
  <<~USAGE
    Usage: #{$PROGRAM_NAME} [OPTIONS]

    Options:
      -a    Install AllScan
      -d    Install DVSwitch
      -s    Install Supermon-NG
      -w    Install SkywarnPlus-NG (skywarnplus-ng-all from hardenedpenguin APT)
      -y    Install saytime-weather-rb (Ruby saytime + weather)
      -i    Install sayip-node-utils (prompts for NODE_NUMBER)
      -m    Install internet-monitor (mobile nodes; prompts for NODE_NUMBER)
      -h    Display this help message

    You can combine options (e.g. #{$PROGRAM_NAME} -a -d -s -w -y -i -m).
  USAGE
end

# --- Main ---

unless Process.uid == 0 && !ENV['SUDO_USER'].to_s.empty?
  error_exit('This script must be run with sudo (e.g. sudo ./asl3_mapp.rb ...).')
end

FileUtils.touch(LOG_FILE) unless File.exist?(LOG_FILE)

log(:info, 'Starting M-Apps installation script')
ensure_fstab_tmpfs!

# Create TEMP_DIR after ensure_fstab_tmpfs! so it lives on disk if /var/tmp was unmounted/remounted.
FileUtils.mkdir_p(TEMP_DIR)
FileUtils.chmod(0o755, TEMP_DIR)

install_allscan_flag = false
install_dvswitch_flag = false
install_supermon_ng_flag = false
install_skywarnplus_ng_flag = false
install_saytime_weather_rb_flag = false
install_sayip_node_utils_flag = false
install_internet_monitor_flag = false

OptionParser.new do |opts|
  opts.on('-a') { install_allscan_flag = true }
  opts.on('-d') { install_dvswitch_flag = true }
  opts.on('-s') { install_supermon_ng_flag = true }
  opts.on('-w') { install_skywarnplus_ng_flag = true }
  opts.on('-y') { install_saytime_weather_rb_flag = true }
  opts.on('-i') { install_sayip_node_utils_flag = true }
  opts.on('-m') { install_internet_monitor_flag = true }
  opts.on('-h') { puts usage; exit 0 }
end.parse!

if !install_allscan_flag && !install_dvswitch_flag && !install_supermon_ng_flag && !install_skywarnplus_ng_flag && !install_saytime_weather_rb_flag && !install_sayip_node_utils_flag && !install_internet_monitor_flag
  puts usage
  exit 1
end

begin
  install_allscan if install_allscan_flag
  install_dvswitch if install_dvswitch_flag
  install_supermon_ng if install_supermon_ng_flag
  install_skywarnplus_ng if install_skywarnplus_ng_flag
  install_saytime_weather_rb if install_saytime_weather_rb_flag
  install_sayip_node_utils if install_sayip_node_utils_flag
  install_internet_monitor if install_internet_monitor_flag

  log(:info, "Installation completed. Log file: #{LOG_FILE}")
ensure
  FileUtils.rm_rf(TEMP_DIR)
end
