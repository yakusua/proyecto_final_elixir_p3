defmodule Emergencias.Shelters.Shelter do
  @moduledoc """
  Albergue y sus reglas **puras** de ocupación. Los ocupantes se guardan en un
  `MapSet` de documentos: una persona no puede estar dos veces en el albergue y la
  ocupación (el tamaño del conjunto) nunca se desincroniza de las personas.
  """

  @enforce_keys [:code, :name, :zone, :capacity]
  defstruct [:code, :name, :zone, :capacity, occupants: MapSet.new()]

  @type t :: %__MODULE__{}

  @spec occupancy(t()) :: non_neg_integer()
  def occupancy(%__MODULE__{occupants: occupants}), do: MapSet.size(occupants)

  @spec available(t()) :: non_neg_integer()
  def available(%__MODULE__{capacity: capacity} = shelter), do: capacity - occupancy(shelter)

  @doc "Porcentaje de ocupación (0.0..100.0)."
  @spec occupancy_percent(t()) :: float()
  def occupancy_percent(%__MODULE__{capacity: capacity} = shelter),
    do: Float.round(occupancy(shelter) * 100 / capacity, 1)

  @doc "Ingreso de una persona; falla si ya está dentro o si no hay cupo."
  @spec enter(t(), String.t()) :: {:ok, t()} | {:error, term()}
  def enter(%__MODULE__{} = shelter, document) do
    cond do
      MapSet.member?(shelter.occupants, document) -> {:error, {:already_in_shelter, shelter.code}}
      available(shelter) <= 0 -> {:error, {:shelter_full, shelter.code}}
      true -> {:ok, %{shelter | occupants: MapSet.put(shelter.occupants, document)}}
    end
  end

  @doc "Salida de una persona; falla si no estaba en el albergue."
  @spec leave(t(), String.t()) :: {:ok, t()} | {:error, term()}
  def leave(%__MODULE__{} = shelter, document) do
    if MapSet.member?(shelter.occupants, document),
      do: {:ok, %{shelter | occupants: MapSet.delete(shelter.occupants, document)}},
      else: {:error, {:not_in_shelter, shelter.code}}
  end

  # El MapSet se guarda en disco como lista ordenada (formato estable y legible).
  @doc false
  def to_record(%__MODULE__{} = shelter) do
    shelter
    |> Map.from_struct()
    |> Map.update!(:occupants, &(&1 |> MapSet.to_list() |> Enum.sort()))
  end

  @doc false
  def from_record(record), do: struct!(__MODULE__, Map.update!(record, :occupants, &MapSet.new/1))
end
