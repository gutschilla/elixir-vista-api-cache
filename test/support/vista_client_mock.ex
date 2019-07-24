defmodule VistaClient.Mock do

  # make sure we implenet it all
  @behaviour VistaClient.Behaviour

  def get_fixture(mocked_call) do
    priv_dir = :code.priv_dir(:vista_storage)
    "#{priv_dir}/fixtures/VistaClient.#{mocked_call}.term"
    |> File.read!
    |> :erlang.binary_to_term
  end

  def get_sessions,        do: "get_sessions"        |> get_fixture()
  def get_scheduled_films, do: "get_scheduled_films" |> get_fixture()
  def get_cinemas,         do: "get_cinemas"         |> get_fixture()

  def get_session_availabilty(),      do: get_session_availabilty(24)
  def get_session_availabilty(seats), do: %VistaClient.SessionAvailability{seats_available: seats}

end
