Genomu.Config.config do
  {:ok, hostname} = :inet.gethostname
  config.instance_name (hostname |> to_binary) <> "1"
  config.http_port 9119
  config.handoff_port 8099
  config.quiet_mode true
end