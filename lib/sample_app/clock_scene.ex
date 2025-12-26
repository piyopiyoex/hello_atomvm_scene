defmodule SampleApp.ClockScene do
  import SampleApp.Utils, only: [panel_color: 1]

  @display_options Application.compile_env(:sample_app, :display_port, [])
  @width Keyword.get(@display_options, :width, 320)
  @height Keyword.get(@display_options, :height, 240)

  @tz_offset_seconds 9 * 3600

  def start_link(args, opts) do
    :avm_scene.start_link(__MODULE__, args, opts)
  end

  def init(_args) do
    face = clock_face_items(@width, @height)
    label = {:text, 10, 20, :default16px, panel_color(0x000000), :transparent, "Clock test"}

    send(self(), :tick)

    {:ok, %{face: face, label: label, width: @width, height: @height}}
  end

  def handle_info(:tick, %{face: face, label: label, width: w, height: h} = state) do
    {date, {hour, minute, second}} = now_date_hms()

    hands = clock_hands_items(w, h, hour, minute, second)
    digital = digital_clock_items(h, date, hour, minute, second)
    background = {:rect, 0, 0, w, h, panel_color(0xFFFFFF)}

    items = [label] ++ hands ++ digital ++ face ++ [background]

    schedule_next_tick()

    {:noreply, state, [{:push, items}]}
  end

  defp digital_clock_items(h, {year, month, day}, hour, minute, second) do
    time_text = "#{pad2(hour)}:#{pad2(minute)}:#{pad2(second)}"
    date_text = "#{year}-#{pad2(month)}-#{pad2(day)}"

    x = 10
    y1 = h - 36
    y2 = h - 18

    [
      {:text, x, y1, :default16px, panel_color(0x000000), :transparent, time_text},
      {:text, x, y2, :default16px, panel_color(0x000000), :transparent, date_text}
    ]
  end

  defp clock_face_items(w, h) do
    cx = div(w, 2)
    cy = div(h, 2)
    radius = div(min(w, h), 2) - 14
    color = panel_color(0x000000)

    hour_dots(cx, cy, radius, 2, color)
  end

  defp hour_dots(cx, cy, radius, dot_r, color) do
    for i <- 0..11 do
      angle = :math.pi() * 2 * (i / 12) - :math.pi() / 2
      {x, y} = endpoint(cx, cy, radius, angle)
      {:rect, x - dot_r, y - dot_r, dot_r * 2 + 1, dot_r * 2 + 1, color}
    end
  end

  defp clock_hands_items(w, h, hour, minute, second) do
    cx = div(w, 2)
    cy = div(h, 2)
    radius = div(min(w, h), 2) - 14

    minute_angle = angle_for_minute(minute, second)
    hour_angle = angle_for_hour(hour, minute, second)
    second_angle = angle_for_second(second)

    minute_len = trunc(radius * 0.78)
    hour_len = trunc(radius * 0.52)
    second_len = trunc(radius * 0.88)

    {mx, my} = endpoint(cx, cy, minute_len, minute_angle)
    {hx, hy} = endpoint(cx, cy, hour_len, hour_angle)
    {sx, sy} = endpoint(cx, cy, second_len, second_angle)

    second_hand = hand_rects(cx, cy, sx, sy, 1, 2, panel_color(0xFF0000))
    minute_hand = hand_rects(cx, cy, mx, my, 2, 3, panel_color(0x000000))
    hour_hand = hand_rects(cx, cy, hx, hy, 3, 4, panel_color(0x000000))

    center = {:rect, cx - 2, cy - 2, 5, 5, panel_color(0x000000)}

    second_hand ++ minute_hand ++ hour_hand ++ [center]
  end

  defp hand_rects(x0, y0, x1, y1, thickness, step, color) do
    half = thickness

    for {x, y} <- line_points(x0, y0, x1, y1, step) do
      {:rect, x - half, y - half, half * 2 + 1, half * 2 + 1, color}
    end
  end

  defp line_points(x0, y0, x1, y1, step) when step >= 1 do
    dx = abs(x1 - x0)
    sx = if x0 < x1, do: 1, else: -1
    dy = -abs(y1 - y0)
    sy = if y0 < y1, do: 1, else: -1
    err = dx + dy

    line_points_loop(x0, y0, x1, y1, dx, dy, sx, sy, err, step, 0, [])
  end

  defp line_points_loop(x, y, x1, y1, dx, dy, sx, sy, err, step, i, acc) do
    acc =
      if rem(i, step) == 0 do
        [{x, y} | acc]
      else
        acc
      end

    if x == x1 and y == y1 do
      Enum.reverse(acc)
    else
      e2 = 2 * err

      {x, err} =
        if e2 >= dy do
          {x + sx, err + dy}
        else
          {x, err}
        end

      {y, err} =
        if e2 <= dx do
          {y + sy, err + dx}
        else
          {y, err}
        end

      line_points_loop(x, y, x1, y1, dx, dy, sx, sy, err, step, i + 1, acc)
    end
  end

  defp angle_for_second(second) do
    :math.pi() * 2 * (second / 60) - :math.pi() / 2
  end

  defp angle_for_minute(minute, second) do
    m = minute + second / 60
    :math.pi() * 2 * (m / 60) - :math.pi() / 2
  end

  defp angle_for_hour(hour, minute, second) do
    h12 = rem(hour, 12) + (minute + second / 60) / 60
    :math.pi() * 2 * (h12 / 12) - :math.pi() / 2
  end

  defp endpoint(cx, cy, len, angle) do
    x = cx + round(:math.cos(angle) * len)
    y = cy + round(:math.sin(angle) * len)
    {x, y}
  end

  defp now_date_hms do
    secs = :erlang.system_time(:second) + @tz_offset_seconds
    :calendar.system_time_to_universal_time(secs, :second)
  end

  defp schedule_next_tick do
    now_ms = :erlang.system_time(:millisecond)
    delay = 1_000 - rem(now_ms, 1_000)
    :erlang.send_after(delay, self(), :tick)
  end

  defp pad2(n) when n < 10, do: "0#{n}"
  defp pad2(n), do: Integer.to_string(n)
end
