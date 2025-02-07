# Argon One V3 Fan Control

This Home Assistant add-on manages the fan speed for the Argon One V3 on Raspberry Pi and Home Assistant Yellow, adjusting based on temperature.

## Features

- **Fan Control Modes:**
  - **Linear:** Direct temperature-to-speed mapping.
  - **Fluid:** Smooth, non-linear response.
  - **Extended:** Multiple speed thresholds with quiet options.
- **Safe Mode:** Sets fan to 100% on error.
- **Logging:** Tracks temperature and fan speed.

## Operation

1. **Temperature Reading:** Monitors CPU temperature.
2. **Speed Calculation:** Adjusts fan speed based on selected mode.
3. **Command Execution:** Sends speed commands via I2C.
4. **Error Handling:** Activates safe mode on errors.

## Configuration

Settings are read from `options.json`, including fan mode, temperature unit, and update interval.
