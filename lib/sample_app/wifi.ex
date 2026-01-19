defmodule SampleApp.WiFi do
  @moduledoc """
  Start Wi-Fi (STA) and synchronize time via SNTP.
  """

  @compile {:no_warn_undefined, :network}

  @dhcp_hostname "piyopiyo"
  @sntp_host "jp.pool.ntp.org"

  def start_link(_opts \\ []) do
    case fetch_wifi_credentials() do
      {:ok, {wifi_ssid, wifi_passphrase}} ->
        :network.start_link(
          sta:
            [
              dhcp_hostname: @dhcp_hostname,
              connected: &handle_sta_connected/0,
              disconnected: &handle_sta_disconnected/0,
              got_ip: &handle_sta_got_ip/1,
              ssid: wifi_ssid
            ]
            |> maybe_put(:psk, wifi_passphrase),
          sntp: [
            host: @sntp_host,
            synchronized: &handle_sntp_synchronized/1
          ]
        )

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp fetch_wifi_credentials do
    wifi_ssid = SampleApp.NVS.get_binary(:wifi_ssid)

    if is_nil(wifi_ssid) do
      IO.puts("wifi: missing SSID in NVS (key: wifi_ssid). Provision first.")
      {:error, {:missing_nvs_key, :wifi_ssid}}
    else
      wifi_passphrase = SampleApp.NVS.get_binary(:wifi_passphrase)
      {:ok, {wifi_ssid, wifi_passphrase}}
    end
  end

  defp maybe_put(keyword, _key, nil), do: keyword
  defp maybe_put(keyword, key, value) when is_binary(value), do: Keyword.put(keyword, key, value)

  def handle_sta_connected, do: IO.puts("wifi: connected to AP")
  def handle_sta_disconnected, do: IO.puts("wifi: disconnected from AP")
  def handle_sta_got_ip(ip_info), do: IO.puts("wifi: got IP #{inspect(ip_info)}")
  def handle_sntp_synchronized(timeval), do: IO.puts("sntp: synced #{inspect(timeval)}")
end
