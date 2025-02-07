#!/usr/bin/with-contenv bashio
set -euo pipefail

# -----------------------------------------------------------------------------
# Utility Functions
# -----------------------------------------------------------------------------

# Convert input to a float representation.
mkfloat() {
  local str="$1"
  if [[ "$str" != *"."* ]]; then
    str="${str}.0"
  fi
  echo "$str"
}

# Compare two floating-point numbers.
fcomp() {
  local oldIFS="$IFS" op="$2" x y digitx digity
  IFS='.'
  x=( ${1##+([0]|[-]|[+])} )
  y=( ${3##+([0]|[-]|[+])} )
  IFS="$oldIFS"
  while [[ "${x[1]}${y[1]}" =~ [^0] ]]; do
    digitx=${x[1]:0:1}
    digity=${y[1]:0:1}
    (( x[0] = x[0] * 10 + ${digitx:-0}, y[0] = y[0] * 10 + ${digity:-0} ))
    x[1]=${x[1]:1}
    y[1]=${y[1]:1}
  done
  [[ ${1:0:1} == '-' ]] && (( x[0] *= -1 ))
  [[ ${3:0:1} == '-' ]] && (( y[0] *= -1 ))
  (( "${x:-0}" "$op" "${y:-0}" ))
}

# -----------------------------------------------------------------------------
# I2C Port Detection (with optional override)
# -----------------------------------------------------------------------------
calibrateI2CPort() {
  local override
  override=$(jq -r '."I2C Port Override"' < /data/options.json)
  if [[ "$override" != "null" && "$override" != "255" ]]; then
    echo "Using I2C Port Override: $override"
    thePort="$override"
    return 0
  fi
  if [ -z "$(ls /dev/i2c-*)" ]; then
    echo "Cannot find I2C port. Enable I2C for this add-on to operate properly."
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
      echo "Found Argon device at ${device}"
      return 0
    fi
    echo "Not found on ${device}"
  done
  thePort=255
  return 1
}

# -----------------------------------------------------------------------------
# Fan Ramping: Gradually change speed between two values.
# -----------------------------------------------------------------------------
rampFanSpeed() {
  local current="$1"
  local target="$2"
  local delay
  delay=$(jq -r '."Fan Ramping Delay (seconds)"' < /data/options.json)
  delay=${delay:-0}
  if [ "$delay" -le 0 ] || [ "$current" -eq "$target" ]; then
    echo "$target"
    return
  fi
  local step=1
  if [ "$current" -lt "$target" ]; then
    while [ "$current" -lt "$target" ]; do
      current=$(( current + step ))
      actionSetFan "$current"
      sleep "$delay"
    done
  else
    while [ "$current" -gt "$target" ]; do
      current=$(( current - step ))
      actionSetFan "$current"
      sleep "$delay"
    done
  fi
  echo "$target"
}

# -----------------------------------------------------------------------------
# Set Fan Speed (common to both modes)
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
  i2cset -y "${thePort}" 0x01a ${i2c_reg} "${fanHex}"
}

# -----------------------------------------------------------------------------
# Home Assistant Fan Speed Reporting (common)
# -----------------------------------------------------------------------------
fanSpeedReport() {
  local fanPercent="$1"
  local extra="$2"  # mode info or additional details
  local cpuTemp="$3"
  local unit="$4"
  local icon="$5"
  local reqBody
  reqBody='{"state": "'"${fanPercent}"'", "attributes": { "unit_of_measurement": "%", "icon": "'"${icon}"'", "info": "'"${extra}"'", "Temperature '"${unit}"'": "'"${cpuTemp}"'", "friendly_name": "Argon Fan Speed"}}'
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
# Fluid Mode Action: Discrete fan steps based on thresholds.
# -----------------------------------------------------------------------------
actionFluid() {
  local fanPercent="$1"
  local fanLevel="$2"
  local fanMode="$3"
  local cpuTemp="$4"
  local unit="$5"
  i2c_reg="0x01a"  # For Fluid mode, no extra command byte
  actionSetFan "$fanPercent"
  local retVal=$?
  local createEntity
  createEntity=$(jq -r '."Create a Fan Speed entity in Home Assistant"' < /data/options.json)
  if [ "$createEntity" == "true" ]; then
    case ${fanLevel} in
      1) icon="mdi:fan" ;;
      2) icon="mdi:fan-speed-1" ;;
      3) icon="mdi:fan-speed-2" ;;
      4) icon="mdi:fan-speed-3" ;;
      *) icon="mdi:fan" ;;
    esac
    fanSpeedReport "$fanPercent" "${fanMode} (L${fanLevel})" "$cpuTemp" "$unit" "${icon}" &
  fi
  return $retVal
}

# -----------------------------------------------------------------------------
# Linear Mode Action: Continuous mapping of temperature to fan speed.
# -----------------------------------------------------------------------------
actionLinear() {
  local fanPercent="$1"
  local cpuTemp="$2"
  local unit="$3"
  i2c_reg="0x01a"  # For Linear mode, command byte is set via i2c_reg if needed
  actionSetFan "$fanPercent"
  local retVal=$?
  local createEntity
  createEntity=$(jq -r '."Create a Fan Speed entity in Home Assistant"' < /data/options.json)
  if [ "$createEntity" == "true" ]; then
    fanSpeedReport "$fanPercent" "Linear" "$cpuTemp" "$unit" "mdi:fan" &
  fi
  return $retVal
}

# -----------------------------------------------------------------------------
# Diagnostic Reporting (AI-Enhanced)
# -----------------------------------------------------------------------------
diagnosticReport() {
  if [ "$debugMode" = "true" ]; then
    echo "Diagnostic Report:"
    echo "  Timestamp: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "  Cooling Mode: ${cooling_mode}"
    echo "  Current Fan Speed: ${currentFanSpeed}%"
    echo "  I2C Port: ${thePort}"
    echo "  CPU Temperature: ${cpuTemp}°${unit}"
  fi
}

# -----------------------------------------------------------------------------
# Load Configuration Options
# -----------------------------------------------------------------------------
cooling_mode=$(jq -r '."Cooling Mode"' < /data/options.json | tr '[:upper:]' '[:lower:]')
updateInterval=$(jq -r '."Update Interval"' < /data/options.json)
createEntity=$(jq -r '."Create a Fan Speed entity in Home Assistant"' < /data/options.json)
logTemp=$(jq -r '."Log current temperature every 30 seconds"' < /data/options.json)
debugMode=$(jq -r '."Debug Mode"' < /data/options.json)
manualOverride=$(jq -r '."Manual Fan Speed Override"' < /data/options.json)

i2c_reg="0x01a"  # Default I2C register setting

if [ "$cooling_mode" = "linear" ]; then
  unit=$(jq -r '."Celsius or Fahrenheit"' < /data/options.json)
  tmini=$(jq -r '."Minimum Temperature"' < /data/options.json)
  tmaxi=$(jq -r '."Maximum Temperature"' < /data/options.json)
  if [ "$tmaxi" -eq "$tmini" ]; then
    echo "Error: Minimum Temperature equals Maximum Temperature in Linear mode."
    exit 1
  fi
  value_a=$(( 100 / (tmaxi - tmini) ))
  value_b=$(( -value_a * tmini ))
else
  unit=$(jq -r '.CorF' < /data/options.json)
  lowRange=$(mkfloat "$(jq -r '.LowRange' < /data/options.json)")
  medRange=$(mkfloat "$(jq -r '.MediumRange' < /data/options.json)")
  highRange=$(mkfloat "$(jq -r '.HighRange' < /data/options.json)")
  quiet=$(jq -r '.QuietProfile' < /data/options.json)
fi

# -----------------------------------------------------------------------------
# Initialization: I2C Port Detection & Setup
# -----------------------------------------------------------------------------
thePort=255
echo "Detecting I2C layout; expecting to see '1a' or '1b'..."
calibrateI2CPort
port="${thePort}"
echo "I2C Port detected: ${port}"

if [ "$port" == "255" ]; then
  echo "No Argon device detected on I2C. Cooling control disabled."
  exit 1
fi

safetyFanSpeed=$(jq -r '."Safety Fan Speed (%)"' < /data/options.json)
[ -z "$safetyFanSpeed" ] && safetyFanSpeed=100
trap 'echo "Error at line ${LINENO}: ${BASH_COMMAND}"; i2cset -y ${port} 0x01a 0x63; echo "Safe Mode Activated (Fan ${safetyFanSpeed}%)"; exit 1' ERR EXIT INT TERM

# -----------------------------------------------------------------------------
# Main Loop
# -----------------------------------------------------------------------------
currentFanSpeed=0
cycleCount=0
if [ "$cooling_mode" = "fluid" ]; then
  previousFanLevel=-1
else
  previousFanPercent=-1
fi

while true; do
  if ! read -r cpuRawTemp < /sys/class/thermal/thermal_zone0/temp; then
    echo "Error reading CPU temperature."
    sleep "$updateInterval"
    continue
  fi
  cpuTemp=$(( cpuRawTemp / 1000 ))
  if [ "$unit" = "F" ] || [ "$unit" = "Fahrenheit" ]; then
    cpuTemp=$(( (cpuTemp * 9 / 5) + 32 ))
  fi

  [ "$logTemp" = "true" ] && echo "$(date '+%Y-%m-%d_%H:%M:%S'): Current Temperature = ${cpuTemp}°${unit}"
  [ "$debugMode" = "true" ] && echo "Mode: ${cooling_mode} | CPU Temp: ${cpuTemp}°${unit}"

  if [ "$manualOverride" -ge 0 ]; then
    if [ "$manualOverride" -ne "$currentFanSpeed" ]; then
      echo "Manual Fan Speed Override activated: ${manualOverride}%"
      currentFanSpeed=$(rampFanSpeed "$currentFanSpeed" "$manualOverride")
    fi
  else
    if [ "$cooling_mode" = "linear" ]; then
      fanPercent=$(( value_a * cpuTemp + value_b ))
      if [ "$fanPercent" -lt 0 ]; then fanPercent=0; fi
      if [ "$fanPercent" -gt 100 ]; then fanPercent=100; fi
      if [ "$previousFanPercent" != "$fanPercent" ]; then
        currentFanSpeed=$(rampFanSpeed "$currentFanSpeed" "$fanPercent")
        actionLinear "$currentFanSpeed" "$cpuTemp" "$unit"
        previousFanPercent="$fanPercent"
      fi
    else
      tempFloat=$(mkfloat "$cpuTemp")
      if fcomp "$tempFloat" '<=' "$lowRange"; then
        fanLevel=1
      elif fcomp "$tempFloat" '>=' "$lowRange" && fcomp "$tempFloat" '<=' "$medRange"; then
        fanLevel=2
      elif fcomp "$tempFloat" '>=' "$medRange" && fcomp "$tempFloat" '<=' "$highRange"; then
        fanLevel=3
      else
        fanLevel=4
      fi
      if [ "$previousFanLevel" != "$fanLevel" ]; then
        case $fanLevel in
          1)
            fanMode="OFF"
            fanPercent=0
            ;;
          2)
            if [ "$quiet" = "true" ]; then
              fanMode="Quiet Low"
              fanPercent=1
            else
              fanMode="Low"
              fanPercent=33
            fi
            ;;
          3)
            if [ "$quiet" = "true" ]; then
              fanMode="Quiet Medium"
              fanPercent=3
            else
              fanMode="Medium"
              fanPercent=66
            fi
            ;;
          4)
            fanMode="High"
            fanPercent=100
            ;;
        esac
        currentFanSpeed=$(rampFanSpeed "$currentFanSpeed" "$fanPercent")
        actionFluid "$currentFanSpeed" "$fanLevel" "$fanMode" "$cpuTemp" "$unit"
        previousFanLevel="$fanLevel"
      fi
    fi
  fi

  if [ $(( cycleCount % (600 / updateInterval) )) -eq 0 ]; then
    if [ "$cooling_mode" = "fluid" ]; then
      fanSpeedReport "$currentFanSpeed" "${fanMode} (L${previousFanLevel})" "$cpuTemp" "$unit" "mdi:fan"
    else
      fanSpeedReport "$currentFanSpeed" "Linear" "$cpuTemp" "$unit" "mdi:fan"
    fi
  fi

  diagnosticReport
  [ "$debugMode" = "true" ] && echo "Cycle $cycleCount | Current Fan: ${currentFanSpeed}%"
  sleep "$updateInterval"
  cycleCount=$(( cycleCount + 1 ))
done