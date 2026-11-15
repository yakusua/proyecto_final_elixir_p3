defmodule Emergencias.Types do
  @moduledoc """
  Valores enumerados del dominio y su conversión desde texto. Cada texto se busca
  en una tabla cerrada (nunca se crean átomos desde la entrada del usuario).
  El orden de cada lista va de mayor a menor jerarquía/severidad (ver `rank/2`).
  """

  alias Emergencias.Text

  # valor canónico: alias aceptados además del propio nombre
  @definitions %{
    role: [administrador: [], coordinador: [], voluntario: [], ciudadano: []],
    level: [critico: ~w(critica), alto: ~w(alta), medio: ~w(media), bajo: ~w(baja)],
    priority: [critica: ~w(critico), alta: ~w(alto), media: ~w(medio), baja: ~w(bajo)],
    need_type: [
      agua: [],
      alimentos: [],
      medicamentos: [],
      primeros_auxilios: [],
      refugio: [],
      transporte: [],
      rescate: [],
      otra: ~w(otro)
    ],
    need_status: [pendiente: [], asignada: [], en_atencion: [], atendida: [], cancelada: []],
    person_status: [
      sin_informacion: [],
      reportada: [],
      localizada: [],
      trasladada: [],
      en_albergue: [],
      reunificada: []
    ],
    message_status: [pendiente: [], entregado: []],
    pet_kind: [perdida: ~w(lost), encontrada: ~w(found)],
    pet_status: [activa: [], posible_coincidencia: [], resuelta: []],
    pet_size: [grande: [], mediano: ~w(mediana), pequeno: ~w(pequena)]
  }

  @lookup Map.new(@definitions, fn {type, defs} ->
            {type,
             for(
               {value, aliases} <- defs,
               name <- [Atom.to_string(value) | aliases],
               into: %{},
               do: {name, value}
             )}
          end)

  @values Map.new(@definitions, fn {type, defs} -> {type, Keyword.keys(defs)} end)

  @doc "Valores válidos de un tipo, de mayor a menor jerarquía."
  @spec values(atom()) :: [atom()]
  def values(type), do: Map.fetch!(@values, type)

  @doc """
  Convierte texto (o un átomo ya válido) al valor del tipo indicado.

      iex> Emergencias.Types.parse(:priority, "Crítica")
      {:ok, :critica}
  """
  @spec parse(atom(), String.t() | atom() | nil) :: {:ok, atom()} | {:error, term()}
  def parse(type, input) when is_binary(input) do
    case Map.fetch(Map.fetch!(@lookup, type), Text.slug(input)) do
      {:ok, value} -> {:ok, value}
      :error -> {:error, {:invalid_value, type, input}}
    end
  end

  def parse(type, input) when is_atom(input) and not is_nil(input) do
    if input in values(type), do: {:ok, input}, else: {:error, {:invalid_value, type, input}}
  end

  def parse(type, input), do: {:error, {:invalid_value, type, input}}

  @doc "Como `parse/2`, pero `nil` o cadena vacía devuelven `{:ok, nil}`."
  @spec parse_optional(atom(), String.t() | atom() | nil) ::
          {:ok, atom() | nil} | {:error, term()}
  def parse_optional(_type, value) when value in [nil, ""], do: {:ok, nil}
  def parse_optional(type, value), do: parse(type, value)

  @doc "Rango numérico: el valor más severo/jerárquico tiene el número más alto."
  @spec rank(atom(), atom()) :: pos_integer()
  def rank(type, value) do
    list = values(type)
    length(list) - Enum.find_index(list, &(&1 == value))
  end
end
