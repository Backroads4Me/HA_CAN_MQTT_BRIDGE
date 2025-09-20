# HA_CAN_MQTT_BRIDGE - CAN to MQTT Bridge Add-on

A Home Assistant add-on that initializes CAN interfaces and provides bidirectional bridging to MQTT.

## Features

- **CAN Interface Initialization**: Automatically configures and brings up CAN interfaces
- **Bidirectional Bridge**: CAN ↔ MQTT message bridging
- **Robust Error Handling**: Automatic reconnection on connection loss
- **Configurable Topics**: Customize MQTT topics for different message types
- **Status Monitoring**: Real-time bridge status via MQTT
- **Debug Logging**: Optional verbose logging for troubleshooting
- **Service Discovery**: Automatic MQTT broker detection
- **Web Interface**: Built-in status monitoring via Home Assistant ingress

## Installation

1.  Navigate to the Add-on Store in Home Assistant:

    - Go to **Settings** > **Add-ons**.
    - Click on the **Add-on Store** button in the bottom right.

2.  Add the repository URL:

    - Click the vertical ellipsis (⋮) in the top right corner and select **Repositories**.
    - Paste the following URL and click **Add**:

    ```
    https://github.com/Backroads4Me/HA_CAN_MQTT_BRIDGE
    ```

3.  Install the add-on:
    - Close the repository management window.
    - The "CAN to MQTT Bridge" add-on will now be available in the store.
    - Click on it and then click **Install**.

## Configuration

### User Options

The add-on has minimal configuration options:

| Option              | Default            | Description                                      |
| ------------------- | ------------------ | ------------------------------------------------ |
| `can_interface`     | `can0`             | CAN interface name                               |
| `can_bitrate`       | `250000`           | CAN bitrate (125000, 250000, 500000, or 1000000) |
| `mqtt_host`         | `core-mosquitto`   | MQTT broker hostname (uses service discovery)   |
| `mqtt_port`         | `1883`             | MQTT broker port                                 |
| `mqtt_user`         | `addons`           | MQTT broker username (auto-discovered)          |
| `mqtt_pass`         | ``                 | MQTT broker password (auto-discovered)          |
| `mqtt_topic_raw`    | `can/raw`          | Topic for raw CAN frames                         |
| `mqtt_topic_send`   | `can/send`         | Topic to send CAN frames                         |
| `mqtt_topic_status` | `can/status`       | Topic for bridge status                          |
| `debug_logging`     | `false`            | Enable verbose debug logging                     |
| `ssl`               | `false`            | Enable SSL/TLS for MQTT connections             |
| `password`          | ``                 | Web interface password protection                |

The add-on uses the following advanced features:

- **S6-Overlay**: For robust process management
- **Health Checks**: Automatic monitoring of bridge processes
- **Home Assistant API**: For service discovery and web interface integration

## Usage

### Monitoring CAN Traffic

Subscribe to see all CAN frames (replace credentials as needed):

```bash
mosquitto_sub -h localhost -t can/raw -u canbus -P ha_can_mqtt_bridge
```

### Sending CAN Messages

Publish CAN frames (replace credentials as needed):

```bash
mosquitto_pub -h localhost -t can/send -u canbus -P ha_can_mqtt_bridge -m "123#DEADBEEF"
```

### Bridge Status

Monitor bridge status (replace credentials as needed):

```bash
mosquitto_sub -h localhost -t can/status -u canbus -P ha_can_mqtt_bridge
```

## Logging

The add-on provides comprehensive logging through:

1. **Home Assistant Logs**: Available in the add-on log viewer
2. **MQTT Status Messages**: Published to the `can/status` topic

Logs include:
- CAN interface initialization status
- MQTT connection status
- Bridge process monitoring
- CAN frame transmission details (when debug logging enabled)
- Error messages and reconnection attempts

Status messages published to MQTT:
- `bridge_online`: Bridge is running
- `bridge_offline`: Bridge has stopped
- `bridge_healthy`: Periodic health check confirmation

## CAN Frame Format

The add-on supports two CAN frame formats:

### Standard Format: `ID#DATA`
- `ID`: Hexadecimal CAN identifier (3 or 8 digits)
- `DATA`: Hexadecimal data payload (0-16 hex digits)

Examples:
- `123#DEADBEEF` - Standard ID with 4 bytes of data
- `18FEF017#0102030405060708` - Extended ID with 8 bytes

### Raw Hex Format (Auto-Converted)
For convenience, the add-on automatically converts raw hex strings to the standard format:
- **Input**: `19FEDB9406FFFA05FF00FFFF` (raw hex string)
- **Converted to**: `19FEDB94#06FFFA05FF00FFFF` (ID#DATA format)
- **CAN ID**: First 8 characters become the identifier
- **Data**: Remaining characters become the data payload

This allows seamless integration with systems that send CAN frames as continuous hex strings.

## Requirements

### Hardware

- CAN interface hardware (CAN HAT, USB-CAN adapter, etc.)
- Properly configured CAN interface in Home Assistant OS

### Software

- Home Assistant OS with CAN support enabled
- MQTT broker (Mosquitto add-on recommended)

## Troubleshooting

### Common Issues

**CAN interface initialization failed:**
- Verify CAN hardware is connected (USB-CAN adapter, CAN HAT, etc.)
- Check that interface name matches your hardware (usually `can0`)
- Ensure CAN drivers are available in Home Assistant OS
- Try different bitrate settings (125000, 250000, 500000, 1000000)

**MQTT connection issues:**
- Verify Mosquitto add-on is installed and running
- Check if service discovery is working (default setup should auto-configure)
- For manual configuration, verify broker hostname, port, and credentials
- Check MQTT broker logs for connection errors

**Bridge process crashes:**
- Enable debug logging to see detailed error messages
- Check Home Assistant system logs for permission errors
- Verify add-on has necessary privileges (NET_ADMIN)
- Restart the add-on to clear any stuck processes

**CAN messages not being sent:**
- Verify CAN frame format (either `ID#DATA` or raw hex strings)
- Check CAN bus termination and wiring
- Use debug logging to see frame conversion and transmission attempts
- Test with known-good CAN frames first

### Debug Mode

Enable `debug_logging: true` in configuration for verbose output.

### Security Options

The add-on provides several security features:

- **SSL**: Enable secure MQTT connections with `ssl: true`
- **Password Protection**: Set `password` to restrict access to the web interface
- **AppArmor**: Container isolation for improved security
- **Ingress**: Access the web interface securely through Home Assistant

## Home Assistant Integration

The add-on integrates with Home Assistant in several ways:

### Integration Features

The add-on integrates with Home Assistant through:

### Service Discovery

The add-on uses Home Assistant's service discovery to automatically find and connect to the MQTT broker, eliminating the need for manual configuration in most cases.

### Web Interface

Access the add-on's status page directly through Home Assistant's UI using the Ingress feature, providing a secure way to monitor the CAN bridge without exposing additional ports.

## Health Checks

The add-on includes automatic health monitoring that:

- Verifies CAN interface status during startup
- Monitors MQTT connection health
- Tracks bridge process status (CAN→MQTT and MQTT→CAN)
- Automatically restarts failed processes
- Reports status via MQTT topics (`can/status`)
- Provides process monitoring with automatic cleanup on failure

## Support

For issues, feature requests, or contributions:
https://github.com/Backroads4Me/HA_CAN_MQTT_BRIDGE/issues

## License

MIT License - see [LICENSE](LICENSE) file for details

---

Built with ❤️ for Home Assistant
