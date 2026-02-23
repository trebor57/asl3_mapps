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

require 'etc'
require 'fileutils'
require 'open-uri'
require 'optparse'
require 'open3'
require 'shellwords'

# Configuration
LOG_FILE = '/var/log/m_app_install.log'
TEMP_DIR = '/var/tmp/m_app_install'
DVSWITCH_CONFIG = '/usr/share/dvswitch/include/config.php'
SUPERMON_NG_VERSION = 'V4.1.2'
SUPERMON_NG_TARBALL = "supermon-ng-#{SUPERMON_NG_VERSION}.tar.xz"
SUPERMON_NG_URL = "https://github.com/hardenedpenguin/supermon-ng/releases/download/#{SUPERMON_NG_VERSION}/#{SUPERMON_NG_TARBALL}"
SKYWARNPLUS_NG_VERSION = '1.0.4'
SKYWARNPLUS_NG_TARBALL = "skywarnplus-ng-#{SKYWARNPLUS_NG_VERSION}.tar.gz"
SKYWARNPLUS_NG_URL = "https://github.com/hardenedpenguin/SkywarnPlus-NG/releases/download/v#{SKYWARNPLUS_NG_VERSION}/#{SKYWARNPLUS_NG_TARBALL}"
SKYWARNPLUS_NG_EXTRACT_DIR = "skywarnplus-ng-#{SKYWARNPLUS_NG_VERSION}"
SAYTIME_WEATHER_RB_VERSION = '0.0.6'
SAYTIME_WEATHER_RB_DEB = "saytime-weather-rb_#{SAYTIME_WEATHER_RB_VERSION}-1_all.deb"
SAYTIME_WEATHER_RB_URL = "https://github.com/hardenedpenguin/saytime_weather_rb/releases/download/v#{SAYTIME_WEATHER_RB_VERSION}/#{SAYTIME_WEATHER_RB_DEB}"
SAYIP_NODE_UTILS_VERSION = '1.0.0'
SAYIP_NODE_UTILS_DEB = "sayip-node-utils_#{SAYIP_NODE_UTILS_VERSION}-1_all.deb"
SAYIP_NODE_UTILS_URL = "https://github.com/hardenedpenguin/sayip-reboot-halt-saypublicip/releases/download/v#{SAYIP_NODE_UTILS_VERSION}/#{SAYIP_NODE_UTILS_DEB}"
INTERNET_MONITOR_VERSION = '1.0.1'
INTERNET_MONITOR_DEB = "internet-monitor_#{INTERNET_MONITOR_VERSION}-1_all.deb"
INTERNET_MONITOR_URL = "https://github.com/hardenedpenguin/internet_monitor_rb/releases/download/v#{INTERNET_MONITOR_VERSION}/#{INTERNET_MONITOR_DEB}"
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

  log(:warn, 'fstab was modified. Reboot before continuing to ensure /tmp and mounts are correct and to avoid failures during install.')
  $stdout.write('Reboot now, then re-run this script. Press Enter to continue without rebooting (not recommended): ')
  $stdout.flush
  $stdin.gets

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
  supermon_install_dir = ENV.fetch('SUPERMON_INSTALL_DIR', '/var/www/html/supermon-ng')
  common_inc = File.join(supermon_install_dir, 'includes', 'common.inc')
  if Dir.exist?(supermon_install_dir) && File.file?(common_inc)
    log(:info, 'Supermon-NG is already installed; skipping installation.')
    return
  end

  log(:info, 'Installing Supermon-NG...')

  FileUtils.cd(TEMP_DIR) do
    log(:info, "Downloading #{SUPERMON_NG_TARBALL}...")
    safe_download(SUPERMON_NG_URL, SUPERMON_NG_TARBALL)

    log(:info, 'Extracting archive...')
    run!("tar -xJf #{SUPERMON_NG_TARBALL}")

    install_dir = 'supermon-ng'
    unless Dir.exist?(install_dir)
      error_exit("Expected directory #{install_dir} not found after extract")
    end

    log(:info, 'Running Supermon-NG installer...')
    Dir.chdir(install_dir) do
      ok, _, stderr = run('./install.sh')
      if ok
        log(:info, 'Supermon-NG installation completed successfully')
      else
        error_exit("Supermon-NG installation failed: #{stderr}")
      end
    end

    FileUtils.rm_f(SUPERMON_NG_TARBALL)
    FileUtils.rm_rf(install_dir)
  end
end

def install_skywarnplus_ng
  sudo_user = ENV['SUDO_USER']

  log(:info, "Installing SkywarnPlus-NG (install.sh will run as #{sudo_user})...")

  begin
    pw = Etc.getpwnam(sudo_user)
  rescue ArgumentError
    error_exit("User #{sudo_user} (SUDO_USER) not found on this system.")
  end

  extract_path = File.join(TEMP_DIR, SKYWARNPLUS_NG_EXTRACT_DIR)

  FileUtils.cd(TEMP_DIR) do
    log(:info, "Downloading #{SKYWARNPLUS_NG_TARBALL}...")
    safe_download(SKYWARNPLUS_NG_URL, SKYWARNPLUS_NG_TARBALL)

    log(:info, 'Extracting archive...')
    run!("tar -xzf #{SKYWARNPLUS_NG_TARBALL}")

    unless Dir.exist?(SKYWARNPLUS_NG_EXTRACT_DIR)
      error_exit("Expected directory #{SKYWARNPLUS_NG_EXTRACT_DIR} not found after extract")
    end

    log(:info, "Chowning #{SKYWARNPLUS_NG_EXTRACT_DIR} to #{sudo_user}...")
    FileUtils.chown_R(pw.uid, pw.gid, SKYWARNPLUS_NG_EXTRACT_DIR)

    log(:info, 'Running SkywarnPlus-NG installer (as non-root)...')
    home_s = Shellwords.escape(pw.dir)
    path_s = Shellwords.escape(extract_path)
    install_cmd = "sudo -u #{sudo_user} env HOME=#{home_s} bash -c \"cd #{path_s} && ./install.sh\""
    ok, _, stderr = run(install_cmd)
    if ok
      log(:info, 'SkywarnPlus-NG installation completed successfully')
    else
      error_exit("SkywarnPlus-NG installation failed: #{stderr}")
    end

    FileUtils.rm_f(SKYWARNPLUS_NG_TARBALL)
    FileUtils.rm_rf(SKYWARNPLUS_NG_EXTRACT_DIR)
  end

  log(:info, 'Enabling and starting skywarnplus-ng service...')
  run!('systemctl enable skywarnplus-ng')
  run!('systemctl start skywarnplus-ng')
  log(:info, 'SkywarnPlus-NG service enabled and started. Dashboard: http://localhost:8100 (default: admin / skywarn123)')
  log(:info, 'If accessing the dashboard from another machine, open port 8100 in your firewall manually (e.g. sudo ufw allow 8100/tcp).')
end

def install_saytime_weather_rb
  log(:info, 'Installing saytime-weather-rb...')
  log(:warn, 'Do not install this alongside other saytime_weather implementations; it is a replacement.')

  FileUtils.cd(TEMP_DIR) do
    log(:info, "Downloading #{SAYTIME_WEATHER_RB_DEB}...")
    safe_download(SAYTIME_WEATHER_RB_URL, SAYTIME_WEATHER_RB_DEB)

    already = deb_package_installed?('saytime-weather-rb')
    log(:info, already ? 'Reinstalling .deb package...' : 'Installing .deb package...')
    if already
      run!("apt install --reinstall -y ./#{SAYTIME_WEATHER_RB_DEB}")
    else
      run!("apt install -y ./#{SAYTIME_WEATHER_RB_DEB}")
    end

    FileUtils.rm_f(SAYTIME_WEATHER_RB_DEB)
  end
end

def install_sayip_node_utils
  log(:info, 'Installing sayip-node-utils (SayIP/reboot/halt/public IP)...')
  node_number = prompt_node_number

  FileUtils.cd(TEMP_DIR) do
    log(:info, "Downloading #{SAYIP_NODE_UTILS_DEB}...")
    safe_download(SAYIP_NODE_UTILS_URL, SAYIP_NODE_UTILS_DEB)

    already = deb_package_installed?('sayip-node-utils')
    log(:info, already ? "Reinstalling sayip-node-utils for NODE_NUMBER=#{node_number}..." : "Installing sayip-node-utils for NODE_NUMBER=#{node_number}...")
    run!("NODE_NUMBER=#{node_number} dpkg -i ./#{SAYIP_NODE_UTILS_DEB}")
    run!('apt install -f -y')

    FileUtils.rm_f(SAYIP_NODE_UTILS_DEB)
  end

  log(:info, 'Post-install: you may need `sudo asterisk -rx "rpt reload"` (and/or restart asterisk) for new DTMF config to load.')
end

def install_internet_monitor
  log(:info, 'Installing internet-monitor (primarily for mobile nodes)...')
  node_number = prompt_node_number

  FileUtils.cd(TEMP_DIR) do
    log(:info, "Downloading #{INTERNET_MONITOR_DEB}...")
    safe_download(INTERNET_MONITOR_URL, INTERNET_MONITOR_DEB)

    already = deb_package_installed?('internet-monitor')
    log(:info, already ? 'Reinstalling .deb package...' : 'Installing .deb package...')
    # Use apt so dependencies are resolved automatically.
    if already
      run!("apt install --reinstall -y ./#{INTERNET_MONITOR_DEB}")
    else
      run!("apt install -y ./#{INTERNET_MONITOR_DEB}")
    end

    FileUtils.rm_f(INTERNET_MONITOR_DEB)
  end

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
      -w    Install SkywarnPlus-NG (run with sudo so install.sh runs as your user)
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
