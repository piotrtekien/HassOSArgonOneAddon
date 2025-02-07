# ArgonOne V3 Active Linear Cooling Add-on

![Active Cooling](https://raw.githubusercontent.com/adamoutler/HassOSArgonOneAddon/main/gitResources/activecooling.jpg)

This Home Assistant add-on enables and automates the active cooling system on your ArgonOne V3. Running in a Docker container, it smoothly adjusts the fan speed based on real-time temperature readings to keep your device within safe operating ranges.

![Fan Control](https://raw.githubusercontent.com/adamoutler/HassOSArgonOneAddon/main/gitResources/argonlinear.png)

## Features

- **Dynamic Fan Control:** Adjusts fan speed from 0% to 100% based on temperature.
- **Configurable Temperature Ranges:** Set a minimum temperature to trigger the fan and a maximum temperature for full-speed operation.
- **Safe Mode:** On error, the fan is set to 100% to protect your hardware.
- **Optional Logging & Entity Reporting:** Log temperature at regular intervals and (optionally) report fan speed to Home Assistant.

## How It Works

The fan speed is determined by a linear formula:

```bash
y = a * x + b
# where:
# y = fan speed (%)
# x = current temperature
# a = gradient (calculated as 100 / (MaxTemperature - MinTemperature))
# b = offset (calculated as -a * MinTemperature)

value_a=$((100 / (tmaxi - tmini)))
value_b=$((-value_a * tmini))
fanPercent=$((value_a * value + value_b))

