defmodule VistaStorage.SessionsServer do
  use GenServer
  require Logger

  alias VistaStorage.State
  alias VistaClient.{Session, SessionAvailability} # structs

  # pidless API, assumes you started this server under its own name

  def me(),          do: Process.whereis(__MODULE__)
  def full_reload(), do: full_reload(me())
  def restart(),     do: Process.exit(me(), :kill)

  # which client to use
  def client, do: Application.get_env(:vista_storage, :client) || VistaClient

  # GenServer API

  def start_link(opts), do: start_link_for(__MODULE__, opts)

  @doc ~S"""
  To allow dynamic redifing of callbacks and ttl that survive restarts of this
  gernServer, we store this config in the Application envoronment

  # CONFIG (especially for on_change {m,f} callbaks)

  - SignageWeb.Application.redefine_server_callsbacks/0 will set the Application
    environment for the modules defined in it config

  - Films-/Cinemas-/SessionsServer will take their config default from a call to
    VistaStorage.State.new(:<sessions|films|cinemas>_server)

  - VistaStorage.State.new will take its defaults from Application environent
  """
  def start_link_for(module, opts) do
    default_state = State.new(:sessions_server)
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

  def register_items(server) do
    GenServer.cast(server, :register_items)
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
    self() |> full_reload()
    {:ok, %State{default_state | name: name}}
  end

  ## HANDLE_CAST

  def handle_cast(:full_reload, state) do
    {:noreply, handle(:full_reload, state)}
  end

  def handle_cast(:register_items, state = %State{items: items, ttl: ttl, name: name}) do
    Logger.debug(":register_items for #{length(items)} items in #{name}")
    # depending on time-till-show, reload each sessions possibly sooner
    Enum.each(items, fn item -> register_item_for_reload(item, ttl) end)
    {:noreply, state}
  end

  def handle_cast({:updated, {type = :removed_item, id}}, state) do
    apply_on_change(state.on_change, {type, id})
    log_telemetry(:removed, %{count: length(state.items), id: id})
    Logger.debug "removed session #{id}} - having #{length(state.items)} sessions, now"
    {:noreply, state}
  end

  def handle_cast({:updated, {type = :item, id, seats_available}}, state) do
    apply_on_change(state.on_change, {type, id, seats_available})
    log_telemetry(:updated, %{seats_available: seats_available, id: id})
    Logger.debug "update seating for session id: #{id}, seats: #{seats_available}"
    {:noreply, state}
  end

  def handle_cast({:updated, type = :full_reload}, state) do
    apply_on_change(state.on_change, {type, :sessions})
    log_telemetry(:full_reload, %{count: length(state.items)})
    Logger.debug "update #{type}} sessions"
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

  def handle_info({:reload_item, id}, state = %State{items: items}) do
    Logger.debug "reloading session id:#{id}"
    items
    |> Enum.any?(fn %Session{id_string: ^id} -> true; _ -> false end)
    |> handle_reload(state, id)
  end

  # undefined messages shalle error and crash the thing. It's OK.

  # # So that unhandled messages don't error
  # def handle_info(_, state) do
  #   {:noreply, state}
  # end

  # HANDLERS, usually when both handle_cast(:what) and handle_info(:what) shall
  # do the same thing

  def handle(:full_reload, state = %State{timer: old_timer_ref, ttl: ttl}) do
    Logger.info("reload sessions")
    {:ok, sessions} = client().get_sessions() # errors shall crash, will be restarted
    new_timer_ref = restart_timer(old_timer_ref, :full_reload, 1000 * ttl)
    notify_updated(:full_reload)
    register_items(self())
    %State{state | items: sessions, timer: new_timer_ref}
  end

  @type state       :: State.t()
  @type id_in_items :: boolean()
  @type session_id  :: binary()
  @type index       :: integer()

  @spec handle_reload(id_in_items, state, session_id) :: {:noreply, state}
  def handle_reload(true, state = %State{items: items}, id) do
    Logger.debug "attempting to reload session id: #{id}"
    with {:ok, seats_available}         <- reload_session_availability(id),
         index when is_integer(index)   <- get_index_for_id(items, id),
         {:updated, updated = %State{}} <- update_session_availability(state, index, id, seats_available), # could also (oftlen) yield {:unchanged, state} => do nothing
         {:p, :ok}                      <- {:p, notify_updated({:item, id, seats_available})},
         item = %Session{}              <- Enum.at(updated.items, index),
         {:r, :ok}                      <- {:r, register_item_for_reload(item, updated.ttl)} do
      {:noreply, updated}
    else
      {:unchanged, _session_state}        -> log_telemetry(:unchanged, %{id: id}); {:noreply, state}
      {:error, {:session_not_found, _id}} -> handle_removed(state, id)
      _                                   -> {:noreply, state}
    end
    {:noreply, state}
  end

  def handle_reload(false, state, id) when is_binary(id) do
    Logger.debug "session id: #{id} to update not in state items any more."
    {:noreply, state}
  end

  @spec handle_removed(state, session_id) :: {:noreply, state}
  def handle_removed(state = %State{items: items}, id) when is_binary(id) do
    Logger.debug "removing session id: #{id}"
    # send "removed"-update no matter what
    notify_updated({:removed_item, id})

    with index when is_integer(index) <- get_index_for_id(items, id),
         new_state <- remove_session(state, index) do
      {:noreply, new_state}
    else
      _ -> {:noreply, state}
    end
  end

  # HELPERS

  @type maybe_ref :: reference() | nil
  @type action_id :: atom() | {atom(), any()}
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

  @spec get_index_for_id([items], session_id) :: index
  def get_index_for_id(items, id) when is_binary(id) do
    Enum.find_index(items, fn %Session{id_string: ^id} -> true; _ -> false end)
  end

  @spec remove_session(state, index) :: state
  def remove_session(state = %State{items: sessions}, index) do
    updated = List.delete_at(sessions, index)
    %State{state | items: updated}
  end

  @spec update_session_availability(state, index, session_id, integer()) :: state
  def update_session_availability(state = %State{items: items}, index, id, seats_available) do
    Logger.debug "session availablility for id: #{id} successfully reloaded: #{seats_available}"
    old_item = Enum.at(items, index)
    if old_item.seats_available == seats_available do
      replaced = List.update_at(items, index, fn session -> %Session{ session | seats_available: seats_available} end)
      {:updated, %State{state | items: replaced}}
    else
      {:unchanged, state}
    end
  end

  def apply_on_change({m, f}, args) do
    apply(m, f, [args])
  end

  @type item    :: Item.t()
  @type items   :: [item()]
  @type seconds :: integer()
  @type reason  :: any()

  def register_item_for_reload(item = %Session{id_string: id}, ttl) do
    with when_to_reload <- when_to_reload(item, ttl),
          _timer_ref    <- register_reload(when_to_reload, id) do
      _action =
        case when_to_reload do
          {:after, s}   -> Logger.debug("registering session #{id} for reload after #{s} seconds")
          _now_or_never -> :noop
        end
      :ok
    end
  end

  def register_reload({:after, seconds}, id), do: Process.send_after(self(), {:reload_item, id}, seconds * 1000)
  def register_reload(:now,              id), do: Process.send(      self(), {:reload_item, id}, [])
  def register_reload(:never,           _id), do: :ok

  def when_to_reload(session = %Session{}, ttl) do
    # reload more often when session is about to be screened
    # never reload when screening has happened
    # otherwise, reload randomly every hour (on average) or so
    session
    |> Session.showing_in
    |> when_to_reload(ttl)
  end

  def when_to_reload(seconds, _ttl)
  when is_integer(seconds) and seconds <= -1200 do
    # no need to reload old session (-1200 => 20 minutes after start)
    :never
  end

  def when_to_reload(seconds, ttl)
  when is_integer(seconds) and seconds >= ttl do
    # no need to reload as will be reloaded in full_reload cycle
    :never
  end

  def when_to_reload(seconds, _ttl)
  when is_integer(seconds) and seconds > -600 and seconds <= 600 do
    # ten minutes before and after show begin: always reload each 10 secs
    {:after, 10}
  end

  def when_to_reload(seconds, ttl)
  when is_integer(seconds) and seconds > -1200 and seconds < ttl do
    # when we're approaching the screening, make reloads faster as closer we get
    # but don'r reload faster than once every minute
    cutoff  = seconds - 600
    upper   = :math.pow(cutoff, 2) # quadratic increase => slow
    ratio   = ttl * 2
    rated   = upper / ratio # ratio
    add_min = 60 + rated    # start at 60
    calculated = trunc(add_min)
    # IO.inspect({:sec_ttl_calc, seconds, ttl, calculated})
    {:after, calculated}
  end

  def reload_session_availability(id) do
    with {:ok, %SessionAvailability{seats_available: seats_available } } <- client().get_session_availabilty(id) do
      {:ok, seats_available}
    end
  end

  def log_telemetry(what, metrics = %{}) when what in [:updated, :full_reload, :removed] do
    {module, function} = Application.get_env(:vista_storage, :log_telemetry_to)
    apply(module, function, [[:storage, :sessions, what, :done], metrics, %{}])
  end

end
