defmodule Emergencias.Text do
  @moduledoc "Utilidades puras de texto: normalización, comparación e identificadores."

  @doc "Minúsculas, sin tildes y con espacios colapsados."
  @spec normalize(String.t()) :: String.t()
  def normalize(text) do
    text
    |> :unicode.characters_to_nfd_binary()
    |> String.replace(~r/\p{Mn}/u, "")
    |> String.downcase()
    |> String.replace(~r/\s+/u, " ")
    |> String.trim()
  end

  @doc "Como `normalize/1`, uniendo las palabras con `_` (`\"Primeros Auxilios\"` -> `\"primeros_auxilios\"`)."
  @spec slug(String.t()) :: String.t()
  def slug(text), do: text |> normalize() |> String.replace(~r/[\s\-]+/u, "_")

  @doc "Palabras normalizadas de un texto."
  @spec tokens(String.t() | nil) :: [String.t()]
  def tokens(nil), do: []
  def tokens(text), do: text |> normalize() |> String.split(~r/[^[:alnum:]]+/u, trim: true)

  @doc "Índice de Jaccard (0.0..1.0) entre dos listas de palabras."
  @spec jaccard([String.t()], [String.t()]) :: float()
  def jaccard(a, b) do
    {a, b} = {MapSet.new(a), MapSet.new(b)}
    union = MapSet.size(MapSet.union(a, b))
    if union == 0, do: 0.0, else: MapSet.size(MapSet.intersection(a, b)) / union
  end

  @doc "¿El texto contiene el fragmento (sin tildes ni mayúsculas)?"
  @spec contains?(String.t(), String.t()) :: boolean()
  def contains?(text, fragment), do: String.contains?(normalize(text), normalize(fragment))

  @doc "Identificador consecutivo: `sequence_id(\"N\", 7)` -> `\"N007\"`."
  @spec sequence_id(String.t(), pos_integer()) :: String.t()
  def sequence_id(prefix, seq), do: prefix <> String.pad_leading(Integer.to_string(seq), 3, "0")
end
