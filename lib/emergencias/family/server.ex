defmodule Emergencias.Family.Server do
  @moduledoc """
  GenServer con las personas afectadas y los mensajes entre familiares. Al ser un
  único proceso, registrar la misma persona dos veces a la vez produce exactamente
  un alta y un error de duplicado.
  """

  use Emergencias.Server, file: "family"

  alias Emergencias.{Clock, Storage}
  alias Emergencias.Family.{Message, Person}

  defmodule State do
    @moduledoc false
    defstruct persons: %{}, messages: %{}, next_person: 1, next_message: 1
  end

  defp initial_state, do: %State{}

  def report_person(valid, actor), do: call({:report_person, valid, actor})

  def update_person(document, changes, actor),
    do: call({:update_person, document, changes, actor})

  def persons, do: call(:persons)
  def send_message(from, to, content), do: call({:send_message, from, to, content})
  def mark_message(id, status), do: call({:mark_message, id, status})
  def messages, do: call(:messages)

  @impl true
  def handle_call({:report_person, valid, actor}, _from, state) do
    if Map.has_key?(state.persons, valid.document) do
      {:reply, {:error, {:duplicate, :person, valid.document}}, state}
    else
      person = Person.create(valid, state.next_person, actor, Clock.now())

      new_state = %{
        state
        | persons: Map.put(state.persons, person.document, person),
          next_person: state.next_person + 1
      }

      Storage.commit(@file_name, state, new_state, {:ok, person})
    end
  end

  def handle_call({:update_person, document, changes, actor}, _from, state) do
    with {:ok, person} <- Map.fetch(state.persons, document) |> found(:person, document),
         {:ok, updated} <- Person.update(person, changes, actor, Clock.now()) do
      Storage.commit(
        @file_name,
        state,
        %{state | persons: Map.put(state.persons, document, updated)},
        {:ok, updated}
      )
    else
      {:error, _} = error -> {:reply, error, state}
    end
  end

  def handle_call({:send_message, from, to, content}, _from, state) do
    message = Message.create(state.next_message, from, to, content, Clock.now())

    new_state = %{
      state
      | messages: Map.put(state.messages, message.id, message),
        next_message: state.next_message + 1
    }

    Storage.commit(@file_name, state, new_state, {:ok, message})
  end

  def handle_call({:mark_message, id, status}, _from, state) do
    case Map.fetch(state.messages, id) |> found(:message, id) do
      {:ok, message} ->
        updated = Message.mark(message, status, Clock.now())

        Storage.commit(
          @file_name,
          state,
          %{state | messages: Map.put(state.messages, id, updated)},
          {:ok, updated}
        )

      error ->
        {:reply, error, state}
    end
  end

  def handle_call(:persons, _from, state),
    do: {:reply, Enum.sort_by(Map.values(state.persons), & &1.id), state}

  def handle_call(:messages, _from, state),
    do: {:reply, Enum.sort_by(Map.values(state.messages), & &1.id), state}

  defp found({:ok, value}, _entity, _id), do: {:ok, value}
  defp found(:error, entity, id), do: {:error, {:not_found, entity, id}}
end
