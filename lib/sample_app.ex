defmodule SampleApp do
  @spi_config Application.compile_env!(:sample_app, :spi)
  @display_port_options Application.compile_env!(:sample_app, :display_port)
  @scene Application.compile_env!(:sample_app, :scene)
  @touch_options Application.compile_env(:sample_app, :touch, [])

  def start do
    SampleApp.Provision.maybe_provision()

    SampleApp.WiFi.start_link()

    spi_host = :spi.open(@spi_config)

    display_port =
      :erlang.open_port(
        {:spawn, "display"},
        @display_port_options ++ [spi_host: spi_host]
      )

    input_server_pid = maybe_start_input_server(spi_host)

    {:ok, _scene_pid} =
      @scene.start_link([],
        display_server: {:port, display_port},
        input_server: input_server_pid
      )

    Process.sleep(:infinity)
  end

  defp maybe_start_input_server(spi_host) do
    if input_server_required?(@scene) do
      {:ok, pid} =
        SampleApp.TouchInput.start_link(
          spi: spi_host,
          device: :spi_dev_touch,
          width: Keyword.fetch!(@display_port_options, :width),
          height: Keyword.fetch!(@display_port_options, :height),
          rotation: Keyword.fetch!(@display_port_options, :rotation),
          touch: @touch_options
        )

      pid
    else
      nil
    end
  end

  defp input_server_required?(SampleApp.TouchCalibrationScene), do: true
  defp input_server_required?(_), do: false
end
