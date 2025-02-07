#!/usr/bin/with-contenv bashio
# shellcheck shell=bash
# Upgraded Argon One V3 Fan Control Add-on
# Modes supported: linear, fluid, extended

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

# Compare two floating-point numbers using bash arithmetic.
fcomp() {
  local op="$2" x y digitx digity
  IFS='.' read -r -a x <<< "${1##+([0]|[-]|[+])}"
  IFS='.' read -r -a y <<< "${3##+([0]|[-]|[+])}"
  while [[ "${x[1]}${y[1]}" =~ [^0] ]]; do
    digitx=${x[1]:0:1}
    digity=${y[1]:0:1}
    (( x[0] = x[0] * 10 + ${digitx:-0}, y[0] = y[0] * 10 + ${digity:-0} ))
    x[1]=${x[1]:1}
    y[1]=${y[1]:1}
  done
  [[ ${1:0:1} = '-' ]] && (( x[0] *= -1 ))
  [[ ${3:0:1} = '-' ]] && (( y[0] *= -1 ))
  case "$op" in
    '<')
      (( x[0] < y[0] ))
      return
      ;;
    '<=')
      (( x[0] <= y[0] ))
      return
      ;;
    '>')
      (( x[0] > y[0] ))
      return
      ;;
    '>=')
      (( x[0] >= y[0] ))
      return
      ;;
    '==')
      (( x[0] == y[0] ))
      return
      ;;
    '!=')
      (( x[0] != y[0] ))
      return
      ;;
    *)
      echo "Invalid operator: $op" >&2
      return 1
      ;;
  esac
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

# Set the fan speed via I2C; also reports the state if create_entity is true.
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

# Common settings from options.json
fan_control_mode=$(jq -r '."Fan Control Mode"' <options.json)
[ -z "$fan_control_mode" ] || [ "$fan_control_mode" = "null" ] && fan_control_mode="linear"

temp_unit=$(jq -r '."Celsius or Fahrenheit"' <options.json)
create_entity=$(jq -r '."Create a Fan Speed entity in Home Assistant"' <options.json)
log_temp=$(jq -r '."Log current temperature every 30 seconds"' <options.json)
update_interval=$(jq -r '."Update Interval"' <options.json)
[ -z "$update_interval" ] || [ "$update_interval" = "null" ] && update_interval=30

# For linear and fluid modes
min_temp=$(jq -r '."Minimum Temperature"' <options.json)
max_temp=$(jq -r '."Maximum Temperature"' <options.json)
fluid_sensitivity=$(jq -r '."Fluid Sensitivity"' <options.json)
[ -z "$fluid_sensitivity" ] && fluid_sensitivity=2.0

# For extended mode
ext_off=$(jq -r '."Extended Off Temperature"' <options.json)
ext_low=$(jq -r '."Extended Low Temperature"' <options.json)
ext_med=$(jq -r '."Extended Medium Temperature"' <options.json)
ext_high=$(jq -r '."Extended High Temperature"' <options.json)
ext_boost=$(jq -r '."Extended Boost Temperature"' <options.json)
quiet=$(jq -r '."Quiet Profile"' <options.json)

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

# Trap errors, INT, and TERM. (If you don’t want to trigger safe-mode on a clean exit, remove EXIT.)
trap 'echo "Error on line ${LINENO}: ${BASH_COMMAND}"; i2cset -y "$detected_port" "$device_address" 0x63; previous_fan_speed=-1; echo "Safe Mode Activated!"' ERR EXIT INT TERM

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

  #######################################
  # Calculate Fan Speed Based on Mode
  #######################################
  extra_info=""
  if [ "$fan_control_mode" = "linear" ]; then
    # Calculate a linear mapping from temperature to fan speed.
    slope=$(( 100 / (max_temp - min_temp) ))
    offset=$(( -slope * min_temp ))
    fan_speed_percent=$(( slope * cpu_temp + offset ))
    extra_info="(Linear Mode)"
  elif [ "$fan_control_mode" = "fluid" ]; then
    # Calculate using a non-linear (exponential) response.
    fan_speed_percent=$(awk -v t="$cpu_temp" -v tmin="$min_temp" -v tmax="$max_temp" -v exp="$fluid_sensitivity" 'BEGIN {
      ratio = (t - tmin) / (tmax - tmin);
      if (ratio < 0) ratio = 0;
      if (ratio > 1) ratio = 1;
      printf "%d", (ratio ^ exp) * 100;
    }')
    extra_info="(Fluid Mode, Sensitivity: ${fluid_sensitivity})"
  elif [ "$fan_control_mode" = "extended" ]; then
    # Extended mode uses multiple thresholds with quiet-mode adjustments.
    if fcomp "$(mk_float "$cpu_temp")" '<=' "$(mk_float "$ext_off")"; then
      fan_speed_percent=0
      extra_info="(Extended Mode: OFF)"
    elif fcomp "$(mk_float "$cpu_temp")" '<=' "$(mk_float "$ext_low")"; then
      if [ "$quiet" = "true" ]; then
        fan_speed_percent=1
      else
        fan_speed_percent=25
      fi
      extra_info="(Extended Mode: Low)"
    elif fcomp "$(mk_float "$cpu_temp")" '<=' "$(mk_float "$ext_med")"; then
      if [ "$quiet" = "true" ]; then
        fan_speed_percent=3
      else
        fan_speed_percent=50
      fi
      extra_info="(Extended Mode: Medium)"
    elif fcomp "$(mk_float "$cpu_temp")" '<=' "$(mk_float "$ext_high")"; then
      if [ "$quiet" = "true" ]; then
        fan_speed_percent=6
      else
        fan_speed_percent=75
      fi
      extra_info="(Extended Mode: High)"
    else
      if fcomp "$(mk_float "$cpu_temp")" '<' "$(mk_float "$ext_boost")"; then
        if [ "$quiet" = "true" ]; then
          fan_speed_percent=$(awk -v t="$cpu_temp" -v t_low="$ext_high" -v t_high="$ext_boost" 'BEGIN {
            printf "%d", 6 + ((t - t_low) / (t_high - t_low)) * (10 - 6);
          }')
        else
          fan_speed_percent=$(awk -v t="$cpu_temp" -v t_low="$ext_high" -v t_high="$ext_boost" 'BEGIN {
            printf "%d", 75 + ((t - t_low) / (t_high - t_low)) * 25;
          }')
        fi
      else
        fan_speed_percent=100
      fi
      extra_info="(Extended Mode: Boost)"
    fi
  else
    echo "Unknown Fan Control Mode: ${fan_control_mode}"
    exit 1
  fi

  #######################################
  # Send Fan Speed if Changed
  #######################################
  if [ "$previous_fan_speed" -ne "$fan_speed_percent" ]; then
    if ! set_fan_speed_generic "${fan_speed_percent}" "${extra_info}" "${cpu_temp}" "${unit}"; then
      fan_speed_percent="$previous_fan_speed"
    fi
    previous_fan_speed="${fan_speed_percent}"
  fi

  if [ $(( poll_count % entity_update_interval_count )) -eq 0 ] && [ "$create_entity" = "true" ]; then
    report_fan_speed "${fan_speed_percent}" "${cpu_temp}" "${unit}" "${extra_info}"
  fi

  sleep "${update_interval}"
  poll_count=$(( poll_count + 1 ))
done
