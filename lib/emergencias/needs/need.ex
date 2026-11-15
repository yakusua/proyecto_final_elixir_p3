defmodule Emergencias.Needs.Need do
  @moduledoc """
  Necesidad puntual y sus reglas **puras**: validación, máquina de estados y control
  de lo ya asignado.

      pendiente   -> asignada | cancelada
      asignada    -> en_atencion | cancelada
      en_atencion -> atendida | cancelada
      atendida / cancelada -> (finales)

  El paso `pendiente -> asignada` es automático cuando lo asignado cubre la cantidad
  requerida; una asignación parcial deja la necesidad en `pendiente`.
  """

  alias Emergencias.{Text, Types, Validation}

  @transitions %{
    pendiente: [:asignada, :cancelada],
    asignada: [:en_atencion, :cancelada],
    en_atencion: [:atendida, :cancelada],
    atendida: [],
    cancelada: []
  }

  @enforce_keys [:id, :seq, :type, :quantity, :zone, :priority, :reporter]
  defstruct [
    :id,
    :seq,
    :type,
    :description,
    :quantity,
    :zone,
    :priority,
    :reporter,
    :shelter,
    :person,
    :created_at,
    status: :pendiente,
    assignments: [],
    history: []
  ]

  @type t :: %__MODULE__{}

  @doc "Valida y normaliza los datos de una necesidad nueva."
  @spec validate(map()) :: {:ok, map()} | {:error, term()}
  def validate(attrs) do
    with {:ok, type} <- Types.parse(:need_type, attrs[:type]),
         {:ok, quantity} <- Validation.positive_integer(attrs[:quantity], :quantity),
         {:ok, priority} <- Types.parse(:priority, attrs[:priority]),
         {:ok, zone} <- Validation.code(attrs[:zone], :zone),
         {:ok, description} <- Validation.text(attrs[:description], :description),
         {:ok, shelter} <-
           Validation.optional(attrs[:shelter], &Validation.code(&1, :shelter, :up)),
         {:ok, person} <-
           Validation.optional(attrs[:person], &Validation.code(&1, :person, :keep)) do
      {:ok,
       %{
         type: type,
         quantity: quantity,
         priority: priority,
         zone: zone,
         description: description,
         shelter: shelter,
         person: person
       }}
    end
  end

  @spec create(map(), pos_integer(), String.t(), DateTime.t()) :: t()
  def create(valid, seq, reporter, at) do
    struct!(
      __MODULE__,
      Map.merge(valid, %{
        id: Text.sequence_id("N", seq),
        seq: seq,
        reporter: reporter,
        created_at: at,
        history: [%{status: :pendiente, by: reporter, at: at}]
      })
    )
  end

  @spec assigned(t()) :: non_neg_integer()
  def assigned(%__MODULE__{assignments: assignments}),
    do: Enum.reduce(assignments, 0, &(&1.quantity + &2))

  @spec remaining(t()) :: non_neg_integer()
  def remaining(%__MODULE__{quantity: quantity} = need), do: quantity - assigned(need)

  @doc """
  ¿Se puede consumir inventario? Solo las necesidades `pendiente` consumen: una
  atendida o cancelada nunca vuelve a hacerlo. Una necesidad `:otra` acepta
  cualquier categoría; el resto exige la categoría de su tipo.
  """
  @spec check_assignable(t(), String.t(), pos_integer()) :: :ok | {:error, term()}
  def check_assignable(%__MODULE__{status: status}, _category, _quantity)
      when status != :pendiente,
      do: {:error, {:need_not_assignable, status}}

  def check_assignable(%__MODULE__{} = need, category, quantity) do
    cond do
      need.type != :otra and Atom.to_string(need.type) != category ->
        {:error, {:category_mismatch, need.type, category}}

      quantity > remaining(need) ->
        {:error, {:exceeds_need, remaining(need)}}

      true ->
        :ok
    end
  end

  @doc "Registra lo asignado; si ya se cubre toda la cantidad pasa a `:asignada`."
  @spec add_assignments(t(), [map()], String.t(), DateTime.t()) :: t()
  def add_assignments(%__MODULE__{} = need, allocations, actor, at) do
    need = %{need | assignments: need.assignments ++ allocations}
    if remaining(need) == 0, do: put_status(need, :asignada, actor, at), else: need
  end

  @doc "Cambio de estado pedido por una persona, validando la transición."
  @spec transition(t(), atom(), String.t(), DateTime.t()) :: {:ok, t()} | {:error, term()}
  def transition(%__MODULE__{status: from} = need, to, actor, at) do
    if to in Map.fetch!(@transitions, from),
      do: {:ok, put_status(need, to, actor, at)},
      else: {:error, {:invalid_transition, :need, from, to}}
  end

  @doc "Orden de atención: mayor prioridad primero y, en empate, la más antigua."
  @spec sort_by_priority([t()]) :: [t()]
  def sort_by_priority(needs),
    do: Enum.sort_by(needs, &{-Types.rank(:priority, &1.priority), &1.seq})

  defp put_status(need, status, actor, at),
    do: %{need | status: status, history: [%{status: status, by: actor, at: at} | need.history]}
end
