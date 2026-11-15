defmodule Emergencias.Family.Person do
  @moduledoc """
  Persona afectada y sus reglas puras. Cada cambio de estado o de zona queda en el
  historial (el más reciente primero).

      sin_informacion -> reportada | localizada | trasladada | en_albergue
      reportada       -> localizada | trasladada | en_albergue | reunificada
      localizada      -> trasladada | en_albergue | reunificada
      trasladada      -> localizada | en_albergue | reunificada
      en_albergue     -> localizada | trasladada | reunificada
      reunificada     -> (final)
  """

  alias Emergencias.{Text, Types, Validation}

  @transitions %{
    sin_informacion: [:reportada, :localizada, :trasladada, :en_albergue],
    reportada: [:localizada, :trasladada, :en_albergue, :reunificada],
    localizada: [:trasladada, :en_albergue, :reunificada],
    trasladada: [:localizada, :en_albergue, :reunificada],
    en_albergue: [:localizada, :trasladada, :reunificada],
    reunificada: []
  }

  @enforce_keys [:id, :document, :name, :zone, :status]
  defstruct [:id, :document, :name, :age, :zone, :status, :reported_by, :created_at, history: []]

  @type t :: %__MODULE__{}

  @spec validate(map()) :: {:ok, map()} | {:error, term()}
  def validate(attrs) do
    with {:ok, document} <- Validation.code(attrs[:document], :document, :keep),
         {:ok, name} <- Validation.text(attrs[:name], :name),
         {:ok, zone} <- Validation.code(attrs[:zone], :zone),
         {:ok, status} <- Types.parse(:person_status, attrs[:status] || :sin_informacion),
         {:ok, age} <-
           Validation.optional(attrs[:age], &Validation.non_negative_integer(&1, :age)) do
      {:ok, %{document: document, name: name, zone: zone, status: status, age: age}}
    end
  end

  @spec create(map(), pos_integer(), String.t(), DateTime.t()) :: t()
  def create(valid, seq, actor, at) do
    struct!(
      __MODULE__,
      Map.merge(valid, %{
        id: Text.sequence_id("P", seq),
        reported_by: actor,
        created_at: at,
        history: [%{from: nil, to: valid.status, zone: valid.zone, by: actor, at: at}]
      })
    )
  end

  @doc "Aplica un cambio de `:status` y/o `:zone`; las transiciones no permitidas devuelven error."
  @spec update(t(), map(), String.t(), DateTime.t()) :: {:ok, t()} | {:error, term()}
  def update(%__MODULE__{} = person, changes, actor, at) do
    status = changes[:status] || person.status
    zone = changes[:zone] || person.zone
    status_changed? = status != person.status

    cond do
      not status_changed? and zone == person.zone ->
        {:error, {:invalid_transition, :person, person.status, status}}

      status_changed? and status not in Map.fetch!(@transitions, person.status) ->
        {:error, {:invalid_transition, :person, person.status, status}}

      true ->
        entry = %{from: person.status, to: status, zone: zone, by: actor, at: at}
        {:ok, %{person | status: status, zone: zone, history: [entry | person.history]}}
    end
  end
end
