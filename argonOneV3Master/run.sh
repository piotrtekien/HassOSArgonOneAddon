#!/usr/bin/with-contenv bashio
# shellcheck shell=bash

#######################################
# Global Variables
#######################################
detected_port=""
device_address=""  # Will be set to the detected I2C device address (e.g. 0x1a or 0x1b)

#######################################
# Utility Functions
#######################################

# Convert a value to a float (ensure a decimal point exists)
mk_float() {
  local str="$1"
  [[ "$str" == *"."* ]] || str="${str}.0"
  echo "$str"
}

# Scan for available I2C ports and set detected_port (and device_address) if a matching device is found.
calibrate_i2c_port() {
  if ! compgen -G "/dev/i2c-*" > /dev/null; then
    echo "ERROR: I2C port not found. Please enable I2C for this add-on." >&2
    sleep 999999
    exit 1
  fi
  for device in /dev/i2c-*; do 
    local port="${device:9}"
    echo "Checking I2C port ${port} at ${device}"
    local detection
    detection=$(i2cdetect -y "${port}")
    echo "${detection}"
    if [[ "${detection}" == *"10: -- -- -- -- -- -- -- -- -- -- 1a -- -- -- -- --"* ]]; then
      device_address="0x1a"
      detected_port="${port}"
      echo "Found Argon One V3 device at ${device} (address ${device_address})"
      break
    elif [[ "${detection}" == *"10: -- -- -- -- -- -- -- -- -- -- 1b -- -- -- --"* ]]; then
      device_address="0x1b"
      detected_port="${port}"
      echo "Found Argon One V3 device at ${device} (address ${device_address})"
      break
    fi
    echo "Device not found on ${device}"
  done
}

# Report the current fan speed state to Home Assistant.
report_fan_speed() {
  local fan_speed_percent="$1"
  local cpu_temp="$2"
  local temp_unit="$3"
  local extra_info="$4"
  local icon="mdi:fan"
  local friendly_name="Argon Fan Speed"
  [ -n "$extra_info" ] && friendly_name="${friendly_name} ${extra_info}"
  local reqBody
  reqBody=$(cat <<EOF
{"state": "${fan_speed_percent}", "attributes": { "unit_of_measurement": "%", "icon": "${icon}", "Temperature ${temp_unit}": "${cpu_temp}", "friendly_name": "${friendly_name}"}}
EOF
)
  # Remove newline characters to ensure a compact JSON payload.
  reqBody=$(echo "$reqBody" | tr -d '\n')
  exec 3<>/dev/tcp/hassio/80
  echo -ne "POST /homeassistant/api/states/sensor.argon_one_addon_fan_speed HTTP/1.1\r\n" >&3
  echo -ne "Connection: close\r\n" >&3
  echo -ne "Authorization: Bearer ${SUPERVISOR_TOKEN}\r\n" >&3
  echo -ne "Content-Length: $(echo -n "${reqBody}" | wc -c)\r\n" >&3
  echo -ne "\r\n" >&3
  echo -ne "${reqBody}" >&3
  local timeout=5
  while read -t "${timeout}" -r _; do
    :
  done <&3
  exec 3>&-
}

# Set the fan speed via I2C
set_fan_speed_generic() {
  local fan_speed_percent="$1"
  local extra_info="$2"
  local cpu_temp="$3"
  local temp_unit="$4"

  # Clamp fan speed between 0 and 100.
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

  # Print a timestamp and state message.
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
# Configuration Variables
#######################################

# Get configuration options from Home Assistant
fan_control_mode="${fan_control_mode:-linear}"
temp_unit=$(bashio::config 'Celsius or Fahrenheit')
create_entity=$(bashio::config 'Create a Fan Speed entity in Home Assistant')
log_temp=$(bashio::config 'Log current temperature every 30 seconds')
update_interval=$(bashio::config 'Update Interval')
min_temp=$(bashio::config 'Minimum Temperature')
max_temp=$(bashio::config 'Maximum Temperature')
fluid_sensitivity=$(bashio::config 'Fluid Sensitivity')
ext_off=$(bashio::config 'Extended Off Temperature')
ext_low=$(bashio::config 'Extended Low Temperature')
ext_med=$(bashio::config 'Extended Medium Temperature')
ext_high=$(bashio::config 'Extended High Temperature')
ext_boost=$(bashio::config 'Extended Boost Temperature')
quiet=$(bashio::config 'Quiet Profile')

# Default values if not set in the config
[ -z "$ext_off" ] && ext_off=20
[ -z "$ext_low" ] && ext_low=30
[ -z "$ext_med" ] && ext_med=40
[ -z "$ext_high" ] && ext_high=50
[ -z "$ext_boost" ] && ext_boost=60
[ -z "$fluid_sensitivity" ] && fluid_sensitivity=2.0

#######################################
# Initialization
#######################################

previous_fan_speed=-1

echo "Detecting I2C layout, expecting to see '1a' or '1b'..."
calibrate_i2c_port
echo "I2C Port: ${detected_port}  |  Device Address: ${device_address}"
if [ -z "$detected_port" ] || [ "$detected_port" = "255" ]; then
  echo "Argon One V3 not detected. Exiting."
  exit 1
fi

# Trap errors, INT, and TERM
trap 'echo "Error on line ${LINENO}: ${BASH_COMMAND}"; i2cset -y "$detected_port" "$device_address" 0x63; previous_fan_speed=-1; echo "Safe Mode Activated!"' ERR EXIT INT TERM

# Calculate how often we should update the entity based on the user-defined interval
entity_update_interval_count=$(( 600 / update_interval ))
poll_count=0

#######################################
# Main Loop
#######################################
while true; do
  read -r cpu_raw_temp < /sys/class/thermal/thermal_zone0/temp
  cpu_temp=$(( cpu_raw_temp / 1000 ))
  unit="C"
  if [ "$temp_unit" = "F" ]; then
    cpu_temp=$(( (cpu_temp * 9 / 5) + 32 ))
    unit="F"
  fi

  [ "$log_temp" = "true" ] && echo "Current Temperature = ${cpu_temp} °${unit}"

  # Fan control logic (linear, fluid, extended modes)
  extra_info=""
  if [ "$fan_control_mode" = "linear" ]; then
    slope=$(( 100 / (max_temp - min_temp) ))
    offset=$(( -slope * min_temp ))
    fan_speed_percent=$(( slope * cpu_temp + offset ))
    extra_info="(Linear Mode)"
  elif [ "$fan_control_mode" = "fluid" ]; then
    fan_speed_percent=$(awk -v t="$cpu_temp" -v tmin="$min_temp" -v tmax="$max_temp" -v exp="$fluid_sensitivity" 'BEGIN {
      ratio = (t - tmin) / (tmax - tmin);
      if (ratio < 0) ratio = 0;
      if (ratio > 1) ratio = 1;
      printf "%d", (ratio ^ exp) * 100;
    }')
    extra_info="(Fluid Mode, Sensitivity: ${fluid_sensitivity})"
  elif [ "$fan_control_mode" = "extended" ]; then
    if fcomp "$(mk_float "$cpu_temp")" '<=' "$(mk_float "$ext_off")"; then
      fan_speed_percent=0
      extra_info="(Extended Mode: OFF)"
    elif fcomp "$(mk_float "$cpu_temp")" '<=' "$(mk_float "$ext_low")"; then
      fan_speed_percent=25
      extra_info="(Extended Mode: Low)"
    elif fcomp "$(mk_float "$cpu_temp")" '<=' "$(mk_float "$ext_med")"; then
      fan_speed_percent=50
      extra_info="(Extended Mode: Medium)"
    elif fcomp "$(mk_float "$cpu_temp")" '<=' "$(mk_float "$ext_high")"; then
      fan_speed_percent=75
      extra_info="(Extended Mode: High)"
    else
      fan_speed_percent=100
      extra_info="(Extended Mode: Boost)"
    fi
  else
    echo "Unknown Fan Control Mode: ${fan_control_mode}"
    exit 1
  fi

  if [ "$previous_fan_speed" -ne "$fan_speed_percent" ]; then
    set_fan_speed_generic "${fan_speed_percent}" "${extra_info}" "${cpu_temp}" "${unit}"
    previous_fan_speed="${fan_speed_percent}"
  fi

  # Report fan speed at regular intervals
  if [ $(( poll_count % entity_update_interval_count )) -eq 0 ] && [ "$create_entity" = "true" ]; then
    report_fan_speed "${fan_speed_percent}" "${cpu_temp}" "${unit}" "${extra_info}"
  fi

  sleep "${update_interval}"
  poll_count=$(( poll_count + 1 ))
done
