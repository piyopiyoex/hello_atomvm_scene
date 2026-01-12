# AtomGL Example

A tiny Elixir/AtomVM demo that renders something simple on an SPI LCD using:

- [atomvm/atomgl](https://github.com/atomvm/atomgl)
- [atomvm/avm_scene](https://github.com/atomvm/avm_scene)
- [Supported displays](https://github.com/atomvm/atomgl/blob/main/docs/display-drivers.md#supported-displays)
- Target board: [Piyopiyo PCB](https://github.com/piyopiyoex/piyopiyo-pcb) with [Seeed XIAO-ESP32S3](https://wiki.seeedstudio.com/xiao_esp32s3_getting_started/)

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

Build a custom AtomVM image with AtomGL and flash it to the device:

```sh
bash scripts/atomvm-esp32.sh build-erase-flash --port /dev/ttyACM0 --target esp32s3
```

Flash this Elixir app to the device:

```sh
mix deps.get
mix do clean + atomvm.esp32.flash --port /dev/ttyACM0
```

Monitor the device in another terminal:

```sh
bash scripts/atomvm-esp32.sh monitor --port /dev/ttyACM0
```
