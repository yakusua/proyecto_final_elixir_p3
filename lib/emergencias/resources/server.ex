defmodule Emergencias.Resources.Server do
  @moduledoc """
  GenServer dueño del inventario.

  **Garantía de concurrencia:** todas las solicitudes llegan al buzón de este
  proceso y se atienden una por una. Si dos solicitudes quieren los últimos 50
  litros, la primera los obtiene y la segunda recibe `{:insufficient_stock, _}`:
  lo asignado nunca supera lo disponible. Cada operación se guarda en disco antes
  de confirmarse.
  """

  use Emergencias.Server, file: "resources"

  alias Emergencias.Resources.Inventory
  alias Emergencias.Storage

  defp initial_state, do: %Inventory{}

  def register(resource, actor), do: call({:register, resource, actor})
  def add(code, location, qty, actor), do: call({:add, code, location, qty, actor})
  def remove(code, location, qty, actor), do: call({:remove, code, location, qty, actor})

  def transfer(code, from, to, qty, zone, actor),
    do: call({:transfer, code, from, to, qty, zone, actor})

  def allocate(category, qty, zone, need_id, actor),
    do: call({:allocate, category, qty, zone, need_id, actor})

  def release(allocations, need_id, actor), do: call({:release, allocations, need_id, actor})
  def query(fun) when is_function(fun, 1), do: call({:query, fun})

  @impl true
  def handle_call({:register, resource, actor}, _from, inv) do
    apply_change(inv, Inventory.register(inv, resource, actor), fn _ -> {:ok, resource} end)
  end

  def handle_call({:add, code, location, qty, actor}, _from, inv) do
    apply_change(
      inv,
      Inventory.add(inv, code, location, qty, actor),
      &{:ok, stock(&1, code, location)}
    )
  end

  def handle_call({:remove, code, location, qty, actor}, _from, inv) do
    apply_change(
      inv,
      Inventory.remove(inv, code, location, qty, actor),
      &{:ok, stock(&1, code, location)}
    )
  end

  def handle_call({:transfer, code, from, to, qty, zone, actor}, _from, inv) do
    apply_change(
      inv,
      Inventory.transfer(inv, code, from, to, qty, zone, actor),
      &{:ok, stock(&1, code, to)}
    )
  end

  def handle_call({:allocate, category, qty, zone, need_id, actor}, _from, inv) do
    case Inventory.allocate(inv, category, qty, zone, need_id, actor) do
      {:ok, allocations, new_inv} -> Storage.commit(@file_name, inv, new_inv, {:ok, allocations})
      {:error, _} = error -> {:reply, error, inv}
    end
  end

  def handle_call({:release, allocations, need_id, actor}, _from, inv) do
    Storage.commit(@file_name, inv, Inventory.release(inv, allocations, need_id, actor), :ok)
  end

  # Consultas de solo lectura: la función se ejecuta sobre una copia inmutable.
  def handle_call({:query, fun}, _from, inv), do: {:reply, fun.(inv), inv}

  defp apply_change(inv, {:ok, new_inv}, reply),
    do: Storage.commit(@file_name, inv, new_inv, reply.(new_inv))

  defp apply_change(inv, {:error, _} = error, _reply), do: {:reply, error, inv}

  defp stock(inv, code, location), do: Map.fetch!(inv.stocks, {code, location})
end
