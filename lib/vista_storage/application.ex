defmodule VistaStorage.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  alias VistaStorage.{SessionsServer, FilmsServer, CinemasServer}
  use Application
  import Supervisor, only: [child_spec: 2]

  def start(_type, _args) do
    # List all child processes to be supervised
    children = [
      # Quantum
      {VistaStorage.Scheduler, []},

      # now, our three Servers
      child_spec(
        {
          SessionsServer, [
            init_args: [name: "Sessions"],
            name: SessionsServer
          ]
        },
        id: :sessions
      ),
      child_spec(
        {
          FilmsServer, [
            init_args: [name: "Films"],
            name: FilmsServer
          ]
        },
        id: :films
      ),
      child_spec(
        {
          CinemasServer, [
            init_args: [name: "Cinemas"],
            name: CinemasServer
          ]
        },
        id: :cinema
      ),
    ]

    opts = [strategy: :one_for_one, name: VistaStorage.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @doc """
  Directly set VistaStorage.<Session|Film|Cinema>Server's on_change callback
  {module, function}-tuple to whatwver is configured (see doc for
  redefine_server_callbacks/0).

  Also, set the Application env.

  # EXAMPLE

  iex> {VistaStorage.SessionsServer, SignageWeb.SessionsChannel, :on_session_change} |> redefine_server_callback()

  # CAUTION

  This assumes that Server modules are namespaced like this: **Main.Sub** e.g.
  VistaStorage.SessionsServer (two parts). This will not work if the server's
  name is like VistaStorage.NextCool.WhatnotServer (3 parts).
  """
  def redefine_server_callback({server_module, callback_module, callback_function}) do
    server = Process.whereis(server_module)
    server_module.set(server, :on_change, {callback_module, callback_function})

    # set app configuration so restarts of servers will load it from there
    # [:vista_storage, :sessions_server] = VistaStorage.SessionsServer |> Module.split() …

    [main, sub] = # <- will fail when Module.split() returns anything else but 2 parts
      server_module
      |> Module.split()
      |> Enum.map(&Macro.underscore/1)
      |> Enum.map(&String.to_existing_atom/1)

    config = Application.get_env(main, sub)
    Application.put_env(main, sub, Map.put(config, :on_change, {callback_module, callback_function}))
  end
end
