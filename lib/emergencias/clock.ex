defmodule Emergencias.Clock do
  @moduledoc "Fuente única de la hora actual (UTC, precisión de segundos)."

  @spec now() :: DateTime.t()
  def now, do: DateTime.utc_now() |> DateTime.truncate(:second)
end
