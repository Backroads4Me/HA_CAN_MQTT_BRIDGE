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
- **Home Assistant Integration**: Exposes CAN bus data as Home Assistant entities

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

| Option              | Default      | Description                                      |
| ------------------- | ------------ | ------------------------------------------------ |
| `can_interface`     | `can0`       | CAN interface name                               |
| `can_bitrate`       | `250000`     | CAN bitrate (125000, 250000, 500000, or 1000000) |
| `mqtt_host`         | `127.0.0.1`  | MQTT broker hostname or IP                       |
| `mqtt_port`         | `1883`       | MQTT broker port                                 |
| `mqtt_user`         | `canbus`     | MQTT broker username                             |
| `mqtt_pass`         | ``           | MQTT broker password                             |
| `mqtt_topic_raw`    | `can/raw`    | Topic for raw CAN frames                         |
| `mqtt_topic_send`   | `can/send`   | Topic to send CAN frames                         |
| `mqtt_topic_status` | `can/status` | Topic for bridge status                          |
| `debug_logging`     | `false`      | Enable verbose debug logging                     |

The add-on uses the following advanced features:

- **S6-Overlay**: For robust process management
- **Health Checks**: Automatic monitoring of bridge processes
- **Home Assistant API**: Integration with Home Assistant core

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

The add-on creates comprehensive logs in two locations:

1. **Home Assistant Logs**: Available in the add-on log viewer
2. **Dedicated Log File**: `/share/ha_can_mqtt_bridge.log` for detailed troubleshooting

Logs include:

- CAN interface initialization status
- MQTT connection status
- Bridge process monitoring
- CAN frame transmission details
- Error messages and reconnection attempts
- `bridge_online`: Bridge is running
- `bridge_offline`: Bridge has stopped

## CAN Frame Format

CAN frames use the standard format: `ID#DATA`

- `ID`: Hexadecimal CAN identifier (3 or 8 digits)
- `DATA`: Hexadecimal data payload (0-16 hex digits)

Examples:

- `123#DEADBEEF` - Standard ID with 4 bytes of data
- `18FEF017#0102030405060708` - Extended ID with 8 bytes

## Requirements

### Hardware

- CAN interface hardware (CAN HAT, USB-CAN adapter, etc.)
- Properly configured CAN interface in Home Assistant OS

### Software

- Home Assistant OS with CAN support enabled
- MQTT broker (Mosquitto add-on recommended)

## Troubleshooting

### Common Issues

**CAN interface not found:**

- Verify CAN hardware is connected
- Check that CAN drivers are loaded in HAOS
- Confirm interface name matches configuration

**MQTT connection failed:**

- Verify MQTT broker is running
- Check credentials and network connectivity
- Ensure MQTT topics don't conflict with other services

**Bridge disconnections:**

- Check system logs for error messages
- Enable debug logging for more details
- Verify CAN bus termination and wiring

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

### Sensors

The add-on automatically creates the following entities in Home Assistant:

- **sensor.can_bridge_status**: Shows the current status of the CAN bridge (online/offline)
- **sensor.can_message_count**: Counts the number of CAN messages processed

### Service Discovery

The add-on uses Home Assistant's service discovery to automatically find and connect to the MQTT broker, eliminating the need for manual configuration in most cases.

### Web Interface

Access the add-on's status page directly through Home Assistant's UI using the Ingress feature, providing a secure way to monitor the CAN bridge without exposing additional ports.

## Health Checks

The add-on includes automatic health monitoring that:

- Verifies CAN interface status
- Monitors MQTT connection
- Checks bridge processes
- Reports status via MQTT and Docker health checks
- Updates Home Assistant entities with current status

## Support

For issues, feature requests, or contributions:
https://github.com/Backroads4Me/HA_CAN_MQTT_BRIDGE/issues

## License

MIT License - see [LICENSE](LICENSE) file for details

---

Built with ❤️ for Home Assistant
