defmodule SampleApp.WiFi do
  # Wi-Fi STA mode
  @sta_config [
    dhcp_hostname: "piyopiyo",
    connected: &__MODULE__.handle_sta_connected/0,
    disconnected: &__MODULE__.handle_sta_disconnected/0,
    got_ip: &__MODULE__.handle_sta_got_ip/1
  ]

  # Sync time via SNTP
  @sntp_config [
    host: "pool.ntp.org",
    synchronized: &__MODULE__.handle_sntp_synchronized/1
  ]

  def start do
    wifi_ssid = SampleApp.NVS.get_binary(:sta_ssid)
    wifi_passphrase = SampleApp.NVS.get_binary(:sta_psk)

    # Start Wi-Fi in the background so the UI can start immediately.
    spawn(fn -> start_network(wifi_ssid, wifi_passphrase) end)
  end

  defp start_network(_wifi_ssid = nil, _wifi_passphrase) do
    IO.puts("wifi: ssid is missing")
  end

  defp start_network(wifi_ssid, wifi_passphrase) do
    network_config = [
      sta:
        @sta_config
        |> Keyword.put(:ssid, wifi_ssid)
        |> maybe_put(:psk, wifi_passphrase),
      sntp: @sntp_config
    ]

    result =
      try do
        :network.start(network_config)
      catch
        kind, reason -> {:error, {kind, reason}}
      end

    case result do
      {:ok, _pid} ->
        IO.puts("wifi: started")

      {:error, reason} ->
        IO.puts("wifi: start failed #{inspect(reason)}")
    end
  end

  defp maybe_put(keyword, _key, nil), do: keyword
  defp maybe_put(keyword, key, value) when is_binary(value), do: Keyword.put(keyword, key, value)

  def handle_sta_connected do
    IO.puts("wifi: connected to AP")
  end

  def handle_sta_disconnected do
    IO.puts("wifi: disconnected from AP")
  end

  def handle_sta_got_ip(ip_info) do
    IO.puts("wifi: got IP #{inspect(ip_info)}")
  end

  def handle_sntp_synchronized(timeval) do
    try do
      IO.puts("sntp: synced #{inspect(timeval)}")
    catch
      _, reason ->
        IO.puts("sntp: callback failed #{inspect(reason)} #{inspect(timeval)}")
    end
  end
end
