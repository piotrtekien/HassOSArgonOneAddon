# Argon One V3 Advanced Fan Control Add-on

![Active Cooling](https://raw.githubusercontent.com/piotrtekien/HassOSArgonOneAddon/main/gitResources/activecooling.jpg)

This Home Assistant add-on provides **advanced fan control** for the Argon One V3 device on Raspberry Pi and Home Assistant Yellow. Running in a Docker container on ARM‐based systems, it smoothly adjusts the fan speed based on real-time temperature readings and supports three distinct control modes for maximum flexibility.

![Fan Control](https://raw.githubusercontent.com/piotrtekien/HassOSArgonOneAddon/main/gitResources/argonlinear.png)

## Features

- **Multi-Mode Fan Control:**
  - **Linear Mode:** Continuous, proportional control between a minimum and maximum temperature.
  - **Fluid Mode:** Non-linear (exponential) response with adjustable sensitivity for a smoother transition.
  - **Extended Mode:** Discrete control with multiple thresholds and optional quiet settings for fine-tuned performance.
- **Configurable Temperature Ranges:** Set thresholds for each mode to tailor fan response.
- **Safe Mode:** On error, the fan is set to 100% to protect your hardware.
- **Optional Logging & Entity Reporting:** Log temperature readings and report fan speed changes to Home Assistant.

## How It Works

Depending on the chosen mode, the fan speed is calculated as follows:
- y = a * x + b
  - where:
  - y = fan speed (%)
  - x = current temperature
  - a = 100 / (MaxTemperature - Minimum Temperature)
  - b = -a * Minimum Temperature

### Initializes and Detects Hardware

- **I2C Detection:** It searches through available I2C ports (devices like `/dev/i2c-*`) and runs a diagnostic (using `i2cdetect`) to look for the Argon One V3 hardware at specific I2C addresses (`0x1a` or `0x1b`). Once it finds a matching device, it records the I2C port and address.
- **Error Handling:** If no I2C port is available, it outputs an error message and essentially halts (using a long sleep and exit). It also traps errors and signals (like INT and TERM) to trigger a “safe mode” by sending a specific command to the device.

### Utility Functions

- `mk_float`: Ensures a given number is in floating-point format (adding a decimal if needed). This is used to help with temperature comparisons.
- `calibrate_i2c_port`: Loops through possible I2C ports to locate the Argon One device.
- `fcomp`: Compares two floating-point numbers with a given operator (like `<`, `<=`, `==`, etc.) by converting the numbers into an integer representation that preserves their relative scale.
- `report_fan_speed`: Sends an HTTP POST request to Home Assistant, reporting the current fan speed and CPU temperature. This creates or updates a sensor entity within Home Assistant so you can monitor the fan’s operation.
- `set_fan_speed_generic`: Converts the desired fan speed percentage to a hexadecimal value (as required by the hardware), logs a timestamped message, sends the command to set the fan speed over I2C, and optionally reports the new state to Home Assistant.

### Configuration Settings

The script reads its configuration from an `options.json` file using `jq`. The configurable parameters include:

- **Fan Control Mode:** There are three modes:
  - **Linear:** Directly maps temperature to fan speed using a straight-line formula.
  - **Fluid:** Uses an exponential (or “fluid”) formula to provide a more gradual ramp-up in speed.
  - **Extended:** Has several temperature thresholds (off, low, medium, high, boost) and can adjust the fan speed differently based on whether “quiet” mode is enabled.
- **Temperature Unit:** Celsius or Fahrenheit.
- **Update Interval:** How often (in seconds) the script will re-check the temperature and adjust the fan speed.
- **Other Options:** Such as whether to log the temperature every cycle or create a fan speed entity in Home Assistant.

### Main Operational Loop

Once the device is detected and configuration is loaded, the script enters an endless loop:

1. **Temperature Reading:** It reads the CPU temperature (usually provided in millidegrees from `/sys/class/thermal/thermal_zone0/temp`) and converts it to either Celsius or Fahrenheit.
2. **Fan Speed Calculation:** Depending on the chosen mode:
   - **Linear Mode:** Uses a simple linear equation based on the minimum and maximum temperature settings.
   - **Fluid Mode:** Applies a non-linear (exponential) formula to calculate the fan speed, allowing for a smoother transition.
   - **Extended Mode:** Checks a series of temperature thresholds:
     - Below a defined “off” temperature: fan remains off.
     - Between thresholds: assigns predefined speeds (with variations for “quiet” mode).
     - Above a “boost” temperature: ramps up to 100% speed.
3. **Command Execution:** If the calculated fan speed differs from the previous cycle, it sends the new speed command via I2C.
   - It logs the change with a timestamp and sends an update to Home Assistant (if enabled) to keep the status sensor in sync.
4. **Sleep Interval:** It then sleeps for the configured update interval before checking the temperature again.

### Error & Safe Mode Handling

A trap is set up so that if any error occurs (or if the script receives an interrupt or termination signal), it attempts to set the fan to a “safe mode” state and outputs an error message including the line where the error happened.
