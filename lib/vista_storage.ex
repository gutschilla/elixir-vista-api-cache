defmodule VistaStorage do

  alias VistaStorage.State
  alias VistaClient.{Session, Film, Cinema}

  def get_cinemas do
    # Using ItemServer (no reloads as we're probably not building a site every day)
    VistaStorage.CinemasServer
    |> Process.whereis()
    |> VistaStorage.CinemasServer.get()
    |> handle_state(:cinemas)
  end

  def get_scheduled_films do
    # Using ReloadServer, but w/o individual reloads for films
    VistaStorage.FilmsServer
    |> Process.whereis()
    |> VistaStorage.FilmsServer.get()
    |> handle_state(:films)
  end

  def get_sessions do
    # Using ReloadServer with individual reloads per session
    VistaStorage.SessionsServer
    |> Process.whereis()
    |> VistaStorage.SessionsServer.get()
    |> handle_state(:sessions)
  end

  def handle_state(%State{items: []}, atom) when atom in [:sessions, :films, :cinemas] do
    {:error, :not_yet_loaded}
  end
  def handle_state(%State{items: items = [%Session{}|_tail]}, :sessions) do
    {:ok, items}
  end
  def handle_state(%State{items: items = [%Film{}|_tail]}, :films) do
    {:ok, items}
  end
  def handle_state(%State{items: items = [%Cinema{}|_tail]}, :cinemas) do
    {:ok, items}
  end

  def telemetry_execute_mock(path_list, metrics, opts_map) do
    IO.inspect({:telemetry_execute_mock, path_list, metrics, opts_map})
  end

end

