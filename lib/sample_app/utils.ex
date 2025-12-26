defmodule SampleApp.Utils do
  @swap_red_blue Application.compile_env(:sample_app, :swap_red_blue, false)

  def panel_color(rgb24) when rgb24 in 0..0xFFFFFF do
    if @swap_red_blue do
      <<r::8, g::8, b::8>> = <<rgb24::24>>
      b * 0x10000 + g * 0x100 + r
    else
      rgb24
    end
  end
end
