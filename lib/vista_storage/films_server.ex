defmodule VistaStorage.FilmsServer do

  @moduledoc ~S"""
  This is a copy of VistaStorage.SessionsServer with all occurences of "session"
  replaced with "film". Also register_item_for_reload was changed to just
  return :ok. Also, occurences of "id_string" have been replaced with "id"

  Emacs/Vim Sequence:

  copy VistaStorage.SessionsServer
  paste into VistaStorage.CinemasServer
  :%s/session/cinema/g
  :%s/id_string/id/g
  """

  use GenServer
  require Logger

  alias VistaStorage.State
  alias VistaClient.{Film}

  # pidless API, assumes you started this server under its own name

  def me(),          do: Process.whereis(__MODULE__)
  def full_reload(), do: full_reload(me())
  def restart(),     do: Process.exit(me(), :kill)

  # which client to use
  def client, do: Application.get_env(:vista_storage, :client) || VistaClient

  # GenServer API

  def start_link(opts), do: start_link_for(__MODULE__, opts)

  def start_link_for(module, opts) do
    default_state  = State.new(:films_server)
    name =
      opts
      |> Keyword.get(:init_args, [])
      |> Keyword.get(:name, to_string(module))
    GenServer.start_link(module, {name, default_state}, opts)
  end

  def stop(server) do
    GenServer.stop(server)
  end

  def get(server) do
    GenServer.call(server, :get)
  end

  def set(server, key, value) do
    GenServer.call(server, {:set, key, value})
  end

  def full_reload(server) do
    GenServer.cast(server, :full_reload)
  end

  def notify_updated(server, args) when is_pid(server) do
    GenServer.cast(server, {:updated, args})
  end

  def notify_updated(args) when is_tuple(args) or is_atom(args)  do
    notify_updated(self(), args)
  end

  ## SERVER

  def init({name, default_state}) do
    full_reload(self())
    {:ok, %State{default_state | name: name}}
  end

  ## HANDLE_CAST

  def handle_cast(:full_reload, state) do
    {:noreply, handle(:full_reload, state)}
  end

  def handle_cast({:updated, type = :full_reload}, state) do
    apply_on_change(state.on_change, {type, :films})
    log_telemetry(:full_reload, %{count: length(state.items)})
    Logger.debug "update: full_reload - having #{length(state.items)} films, now"
    {:noreply, state}
  end

  ## CALLBACKS: HANDLE_CALL

  def handle_call(:get, _from, state) do
    {:reply, state, state}
  end

  def handle_call({:set, key, value}, _from, state) do
    {:reply, :ok, state |> Map.put(key, value)}
  end

  ## CALLBACKS: HANDLE_INFO

  def handle_info(:full_reload, state) do
    {:noreply, handle(:full_reload, state)}
  end

  # undefined messages shalle error and crash the thing. It's OK.

  # # So that unhandled messages don't error
  # def handle_info(_, state) do
  #   {:noreply, state}
  # end

  # HANDLERS, usually when both handle_cast(:what) and handle_info(:what) shall
  # do the same thing

  def handle(:full_reload, state = %State{timer: old_timer_ref, ttl: ttl}) do
    Logger.info("reload films")
    {:ok, films} = client().get_scheduled_films() # errors shall crash, will be restarted
    new_timer_ref = restart_timer(old_timer_ref, :full_reload, 1000 * ttl)
    notify_updated(:full_reload)
    %State{state | items: films, timer: new_timer_ref}
  end

  @type state     :: State.t()
  @type film_id   :: binary()
  @type index     :: integer()
  @type item      :: Item.t()
  @type items     :: [item()]
  @type maybe_ref :: reference() | nil
  @type action_id :: atom() | {atom(), any()}

  # HELPERS

  @doc """
  Restarts a timed Process.send_after(:what, whem_msecs) call.
  maybe_ref can be a timemr reference (can be timed out already) that will be
  canceled.
  """
  @spec restart_timer(maybe_ref, action_id, integer()) :: reference()
  def restart_timer(ref, action, msecs) do
    maybe_cancel_timer(ref)
    Process.send_after(self(), action, msecs)
  end

  def maybe_cancel_timer(timer) when is_reference(timer), do: Process.cancel_timer(timer)
  def maybe_cancel_timer(nil),                            do: :noop

  @spec get_index_for_id([items], film_id) :: index
  def get_index_for_id(items, id) when is_binary(id) do
    Enum.find_index(items, fn %Film{id: ^id} -> true; _ -> false end)
  end

  def apply_on_change({m, f}, args) do
    apply(m, f, [args])
  end

  def log_telemetry(what, metrics = %{}) when what in [:updated, :full_reload, :removed] do
    {module, function} = Application.get_env(:vista_storage, :log_telemetry_to)
    apply(module, function, [[:storage, :films, what, :done], metrics, %{}])
  end

end
