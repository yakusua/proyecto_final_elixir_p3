defmodule Emergencias.Needs.Server do
  @moduledoc """
  GenServer dueño de las necesidades.

  **Por qué no hay doble consumo:** toda asignación pasa por este proceso, que
  atiende una solicitud a la vez. Dentro de `{:assign, ...}` revisa el estado de la
  necesidad y *luego* pide el inventario a `Emergencias.Resources.Server` (también
  secuencial). Así una necesidad no se sobre-asigna, una atendida no vuelve a
  consumir y varias necesidades que compiten por el mismo inventario se resuelven
  de una en una.

  Orden de llamadas (evita bloqueos mutuos): `Needs.Server` llama a
  `Resources.Server`, nunca al revés.
  """

  use Emergencias.Server, file: "needs"

  require Logger

  alias Emergencias.{Clock, Filter, Resources, Storage}
  alias Emergencias.Needs.Need

  defmodule State do
    @moduledoc false
    defstruct needs: %{}, next_seq: 1
  end

  defp initial_state, do: %State{}

  def register(valid, actor), do: call({:register, valid, actor})
  def assign(id, category, quantity, actor), do: call({:assign, id, category, quantity, actor})
  def transition(id, status, actor), do: call({:transition, id, status, actor})
  def list(filters), do: call({:list, filters})

  @impl true
  def handle_call({:register, valid, actor}, _from, state) do
    need = Need.create(valid, state.next_seq, actor, Clock.now())

    new_state = %{
      state
      | needs: Map.put(state.needs, need.id, need),
        next_seq: state.next_seq + 1
    }

    Storage.commit(@file_name, state, new_state, {:ok, need})
  end

  def handle_call({:assign, id, category, quantity, actor}, _from, state) do
    with {:ok, need} <- fetch(state, id),
         :ok <- Need.check_assignable(need, category, quantity),
         {:ok, allocations} <- Resources.allocate(category, quantity, need.zone, id, actor) do
      updated = Need.add_assignments(need, allocations, actor, Clock.now())

      case Storage.commit(@file_name, state, put(state, updated), {:ok, updated}) do
        {:reply, {:error, _}, _} = failed ->
          # No se pudo guardar la necesidad: se devuelve el inventario para no perderlo.
          Resources.release(allocations, id, actor)
          failed

        ok ->
          ok
      end
    else
      {:error, _} = error -> {:reply, error, state}
    end
  end

  def handle_call({:transition, id, status, actor}, _from, state) do
    with {:ok, need} <- fetch(state, id),
         {:ok, updated} <- Need.transition(need, status, actor, Clock.now()) do
      # Al cancelar antes de la atención, lo asignado vuelve al inventario.
      refund =
        if status == :cancelada and need.status in [:pendiente, :asignada],
          do: need.assignments,
          else: []

      updated = if refund == [], do: updated, else: %{updated | assignments: []}

      case Storage.commit(@file_name, state, put(state, updated), {:ok, updated}) do
        {:reply, {:ok, _}, _} = ok ->
          if refund != [], do: Resources.release(refund, id, actor)
          ok

        failed ->
          failed
      end
    else
      {:error, _} = error -> {:reply, error, state}
    end
  end

  def handle_call({:list, filters}, _from, state) do
    {:reply, state.needs |> Map.values() |> Filter.by(filters) |> Need.sort_by_priority(), state}
  end

  defp fetch(state, id) do
    case Map.fetch(state.needs, id) do
      {:ok, need} -> {:ok, need}
      :error -> {:error, {:not_found, :need, id}}
    end
  end

  defp put(state, need), do: %{state | needs: Map.put(state.needs, need.id, need)}
end
