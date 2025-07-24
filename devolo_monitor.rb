require 'net/http'
require 'uri'
require 'json'
require 'digest'
require_relative 'logger'

class DevoloMonitor
  def initialize(host, password = nil)
    @host = host
    @password = password
    @csrf_token = nil
    @api_tokens = {}
    @session_cookie = nil
    @logger = DevoloLogger.new(level: ENV['LOG_LEVEL'] || 'info', format: ENV['LOG_FORMAT'] || 'json')
  end

  def get_device_info
    uri = URI("http://#{@host}/assets/data.cfl")
    http = Net::HTTP.new(uri.host, uri.port)

    request = Net::HTTP::Get.new(uri)
    request['Cookie'] = @session_cookie if @session_cookie

    response = http.request(request)

    if response.code == '200'
      parse_device_data(response.body)
    else
      @logger.error("Failed to get device info", host: @host, response_code: response.code)
      nil
    end
  end

  def parse_device_data(data)
    info = {}
    data.lines.each do |line|
      key, value = line.strip.split('=', 2)
      info[key] = value if key && value
    end

    @csrf_token = info['CSRFTOKEN']
    @api_tokens['plcnet'] = info['HNAPPBACKEND.GENERAL.PLCNETAPI_TOKEN']
    @api_tokens['device'] = info['HNAPPBACKEND.GENERAL.DEVICEAPI_TOKEN']

    info
  end

  def authenticate
    # Always refresh CSRF token before authentication
    refresh_csrf_token

    return false unless @csrf_token && @password

    password_hash = generate_password_hash(@password, @csrf_token)

    uri = URI("http://#{@host}/")
    http = Net::HTTP.new(uri.host, uri.port)

    request = Net::HTTP::Post.new(uri)
    request['Content-Type'] = 'application/x-www-form-urlencoded'
    request.body = ".PASSWD_HASH=#{password_hash}&.CSRFTOKEN=#{@csrf_token}"

    response = http.request(request)

    if response.code == '200'
      # Extract session cookie from response headers
      if response['Set-Cookie']
        cookie_header = response['Set-Cookie']
        if cookie_header =~ /plcfw-http-session-id=([^;]+)/
          @session_cookie = "plcfw-http-session-id=#{$1}"
          @logger.debug("Session cookie set", host: @host, session_id: $1)
        end
      end

      # Parse response to check if authentication was successful
      auth_info = parse_device_data(response.body)
      auth_info['AUTHORIZED'] == 'Y'
    else
      false
    end
  end

  def generate_password_hash(password, csrf_token)
    # Algorithm from JavaScript code:
    # 1. First SHA256 hash of password
    # 2. Second SHA256 hash of (csrfToken + firstHashAsArrayBuffer)
    # 3. Return hex string of second hash

    # First hash: SHA256(password)
    first_hash = Digest::SHA256.digest(password)

    # Second hash: SHA256(csrfToken + firstHashAsArrayBuffer)
    second_input = csrf_token + first_hash
    Digest::SHA256.hexdigest(second_input)
  end

  def check_connection_quality
    info = get_device_info
    return nil unless info

    # Parse connection metrics
    rx_bps = parse_bps_string(info['DIDMNG.GENERAL.ACTUAL_RX_BPS'])
    tx_bps = parse_bps_string(info['DIDMNG.GENERAL.ACTUAL_TX_BPS'])
    device_ids = parse_bps_string(info['DIDMNG.GENERAL.DIDS'])
    mac_addresses = parse_mac_addresses(info['DIDMNG.GENERAL.MACS'])
    master_lost = info['MASTERSELECTION.DOMAIN.MASTER_LOST'].to_i
    lost_maps = info['MASTERSELECTION.DOMAIN.LOST_MAPS'].to_i

    # Get current device ID and domain master ID
    current_device_id = info['NODE.GENERAL.DEVICE_ID'].to_i
    domain_master_id = info['NODE.GENERAL.DOMAIN_MASTER_DEVICE_ID'].to_i

    # Find the domain master's bandwidth (this is the actual connection speed)
    master_rx_bps = 0
    master_tx_bps = 0

    device_ids.each_with_index do |device_id, index|
      if device_id == domain_master_id
        master_rx_bps = rx_bps[index] || 0
        master_tx_bps = tx_bps[index] || 0
        break
      end
    end

    # If no domain master found, use the highest bandwidth values
    if master_rx_bps == 0 && master_tx_bps == 0
      master_rx_bps = rx_bps.max || 0
      master_tx_bps = tx_bps.max || 0
    end

    {
      device_name: info['NODE.GENERAL.DEVICE_NAME'],
      uptime: info['SYSTEM.GENERAL.UPTIME'],
      rx_bps: rx_bps,
      tx_bps: tx_bps,
      device_ids: device_ids,
      mac_addresses: mac_addresses,
      current_device_id: current_device_id,
      domain_master_id: domain_master_id,
      master_rx_bps: master_rx_bps,
      master_tx_bps: master_tx_bps,
      master_lost: master_lost,
      lost_maps: lost_maps,
      connection_issues: detect_connection_issues(master_rx_bps, master_tx_bps, master_lost, lost_maps)
    }
  end

  def parse_bps_string(bps_string)
    return [] unless bps_string
    bps_string.split(',').map(&:to_i)
  end

  def parse_mac_addresses(macs_string)
    return [] unless macs_string
    macs_string.split(',')
  end

  def detect_connection_issues(rx_bps, tx_bps, master_lost, lost_maps)
    issues = []

    # Convert BPS to Mbps using the interface's magic factor
    # Formula: Math.floor(32 * BPS / 1000 * 1) = BPS * 0.032
    rx_mbps = (rx_bps * 32.0 / 1000.0).floor
    tx_mbps = (tx_bps * 32.0 / 1000.0).floor

    # Check for zero bandwidth (indicating no connection)
    if rx_bps == 0 && tx_bps == 0
      issues << "No bandwidth detected (0 Mbps RX/TX)"
    elsif rx_bps == 0
      issues << "No receive bandwidth (0 Mbps RX)"
    elsif tx_bps == 0
      issues << "No transmit bandwidth (0 Mbps TX)"
    end

    # Check for low bandwidth (less than 25 Mbps)
    if rx_mbps < 25
      issues << "Low receive bandwidth (#{rx_mbps} Mbps)"
    end

    if tx_mbps < 25
      issues << "Low transmit bandwidth (#{tx_mbps} Mbps)"
    end

    issues
  end

  def restart_device
    return false unless @session_cookie

    # Always refresh CSRF token before restart
    refresh_csrf_token

    @logger.info("Attempting to restart device", host: @host)

    uri = URI("http://#{@host}/")
    http = Net::HTTP.new(uri.host, uri.port)

    request = Net::HTTP::Post.new(uri)
    request['Cookie'] = @session_cookie
    request['Content-Type'] = 'application/x-www-form-urlencoded'
    request.body = "SYSTEM.GENERAL.HW_RESET=1&.CSRFTOKEN=#{@csrf_token}"

    response = http.request(request)

    if response.code == '200'
      @logger.info("Restart command sent successfully", host: @host)
      return true
    else
      @logger.error("Restart failed", host: @host, response_code: response.code)
      return false
    end
  rescue => e
    @logger.error("Restart error", host: @host, error: e.message)
    false
  end

  def refresh_csrf_token
    info = get_device_info
    if info && info['CSRFTOKEN']
      @csrf_token = info['CSRFTOKEN']
      @logger.debug("CSRF token refreshed", host: @host, token: @csrf_token)
    else
      @logger.warn("Failed to refresh CSRF token", host: @host)
    end
  end

  def check_connection_quality_only
    # Authenticate first
    unless authenticate
      return nil
    end

    # Check connection quality and return data only
    check_connection_quality
  end

  def monitor_and_restart_if_needed
    # Authenticate first
    unless authenticate
      return false
    end

    # Check connection quality
    quality = check_connection_quality
    if quality
      if quality[:connection_issues].any?
        # Attempt restart if issues detected
        if restart_device
          return true
        else
          return false
        end
      else
        return true
      end
    else
      return false
    end
  end
end
