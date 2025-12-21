# AtomGL Example

A tiny Elixir/AtomVM demo that renders something simple on an SPI LCD using:

- [atomvm/atomgl](https://github.com/atomvm/atomgl)
- [atomvm/avm_scene](https://github.com/atomvm/avm_scene)
- Target board: Seeed XIAO-ESP32S3
- LCD driver: `ilitek,ili9342c`

<p align="center">
  <img src="https://github.com/user-attachments/assets/10f79bb1-e0eb-4a64-8de9-8358382f254f" alt="Piyopiyo PCB" width="320">
</p>

## Wiring

| Function | XIAO-ESP32S3 pin | ESP32-S3 GPIO |
| -------- | ---------------- | ------------- |
| SCLK     | D8               | 7             |
| MISO     | D9               | 8             |
| MOSI     | D10              | 9             |
| LCD CS   | —                | 43            |
| LCD D/C  | D2               | 3             |
| LCD RST  | D1               | 2             |

## Build & Flash

Build a custom AtomVM image (with AtomGL) and flash your Elixir app.

```sh
# Build + flash AtomVM (ESP32-S3) with AtomGL
bash scripts/atomvm-esp32.sh all --port /dev/ttyACM0 --baud 115200

# Fetch Elixir deps
mix deps.get

# Flash this Elixir app to the device
mix atomvm.esp32.flash --port /dev/ttyACM0 --baud 115200
```

Monitor the device in another terminal:

```sh
bash scripts/monitor-esp32.sh --port /dev/ttyACM0 --baud 115200
```
