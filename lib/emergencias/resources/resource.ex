defmodule Emergencias.Resources.Resource do
  @moduledoc """
  Existencias de un recurso en una ubicación (centro de acopio, albergue o punto
  de atención). El `code` identifica al recurso; sus existencias pueden estar
  repartidas en varias ubicaciones por transferencias.
  """

  @enforce_keys [:code, :name, :category, :unit, :location, :zone]
  defstruct [:code, :name, :category, :unit, :location, :zone, quantity: 0]

  @type t :: %__MODULE__{}
end
