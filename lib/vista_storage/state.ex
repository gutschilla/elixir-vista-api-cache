defmodule VistaStorage.State do
  defstruct [
    items: [],
    ttl: 3600,
    on_change: {IO, :inspect},
    name: nil,
    timer: nil,
  ]

  def new(kind) when kind in [:sessions_server, :films_server, :cinemas_server] do
    config = Application.get_env(:vista_storage, :sessions_server)
    default = %__MODULE__{}

    %__MODULE__{
      on_change:  Map.get(config, :on_change,  default.on_change),
      ttl:        Map.get(config, :ttl,        default.ttl),
    }
  end
end
