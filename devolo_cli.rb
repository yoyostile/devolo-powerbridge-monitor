#!/usr/bin/env ruby

require 'yaml'
require 'optparse'
require_relative 'devolo_monitor'

class DevoloCli
  def initialize
    @config = load_config
    @last_restart = {}
  end

  def load_config
    YAML.load_file('config.yml')
  rescue => e
    puts "Error loading config.yml: #{e.message}"
    exit 1
  end

  def run
    parser = OptionParser.new do |opts|
      opts.banner = "Usage: ruby devolo_cli.rb [command] [options]"
      opts.separator ""
      opts.separator "Commands:"
      opts.separator "  check     Check status of all devices"
      opts.separator "  monitor   Monitor devices continuously and restart if needed"
      opts.separator "  restart   Manually restart a device"
      opts.separator "  help      Show this help message"
      opts.separator ""
      opts.separator "Examples:"
      opts.separator "  ruby devolo_cli.rb check"
      opts.separator "  ruby devolo_cli.rb monitor"
      opts.separator "  ruby devolo_cli.rb restart"
    end

    begin
      parser.parse!
    rescue OptionParser::InvalidOption => e
      puts e.message
      puts parser
      exit 1
    end

    command = ARGV.first

    case command
    when "check"
      check_all_devices
    when "monitor"
      monitor_devices
    when "restart"
      manual_restart
    when "help", nil
      puts parser
    else
      puts "Unknown command: #{command}"
      puts parser
      exit 1
    end
  end

  def check_all_devices
    puts "🔍 Checking all devices..."
    puts "=" * 50

    @config['devices'].each do |host, password|
      puts "\n📡 Device: #{host}"
      puts "-" * 30

      monitor = DevoloMonitor.new(host, password)
      quality = monitor.check_connection_quality_only

      if quality
        display_device_status(quality)
      else
        puts "❌ Failed to get connection quality data"
      end
    end
  end

  def monitor_devices
    puts "🔄 Starting continuous monitoring..."
    puts "Press Ctrl+C to stop"
    puts "=" * 50

    # Initialize monitors before the loop
    monitors = {}
    @config['devices'].each do |host, password|
      monitors[host] = DevoloMonitor.new(host, password)
    end

    loop do
      monitors.each do |host, monitor|
        puts "\n🕐 #{Time.now.strftime('%Y-%m-%d %H:%M:%S')}"
        puts "📡 Monitoring: #{host}"

        # Check connection quality
        quality = monitor.check_connection_quality_only

        if quality
          display_device_status(quality)

          if quality[:connection_issues].any?
            # Check cooldown before restarting
            if @last_restart[host] && Time.now - @last_restart[host] < 300
              remaining = 300 - (Time.now - @last_restart[host]).to_i
              puts "    ⏳ Cooldown active. Wait #{remaining} seconds before next restart."
            else
              puts "    🔄 Issues detected - attempting restart..."
              if monitor.restart_device
                @last_restart[host] = Time.now
                puts "    ✅ Restart initiated"
              else
                puts "    ❌ Restart failed"
              end
            end
          end
        else
          puts "❌ Failed to get connection quality data"
        end

        puts "-" * 30
      end

      puts "\n⏳ Waiting 60 seconds before next check..."
      sleep 60
    end
  rescue Interrupt
    puts "\n🛑 Monitoring stopped by user"
  end

  def manual_restart
    puts "🔄 Manual Restart"
    puts "=" * 30

    # Show available devices
    @config['devices'].each_with_index do |(host, password), index|
      puts "#{index + 1}. #{host}"
    end

    print "\nSelect device to restart (1-#{@config['devices'].length}): "
    choice = STDIN.gets.chomp.to_i

    if choice < 1 || choice > @config['devices'].length
      puts "❌ Invalid selection"
      return
    end

    # Get the selected device
    devices_array = @config['devices'].to_a
    host, password = devices_array[choice - 1]

    # Check cooldown
    if @last_restart[host] && Time.now - @last_restart[host] < 300
      remaining = 300 - (Time.now - @last_restart[host]).to_i
      puts "⏳ Cooldown active. Wait #{remaining} seconds before next restart."
      return
    end

    print "Are you sure you want to restart #{host}? (yes/no): "
    confirmation = STDIN.gets.chomp.downcase

    if confirmation == 'yes'
      monitor = DevoloMonitor.new(host, password)

      if monitor.authenticate
        # Just call restart_device directly, don't use monitor_and_restart_if_needed
        if monitor.restart_device
          @last_restart[host] = Time.now
          puts "✅ Restart command sent successfully"
        else
          puts "❌ Restart failed"
        end
      else
        puts "❌ Authentication failed"
      end
    else
      puts "❌ Restart cancelled"
    end
  end

  private

  def display_device_status(quality)
    puts "✅ Device: #{quality[:device_name]}"
    puts "⏱️  Uptime: #{quality[:uptime]}"
    puts "🆔 Current Device ID: #{quality[:current_device_id]}"
    puts "👑 Domain Master ID: #{quality[:domain_master_id]}"
    puts "📥 Domain Master RX: #{(quality[:master_rx_bps] * 32.0 / 1000.0).floor} Mbps"
    puts "📤 Domain Master TX: #{(quality[:master_tx_bps] * 32.0 / 1000.0).floor} Mbps"
    puts "🔗 MAC Addresses: #{quality[:mac_addresses].join(', ')}"
    puts "❌ Master Lost: #{quality[:master_lost]}"
    puts "🗺️  Lost MAPs: #{quality[:lost_maps]}"

    if quality[:connection_issues].any?
      puts "⚠️  Issues detected:"
      quality[:connection_issues].each { |issue| puts "  - #{issue}" }
    else
      puts "✅ Connection looks good"
    end
  end
end

if __FILE__ == $0
  cli = DevoloCli.new
  cli.run
end
