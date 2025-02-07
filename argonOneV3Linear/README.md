# ArgonOne V3 Active Multi-Mode Cooling

![image](https://raw.githubusercontent.com/adamoutler/HassOSArgonOneAddon/main/gitResources/activecooling.jpg)

This addon for ArgonOne V3 in Home Assistant is a comprehensive cooling controller that supports multiple control strategies—**Linear** and **Fluid**—plus advanced features for fine-tuning and diagnostics.

## Features

### Multi-Mode Cooling
- **Linear Mode**  
  Smoothly maps temperature to fan speed using a linear equation. Set your minimum and maximum temperatures to scale the fan speed from 0 to 100%.

- **Fluid Mode**  
  Uses discrete temperature thresholds to step the fan speed between off, low, medium, and high. A “Quiet Profile” option provides softer fan speeds in low and medium ranges.

### Advanced Functionalities
- **Manual Fan Speed Override**  
  Force a specific fan speed percentage to override automatic control when needed.

- **Fan Ramping**  
  Gradually adjust the fan speed (with a configurable delay) to reduce mechanical stress on the hardware.

- **I2C Port Override**  
  If auto-detection isn’t desired, specify an I2C port manually.

- **Diagnostics Mode**  
  Enable verbose logging to help troubleshoot issues with temperature readings or I2C communication.

- **Custom Update Interval**  
  Set how often (in seconds) the addon reads the temperature and adjusts the fan speed.

- **Home Assistant Integration**  
  Optionally create a Fan Speed entity in Home Assistant to monitor the current state.

## Configuration

The addon’s configuration is divided into several sections:

### General Settings
- **Temperature Unit:** `C` for Celsius or `F` for Fahrenheit.
- **Mode:** Select between `Linear` and `Fluid`.
- **Update Interval (seconds):** Set between 10 and 300 seconds.
- **Log Temperature:** Toggle logging of the current temperature.
- **Create a Fan Speed Entity in Home Assistant:** Enable to report the fan speed status.

### Linear Mode Settings
- **Minimum Temperature:** Temperature at which the fan begins (1% speed).
- **Maximum Temperature:** Temperature at which the fan runs at 100%.

### Fluid Mode Settings
- **Low Temperature Threshold:** Upper limit for the fan to remain off (or at very low speed).
- **Medium Temperature Threshold:** Temperature at which the fan ramps to medium speed.
- **High Temperature Threshold:** Temperature above which the fan runs at high speed.
- **Quiet Profile (Fluid Mode):** Use softer speeds for low and medium ranges.

### Advanced Settings
- **I2C Port Override:** Manually specify the I2C port (0–26). Set to 255 to enable auto-detection.
- **Manual Fan Speed Override:** Set a fixed fan speed (0–100%) to bypass automatic control; use -1 to disable.
- **Fan Ramping Delay (seconds):** Delay between incremental fan speed changes (0–10 seconds).
- **Safety Fan Speed (%):** The fan speed to set in case of errors.
- **Diagnostics Mode:** Enable detailed logging for troubleshooting.

## Support

First, check the Logs tab in Home Assistant for any errors or diagnostic messages. Ensure that I2C is enabled and that your configuration settings are correct.

For further assistance, please visit our [Community Forum](https://community.home-assistant.io/t/argon-one-active-cooling-addon/262598/8).

Happy cooling!
