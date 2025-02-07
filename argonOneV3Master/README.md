# Argon One V3 Advanced Fan Control Add-on

![Active Cooling](https://raw.githubusercontent.com/piotrtekien/HassOSArgonOneAddon/main/gitResources/activecooling.jpg)

This Home Assistant add-on provides **advanced fan control** for the
Argon One V3 device on Raspberry Pi and Home Assistant Yellow. Running
in a Docker container on ARM-based systems, it smoothly adjusts the fan
speed based on real-time temperature readings and supports three
distinct control modes for maximum flexibility.

![Fan Control](https://raw.githubusercontent.com/piotrtekien/HassOSArgonOneAddon/main/gitResources/argonlinear.png)

## Features

- **Multi-Mode Fan Control:**
  - **Linear Mode:** Continuous, proportional control between a min
    and max temperature.
  - **Fluid Mode:** Non-linear (exponential) response with adjustable
    sensitivity for a smoother transition.
  - **Extended Mode:** Discrete control with multiple thresholds and
    optional quiet settings for fine-tuned performance.
- **Configurable Temperature Ranges:** Set thresholds for each mode to
  tailor fan response.
- **Safe Mode:** On error, the fan is set to 100% to protect hardware.
- **Optional Logging & Entity Reporting:** Log temperature readings and
  report fan speed changes to Home Assistant.

## How It Works

Depending on the chosen mode, the fan speed is calculated as follows:
- y = a * x + b
  - where:
  - y = fan speed (%)
  - x = current temperature
  - a = 100 / (MaxTemperature - Minimum Temperature)
  - b = -a * Minimum Temperature

### Initializes and Detects Hardware

- **I2C Detection:** It searches available I2C ports (e.g., `/dev/i2c-*`)
  and runs a diagnostic (`i2cdetect`) to locate the Argon One V3 at I2C
  addresses (`0x1a` or `0x1b`). If found, it records the I2C port
  and address.
- **Error Handling:** If no I2C port is available, it outputs an error
  and halts (using a long sleep and exit). It also traps errors and
  signals (like INT and TERM) to trigger a “safe mode.”

### Utility Functions

- **`mk_float`**: Ensures a given number is in floating-point format
  (adds decimal if needed) for temperature comparisons.
- **`calibrate_i2c_port`**: Loops through I2C ports to find the Argon
  One device.
- **`fcomp`**: Compares two floating-point numbers using an operator
  (`<`, `<=`, `==`, etc.) by converting them into an integer-based
  format that maintains precision.
- **`report_fan_speed`**: Sends an HTTP POST request to Home Assistant,
  updating the fan speed and CPU temperature as a sensor entity.
- **`set_fan_speed_generic`**: Converts the fan speed percentage to
  hexadecimal, logs the change, sends the command via I2C, and
  optionally updates Home Assistant.

### Configuration Settings

The script reads its configuration from `options.json` using `jq`.

- **Fan Control Mode:**
  - **Linear:** Maps temperature to fan speed using a straight-line
    formula.
  - **Fluid:** Uses an exponential function for smoother ramp-up.
  - **Extended:** Uses multiple temperature thresholds (off, low,
    medium, high, boost) with quiet mode options.
- **Temperature Unit:** Celsius or Fahrenheit.
- **Update Interval:** Defines how often (in seconds) the script checks
  temperature and adjusts the fan speed.
- **Other Options:** Includes logging temperature each cycle and
  creating a fan speed entity in Home Assistant.

### Main Operational Loop

Once the device is detected and configuration is loaded, the script
enters a loop:

1. **Temperature Reading:** Reads CPU temp from
   `/sys/class/thermal/thermal_zone0/temp` and converts it to °C or °F.
2. **Fan Speed Calculation:** Based on the selected mode:
   - **Linear Mode:** Uses a simple linear equation.
   - **Fluid Mode:** Applies a non-linear (exponential) formula.
   - **Extended Mode:** Uses defined temperature thresholds:
     - Below "off" temp: fan stays off.
     - Between thresholds: assigns predefined speeds (adjusts for
       "quiet" mode).
     - Above "boost" temp: ramps up to 100% speed.
3. **Command Execution:** If fan speed changes, sends a command via
   I2C, logs the update, and optionally updates Home Assistant.
4. **Sleep Interval:** Waits for the configured update interval before
   checking the temperature again.

### Error & Safe Mode Handling

A trap captures errors and signals, setting the fan to "safe mode"
before exiting. It also prints an error message, including the line
where the issue occurred.
