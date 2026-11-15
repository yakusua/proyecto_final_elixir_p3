defmodule Emergencias.Zones do
  @moduledoc "Contexto de zonas: una zona contiene sectores y estos puntos de atención."

  alias Emergencias.{Types, Validation}
  alias Emergencias.Zones.{Node, Server, Tree}

  @spec register_zone(map()) :: {:ok, Node.t()} | {:error, term()}
  def register_zone(attrs),
    do: with({:ok, node} <- build(:zona, attrs), do: Server.register_zone(node))

  @spec add_sector(String.t(), map()) :: {:ok, Node.t()} | {:error, term()}
  def add_sector(parent, attrs), do: add(parent, :sector, attrs)

  @spec add_point(String.t(), map()) :: {:ok, Node.t()} | {:error, term()}
  def add_point(parent, attrs), do: add(parent, :punto_atencion, attrs)

  @doc "Busca un nodo (zona, sector o punto) por código."
  @spec get(String.t()) :: {:ok, Node.t()} | {:error, term()}
  def get(code) when is_binary(code), do: Server.get(String.downcase(String.trim(code)))

  @spec list() :: [Node.t()]
  def list, do: Server.list()

  @doc "Valida que exista una **zona** con ese código (para usar en `with`)."
  @spec ensure_exists(String.t() | nil) :: :ok | {:error, term()}
  def ensure_exists(code) do
    if Enum.any?(list(), &(&1.code == code)), do: :ok, else: {:error, {:not_found, :zone, code}}
  end

  @doc "Estadísticas acumuladas de una zona y todos sus sectores."
  @spec stats(String.t()) :: {:ok, map()} | {:error, term()}
  def stats(code) do
    with {:ok, node} <- get(code) do
      {:ok,
       Map.merge(Tree.stats(node), %{
         node: node,
         tree: for({depth, n} <- Tree.flatten(node), do: {depth, n, Tree.total_affected(n)})
       })}
    end
  end

  defp add(parent, kind, attrs) do
    with {:ok, parent} <- Validation.code(parent, :parent),
         {:ok, node} <- build(kind, attrs),
         do: Server.add_child(parent, node)
  end

  defp build(kind, attrs) do
    with {:ok, code} <- Validation.code(attrs[:code], :code),
         {:ok, name} <- Validation.text(attrs[:name], :name),
         {:ok, level} <- Types.parse(:level, attrs[:level]),
         {:ok, affected} <- Validation.non_negative_integer(attrs[:affected], :affected, 0) do
      {:ok, %Node{code: code, name: name, kind: kind, level: level, affected: affected}}
    end
  end
end
