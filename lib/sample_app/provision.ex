defmodule SampleApp.Provision do
  @wifi_ssid System.get_env("ATOMVM_WIFI_SSID")
  @wifi_passphrase System.get_env("ATOMVM_WIFI_PASSPHRASE")
  @wifi_force System.get_env("ATOMVM_WIFI_FORCE")

  def maybe_provision do
    if present?(@wifi_ssid) do
      if force_enabled?(@wifi_force) do
        write_credentials_to_nvs(@wifi_ssid, @wifi_passphrase, reason: "forced overwrite")
      else
        write_credentials_to_nvs_if_missing(@wifi_ssid, @wifi_passphrase)
      end
    end

    :ok
  end

  defp write_credentials_to_nvs_if_missing(ssid, passphrase) do
    case SampleApp.NVS.get_binary(:sta_ssid) do
      nil -> write_credentials_to_nvs(ssid, passphrase, reason: "first-time provision")
      _ -> :ok
    end
  end

  defp write_credentials_to_nvs(ssid, passphrase, reason: reason) do
    :ok = SampleApp.NVS.put_binary(:sta_ssid, ssid)

    # Passphrase is optional (open networks). Only write if present.
    if present?(passphrase) do
      :ok = SampleApp.NVS.put_binary(:sta_psk, passphrase)
    end

    IO.puts("wifi: #{reason} -> wrote atomvm:sta_ssid / atomvm:sta_psk")
    :ok
  end

  defp force_enabled?(value), do: present?(value)

  defp present?(value) when is_binary(value), do: byte_size(value) > 0
  defp present?(_value), do: false
end
