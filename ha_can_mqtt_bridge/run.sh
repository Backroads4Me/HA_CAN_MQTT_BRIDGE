#!/usr/bin/with-contenv bashio
# CAN to MQTT Bridge Main Script

set -e

# Ensure we're running as s6 service
if [ -z "${S6_SERVICE_PATH+x}" ]; then
  bashio::log.warning "This script is designed to run as an s6 service"
fi

# Create health check file directory
mkdir -p /var/run/s6/healthcheck

# ========================
# Configuration Loading
# ========================
CAN_INTERFACE=$(bashio::config 'can_interface')
CAN_BITRATE=$(bashio::config 'can_bitrate')

# Try to use service discovery for MQTT broker
if bashio::services.available "mqtt"; then
    bashio::log.info "MQTT service discovered"
    MQTT_HOST=$(bashio::services "mqtt" "host")
    MQTT_PORT=$(bashio::services "mqtt" "port")
    MQTT_USER=$(bashio::services "mqtt" "username")
    MQTT_PASS=$(bashio::services "mqtt" "password")
else
    # Fall back to manual configuration
    bashio::log.info "Using manual MQTT configuration"
    MQTT_HOST=$(bashio::config 'mqtt_host')
    MQTT_PORT=$(bashio::config 'mqtt_port')
    MQTT_USER=$(bashio::config 'mqtt_user')
    MQTT_PASS=$(bashio::config 'mqtt_pass')
fi
MQTT_TOPIC_RAW=$(bashio::config 'mqtt_topic_raw')
MQTT_TOPIC_SEND=$(bashio::config 'mqtt_topic_send')
MQTT_TOPIC_STATUS=$(bashio::config 'mqtt_topic_status')
DEBUG_LOGGING=$(bashio::config 'debug_logging')
SSL=$(bashio::config 'ssl')
PASSWORD=$(bashio::config 'password')

# Security settings
MQTT_SSL_ARGS=""
if [ "$SSL" = "true" ]; then
    MQTT_SSL_ARGS="--cafile /etc/ssl/certs/ca-certificates.crt --tls-version tlsv1.2"
    bashio::log.info "SSL enabled for MQTT connections"
fi

# Password protection
if [ -n "$PASSWORD" ]; then
    bashio::log.info "Password protection enabled"
fi

# Global process tracking
CAN_TO_MQTT_PID=""
MQTT_TO_CAN_PID=""

# ========================
# Configuration Validation
# ========================
validate_config() {
    bashio::log.info "Validating configuration..."

    # Validate MQTT connection parameters
    if [[ -z "$MQTT_HOST" ]]; then
        bashio::log.fatal "MQTT host is required"
        return 1
    fi

    # Validate MQTT port
    if ! [[ "$MQTT_PORT" =~ ^[0-9]+$ ]] || [ "$MQTT_PORT" -lt 1 ] || [ "$MQTT_PORT" -gt 65535 ]; then
        bashio::log.fatal "Invalid MQTT port: $MQTT_PORT"
        return 1
    fi

    bashio::log.info "✅ Configuration validation passed"
    return 0
}

# ========================
# CAN Interface Validation (after initialization)
# ========================
validate_can_interface() {
    bashio::log.info "Validating CAN interface after initialization..."

    # Check if CAN interface exists and is up
    if ! ip link show | grep -q "$CAN_INTERFACE"; then
        bashio::log.fatal "CAN interface $CAN_INTERFACE does not exist after initialization"
        return 1
    fi

    # Verify interface is operational
    if ! ip link show "$CAN_INTERFACE" | grep -q "UP"; then
        bashio::log.fatal "CAN interface $CAN_INTERFACE failed to initialize properly"
        return 1
    fi

    bashio::log.info "✅ CAN interface validation passed"
    return 0
}

# ========================
# Health Check Function
# ========================
update_health_check() {
    local status=$1
    echo "$status" > /var/run/s6/healthcheck/status
    
    # Also publish to MQTT if we're online
    if [ "$status" = "OK" ]; then
        mosquitto_pub -h "$MQTT_HOST" -p "$MQTT_PORT" $MQTT_AUTH_ARGS \
                     -t "$MQTT_TOPIC_STATUS" -m "bridge_healthy" -q 1 -r 2>/dev/null || true
    fi
}

# ========================
# Home Assistant Integration
# ========================
create_ha_sensors() {
    bashio::log.info "Creating Home Assistant sensor entities..."
    
    # Create CAN bus status sensor
    if bashio::supervisor.ping; then
        bashio::api.supervisor POST /core/api/states/sensor.can_bridge_status << EOF
        {
            "state": "online",
            "attributes": {
                "friendly_name": "CAN Bridge Status",
                "device_class": "connectivity",
                "icon": "mdi:car-connected"
            }
        }
EOF
        
        # Create CAN bus message count sensor
        bashio::api.supervisor POST /core/api/states/sensor.can_message_count << EOF
        {
            "state": "0",
            "attributes": {
                "friendly_name": "CAN Messages Processed",
                "unit_of_measurement": "messages",
                "icon": "mdi:counter"
            }
        }
EOF
        
        bashio::log.info "✅ Home Assistant sensors created"
    else
        bashio::log.warning "⚠️ Could not create Home Assistant sensors - API not available"
    fi
}

# Function to update Home Assistant sensors
update_ha_sensor() {
    local entity_id=$1
    local state=$2
    local attributes=$3
    
    if bashio::supervisor.ping; then
        bashio::api.supervisor POST /core/api/states/${entity_id} << EOF
        {
            "state": "${state}",
            "attributes": ${attributes}
        }
EOF
    fi
}

# ========================
# Logging Functions
# ========================
log_debug() {
    if [ "$DEBUG_LOGGING" = "true" ]; then
        bashio::log.debug "$1"
    fi
}

# ========================
# Cleanup Function
# ========================
cleanup() {
    bashio::log.info "Shutdown signal received. Cleaning up..."
    
    # Kill background processes
    if [ -n "$CAN_TO_MQTT_PID" ] && kill -0 "$CAN_TO_MQTT_PID" 2>/dev/null; then
        bashio::log.info "Stopping CAN->MQTT bridge (PID: $CAN_TO_MQTT_PID)"
        kill -TERM "$CAN_TO_MQTT_PID" 2>/dev/null || true
    fi
    
    if [ -n "$MQTT_TO_CAN_PID" ] && kill -0 "$MQTT_TO_CAN_PID" 2>/dev/null; then
        bashio::log.info "Stopping MQTT->CAN bridge (PID: $MQTT_TO_CAN_PID)"
        kill -TERM "$MQTT_TO_CAN_PID" 2>/dev/null || true
    fi
    
    # Stop web server if running
    if [ -n "$WEB_SERVER_PID" ] && kill -0 "$WEB_SERVER_PID" 2>/dev/null; then
        bashio::log.info "Stopping web server (PID: $WEB_SERVER_PID)"
        kill -TERM "$WEB_SERVER_PID" 2>/dev/null || true
    fi
    
    # Publish offline status
    mosquitto_pub -h "$MQTT_HOST" -p "$MQTT_PORT" \
                  ${MQTT_USER:+-u "$MQTT_USER"} ${MQTT_PASS:+-P "$MQTT_PASS"} \
                  -t "$MQTT_TOPIC_STATUS" -m "bridge_offline" -q 1 -r 2>/dev/null || true
    
    # Bring down CAN interface
    ip link set "$CAN_INTERFACE" down 2>/dev/null || true
    
    bashio::log.info "Cleanup completed"
    exit 0
}

# Set up signal handlers
trap cleanup SIGTERM SIGINT SIGQUIT

# ========================
# Startup Banner
# ========================
bashio::log.info "=== CAN to MQTT Bridge Starting ==="
bashio::log.info "CAN Interface: $CAN_INTERFACE @ ${CAN_BITRATE} bps"
bashio::log.info "MQTT Broker: $MQTT_HOST:$MQTT_PORT"
bashio::log.info "MQTT User: ${MQTT_USER:-'(none)'}"
bashio::log.info "Topics - Raw: $MQTT_TOPIC_RAW, Send: $MQTT_TOPIC_SEND, Status: $MQTT_TOPIC_STATUS"
echo

# ========================
# CAN Interface Initialization
# ========================
bashio::log.info "Initializing CAN interface..."

# Load CAN kernel modules (similar to HA_EnableCAN)
bashio::log.info "Loading CAN kernel modules..."
modprobe can 2>/dev/null || bashio::log.info "CAN module already loaded or not needed"
modprobe can_raw 2>/dev/null || bashio::log.info "CAN_RAW module already loaded or not needed"

# Bring interface down first (ignore errors if already down)
ip link set "$CAN_INTERFACE" down 2>/dev/null || {
    bashio::log.info "Interface $CAN_INTERFACE was not up (this is normal on first run)"
}

# Configure CAN interface bitrate
log_debug "Setting CAN bitrate to $CAN_BITRATE"
if ! ip link set "$CAN_INTERFACE" type can bitrate "$CAN_BITRATE"; then
    bashio::log.fatal "Failed to set CAN bitrate for $CAN_INTERFACE. Please ensure:"
    bashio::log.fatal "  1. CAN hardware is connected (USB-CAN adapter, CAN HAT, etc.)"
    bashio::log.fatal "  2. Hardware is recognized by the system"
    bashio::log.fatal "  3. Correct interface name is configured"
    exit 1
fi

# Bring interface up
log_debug "Bringing CAN interface up"
if ! ip link set "$CAN_INTERFACE" up; then
    bashio::log.fatal "Failed to bring CAN interface up. Check hardware connection."
    exit 1
fi

bashio::log.info "✅ CAN interface $CAN_INTERFACE initialized successfully at ${CAN_BITRATE} bps"

# ========================
# MQTT Connection Test
# ========================
bashio::log.info "Testing MQTT connection..."

MQTT_AUTH_ARGS=""
[ -n "$MQTT_USER" ] && MQTT_AUTH_ARGS="$MQTT_AUTH_ARGS -u $MQTT_USER"
[ -n "$MQTT_PASS" ] && MQTT_AUTH_ARGS="$MQTT_AUTH_ARGS -P $MQTT_PASS"

if mosquitto_pub -h "$MQTT_HOST" -p "$MQTT_PORT" $MQTT_AUTH_ARGS \
   -t "$MQTT_TOPIC_STATUS" -m "bridge_starting" -q 1 >/dev/null 2>&1; then
    bashio::log.info "✅ MQTT connection successful"
else
    bashio::log.fatal "❌ MQTT connection failed - check broker settings and credentials"
    exit 1
fi

# ========================
# Home Assistant API Check
# ========================
bashio::log.info "Checking Home Assistant API connection..."
if bashio::supervisor.ping; then
    bashio::log.info "✅ Home Assistant API connection successful"
else
    bashio::log.warning "⚠️ Home Assistant API connection failed - some features may be limited"
fi

# Run configuration validation
if ! validate_config; then
    bashio::log.fatal "Configuration validation failed. Exiting."
    exit 1
fi

# Run CAN interface validation after initialization
if ! validate_can_interface; then
    bashio::log.fatal "CAN interface validation failed. Exiting."
    exit 1
fi

# Create Home Assistant sensors
create_ha_sensors

# ========================
# Start Bridge Processes
# ========================

# CAN -> MQTT Bridge (with error handling and reconnection)
bashio::log.info "Starting CAN->MQTT bridge..."
{
    while true; do
        log_debug "Starting candump process"
        candump -L "$CAN_INTERFACE" 2>/dev/null | awk '{print $3}' | \
        while IFS= read -r frame; do
            if [ -n "$frame" ]; then
                log_debug "CAN->MQTT: $frame"
                echo "$frame"
                
                # Increment message counter in Home Assistant
                if bashio::supervisor.ping; then
                    # Get current count
                    local current_count=$(bashio::api.supervisor GET /core/api/states/sensor.can_message_count | jq -r '.state')
                    # Increment
                    local new_count=$((current_count + 1))
                    # Update sensor
                    update_ha_sensor "sensor.can_message_count" "$new_count" '{"friendly_name": "CAN Messages Processed", "unit_of_measurement": "messages", "icon": "mdi:counter"}'
                fi
            fi
        done | mosquitto_pub -h "$MQTT_HOST" -p "$MQTT_PORT" $MQTT_AUTH_ARGS \
                            -t "$MQTT_TOPIC_RAW" -q 1 -l
        
        bashio::log.warning "CAN->MQTT bridge disconnected, reconnecting in 5 seconds..."
        sleep 5
    done
} &
CAN_TO_MQTT_PID=$!
bashio::log.info "✅ CAN->MQTT bridge started (PID: $CAN_TO_MQTT_PID)"

# MQTT -> CAN Bridge (with error handling and reconnection)
bashio::log.info "Starting MQTT->CAN bridge..."
{
    while true; do
        log_debug "Starting mosquitto_sub process"
        mosquitto_sub -h "$MQTT_HOST" -p "$MQTT_PORT" $MQTT_AUTH_ARGS \
                      -t "$MQTT_TOPIC_SEND" -q 1 2>/dev/null | \
        while IFS= read -r message; do
            if [ -n "$message" ]; then
                log_debug "MQTT->CAN: $message"
                if cansend "$CAN_INTERFACE" "$message" 2>/dev/null; then
                    log_debug "Successfully sent CAN frame: $message"
                else
                    bashio::log.warning "Failed to send CAN frame: $message"
                fi
            fi
        done
        
        bashio::log.warning "MQTT->CAN bridge disconnected, reconnecting in 5 seconds..."
        sleep 5
    done
} &
MQTT_TO_CAN_PID=$!
bashio::log.info "✅ MQTT->CAN bridge started (PID: $MQTT_TO_CAN_PID)"

# ========================
# Announce Online Status
# ========================
sleep 2  # Give bridges time to start
mosquitto_pub -h "$MQTT_HOST" -p "$MQTT_PORT" $MQTT_AUTH_ARGS \
              -t "$MQTT_TOPIC_STATUS" -m "bridge_online" -q 1 -r

# ========================
# Start Ingress Web Server
# ========================
if bashio::var.true "$(bashio::addon.ingress)"; then
    bashio::log.info "Starting ingress web server..."
    
    # Create simple status page
    mkdir -p /var/www
    cat > /var/www/index.html << EOF
<!DOCTYPE html>
<html>
<head>
    <title>CAN to MQTT Bridge</title>
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <style>
        body { font-family: Arial, sans-serif; margin: 0; padding: 20px; }
        .status { padding: 10px; margin: 10px 0; border-radius: 4px; }
        .online { background-color: #d4edda; color: #155724; }
        .offline { background-color: #f8d7da; color: #721c24; }
        .card { background: white; border-radius: 8px; padding: 20px; margin: 10px 0; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
        h1 { color: #333; }
    </style>
</head>
<body>
    <h1>CAN to MQTT Bridge</h1>
    <div class="card">
        <h2>Status</h2>
        <div id="status" class="status online">Bridge is online</div>
    </div>
    <div class="card">
        <h2>Configuration</h2>
        <p><strong>CAN Interface:</strong> ${CAN_INTERFACE}</p>
        <p><strong>CAN Bitrate:</strong> ${CAN_BITRATE} bps</p>
        <p><strong>MQTT Broker:</strong> ${MQTT_HOST}:${MQTT_PORT}</p>
    </div>
</body>
</html>
EOF

    # Start simple web server
    cd /var/www
    python3 -m http.server 8099 &
    WEB_SERVER_PID=$!
    bashio::log.info "✅ Web server started (PID: $WEB_SERVER_PID)"
fi

bashio::log.info "🚀 CAN-MQTT Bridge is now running!"
bashio::log.info "Monitoring bridge processes. Press Ctrl+C or stop the add-on to shutdown."

# ========================
# Process Monitoring
# ========================
while true; do
    # Check if either process died
    if ! kill -0 "$CAN_TO_MQTT_PID" 2>/dev/null; then
        bashio::log.error "CAN->MQTT process died unexpectedly"
        update_health_check "UNHEALTHY: CAN->MQTT process died"
        cleanup
        exit 1
    fi
    
    if ! kill -0 "$MQTT_TO_CAN_PID" 2>/dev/null; then
        bashio::log.error "MQTT->CAN process died unexpectedly"
        update_health_check "UNHEALTHY: MQTT->CAN process died"
        cleanup
        exit 1
    fi
    
    # Update health check status
    update_health_check "OK"
    
    # Wait before next check
    sleep 10
done