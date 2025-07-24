require 'json'
require 'time'

class DevoloLogger
  LOG_LEVELS = {
    'debug' => 0,
    'info' => 1,
    'warn' => 2,
    'error' => 3,
    'fatal' => 4
  }

  def initialize(level: 'info', format: 'json')
    @level = LOG_LEVELS[level.downcase] || LOG_LEVELS['info']
    @format = format
  end

  def debug(message, **context)
    log('debug', message, context)
  end

  def info(message, **context)
    log('info', message, context)
  end

  def warn(message, **context)
    log('warn', message, context)
  end

  def error(message, **context)
    log('error', message, context)
  end

  def fatal(message, **context)
    log('fatal', message, context)
  end

  private

  def log(level, message, context)
    return if LOG_LEVELS[level] < @level

    log_entry = {
      timestamp: Time.now.iso8601,
      level: level.upcase,
      message: message,
      **context
    }

    case @format
    when 'json'
      puts log_entry.to_json
    when 'text'
      puts format_text_log(log_entry)
    else
      puts log_entry.to_json
    end
  end

  def format_text_log(entry)
    timestamp = entry[:timestamp]
    level = entry[:level]
    message = entry[:message]

    # Format context as key=value pairs
    context_str = entry.except(:timestamp, :level, :message)
                       .map { |k, v| "#{k}=#{v}" }
                       .join(' ')

    if context_str.empty?
      "#{timestamp} [#{level}] #{message}"
    else
      "#{timestamp} [#{level}] #{message} #{context_str}"
    end
  end
end
