# Configuration

![image](https://raw.githubusercontent.com/adamoutler/HassOSArgonOneAddon/main/gitResources/linearsettings.png)

## Celsius or Fahrenheit

Choose Celsius or Fahrenheit.

- **Celsius or Fahrenheit** - Configures Celsius or Fahrenheit for Linear mode.

## Temperature Ranges

![image](https://raw.githubusercontent.com/adamoutler/HassOSArgonOneAddon/main/gitResources/argonlinear.png)

Set your fan ranges appropriately.

- **Minimum Temperature**: Temperature at which the fan starts (≈1% speed).
- **Maximum Temperature**: Temperature before the fan reaches 100%.

## Enable I2C

To enable I2C, follow one of these methods:

### The easy way

[Addon: HassOS I2C Configurator](https://community.home-assistant.io/t/add-on-hassos-i2c-configurator/264167)

### The official way

[Official Guide](https://www.home-assistant.io/installation/raspberrypi/#enable-i2c)

## Advanced Options

- **I2C Port Override**: Manually specify the I2C port (0–26), or set to 255 for auto-detection.
- **Manual Fan Speed Override**: Force a specific fan speed (0–100%); set to -1 to disable.
- **Fan Ramping Delay**: Delay between incremental fan speed adjustments.
- **Safety Fan Speed**: Fan speed to set if an error is encountered.

## Support

Need support? Click [here](https://community.home-assistant.io/t/argon-one-active-cooling-addon/262598/8).
Provide detailed feedback for effective troubleshooting.