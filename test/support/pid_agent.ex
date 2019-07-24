defmodule VistaStorageTest.PidAgent do
  use Agent

  @moduledoc """
  This allows you to store some value. Abusable as global variable.
  """

  def start_link(initial_value) do
    Agent.start_link(fn -> initial_value end, name: __MODULE__)
  end
  def value do
    Agent.get(__MODULE__, & &1)
  end
  def stop do
    Agent.stop(__MODULE__)
  end

end
