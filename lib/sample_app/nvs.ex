defmodule SampleApp.NVS do
  @namespace :atomvm

  # Read a binary from NVS.
  def get_binary(key) when is_atom(key) do
    case :esp.nvs_get_binary(@namespace, key) do
      :undefined -> nil
      <<>> -> nil
      value when is_binary(value) -> value
    end
  end

  # Write a binary to NVS.
  def put_binary(key, value) when is_binary(value) do
    :esp.nvs_put_binary(@namespace, key, value)
  end
end
