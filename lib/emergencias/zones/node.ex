defmodule Emergencias.Zones.Node do
  @moduledoc """
  Nodo de la jerarquía **zona → sectores → puntos de atención**. `affected` son las
  personas afectadas contabilizadas directamente en el nodo; el acumulado de un
  nodo suma además el de todos sus hijos (ver `Emergencias.Zones.Tree`).
  """

  @enforce_keys [:code, :name, :kind, :level]
  defstruct [:code, :name, :kind, :level, affected: 0, children: []]

  @type t :: %__MODULE__{}
end
