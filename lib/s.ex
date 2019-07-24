defmodule S do
  @moduledoc """
  provides a quick-to-type shortcut to :init.stop() in order do perform a
  graceful application shutdown

  # Usage

  `S.top`

  same as: `:init.stop`

  The idea is that since this module only has one function, in `iex`, you can
  type `S`, then `.` and `<TAB>` and hint `<ENTER>` which is pretty quick.

  """
  def top do
    :init.stop()
  end

  @doc """
  Helper to remove bajillions of log messages from terminal when hooking into
  session.
  """
  def top_logging() do
    Logger.remove_backend(:console)
  end
end
