defmodule SampleApp.TouchInput do
  @xpt2046_cmd_read_x 0xD0
  @xpt2046_cmd_read_y 0x90

  def start_link(opts) do
    pid = spawn_link(__MODULE__, :init, [opts])
    {:ok, pid}
  end

  def init(opts) do
    touch_opts = Keyword.get(opts, :touch, [])
    cal = Keyword.get(touch_opts, :calibration, [])

    poll_ms = Keyword.get(touch_opts, :poll_ms, 25)
    emit_mode = Keyword.get(touch_opts, :emit_mode, :edge)

    screen_w = Keyword.fetch!(opts, :width)
    screen_h = Keyword.fetch!(opts, :height)
    rotation = Keyword.get(opts, :rotation, 0)

    {native_w, native_h} =
      if rotation in [1, 3] do
        {screen_h, screen_w}
      else
        {screen_w, screen_h}
      end

    state = %{
      spi: Keyword.fetch!(opts, :spi),
      device: Keyword.fetch!(opts, :device),
      poll_ms: poll_ms,
      emit_mode: emit_mode,
      screen_w: screen_w,
      screen_h: screen_h,
      rotation: rotation,
      native_w: native_w,
      native_h: native_h,
      raw_x_min: Keyword.get(cal, :raw_x_min, 80),
      raw_x_max: Keyword.get(cal, :raw_x_max, 1950),
      raw_y_min: Keyword.get(cal, :raw_y_min, 80),
      raw_y_max: Keyword.get(cal, :raw_y_max, 1950),
      swap_xy: Keyword.get(cal, :swap_xy, false),
      invert_x: Keyword.get(cal, :invert_x, false),
      invert_y: Keyword.get(cal, :invert_y, false),
      subscribers: MapSet.new(),
      pressed?: false
    }

    send(self(), :poll)
    loop(state)
  end

  defp loop(state) do
    receive do
      {:"$call", from, request} ->
        loop(handle_call(from, request, state))

      {:"$gen_call", from, request} ->
        loop(handle_call(from, request, state))

      :poll ->
        state = poll_and_emit(state)
        Process.send_after(self(), :poll, state.poll_ms)
        loop(state)

      _ ->
        loop(state)
    end
  end

  defp handle_call(from, request, state) do
    case request do
      :subscribe_input ->
        state = subscribe(from, state)
        reply(from, :ok)
        state

      {:subscribe_input} ->
        state = subscribe(from, state)
        reply(from, :ok)
        state

      {:subscribe_input, pid} when is_pid(pid) ->
        reply(from, :ok)
        %{state | subscribers: MapSet.put(state.subscribers, pid)}

      _ ->
        reply(from, :ok)
        state
    end
  end

  defp subscribe({pid, _ref}, state) when is_pid(pid) do
    %{state | subscribers: MapSet.put(state.subscribers, pid)}
  end

  defp reply({pid, ref}, value), do: send(pid, {ref, value})

  defp poll_and_emit(state) do
    {raw_x0, raw_y0} = read_raw_xy(state)

    # treat “in-range” as pressed (simple + works OK for calibration)
    pressed? =
      in_range?(raw_x0, state.raw_x_min, state.raw_x_max) and
        in_range?(raw_y0, state.raw_y_min, state.raw_y_max)

    cond do
      pressed? and should_emit?(state) ->
        {x, y} = to_screen_point(raw_x0, raw_y0, state)
        broadcast(state.subscribers, {:touch, x, y, raw_x0, raw_y0})
        %{state | pressed?: true}

      pressed? ->
        %{state | pressed?: true}

      true ->
        %{state | pressed?: false}
    end
  end

  defp should_emit?(%{emit_mode: :drag}), do: true
  defp should_emit?(%{emit_mode: :edge, pressed?: pressed?}), do: not pressed?

  defp broadcast(subscribers, event) do
    Enum.each(subscribers, fn pid -> send(pid, event) end)
  end

  defp read_raw_xy(state) do
    rx = read12(state, @xpt2046_cmd_read_x)
    ry = read12(state, @xpt2046_cmd_read_y)

    if state.swap_xy, do: {ry, rx}, else: {rx, ry}
  end

  defp to_screen_point(raw_x, raw_y, state) do
    # 1) scale into native (rotation=0) coordinate space
    x0 = scale(raw_x, state.raw_x_min, state.raw_x_max, state.native_w - 1)
    y0 = scale(raw_y, state.raw_y_min, state.raw_y_max, state.native_h - 1)

    x0 = if state.invert_x, do: state.native_w - 1 - x0, else: x0
    y0 = if state.invert_y, do: state.native_h - 1 - y0, else: y0

    # 2) rotate into screen coordinate space
    apply_rotation({x0, y0}, state.rotation, state.screen_w, state.screen_h)
  end

  defp in_range?(v, min_v, max_v), do: v >= min_v and v <= max_v

  defp read12(state, cmd) do
    case :spi.write_read(state.spi, state.device, %{write_data: <<cmd, 0x00, 0x00>>}) do
      {:ok, <<_::8, hi::8, lo::8>>} ->
        div(hi * 256 + lo, 16)

      _ ->
        0
    end
  end

  defp scale(v, min_v, max_v, max_out) do
    v = clamp(v, min_v, max_v)
    range = max_v - min_v
    if range <= 0, do: 0, else: div((v - min_v) * max_out, range)
  end

  defp clamp(v, min_v, _max_v) when v < min_v, do: min_v
  defp clamp(v, _min_v, max_v) when v > max_v, do: max_v
  defp clamp(v, _min_v, _max_v), do: v

  defp apply_rotation({x, y}, 0, _w, _h), do: {x, y}
  defp apply_rotation({x, y}, 1, w, _h), do: {w - 1 - y, x}
  defp apply_rotation({x, y}, 2, w, h), do: {w - 1 - x, h - 1 - y}
  defp apply_rotation({x, y}, 3, _w, h), do: {y, h - 1 - x}
end
