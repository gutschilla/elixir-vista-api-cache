# This file is responsible for configuring your application
# and its dependencies with the aid of the Mix.Config module.
use Mix.Config

config :vista_storage,
  client: VistaClient,
  sessions_server: %{
    ttl: 3600, # every hour
    on_change: {IO, :inspect},
  },
  cinemas_server: %{
    ttl: 3600 * 24, # reload every day
    on_change: {IO, :inspect},
  },
  films_server: %{
    ttl: 3600, # once per hour
    on_change: {IO, :inspect},
  },
  # in the Signage project this will be configured as {SignageTelemetry, :execute}
  # SignageTelemetry.execute([:storage, :cinemas, what, :done], metrics, %{})
  log_telemetry_to: {VistaStorage, :telemetry_execute_mock}

config :vista_storage, VistaStorage.Scheduler,
  jobs: [
    # Relaod sessions every hour
    {"10 * * * *",  {VistaStorage.SessionsServer, :restart, []}},
    # Every day at around 5 AM, restart servers
    {"20 5 * * *",  {VistaStorage.FilmsServer,    :restart, []}},
    {"30 5 * * *",  {VistaStorage.CinemasServer,  :restart, []}},
  ]

# This configuration is loaded before any dependency and is restricted
# to this project. If another project depends on this project, this
# file won't be loaded nor affect the parent project. For this reason,
# if you want to provide default values for your application for
# third-party users, it should be done in your "mix.exs" file.

# You can configure your application as:
#
#     config :vista_storage, key: :value
#
# and access this configuration in your application as:
#
#     Application.get_env(:vista_storage, :key)
#
# You can also configure a third-party app:
#
#     config :logger, level: :info
#

# It is also possible to import configuration files, relative to this
# directory. For example, you can emulate configuration per environment
# by uncommenting the line below and defining dev.exs, test.exs and such.
# Configuration from the imported file will override the ones defined
# here (which is why it is important to import them last).
#
import_config "#{Mix.env()}.exs"
