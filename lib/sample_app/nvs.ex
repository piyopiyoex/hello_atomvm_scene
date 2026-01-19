defmodule SampleApp.NVS do
  @moduledoc """
  Tiny wrapper around ESP32 NVS for this app.
  """

  @compile {:no_warn_undefined, :esp}

  @namespace :piyopiyo

  def get_binary(key) when is_atom(key) do
    case :esp.nvs_get_binary(@namespace, key) do
      :undefined -> nil
      <<>> -> nil
      value when is_binary(value) -> value
    end
  end

  def put_binary(key, value) when is_atom(key) and is_binary(value) do
    :esp.nvs_put_binary(@namespace, key, value)
  end

  def delete(key) when is_atom(key) do
    :esp.nvs_erase_key(@namespace, key)
  end

  def delete_all do
    :esp.nvs_erase_all(@namespace)
  end
end
