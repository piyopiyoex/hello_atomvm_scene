defmodule SampleApp do
  @spi_sclk 7
  @spi_miso 8
  @spi_mosi 9

  @lcd_cs 43
  @lcd_dc 3
  @lcd_rst 2

  @width 320
  @height 240
  @rotation 1

  @compatible "ilitek,ili9342c"

  def start do
    spi =
      :spi.open([
        {:bus_config,
         [
           {:sclk, @spi_sclk},
           {:miso, @spi_miso},
           {:mosi, @spi_mosi}
         ]}
      ])

    display_port =
      :erlang.open_port(
        {:spawn, "display"},
        width: @width,
        height: @height,
        compatible: @compatible,
        cs: @lcd_cs,
        dc: @lcd_dc,
        reset: @lcd_rst,
        rotation: @rotation,
        spi_host: spi
      )

    {:ok, _pid} =
      SampleApp.HinomaruScene.start_link([], display_server: {:port, display_port})

    Process.sleep(:infinity)
  end
end
