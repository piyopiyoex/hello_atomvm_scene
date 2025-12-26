import Config

config :sample_app,
  spi: [
    bus_config: [sclk: 7, miso: 8, mosi: 9],
    device_config: [
      spi_dev_lcd: [
        cs: 43,
        mode: 0,
        clock_speed_hz: 20_000_000,
        command_len_bits: 0,
        address_len_bits: 0
      ],
      spi_dev_touch: [
        cs: 44,
        mode: 0,
        clock_speed_hz: 1_000_000,
        command_len_bits: 0,
        address_len_bits: 0
      ]
    ]
  ],
  display_port: [
    width: 320,
    height: 240,
    compatible: "ilitek,ili9342c",
    rotation: 1,
    cs: 43,
    dc: 3,
    reset: 2
  ],
  swap_red_blue: true,
  touch: [
    poll_ms: 25,
    # :edge  -> emit only on “press down”
    # :drag  -> emit continuously while pressed
    emit_mode: :drag,
    calibration: [
      raw_x_min: 80,
      raw_x_max: 1950,
      raw_y_min: 80,
      raw_y_max: 1950,
      swap_xy: false,
      invert_x: false,
      invert_y: true
    ]
  ],
  scene:
    Enum.random([
      SampleApp.ClockScene,
      SampleApp.HinomaruScene,
      SampleApp.TouchCalibrationScene
    ])
