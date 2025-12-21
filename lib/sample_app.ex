defmodule SampleApp do
  @spi_config Application.compile_env!(:sample_app, :spi)
  @display_port_options Application.compile_env!(:sample_app, :display_port)
  @scene Application.compile_env!(:sample_app, :scene)
  @touch_options Application.compile_env(:sample_app, :touch, [])

  def start do
    spi_host = :spi.open(@spi_config)

    display_port =
      :erlang.open_port(
        {:spawn, "display"},
        @display_port_options ++ [spi_host: spi_host]
      )

    {:ok, touch_pid} =
      SampleApp.TouchInput.start_link(
        spi: spi_host,
        device: :spi_dev_touch,
        width: Keyword.get(@display_port_options, :width, 320),
        height: Keyword.get(@display_port_options, :height, 240),
        rotation: Keyword.get(@display_port_options, :rotation, 0),
        touch: @touch_options
      )

    {:ok, _scene_pid} =
      @scene.start_link([],
        display_server: {:port, display_port},
        input_server: touch_pid
      )

    Process.sleep(:infinity)
  end
end
