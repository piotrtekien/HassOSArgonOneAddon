#!/usr/bin/with-contenv bashio
set -euo pipefail

# -----------------------------------------------------------------------------
# Utility Functions
# -----------------------------------------------------------------------------

# Convert a number to a floating point string if needed.
mkfloat() {
  local str="$1"
  if [[ "$str" != *"."* ]]; then
    str="${str}.0"
  fi
  echo "$str"
}

# Compare two floating point numbers.
fcomp() {
  local oldIFS="$IFS" op="$2" x y digitx digity
  IFS='.'
  x=( ${1##+([0]|[-]|[+])} )
  y=( ${3##+([0]|[-]|[+])} )
  IFS="$oldIFS"
  while [[ "${x[1]}${y[1]}" =~ [^0] ]]; do
      digitx=${x[1]:0:1}
      digity=${y[1]:0:1}
      (( x[0] = x[0] * 10 + ${digitx:-0} , y[0] = y[0] * 10 + ${digity:-0} ))
      x[1]=${x[1]:1} y[1]=${y[1]:1}
  done
  [[ ${1:0:1} == '-' ]] && (( x[0] *= -1 ))
  [[ ${3:0:1} == '-' ]] && (( y[0] *= -1 ))
  (( "${x:-0}" "$op" "${y:-0}" ))
}

# -----------------------------------------------------------------------------
# I2C Port Detection (with optional override)
# -----------------------------------------------------------------------------
calibrateI2CPort() {
  local i2c_override
  i2c_override=$(jq -r '."I2C Port Override"' < /data/options.json)
  if [[ "$i2c_override" != "null" && "$i2c_override" != "255" ]]; then
    echo "Using I2C Port Override: $i2c_override"
    thePort="$i2c_override"
    return 0
  fi
  if [ -z "$(ls /dev/i2c-*)" ]; then
    echo "Cannot find I2C port. You must enable I2C for this add-on to operate properly."
    sleep 999999
    exit 1
  fi
  for device in /dev/i2c-*; do 
    local port=${device:9}
    echo "Checking I2C port ${port} at ${device}"
    local detection
    detection=$(i2cdetect -y "${port}")
    echo "${detection}"
    if [[ "${detection}" == *"10: -- -- -- -- -- -- -- -- -- -- 1a -- -- -- -- --"* ]] || \
       [[ "${detection}" == *"10: -- -- -- -- -- -- -- -- -- -- -- 1b -- -- -- --"* ]]; then
      thePort="${port}"
      echo "Found ArgonOne V3 at $device"
      return 0
    fi
    echo "Not found on ${device}"
  done
  thePort=255
  return 1
}

# -----------------------------------------------------------------------------
# Fan Speed Reporting for Home Assistant
# -----------------------------------------------------------------------------
fanSpeedReport() {
  local fanPercent="$1"
  local fanMode="$2"
  local cpuTemp="$3"
  local unit="$4"
  local icon="$5"
  local reqBody
  reqBody='{"state": "'"${fanPercent}"'", "attributes": { "unit_of_measurement": "%", "icon": "'"${icon}"'", "mode": "'"${fanMode}"'", "Temperature '"${unit}"'": "'"${cpuTemp}"'", "friendly_name": "Argon Fan Speed"}}'
  exec 3<>/dev/tcp/hassio/80
  echo -ne "POST /homeassistant/api/states/sensor.argon_one_addon_fan_speed HTTP/1.1\r\n" >&3
  echo -ne "Connection: close\r\n" >&3
  echo -ne "Authorization: Bearer ${SUPERVISOR_TOKEN}\r\n" >&3
  echo -ne "Content-Length: $(echo -ne "${reqBody}" | wc -c)\r\n" >&3
  echo -ne "\r\n" >&3
  echo -ne "${reqBody}" >&3
  local timeout=5
  while read -t "${timeout}" -r line; do :; done <&3
  exec 3>&-
}

# -----------------------------------------------------------------------------
# Fan Ramping: Gradually change speed between two values.
# -----------------------------------------------------------------------------
rampFanSpeed() {
  local current="$1"
  local target="$2"
  local rampDelay
  rampDelay=$(jq -r '."Fan Ramping Delay (seconds)"' < /data/options.json)
  rampDelay=${rampDelay:-0}
  if [ "$rampDelay" -le 0 ] || [ "$current" -eq "$target" ]; then
    echo "$target"
    return
  fi
  local step=1
  if [ "$current" -lt "$target" ]; then
    while [ "$current" -lt "$target" ]; do
      current=$((current + step))
      actionSetFan "$current"
      sleep "$rampDelay"
    done
  else
    while [ "$current" -gt "$target" ]; do
      current=$((current - step))
      actionSetFan "$current"
      sleep "$rampDelay"
    done
  fi
  echo "$target"
}

# -----------------------------------------------------------------------------
# Set Fan Speed (common for both modes)
# -----------------------------------------------------------------------------
actionSetFan() {
  local fanPercent="$1"
  if [ "$fanPercent" -lt 0 ]; then fanPercent=0; fi
  if [ "$fanPercent" -gt 100 ]; then fanPercent=100; fi
  local fanHex
  if [ "$fanPercent" -lt 10 ]; then
    fanHex=$(printf '0x0%x' "$fanPercent")
  else
    fanHex=$(printf '0x%x' "$fanPercent")
  fi
  echo "$(date '+%Y-%m-%d_%H:%M:%S'): Setting fan speed to ${fanPercent}% (hex: ${fanHex})"
  i2cset -y "${thePort}" 0x01a 0x80 "${fanHex}"
}

# -----------------------------------------------------------------------------
# Fluid Mode Action: Discrete fan steps based on thresholds.
# -----------------------------------------------------------------------------
actionFluid() {
  local fanLevel="$1"
  local fanPercent="$2"
  local fanMode="$3"
  local cpuTemp="$4"
  local unit="$5"
  echo "$(date '+%Y-%m-%d_%H:%M:%S'): ${cpuTemp}${unit} - Level ${fanLevel} - Fan ${fanPercent}% (${fanMode})"
  actionSetFan "$fanPercent"
  local createEntity
  createEntity=$(jq -r '."Create a Fan Speed Entity in Home Assistant"' < /data/options.json)
  if [ "$createEntity" == "true" ]; then
    fanSpeedReport "$fanPercent" "$fanMode" "$cpuTemp" "$unit" "mdi:fan"
  fi
}

# -----------------------------------------------------------------------------
# Linear Mode Action: Continuous mapping of temperature to fan speed.
# -----------------------------------------------------------------------------
actionLinear() {
  local fanPercent="$1"
  local cpuTemp="$2"
  local unit="$3"
  echo "$(date '+%Y-%m-%d_%H:%M:%S'): ${cpuTemp}${unit} - Fan ${fanPercent}%"
  actionSetFan "$fanPercent"
  local createEntity
  createEntity=$(jq -r '."Create a Fan Speed Entity in Home Assistant"' < /data/options.json)
  if [ "$createEntity" == "true" ]; then
    fanSpeedReport "$fanPercent" "Linear" "$cpuTemp" "$unit" "mdi:fan"
  fi
}

# -----------------------------------------------------------------------------
# Load Configuration Options
# -----------------------------------------------------------------------------
TemperatureUnit=$(jq -r '."Temperature Unit"' < /data/options.json)
Mode=$(jq -r '."Mode"' < /data/options.json)
UpdateInterval=$(jq -r '."Update Interval (seconds)"' < /data/options.json)
LogTemp=$(jq -r '."Log Temperature"' < /data/options.json)
Diagnostics=$(jq -r '."Diagnostics Mode"' < /data/options.json)

# Default Safety Fan Speed
SafetyFanSpeed=$(jq -r '."Safety Fan Speed (%)"' < /data/options.json)
if [ -z "$SafetyFanSpeed" ] || [ "$SafetyFanSpeed" == "null" ]; then
  SafetyFanSpeed=100
fi

# Manual Fan Speed Override: (-1 disables override)
ManualOverride=$(jq -r '."Manual Fan Speed Override"' < /data/options.json)
if [ -z "$ManualOverride" ] || [ "$ManualOverride" == "null" ]; then
  ManualOverride=-1
fi

# Normalize Mode input (must be either LINEAR or FLUID)
Mode=$(echo "$Mode" | awk '{print toupper($0)}')
if [ "$Mode" != "LINEAR" ] && [ "$Mode" != "FLUID" ]; then
  echo "Invalid Mode specified. Defaulting to LINEAR."
  Mode="LINEAR"
fi

# -----------------------------------------------------------------------------
# Initialization: Detect I2C port and prepare device
# -----------------------------------------------------------------------------
calibrateI2CPort
if [ "$thePort" == "255" ]; then
  echo "Argon One V3 was not detected on I2C. Entering safe mode."
  i2cset -y "${thePort}" 0x01a 0x63
  exit 1
fi
echo "I2C Port ${thePort}"

# On error, set fan to SafetyFanSpeed.
trap 'echo "Error encountered at line ${LINENO}: ${BASH_COMMAND}"; actionSetFan "${SafetyFanSpeed}"; exit 1' ERR EXIT INT TERM

# -----------------------------------------------------------------------------
# Main Loop
# -----------------------------------------------------------------------------
currentFanSpeed=0
cycleCount=0
while true; do
  # Read CPU temperature (in millidegrees Celsius)
  if ! read -r cpuRawTemp < /sys/class/thermal/thermal_zone0/temp; then
    echo "Error reading CPU temperature."
    sleep "$UpdateInterval"
    continue
  fi
  cpuTemp=$(( cpuRawTemp / 1000 ))
  unit="C"
  if [ "$TemperatureUnit" == "F" ]; then
    cpuTemp=$(( (cpuTemp * 9 / 5) + 32 ))
    unit="F"
  fi
  if [ "$LogTemp" == "true" ]; then
    echo "$(date '+%Y-%m-%d_%H:%M:%S'): Current Temperature = ${cpuTemp}°${unit}"
  fi

  # Check for Manual Override (if set to a value ≥ 0)
  if [ "$ManualOverride" -ge 0 ]; then
    if [ "$ManualOverride" -ne "$currentFanSpeed" ]; then
      echo "Manual Fan Speed Override activated: ${ManualOverride}%"
      currentFanSpeed=$(rampFanSpeed "$currentFanSpeed" "$ManualOverride")
    fi
  else
    if [ "$Mode" == "LINEAR" ]; then
      # Linear mode: calculate fan speed with a linear formula.
      tmini=$(jq -r '."Minimum Temperature"' < /data/options.json)
      tmaxi=$(jq -r '."Maximum Temperature"' < /data/options.json)
      if [ "$tmaxi" -eq "$tmini" ]; then
        echo "Error: Minimum Temperature equals Maximum Temperature in Linear mode."
        sleep "$UpdateInterval"
        continue
      fi
      a=$(( 100 / (tmaxi - tmini) ))
      b=$(( -a * tmini ))
      fanPercent=$(( a * cpuTemp + b ))
      if [ "$fanPercent" -lt 0 ]; then fanPercent=0; fi
      if [ "$fanPercent" -gt 100 ]; then fanPercent=100; fi
      if [ "$currentFanSpeed" -ne "$fanPercent" ]; then
        currentFanSpeed=$(rampFanSpeed "$currentFanSpeed" "$fanPercent")
        actionLinear "$currentFanSpeed" "$cpuTemp" "$unit"
      fi
    else
      # Fluid mode: determine fan level based on temperature thresholds.
      t1=$(jq -r '."Low Temperature Threshold"' < /data/options.json)
      t2=$(jq -r '."Medium Temperature Threshold"' < /data/options.json)
      t3=$(jq -r '."High Temperature Threshold"' < /data/options.json)
      quiet=$(jq -r '."Quiet Profile (Fluid Mode)"' < /data/options.json)
      if fcomp "$(mkfloat "$cpuTemp")" '<=' "$(mkfloat "$t1")"; then
        fanLevel=1
        fanMode="OFF"
        fanPercent=0
      elif fcomp "$(mkfloat "$cpuTemp")" '>=' "$(mkfloat "$t1")" && fcomp "$(mkfloat "$cpuTemp")" '<=' "$(mkfloat "$t2")"; then
        fanLevel=2
        if [ "$quiet" == "true" ]; then
          fanMode="Quiet Low"
          fanPercent=1
        else
          fanMode="Low"
          fanPercent=33
        fi
      elif fcomp "$(mkfloat "$cpuTemp")" '>=' "$(mkfloat "$t2")" && fcomp "$(mkfloat "$cpuTemp")" '<=' "$(mkfloat "$t3")"; then
        fanLevel=3
        if [ "$quiet" == "true" ]; then
          fanMode="Quiet Medium"
          fanPercent=3
        else
          fanMode="Medium"
          fanPercent=66
        fi
      else
        fanLevel=4
        fanMode="High"
        fanPercent=100
      fi
      if [ "$currentFanSpeed" -ne "$fanPercent" ]; then
        currentFanSpeed=$(rampFanSpeed "$currentFanSpeed" "$fanPercent")
        actionFluid "$fanLevel" "$currentFanSpeed" "$fanMode" "$cpuTemp" "$unit"
      fi
    fi
  fi

  # Every 10 minutes (based on the update interval) report fan status.
  if [ $((cycleCount % (600 / UpdateInterval))) -eq 0 ]; then
    if [ "$Mode" == "LINEAR" ]; then
      fanSpeedReport "$currentFanSpeed" "Linear" "$cpuTemp" "$unit" "mdi:fan"
    else
      fanSpeedReport "$currentFanSpeed" "$fanMode" "$cpuTemp" "$unit" "mdi:fan"
    fi
  fi

  if [ "$Diagnostics" == "true" ]; then
    echo "Diagnostics: Mode=${Mode}, CurrentFanSpeed=${currentFanSpeed}, CPU Temperature=${cpuTemp}°${unit}"
  fi

  sleep "$UpdateInterval"
  cycleCount=$((cycleCount + 1))
done
