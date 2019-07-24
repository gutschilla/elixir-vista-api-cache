# VistaStorage

Responsible for keeping track of sessiosn, cinemas and films. Will take care of
loading, expiring and via adjusted polling frequencies - the nearer an event,
the higher the frequency.

It's a prewarmed cache that tries to stay warm, basically.

## TODO (known issues)

The whole on_chane callback and telemetry callback works are pretty simple and
also duplicate functionality. The GenServers for films and cinemas are basically
the same and just stripped-down version of the session server which incurs quite
some code duplication.

## Usage

```
cinemas  = VistaStorage.get_cinemas()
films    = VistaStorage.get_films()
sessions = VistaStorage.get_sessions()
```

The results will be same as in `VistaClient.get_something/0` but you'll get an
immediate response – that might be slightly out of date.

## Registering to change events and setting the default update frequency

It's very simple: just configure `on_change` `{module, function}` tuples to be
called on change. The default just sends update messages to `IO.inspect/1`.

```elixir
config :vista_storage,
  client: VistaClient,
  sessions_server: %{
    ttl: 3600, # every hour
    on_change: {MyApplication.EventReceiver, :on_sessions_change},
  },
  cinemas_server: %{
    ttl: 3600 * 24, # reload every day
    on_change: {MyApplication.EventReceiver, :on_cinemas_change},
  },
  films_server: %{
    ttl: 3600, # once per hour
    on_change: {MyApplication.EventReceiver, :on_films_change},
  },
```

### Event formats

By example:

```elixir
# sessions
{:removed_item, "<SESSION_ID>"} # <- this session has gone away, usually when play time is over
{:item, "<SESSION_ID>", seats_available = 42} # <- this session has 42 seats left (was different number before)
{:full_reload, :sessions} # <- all sessions have been reloaded and need updating

# films
{:full_reload, :films} # <- all films have been reloaded. Since films aren't changing every minute, full reloads shall do the trick for now

# cinemas
{:full_reload, :cinemas} # <- all cinemas have been reloaded. Since we don't open/close cinemas every day, expect this happen rarely.
```

## Registering telemetry receiver function

```elixir
config :vista_storage, log_telemetry_to: {MyApplication, :telemetry_execute}
```

This function must have an arity of 3 receiving these arguments:

- list of atoms describing what happend
- metrics
- an empty list

### list of possible call arguments to telemetry receiver

```
[[:storage, :sessions, :unchanged,   :done], %{id: "<SESSION_ID>"}] # <- updated session, nothing changed
[[:storage, :sessions, :updated,     :done], %{seats_available: 45, id: "<SESSION_ID>"}] # <- updated session, now having 45 seats left
[[:storage, :sessions, :removed,     :done], %{count: 19}, %{id: "<SESSION_ID>"}] # <- removed session, having 19 sessions left
[[:storage, :sessions, :full_reload, :done], %{count: 20}, %{}] # <- now having 20 sessions scheduled

[[:storage, :cinemas, :full_reload,  :done], %{count: 4}, %{}] # <- now having 4 cinmeas
[[:storage, :films,   :full_reload,  :done], %{count: 9}, %{}] # <- now having 9 films scheduled
```

The bigger difference to the on_change callbacks above is that `:unchanged`
telemetry events will also appear.

## Installation

The package can be installed by adding `vista_storage` to your list of
dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:vista_storage, "~> 0.1.0"}
  ]
end
```
