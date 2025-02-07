# ArgonOne Multi-Mode Cooling

![Active Cooling](https://raw.githubusercontent.com/adamoutler/HassOSArgonOneAddon/main/gitResources/activecooling.jpg)
![Linear Cooling Diagram](https://raw.githubusercontent.com/adamoutler/HassOSArgonOneAddon/main/gitResources/argonlinear.png)

This addon is designed for Argon devices and supports both Fluid (discrete) and Linear (continuous) cooling modes.

Running as a Docker container within Home Assistant, it dynamically adjusts the fan speed based on CPU temperature.

## Features

- **Dual Cooling Modes:**
  - **Linear Mode:** Smooth, continuous fan speed control based on a linear mapping between a minimum and maximum temperature.
  - **Fluid Mode:** Discrete fan levels based on predefined temperature thresholds.
- **Manual Fan Speed Override:** Force a specific fan speed for testing or special conditions.
- **Fan Ramping:** Gradually adjust fan speed to reduce mechanical stress.
- **Adaptive Diagnostics:** AI-enhanced logging and diagnostic reporting for improved troubleshooting.
- **Advanced I2C Control:** Auto-detection with manual override options for reliable communication.
- **Home Assistant Integration:** Optionally create a sensor to monitor fan speed in real time.
- **Safety Mechanism:** Automatically sets a safety fan speed in case of errors.

## Mathematical Formula (Linear Mode)

The fan speed is calculated using:
 **y = a * x + b**

Where:
- **y**: Fan speed (%)
- **x**: Current temperature
- **a**: Gradient, calculated as `100 / (Maximum Temperature - Minimum Temperature)`
- **b**: Offset, calculated as `-a * Minimum Temperature`

## Installation & Usage

1. Place the provided files into your addon directory.
2. Adjust the configuration via Home Assistant's options.
3. Start the addon and monitor the logs for diagnostic information.
4. Optionally, enable the Home Assistant sensor for real-time fan speed monitoring.

## Support

For assistance, visit the [Home Assistant Community Forum](https://community.home-assistant.io/t/argon-one-active-cooling-addon/262598/8) and provide detailed feedback.
