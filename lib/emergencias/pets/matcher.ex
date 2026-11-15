defmodule Emergencias.Pets.Matcher do
  @moduledoc """
  Coincidencia entre una mascota **perdida** y una **encontrada**: puntaje de 0 a 100
  que suma la similitud de varios atributos.

  | Atributo        | Máx. | Criterio                                                      |
  |-----------------|------|---------------------------------------------------------------|
  | especie         | 20   | obligatoria: si difiere, el total es 0                        |
  | color           | 20   | similitud de Jaccard entre palabras                           |
  | zona            | 20   | misma zona = 20                                               |
  | tamaño          | 15   | igual = 15, contiguo (pequeño/mediano, mediano/grande) = 7.5  |
  | características | 15   | similitud de Jaccard entre palabras                           |
  | nombre          | 10   | solo si ambos lo conocen y coinciden                          |

  Se considera **posible coincidencia** desde `threshold/0` puntos.
  """

  alias Emergencias.{Text, Types}

  @threshold 50

  @spec threshold() :: non_neg_integer()
  def threshold, do: @threshold

  @spec score(map(), map()) :: %{total: non_neg_integer(), breakdown: map()}
  def score(%{species: species} = lost, %{species: species} = found) do
    breakdown = %{
      species: 20.0,
      color: 20 * similarity(lost.color, found.color),
      zone: if(lost.zone == found.zone, do: 20.0, else: 0.0),
      size: size_score(lost.size, found.size),
      traits: 15 * similarity(lost.traits, found.traits),
      name:
        if(lost.name && found.name && Text.normalize(lost.name) == Text.normalize(found.name),
          do: 10.0,
          else: 0.0
        )
    }

    %{total: breakdown |> Map.values() |> Enum.sum() |> round(), breakdown: breakdown}
  end

  def score(_lost, _found), do: %{total: 0, breakdown: %{}}

  defp similarity(a, b), do: Text.jaccard(Text.tokens(a), Text.tokens(b))

  defp size_score(a, b) do
    case abs(Types.rank(:pet_size, a) - Types.rank(:pet_size, b)) do
      0 -> 15.0
      1 -> 7.5
      _ -> 0.0
    end
  end
end
