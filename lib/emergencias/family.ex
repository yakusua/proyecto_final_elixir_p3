defmodule Emergencias.Family do
  @moduledoc "Contexto de comunicación entre familiares: personas afectadas, búsqueda y mensajes."

  alias Emergencias.{Filter, Text, Types, Validation, Zones}
  alias Emergencias.Family.{Message, Person, Server}

  @doc "Registra una persona. Claves: `:document`, `:name`, `:zone`, `:status`, opcional `:age`."
  @spec report_person(map(), String.t()) :: {:ok, Person.t()} | {:error, term()}
  def report_person(attrs, actor) do
    with {:ok, valid} <- Person.validate(attrs),
         :ok <- Zones.ensure_exists(valid.zone) do
      Server.report_person(valid, actor)
    end
  end

  @doc "Cambia el estado y/o la zona de una persona (con validación de transiciones)."
  @spec update_person(String.t(), map(), String.t()) :: {:ok, Person.t()} | {:error, term()}
  def update_person(document, attrs, actor) do
    with {:ok, document} <- Validation.code(document, :document, :keep),
         {:ok, status} <- Types.parse_optional(:person_status, attrs[:status]),
         {:ok, zone} <- Validation.optional(attrs[:zone], &Validation.code(&1, :zone)),
         :ok <- if(zone, do: Zones.ensure_exists(zone), else: :ok) do
      Server.update_person(document, %{status: status, zone: zone}, actor)
    end
  end

  @doc "Busca por `:document`, `:name` (fragmento), `:zone` y `:status`."
  @spec find(keyword()) :: {:ok, [Person.t()]} | {:error, term()}
  def find(filters) do
    with {:ok, document} <-
           Validation.optional(filters[:document], &Validation.code(&1, :document, :keep)),
         {:ok, zone} <- Validation.optional(filters[:zone], &Validation.code(&1, :zone)),
         {:ok, status} <- Types.parse_optional(:person_status, filters[:status]) do
      persons = Server.persons() |> Filter.by(document: document, zone: zone, status: status)
      name = filters[:name]

      {:ok,
       if(name in [nil, ""],
         do: persons,
         else: Enum.filter(persons, &Text.contains?(&1.name, name))
       )}
    end
  end

  @doc "Deja un mensaje para una persona o familia (documento o dato de referencia)."
  @spec send_message(String.t(), String.t(), String.t()) :: {:ok, Message.t()} | {:error, term()}
  def send_message(document, content, sender) do
    with {:ok, document} <- Validation.code(document, :document, :keep),
         {:ok, content} <- Validation.text(content, :content) do
      Server.send_message(sender, document, content)
    end
  end

  @doc "Mensajes dirigidos a un documento, opcionalmente por estado."
  @spec messages(String.t(), String.t() | nil) :: {:ok, [Message.t()]} | {:error, term()}
  def messages(document, status \\ nil) do
    with {:ok, document} <- Validation.code(document, :document, :keep),
         {:ok, status} <- Types.parse_optional(:message_status, status) do
      {:ok, Server.messages() |> Filter.by(to: document, status: status)}
    end
  end

  @doc "Marca un mensaje como entregado o pendiente."
  @spec mark_message(String.t(), String.t()) :: {:ok, Message.t()} | {:error, term()}
  def mark_message(id, status) do
    with {:ok, id} <- Validation.code(id, :message_id, :up),
         {:ok, status} <- Types.parse(:message_status, status) do
      Server.mark_message(id, status)
    end
  end

  @spec all_messages() :: [Message.t()]
  def all_messages, do: Server.messages()
end
