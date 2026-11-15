defmodule Emergencias.Pets.Server do
  @moduledoc """
  GenServer dueño de los reportes de mascotas. Al ser el único que los modifica,
  confirmar una coincidencia es atómico: dos coordinadores que intenten cerrar el
  mismo reporte a la vez obtienen un éxito y un `{:already_resolved, id}`.
  """

  use Emergencias.Server, file: "pets"

  alias Emergencias.{Clock, Storage}
  alias Emergencias.Pets.Report

  defmodule State do
    @moduledoc false
    defstruct reports: %{}, matches: [], next_seq: 1
  end

  defp initial_state, do: %State{}

  def register(valid, actor), do: call({:register, valid, actor})
  def reports, do: call(:reports)
  def refresh_status(matches), do: call({:refresh_status, matches})
  def confirm(lost_id, found_id, actor), do: call({:confirm, lost_id, found_id, actor})

  @impl true
  def handle_call({:register, valid, actor}, _from, state) do
    report = Report.create(valid, state.next_seq, actor, Clock.now())

    new_state = %{
      state
      | reports: Map.put(state.reports, report.id, report),
        next_seq: state.next_seq + 1
    }

    Storage.commit(@file_name, state, new_state, {:ok, report})
  end

  def handle_call(:reports, _from, state),
    do: {:reply, Enum.sort_by(Map.values(state.reports), & &1.seq), state}

  def handle_call({:refresh_status, matches}, _from, state) do
    Storage.commit(
      @file_name,
      state,
      %{state | reports: Report.refresh_status(state.reports, matches)},
      :ok
    )
  end

  def handle_call({:confirm, lost_id, found_id, actor}, _from, state) do
    case Report.confirm(state.reports, lost_id, found_id) do
      {:ok, reports, match} ->
        match = Map.merge(match, %{confirmed_by: actor, at: Clock.now()})

        Storage.commit(
          @file_name,
          state,
          %{state | reports: reports, matches: [match | state.matches]},
          {:ok, match}
        )

      {:error, _} = error ->
        {:reply, error, state}
    end
  end
end
