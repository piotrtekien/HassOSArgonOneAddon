# Argon One V3 Advanced Fan Control Add-on

![Active Cooling](https://raw.githubusercontent.com/adamoutler/HassOSArgonOneAddon/main/gitResources/activecooling.jpg)

This Home Assistant add-on provides **advanced fan control** for the Argon One V3 device on Raspberry Pi and Home Assistant Yellow. Running in a Docker container on ARM‐based systems, it smoothly adjusts the fan speed based on real-time temperature readings and supports three distinct control modes for maximum flexibility.

![Fan Control](https://raw.githubusercontent.com/adamoutler/HassOSArgonOneAddon/main/gitResources/argonlinear.png)

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

- **Linear Mode:**  
  Uses a simple linear formula:
  ```bash
  y = a * x + b
  # where:
  # y = fan speed (%)
  # x = current temperature
  # a = 100 / (MaxTemperature - Minimum Temperature)
  # b = -a * Minimum Temperature
