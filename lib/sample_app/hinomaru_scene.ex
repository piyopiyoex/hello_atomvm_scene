defmodule SampleApp.HinomaruScene do
  import SampleApp.Utils, only: [panel_color: 1]

  @display_options Application.compile_env(:sample_app, :display_port)
  @width Keyword.fetch!(@display_options, :width)
  @height Keyword.fetch!(@display_options, :height)

  def start_link(args, opts) do
    :avm_scene.start_link(__MODULE__, args, opts)
  end

  def init(_args) do
    send(self(), :update_display)
    {:ok, %{}}
  end

  def handle_info(:update_display, state) do
    label = {:text, 10, 20, :default16px, panel_color(0x000000), :transparent, "Hinomaru test"}

    hinomaru =
      filled_circle_scanlines(
        div(@width, 2),
        div(@height, 2),
        div(@height * 3, 10),
        panel_color(0xBC002D)
      )

    background = {:rect, 0, 0, @width, @height, panel_color(0xFFFFFF)}

    items = [label] ++ hinomaru ++ [background]
    {:noreply, state, [{:push, items}]}
  end

  defp filled_circle_scanlines(cx, cy, radius, fill_color) do
    r2 = radius * radius

    for dy <- -radius..radius do
      dx = trunc(:math.sqrt(r2 - dy * dy))
      {:rect, cx - dx, cy + dy, dx * 2 + 1, 1, fill_color}
    end
  end
end
