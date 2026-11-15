defmodule Emergencias.Zones.Server do
  @moduledoc "GenServer que mantiene las zonas (raíces de los árboles). Toda modificación es atómica."

  use Emergencias.Server, file: "zones"

  alias Emergencias.Storage
  alias Emergencias.Zones.Tree

  defp initial_state, do: %{}

  def register_zone(zone), do: call({:register_zone, zone})
  def add_child(parent_code, node), do: call({:add_child, parent_code, node})
  def get(code), do: call({:get, code})
  def list, do: call(:list)

  @impl true
  def handle_call({:register_zone, zone}, _from, zones) do
    if code_taken?(zones, zone.code),
      do: {:reply, {:error, {:duplicate, :zone, zone.code}}, zones},
      else: Storage.commit(@file_name, zones, Map.put(zones, zone.code, zone), {:ok, zone})
  end

  # Los códigos de zonas, sectores y puntos son únicos en todo el sistema.
  def handle_call({:add_child, parent_code, node}, _from, zones) do
    with :ok <- ensure_free(zones, node.code),
         {:ok, root_code, root} <- fetch_root(zones, parent_code),
         {:ok, new_root} <- Tree.insert(root, parent_code, node) do
      Storage.commit(@file_name, zones, Map.put(zones, root_code, new_root), {:ok, node})
    else
      {:error, _} = error -> {:reply, error, zones}
    end
  end

  def handle_call({:get, code}, _from, zones) do
    reply =
      case find_root(zones, code) do
        nil -> {:error, {:not_found, :zone, code}}
        {_root_code, root} -> Tree.find(root, code)
      end

    {:reply, reply, zones}
  end

  def handle_call(:list, _from, zones),
    do: {:reply, zones |> Map.values() |> Enum.sort_by(& &1.code), zones}

  defp code_taken?(zones, code), do: find_root(zones, code) != nil

  defp find_root(zones, code),
    do: Enum.find(zones, fn {_root_code, root} -> Tree.find(root, code) != :error end)

  defp ensure_free(zones, code),
    do: if(code_taken?(zones, code), do: {:error, {:duplicate, :zone, code}}, else: :ok)

  defp fetch_root(zones, code) do
    case find_root(zones, code) do
      nil -> {:error, {:not_found, :zone, code}}
      {root_code, root} -> {:ok, root_code, root}
    end
  end
end
