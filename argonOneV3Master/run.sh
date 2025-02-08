#!/usr/bin/with-contenv bashio
# shellcheck shell=bash

#######################################
# Global Variables and Configurations
#######################################
detected_port=""
device_address=""

# Load all configurations using bashio
fan_control_mode=$(bashio::config 'fan_control_mode' 'linear')
temp_unit=$(bashio::config 'Celsius_or_Fahrenheit' 'C')
create_entity=$(bashio::config 'Create_a_Fan_Speed_entity_in_Home_Assistant' true)
log_temp=$(bashio::config 'Log_current_temperature_every_30_seconds' true)
update_interval=$(bashio::config 'Update_Interval' 30)
min_temp=$(bashio::config 'Minimum_Temperature' 20)
max_temp=$(bashio::config 'Maximum_Temperature' 70)
fluid_sensitivity=$(bashio::config 'Fluid_Sensitivity' 2.0)
ext_off=$(bashio::config 'Extended_Off_Temperature' 20)
ext_low=$(bashio::config 'Extended_Low_Temperature' 30)
ext_med=$(bashio::config 'Extended_Medium_Temperature' 40)
ext_high=$(bashio::config 'Extended_High_Temperature' 50)
ext_boost=$(bashio::config 'Extended_Boost_Temperature' 60)
quiet=$(bashio::config 'Quiet_Profile' true)

# Default value assignments if missing
[ -z "$ext_off" ] && ext_off=20
[ -z "$ext_low" ] && ext_low=30
[ -z "$ext_med" ] && ext_med=40
[ -z "$ext_high" ] && ext_high=50
[ -z "$ext_boost" ] && ext_boost=60
[ -z "$fluid_sensitivity" ] && fluid_sensitivity=2.0

# Temperature Conversion Function (Handles both Celsius and Fahrenheit)
convert_temp() {
  local temp="$1"
  if [ "$temp_unit" = "F" ]; then
    # Convert Celsius to Fahrenheit
    echo "$(( (temp * 9 / 5) + 32 ))"
  else
    # Convert Fahrenheit to Celsius
    echo "$(( (temp - 32) * 5 / 9 ))"
  fi
}

# I2C Port Calibration
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
      bashio::log.info "Found Argon One V3 device at ${device} (address ${device_address})"
      break
    elif [[ "$detection" == *"10: -- -- -- -- -- -- -- -- -- -- 1b -- -- -- --"* ]]; then
      device_address="0x1b"
      detected_port="${port}"
      bashio::log.info "Found Argon One V3 device at ${device} (address ${device_address})"
      break
    fi
  done
}

# Report Fan Speed State to Home Assistant
report_fan_speed() {
  local fan_speed_percent="$1"
  local cpu_temp="$2"
  local extra_info="$3"
  local icon="mdi:fan"
  local friendly_name="Argon Fan Speed"
  [ -n "$extra_info" ] && friendly_name="${friendly_name} ${extra_info}"

  local reqBody
  reqBody=$(cat <<EOF
{"state": "${fan_speed_percent}", "attributes": { "unit_of_measurement": "%", "icon": "${icon}", "Temperature ${temp_unit}": "${cpu_temp}", "friendly_name": "${friendly_name}"}}
EOF
)
  reqBody=$(echo "$reqBody" | tr -d '\n')
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

# Set Fan Speed via I2C
set_fan_speed_generic() {
  local fan_speed_percent="$1"
  local extra_info="$2"
  local cpu_temp="$3"
  local temp_unit="$4"

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
  echo ": ${cpu_temp}${temp_unit} - Fan ${fan_speed_percent}% ${extra_info} | Hex: ${fan_speed_hex}"
  i2cset -y "$detected_port" "$device_address" "0x80" "${fan_speed_hex}"
  local ret_val=$?
  if [ "$create_entity" = "true" ]; then
    report_fan_speed "${fan_speed_percent}" "${cpu_temp}" "${temp_unit}" "${extra_info}" &
  fi
  return ${ret_val}
}

#######################################
# Initialization and Main Loop
#######################################

previous_fan_speed=-1
echo "Detecting I2C layout, expecting to see '1a' or '1b'..."
calibrate_i2c_port
echo "I2C Port: ${detected_port} | Device Address: ${device_address}"
if [ -z "$detected_port" ] || [ "$detected_port" = "255" ]; then
  echo "Argon One V3 not detected. Exiting."
  exit 1
fi

# Trap Errors
trap 'echo "Error on line ${LINENO}: ${BASH_COMMAND}"; i2cset -y "$detected_port" "$device_address" 0x63; previous_fan_speed=-1; echo "Safe Mode Activated!"' ERR EXIT INT TERM

# Loop to Monitor and Control Fan Speed
entity_update_interval_count=$(( 600 / update_interval ))
poll_count=0

while true; do
  read -r cpu_raw_temp < /sys/class/thermal/thermal_zone0/temp
  cpu_temp=$(( cpu_raw_temp / 1000 ))

  # Convert temperature if needed
  cpu_temp=$(convert_temp "$cpu_temp" "$temp_unit")
  unit="$temp_unit"

  [ "$log_temp" = "true" ] && echo "Current Temperature = ${cpu_temp} °${unit}"

  # Adjust fan speed based on selected mode
  extra_info=""
  case "$fan_control_mode" in
    "linear")
      fan_speed_percent=$(( (100 / (max_temp - min_temp)) * (cpu_temp - min_temp) ))
      extra_info="(Linear Mode)"
      ;;
    "fluid")
      fan_speed_percent=$(awk -v t="$cpu_temp" -v tmin="$min_temp" -v tmax="$max_temp" -v exp="$fluid_sensitivity" 'BEGIN { ratio = (t - tmin) / (tmax - tmin); if (ratio < 0) ratio = 0; if (ratio > 1) ratio = 1; printf "%d", (ratio ^ exp) * 100; }')
      extra_info="(Fluid Mode, Sensitivity: ${fluid_sensitivity})"
      ;;
    "extended")
      if (( cpu_temp <= ext_off )); then
        fan_speed_percent=0
        extra_info="(Fluid Mode: OFF)"
      elif (( cpu_temp <= ext_low )); then
        fan_speed_percent=15
        extra_info="(Fluid Mode: Low)"
      elif (( cpu_temp <= ext_med )); then
        fan_speed_percent=30
        extra_info="(Fluid Mode: Medium)"
      elif (( cpu_temp <= ext_high )); then
        fan_speed_percent=45
        extra_info="(Fluid Mode: High)"
      else
        fan_speed_percent=60
        extra_info="(Fluid Mode: Boost)"
      fi
      ;;
  esac

  # Apply Quiet Profile if enabled
  if [ "$quiet" = "true" ]; then
    fan_speed_percent=$(( fan_speed_percent < 30 ? fan_speed_percent : 30 ))
    extra_info="${extra_info} | (Quiet Profile)"
  fi

  # Ensure fan speed stays within range
  if (( fan_speed_percent < 0 )); then
    fan_speed_percent=0
  elif (( fan_speed_percent > 100 )); then
    fan_speed_percent=100
  fi

  if [ "$previous_fan_speed" -ne "$fan_speed_percent" ]; then
    set_fan_speed_generic "$fan_speed_percent" "$extra_info" "$cpu_temp" "$unit"
    previous_fan_speed="$fan_speed_percent"
  fi

  # Report fan speed every specified interval
  if [ $(( poll_count % entity_update_interval_count )) -eq 0 ] && [ "$create_entity" = "true" ]; then
    report_fan_speed "$fan_speed_percent" "$cpu_temp" "$unit" "$extra_info"
  fi

  sleep "${update_interval}"
  poll_count=$(( poll_count + 1 ))
done
