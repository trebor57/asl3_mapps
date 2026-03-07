#!/usr/bin/env ruby
# frozen_string_literal: true

# Updates version constants in asl3_mapp.rb to the latest GitHub release
# for each supported component. Used by CI to keep the script in sync.
#
# Usage: ruby scripts/update_versions.rb [path/to/asl3_mapp.rb]
# Default path: asl3_mapp.rb in repo root (relative to script).

require 'json'
require 'net/http'
require 'uri'

SCRIPT_DIR = File.dirname(File.expand_path(__FILE__))
REPO_ROOT = File.dirname(SCRIPT_DIR)
DEFAULT_SCRIPT_PATH = File.join(REPO_ROOT, 'asl3_mapp.rb')

# repo: GitHub "owner/repo"
# constant: name of the version constant in asl3_mapp.rb
# tag_format: :v_prefix_stripped (constant = "1.0.5") or :keep_tag (constant = "V4.1.3")
COMPONENTS = [
  { repo: 'hardenedpenguin/supermon-ng',           constant: 'SUPERMON_NG_VERSION',           tag_format: :keep_tag },
  { repo: 'hardenedpenguin/SkywarnPlus-NG',       constant: 'SKYWARNPLUS_NG_VERSION',       tag_format: :v_prefix_stripped },
  { repo: 'hardenedpenguin/saytime_weather_rb',   constant: 'SAYTIME_WEATHER_RB_VERSION',   tag_format: :v_prefix_stripped },
  { repo: 'hardenedpenguin/sayip-reboot-halt-saypublicip', constant: 'SAYIP_NODE_UTILS_VERSION', tag_format: :v_prefix_stripped },
  { repo: 'hardenedpenguin/internet_monitor_rb',  constant: 'INTERNET_MONITOR_VERSION',     tag_format: :v_prefix_stripped },
].freeze

def fetch_latest_tag(repo, token: nil)
  uri = URI("https://api.github.com/repos/#{repo}/releases/latest")
  req = Net::HTTP::Get.new(uri)
  req['Accept'] = 'application/vnd.github.v3+json'
  req['Authorization'] = "Bearer #{token}" if token && !token.empty?

  res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) { |http| http.request(req) }
  unless res.is_a?(Net::HTTPSuccess)
    warn "Failed to fetch #{repo}: #{res.code} #{res.message}"
    return nil
  end

  data = JSON.parse(res.body)
  data['tag_name']
end

def tag_to_constant_value(tag_name, tag_format)
  return nil if tag_name.nil? || tag_name.empty?
  normalized = tag_name.sub(/\A[vV]/, '')
  case tag_format
  when :keep_tag
    tag_name.start_with?('v', 'V') ? tag_name : "V#{normalized}"
  when :v_prefix_stripped
    normalized
  else
    normalized
  end
end

def version_less_than?(current, latest)
  return false if current.nil? || latest.nil?
  return true if current.empty?
  return false if latest.empty?
  # Normalize for comparison: strip V/v prefix
  c = current.sub(/\A[vV]/, '')
  l = latest.sub(/\A[vV]/, '')
  Gem::Version.new(c) < Gem::Version.new(l)
rescue ArgumentError
  # Non-semver: compare as strings
  c < l
end

def current_value_in_content(content, constant_name)
  m = content.match(/^\s*#{Regexp.escape(constant_name)}\s*=\s*['"]([^'"]+)['"]\s*$/)
  m ? m[1] : nil
end

def replace_constant_in_content(content, constant_name, new_value)
  content.gsub(
    /^(\s*#{Regexp.escape(constant_name)}\s*=\s*)['"][^'"]*['"](\s*)$/,
    "\\1'#{new_value}'\\2"
  )
end

def main
  script_path = ARGV[0] || DEFAULT_SCRIPT_PATH
  unless File.file?(script_path)
    warn "Not found: #{script_path}"
    exit 1
  end

  token = ENV['GITHUB_TOKEN']
  content = File.read(script_path)
  updated = content.dup
  any_change = false

  COMPONENTS.each do |comp|
    tag = fetch_latest_tag(comp[:repo], token: token)
    next if tag.nil?

    latest_value = tag_to_constant_value(tag, comp[:tag_format])
    current_value = current_value_in_content(content, comp[:constant])

    if current_value.nil?
      warn "Constant #{comp[:constant]} not found in script"
      next
    end

    next unless version_less_than?(current_value, latest_value)

    $stderr.puts "Updating #{comp[:constant]}: #{current_value} -> #{latest_value} (tag: #{tag})"
    updated = replace_constant_in_content(updated, comp[:constant], latest_value)
    any_change = true
  end

  if any_change
    File.write(script_path, updated)
    exit 0
  end

  $stderr.puts 'All components already at latest version.'
  exit 0
end

main
