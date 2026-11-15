defmodule Emergencias.Zones.Tree do
  @moduledoc """
  Funciones **puras y recursivas** sobre la jerarquía zona → sectores → puntos de
  atención: reciben un árbol y devuelven uno nuevo (estructuras inmutables).
  """

  alias Emergencias.Zones.Node

  @allowed_children %{zona: [:sector], sector: [:punto_atencion], punto_atencion: []}

  @doc "Búsqueda en profundidad de un nodo por código."
  @spec find(Node.t(), String.t()) :: {:ok, Node.t()} | :error
  def find(%Node{code: code} = node, code), do: {:ok, node}
  def find(%Node{children: children}, code), do: find_in(children, code)

  defp find_in([], _code), do: :error

  defp find_in([child | siblings], code) do
    case find(child, code) do
      {:ok, _} = found -> found
      :error -> find_in(siblings, code)
    end
  end

  @doc "Inserta `child` bajo el nodo con código `parent_code`, en cualquier nivel del árbol."
  @spec insert(Node.t(), String.t(), Node.t()) :: {:ok, Node.t()} | {:error, term()}
  def insert(%Node{code: parent_code} = parent, parent_code, %Node{} = child) do
    if child.kind in Map.fetch!(@allowed_children, parent.kind),
      do: {:ok, %{parent | children: parent.children ++ [child]}},
      else: {:error, {:invalid_child, parent.kind, child.kind}}
  end

  def insert(%Node{children: children} = node, parent_code, child) do
    with {:ok, new_children} <- insert_in(children, parent_code, child, []),
         do: {:ok, %{node | children: new_children}}
  end

  defp insert_in([], parent_code, _child, _seen), do: {:error, {:not_found, :zone, parent_code}}

  defp insert_in([head | tail], parent_code, child, seen) do
    case insert(head, parent_code, child) do
      {:ok, new_head} -> {:ok, Enum.reverse(seen, [new_head | tail])}
      {:error, {:not_found, :zone, _}} -> insert_in(tail, parent_code, child, [head | seen])
      {:error, _} = error -> error
    end
  end

  @doc "Personas afectadas acumuladas: las del nodo más las de todos sus descendientes."
  @spec total_affected(Node.t()) :: non_neg_integer()
  def total_affected(%Node{affected: own, children: children}) do
    Enum.reduce(children, own, fn child, acc -> acc + total_affected(child) end)
  end

  @doc "Lista `{profundidad, nodo}` en preorden, útil para dibujar el árbol."
  @spec flatten(Node.t(), non_neg_integer()) :: [{non_neg_integer(), Node.t()}]
  def flatten(%Node{children: children} = node, depth \\ 0) do
    [{depth, node} | Enum.flat_map(children, &flatten(&1, depth + 1))]
  end

  @doc "Estadísticas acumuladas del subárbol: nodos por tipo, profundidad, afectados y niveles."
  @spec stats(Node.t()) :: map()
  def stats(%Node{} = node) do
    children = Enum.map(node.children, &stats/1)
    sum = fn key -> Enum.reduce(children, 0, &(&1[key] + &2)) end

    %{
      nodes: 1 + sum.(:nodes),
      sectors: if(node.kind == :sector, do: 1, else: 0) + sum.(:sectors),
      points: if(node.kind == :punto_atencion, do: 1, else: 0) + sum.(:points),
      depth: 1 + (children |> Enum.map(& &1.depth) |> Enum.max(fn -> 0 end)),
      affected: node.affected + sum.(:affected),
      by_level:
        Enum.reduce(children, %{node.level => 1}, fn child, acc ->
          Map.merge(acc, child.by_level, fn _level, a, b -> a + b end)
        end)
    }
  end
end
