defmodule VistaStorageTest do
  use ExUnit.Case
  doctest VistaStorage

  alias VistaStorage.{SessionsServer, CinemasServer, FilmsServer}

  test "see if state is there" do
    assert VistaStorage.SessionsServer.me() |> is_pid()
    assert VistaStorage.CinemasServer.me()  |> is_pid()
    assert VistaStorage.FilmsServer.me()    |> is_pid()
  end

  defp test_server({server, atom}) do
    # store current pid so ping_me can use it
    VistaStorageTest.PidAgent.start_link(self())
    # make on_update messages arrive here
    {server, __MODULE__, :ping_me}
    |> VistaStorage.Application.redefine_server_callback()
    # this should invoke VistaStorage.SessionsServer.on_change(…) to call this
    # module's ping_me function
    server.full_reload()
    assert_receive {:full_reload, ^atom}, 10_000 # reply from mock should be quick
    VistaStorageTest.PidAgent.stop()
  end

  defp infer_atom_from(module) do
    module
    |> to_string
    |> String.split(".")
    |> List.last
    |> String.replace("Server", "")
    |> String.downcase
    |> String.to_atom
  end

  test "full reload works" do
    [SessionsServer, CinemasServer, FilmsServer]
    |> Enum.map(fn module -> {module, module |> infer_atom_from()} end)
    |> Enum.each(&test_server/1)
  end

  def ping_me(message) do
    pid = VistaStorageTest.PidAgent.value()
    Process.send(pid, message, [])
  end

end
