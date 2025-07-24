#!/usr/bin/env ruby

require 'yaml'
require 'optparse'
require_relative 'devolo_monitor'
require_relative 'logger'

class DevoloCli
  def initialize
    @config = load_config
    @last_restart = {}
    @logger = DevoloLogger.new(level: ENV['LOG_LEVEL'] || 'info', format: ENV['LOG_FORMAT'] || 'json')
  end

  def load_config
    YAML.load_file('config.yml')
  rescue => e
    @logger.error("Failed to load config.yml", error: e.message)
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
    @logger.info("Starting device status check", device_count: @config['devices'].length)

    @config['devices'].each do |host, password|
      @logger.info("Checking device", host: host)

      monitor = DevoloMonitor.new(host, password)
      quality = monitor.check_connection_quality_only

      if quality
        log_device_status(quality)
      else
        @logger.error("Failed to get connection quality data", host: host)
      end
    end
  end

  def monitor_devices
    @logger.info("Starting continuous monitoring", device_count: @config['devices'].length)

    # Initialize monitors before the loop
    monitors = {}
    @config['devices'].each do |host, password|
      monitors[host] = DevoloMonitor.new(host, password)
    end

    loop do
      monitors.each do |host, monitor|
        @logger.info("Monitoring device", host: host)

        # Check connection quality
        quality = monitor.check_connection_quality_only

        if quality
          log_device_status(quality)

          if quality[:connection_issues].any?
            # Check cooldown before restarting
            if @last_restart[host] && Time.now - @last_restart[host] < 300
              remaining = 300 - (Time.now - @last_restart[host]).to_i
              @logger.warn("Cooldown active, skipping restart", host: host, remaining_seconds: remaining)
            else
              @logger.warn("Connection issues detected, attempting restart",
                          host: host,
                          issues: quality[:connection_issues])

              if monitor.restart_device
                @last_restart[host] = Time.now
                @logger.info("Restart initiated successfully", host: host)
              else
                @logger.error("Restart failed", host: host)
              end
            end
          else
            @logger.info("Connection status good", host: host)
          end
        else
          @logger.error("Failed to get connection quality data", host: host)
        end
      end

      @logger.debug("Waiting before next check cycle", wait_seconds: 60)
      sleep 60
    end
  rescue Interrupt
    @logger.info("Monitoring stopped by user")
  end

  def manual_restart
    @logger.info("Starting manual restart process")

    # Show available devices
    @config['devices'].each_with_index do |(host, password), index|
      puts "#{index + 1}. #{host}"
    end

    print "\nSelect device to restart (1-#{@config['devices'].length}): "
    choice = STDIN.gets.chomp.to_i

    if choice < 1 || choice > @config['devices'].length
      @logger.error("Invalid device selection", choice: choice, max_devices: @config['devices'].length)
      return
    end

    # Get the selected device
    devices_array = @config['devices'].to_a
    host, password = devices_array[choice - 1]

    # Check cooldown
    if @last_restart[host] && Time.now - @last_restart[host] < 300
      remaining = 300 - (Time.now - @last_restart[host]).to_i
      @logger.warn("Cooldown active, manual restart blocked", host: host, remaining_seconds: remaining)
      return
    end

    print "Are you sure you want to restart #{host}? (yes/no): "
    confirmation = STDIN.gets.chomp.downcase

    if confirmation == 'yes'
      monitor = DevoloMonitor.new(host, password)

      if monitor.authenticate
        if monitor.restart_device
          @last_restart[host] = Time.now
          @logger.info("Manual restart command sent successfully", host: host)
        else
          @logger.error("Manual restart failed", host: host)
        end
      else
        @logger.error("Authentication failed for manual restart", host: host)
      end
    else
      @logger.info("Manual restart cancelled by user", host: host)
    end
  end

  private

  def log_device_status(quality)
    # Calculate Mbps values
    rx_mbps = (quality[:master_rx_bps] * 32.0 / 1000.0).floor
    tx_mbps = (quality[:master_tx_bps] * 32.0 / 1000.0).floor

    @logger.info("Device status",
                device_name: quality[:device_name],
                host: quality[:device_name], # for consistency
                uptime: quality[:uptime],
                current_device_id: quality[:current_device_id],
                domain_master_id: quality[:domain_master_id],
                rx_mbps: rx_mbps,
                tx_mbps: tx_mbps,
                mac_addresses: quality[:mac_addresses],
                master_lost: quality[:master_lost],
                lost_maps: quality[:lost_maps],
                connection_issues: quality[:connection_issues],
                has_issues: quality[:connection_issues].any?)
  end
end

if __FILE__ == $0
  cli = DevoloCli.new
  cli.run
end
