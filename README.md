# Devolo Powerbridge Monitor

A Ruby-based monitoring and automation system for Devolo Powerbridge devices connected via coaxial cable. This tool automatically monitors connection quality and can restart devices when issues are detected.

## Features

- 🔍 **Real-time Monitoring**: Continuously monitors connection quality and bandwidth
- 🔄 **Automatic Restart**: Restarts devices when connection issues are detected
- 📊 **Connection Analysis**: Analyzes bandwidth, master selection, and connection stability
- 🔐 **Secure Authentication**: Handles device authentication with CSRF token management
- ⏱️ **Cooldown Protection**: Prevents excessive restarts with configurable cooldown periods
- 🎯 **Manual Control**: Manual device restart with confirmation prompts

## Requirements

- Ruby 2.6 or higher
- Network access to Devolo Powerbridge devices
- Device passwords

## Installation

1. Clone or download the project files
2. Ensure you have Ruby installed
3. Copy `config.yml.example` to `config.yml` and configure your devices

## Configuration

Copy `config.yml.example` to `config.yml` and add your device information:

```yaml
devices:
  your-device-1.local: "your-password-1"
  your-device-2.local: "your-password-2"
```

## Usage

### Check Device Status

Check the current status of all configured devices:

```bash
ruby devolo_cli.rb check
```

### Monitor Devices Continuously

Start continuous monitoring with automatic restart capability:

```bash
ruby devolo_cli.rb monitor
```

### Manual Restart

Manually restart a specific device:

```bash
ruby devolo_cli.rb restart
```

### Help

Display help information:

```bash
ruby devolo_cli.rb help
# or
ruby devolo_cli.rb --help
# or
ruby devolo_cli.rb -h
```

## License

This project is provided as-is for monitoring Devolo Powerbridge devices. Use at your own risk and ensure you have proper authorization to monitor and restart your devices.

## Disclaimer

This tool interacts with network devices and can restart them. Use responsibly and ensure you have proper backups and monitoring in place. The authors are not responsible for any network disruptions or data loss that may occur from using this tool.
