defmodule SampleApp.ClockScene do
  @width 320
  @height 240

  @color_order :bgr
  @tz_offset_seconds 9 * 3600

  def start_link(args, opts) do
    :avm_scene.start_link(__MODULE__, args, opts)
  end

  def init(_args) do
    face = clock_face_items(@width, @height)
    send(self(), :tick)
    {:ok, %{face: face, width: @width, height: @height}}
  end

  def handle_info(:tick, %{face: face, width: w, height: h} = state) do
    {date, {hour, minute, second}} = now_date_hms()

    label = {:text, 10, 20, :default16px, panel_color(0x000000), :transparent, "Clock test"}
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

  defp clock_hands_items(w, h, hour, minute, second) do
    cx = div(w, 2)
    cy = div(h, 2)
    radius = div(min(w, h), 2) - 14

    minute_angle = angle_for_minute(minute, second)
    hour_angle = angle_for_hour(hour, minute, second)
    second_angle = angle_for_second(second)

    minute_len = trunc(radius * 0.80)
    hour_len = trunc(radius * 0.55)
    second_len = trunc(radius * 0.90)

    {mx, my} = endpoint(cx, cy, minute_len, minute_angle)
    {hx, hy} = endpoint(cx, cy, hour_len, hour_angle)
    {sx, sy} = endpoint(cx, cy, second_len, second_angle)

    hand_rects(cx, cy, sx, sy, 1, panel_color(0xFF0000)) ++
      hand_rects(cx, cy, mx, my, 2, panel_color(0x000000)) ++
      hand_rects(cx, cy, hx, hy, 3, panel_color(0x000000)) ++
      center_dot(cx, cy, 3, panel_color(0x000000))
  end

  defp clock_face_items(w, h) do
    cx = div(w, 2)
    cy = div(h, 2)
    radius = div(min(w, h), 2) - 14

    tick_marks = hour_tick_marks(cx, cy, radius - 2, panel_color(0x000000))
    inner = filled_circle_scanlines(cx, cy, radius - 3, panel_color(0xFFFFFF))
    outer = filled_circle_scanlines(cx, cy, radius, panel_color(0x000000))

    tick_marks ++ inner ++ outer
  end

  defp hour_tick_marks(cx, cy, radius, color) do
    for i <- 0..11, reduce: [] do
      acc ->
        angle = :math.pi() * 2 * (i / 12) - :math.pi() / 2
        {x1, y1} = endpoint(cx, cy, radius, angle)
        {x0, y0} = endpoint(cx, cy, radius - 10, angle)
        acc ++ hand_rects(x0, y0, x1, y1, 1, color)
    end
  end

  defp center_dot(cx, cy, radius, color) do
    filled_circle_scanlines(cx, cy, radius, color)
  end

  defp filled_circle_scanlines(cx, cy, radius, fill_color) do
    r2 = radius * radius

    for dy <- -radius..radius do
      dx = trunc(:math.sqrt(r2 - dy * dy))
      {:rect, cx - dx, cy + dy, dx * 2 + 1, 1, fill_color}
    end
  end

  defp hand_rects(x0, y0, x1, y1, thickness, color) do
    half = thickness

    for {x, y} <- line_points(x0, y0, x1, y1) do
      {:rect, x - half, y - half, half * 2 + 1, half * 2 + 1, color}
    end
  end

  defp line_points(x0, y0, x1, y1) do
    dx = abs(x1 - x0)
    sx = if x0 < x1, do: 1, else: -1
    dy = -abs(y1 - y0)
    sy = if y0 < y1, do: 1, else: -1
    err = dx + dy

    line_points_loop(x0, y0, x1, y1, dx, dy, sx, sy, err, [])
  end

  defp line_points_loop(x, y, x1, y1, dx, dy, sx, sy, err, acc) do
    acc = [{x, y} | acc]

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

      line_points_loop(x, y, x1, y1, dx, dy, sx, sy, err, acc)
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
