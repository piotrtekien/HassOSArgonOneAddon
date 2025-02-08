#!/usr/bin/with-contenv bashio
# shellcheck shell=bash
# =============================================================================
# ArgonOne V3 Master Cooling Add-on (Celsius Only)
#
# This script monitors the CPU temperature (in Celsius) and controls the
# Argon One fan via I2C accordingly.
#
# Author: Your Name
# Date: 2025-02-08
#
# Change Log:
#  - Refactored for clarity and robustness.
#  - Removed Fahrenheit support to focus solely on Celsius.
#  - Updated configuration keys to avoid spaces.
# =============================================================================

# -----------------------------------------------------------------------------
# Global Variables & Configuration
# -----------------------------------------------------------------------------

detected_port=""
device_address=""

# Load configuration values using bashio (ensure these keys match your config.yaml)
fan_control_mode=$(bashio::config 'fan_control_mode' 'linear')
# We always assume Celsius in this version; the temperature_unit key is ignored.
update_interval=$(bashio::config 'update_interval' 30)
log_temp=$(bashio::config 'log_temperature' true)
create_entity=$(bashio::config 'create_fan_entity' true)
min_temp=$(bashio::config 'min_temperature' 20)
max_temp=$(bashio::config 'max_temperature' 70)
fluid_sensitivity=$(bashio::config 'fluid_sensitivity' 2.0)
ext_off=$(bashio::config 'extended_off_temp' 20)
ext_low=$(bashio::config 'extended_low_temp' 30)
ext_med=$(bashio::config 'extended_med_temp' 40)
ext_high=$(bashio::config 'extended_high_temp' 50)
ext_boost=$(bashio::config 'extended_boost_temp' 60)
quiet=$(bashio::config 'quiet_profile' true)

# Default values if any configuration is missing
: "${min_temp:=20}"
: "${max_temp:=70}"
: "${fluid_sensitivity:=2.0}"
: "${ext_off:=20}"
: "${ext_low:=30}"
: "${ext_med:=40}"
: "${ext_high:=50}"
: "${ext_boost:=60}"

# -----------------------------------------------------------------------------
# Functions
# -----------------------------------------------------------------------------

# convert_temp: Since we are only supporting Celsius, just return the value.
#   Arguments:
#     $1 - Temperature (Celsius)
#   Returns:
#     The same temperature in Celsius.
convert_temp() {
  local temp="$1"
  echo "$temp"
}

# calibrate_i2c_port: Detects the proper I2C port for the Argon One device.
calibrate_i2c_port() {
  if ! compgen -G "/dev/i2c-*" > /dev/null; then
    bashio::log.error "I2C port not found. Please enable I2C for this add-on."
    sleep 999999
    exit 1
  fi

  for device in /dev/i2c-*; do
    local port="${device:9}"
    bashio::log.info "Checking I2C port ${port} at ${device}"
    local detection
    detection=$(i2cdetect -y "${port}")
    if [[ "$detection" == *"10: -- -- -- -- -- -- -- -- -- -- 1a -- -- -- -- --"* ]]; then
      device_address="0x1a"
      detected_port="${port}"
      bashio::log.info "Found Argon One V3 at ${device} (address ${device_address})"
      break
    elif [[ "$detection" == *"10: -- -- -- -- -- -- -- -- -- -- 1b -- -- -- --"* ]]; then
      device_address="0x1b"
      detected_port="${port}"
      bashio::log.info "Found Argon One V3 at ${device} (address ${device_address})"
      break
    fi
  done
}

# report_fan_speed: Sends the current fan speed state to Home Assistant.
#   Arguments:
#     $1 - Fan speed percentage.
#     $2 - CPU temperature (Celsius).
#     $3 - Extra information string.
report_fan_speed() {
  local fan_speed_percent="$1"
  local cpu_temp="$2"
  local extra_info="$3"
  local icon="mdi:fan"
  local friendly_name="Argon Fan Speed"
  [ -n "$extra_info" ] && friendly_name="${friendly_name} ${extra_info}"

  local reqBody
  reqBody=$(cat <<EOF
{"state": "${fan_speed_percent}", "attributes": { "unit_of_measurement": "%", "icon": "${icon}", "Temperature °C": "${cpu_temp}", "friendly_name": "${friendly_name}"}}
EOF
)
  reqBody=$(echo "$reqBody" | tr -d '\n')

  # Open TCP connection to Home Assistant and send the HTTP POST
  exec 3<>/dev/tcp/hassio/80
  echo -ne "POST /homeassistant/api/states/sensor.argon_one_addon_fan_speed HTTP/1.1\r\n" >&3
  echo -ne "Connection: close\r\n" >&3
  echo -ne "Authorization: Bearer ${SUPERVISOR_TOKEN}\r\n" >&3
  echo -ne "Content-Length: $(echo -n "${reqBody}" | wc -c)\r\n" >&3
  echo -ne "\r\n" >&3
  echo -ne "${reqBody}" >&3

  local timeout=5
  while read -t "${timeout}" -r _; do :; done <&3
  exec 3>&-
}

# set_fan_speed_generic: Adjusts the fan speed via I2C.
#   Arguments:
#     $1 - Fan speed percentage.
#     $2 - Extra information string.
#     $3 - CPU temperature (Celsius).
set_fan_speed_generic() {
  local fan_speed_percent="$1"
  local extra_info="$2"
  local cpu_temp="$3"

  # Clamp fan speed between 0 and 100%
  if (( fan_speed_percent < 0 )); then
    fan_speed_percent=0
  elif (( fan_speed_percent > 100 )); then
    fan_speed_percent=100
  fi

  local fan_speed_hex
  if (( fan_speed_percent < 10 )); then
    fan_speed_hex=$(printf '0x0%x' "${fan_speed_percent}")
  else
    fan_speed_hex=$(printf '0x%x' "${fan_speed_percent}")
  fi

  printf '%(%Y-%m-%d %H:%M:%S)T'
  echo ": ${cpu_temp}°C - Fan ${fan_speed_percent}% ${extra_info} | Hex: ${fan_speed_hex}"
  i2cset -y "$detected_port" "$device_address" "0x80" "${fan_speed_hex}"
  local ret_val=$?

  if [ "$create_entity" = "true" ]; then
    report_fan_speed "${fan_speed_percent}" "${cpu_temp}" "${extra_info}" &
  fi

  return ${ret_val}
}

# main: Primary loop for monitoring temperature and controlling fan speed.
main() {
  local previous_fan_speed=-1
  bashio::log.info "Detecting I2C layout, expecting to see '1a' or '1b'..."
  calibrate_i2c_port
  bashio::log.info "I2C Port: ${detected_port} | Device Address: ${device_address}"
  if [ -z "$detected_port" ] || [ "$detected_port" = "255" ]; then
    bashio::log.error "Argon One V3 not detected. Exiting."
    exit 1
  fi

  # Set error trap for safe shutdown
  trap 'bashio::log.error "Error on line ${LINENO}: ${BASH_COMMAND}"; i2cset -y "$detected_port" "$device_address" 0x63; previous_fan_speed=-1; bashio::log.error "Safe Mode Activated!"' ERR EXIT INT TERM

  local entity_update_interval_count=$(( 600 / update_interval ))
  local poll_count=0

  while true; do
    local cpu_raw_temp
    read -r cpu_raw_temp < /sys/class/thermal/thermal_zone0/temp
    # CPU raw temperature is in millidegrees; convert to Celsius.
    local cpu_temp=$(( cpu_raw_temp / 1000 ))
    cpu_temp=$(convert_temp "$cpu_temp")
    
    [ "$log_temp" = "true" ] && bashio::log.info "Current Temperature = ${cpu_temp}°C"

    local extra_info=""
    local fan_speed_percent=0

    # Determine fan speed based on the chosen mode
    case "$fan_control_mode" in
      linear)
        fan_speed_percent=$(( (100 / (max_temp - min_temp)) * (cpu_temp - min_temp) ))
        extra_info="(Linear Mode)"
        ;;
      fluid)
        fan_speed_percent=$(awk -v t="$cpu_temp" -v tmin="$min_temp" -v tmax="$max_temp" -v sensitivity="$fluid_sensitivity" 'BEGIN {
          ratio = (t - tmin) / (tmax - tmin);
          if (ratio < 0) ratio = 0;
          if (ratio > 1) ratio = 1;
          printf "%d", (ratio ^ sensitivity) * 100;
        }')
        extra_info="(Fluid Mode, Sensitivity: ${fluid_sensitivity})"
        ;;
      extended)
        if (( cpu_temp <= ext_off )); then
          fan_speed_percent=0
          extra_info="(Extended Mode: OFF)"
        elif (( cpu_temp <= ext_low )); then
          fan_speed_percent=15
          extra_info="(Extended Mode: Low)"
        elif (( cpu_temp <= ext_med )); then
          fan_speed_percent=30
          extra_info="(Extended Mode: Medium)"
        elif (( cpu_temp <= ext_high )); then
          fan_speed_percent=45
          extra_info="(Extended Mode: High)"
        else
          fan_speed_percent=60
          extra_info="(Extended Mode: Boost)"
        fi
        ;;
      *)
        bashio::log.warning "Unknown fan control mode: ${fan_control_mode}. Defaulting to linear."
        fan_speed_percent=$(( (100 / (max_temp - min_temp)) * (cpu_temp - min_temp) ))
        extra_info="(Linear Mode)"
        ;;
    esac

    # Apply Quiet Profile if enabled (limits maximum fan speed to 30%)
    if [ "$quiet" = "true" ]; then
      fan_speed_percent=$(( fan_speed_percent < 30 ? fan_speed_percent : 30 ))
      extra_info="${extra_info} | (Quiet Profile)"
    fi

    # Clamp fan speed to 0-100%
    if (( fan_speed_percent < 0 )); then
      fan_speed_percent=0
    elif (( fan_speed_percent > 100 )); then
      fan_speed_percent=100
    fi

    if [ "$previous_fan_speed" -ne "$fan_speed_percent" ]; then
      set_fan_speed_generic "$fan_speed_percent" "$extra_info" "$cpu_temp"
      previous_fan_speed="$fan_speed_percent"
    fi

    # Report fan speed every specified interval
    if [ $(( poll_count % entity_update_interval_count )) -eq 0 ] && [ "$create_entity" = "true" ]; then
      report_fan_speed "$fan_speed_percent" "$cpu_temp" "$extra_info"
    fi

    sleep "${update_interval}"
    poll_count=$(( poll_count + 1 ))
  done
}

# -----------------------------------------------------------------------------
# Script Entry Point
# -----------------------------------------------------------------------------
main
