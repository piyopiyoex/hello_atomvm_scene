defmodule SampleApp.TouchCalibrationScene do
  @display_port_options Application.compile_env(:sample_app, :display_port, [])
  @width Keyword.get(@display_port_options, :width, 320)
  @height Keyword.get(@display_port_options, :height, 240)
  @color_order Application.compile_env(:sample_app, :color_order, :rgb)

  @text_x 10
  @line1_y 20
  @line_h 20

  def start_link(args, opts), do: :avm_scene.start_link(__MODULE__, args, opts)

  def init(_args) do
    send(self(), :render)

    {:ok,
     %{
       counter: 0,
       last_raw: nil,
       last_screen: nil,
       raw_range: %{x_min: nil, x_max: nil, y_min: nil, y_max: nil}
     }}
  end

  def handle_info(:render, state) do
    {:noreply, state, [{:push, render_items(state)}]}
  end

  def handle_info({:touch, x, y, raw_x, raw_y}, state) do
    {:noreply, apply_touch(state, x, y, raw_x, raw_y), [{:push, render_items(state)}]}
  end

  def handle_input({:touch, x, y, raw_x, raw_y}, _ts, _pid, state) do
    {:noreply, apply_touch(state, x, y, raw_x, raw_y), [{:push, render_items(state)}]}
  end

  defp apply_touch(state, x, y, raw_x, raw_y) do
    state
    |> bump_counter()
    |> put_last({raw_x, raw_y}, {x, y})
    |> update_range(raw_x, raw_y)
  end

  defp bump_counter(state), do: %{state | counter: state.counter + 1}
  defp put_last(state, raw, screen), do: %{state | last_raw: raw, last_screen: screen}

  defp update_range(state, raw_x, raw_y) when is_integer(raw_x) and is_integer(raw_y) do
    rr = state.raw_range

    rr = %{
      x_min: min_or(raw_x, rr.x_min),
      x_max: max_or(raw_x, rr.x_max),
      y_min: min_or(raw_y, rr.y_min),
      y_max: max_or(raw_y, rr.y_max)
    }

    %{state | raw_range: rr}
  end

  defp update_range(state, _raw_x, _raw_y), do: state

  defp min_or(v, nil), do: v
  defp min_or(v, cur), do: min(v, cur)

  defp max_or(v, nil), do: v
  defp max_or(v, cur), do: max(v, cur)

  defp render_items(state) do
    rr = state.raw_range

    label1 = text_line(0, "Counter: #{state.counter}")
    label2 = text_line(1, "Raw: #{fmt_pair(state.last_raw)}")
    label3 = text_line(2, "Screen: #{fmt_pair(state.last_screen)}")

    range_text =
      "Range x:[#{fmt(rr.x_min)}..#{fmt(rr.x_max)}] y:[#{fmt(rr.y_min)}..#{fmt(rr.y_max)}]"

    label4 = text_line(3, range_text)

    background = {:rect, 0, 0, @width, @height, panel_color(0xFFFFFF)}
    dot = dot_items(state.last_screen)

    [label1, label2, label3, label4] ++ dot ++ [background]
  end

  defp text_line(i, text) do
    {:text, @text_x, @line1_y + @line_h * i, :default16px, panel_color(0x000000), :transparent,
     text}
  end

  defp dot_items(nil), do: []

  defp dot_items({x, y}) when is_integer(x) and is_integer(y) do
    x = clamp_i(x, 2, @width - 3)
    y = clamp_i(y, 2, @height - 3)
    [{:rect, x - 2, y - 2, 5, 5, panel_color(0xFF0000)}]
  end

  defp dot_items(_), do: []

  defp fmt_pair(nil), do: "-"
  defp fmt_pair({a, b}), do: "{#{fmt(a)}, #{fmt(b)}}"
  defp fmt_pair(_), do: "-"

  defp fmt(nil), do: "-"
  defp fmt(:undefined), do: "-"
  defp fmt(v), do: "#{v}"

  defp clamp_i(v, lo, _hi) when v < lo, do: lo
  defp clamp_i(v, _lo, hi) when v > hi, do: hi
  defp clamp_i(v, _lo, _hi), do: v

  defp panel_color(rgb24) when rgb24 in 0..0xFFFFFF do
    case @color_order do
      :rgb ->
        rgb24

      :bgr ->
        <<r::8, g::8, b::8>> = <<rgb24::24>>
        b * 0x10000 + g * 0x100 + r
    end
  end
end
