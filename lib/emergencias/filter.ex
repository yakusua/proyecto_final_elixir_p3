defmodule Emergencias.Filter do
  @moduledoc "Filtro genérico por igualdad de campos: los criterios con valor `nil` se ignoran."

  @spec by([map()], keyword()) :: [map()]
  def by(items, filters) do
    filters = Enum.reject(filters, fn {_field, value} -> is_nil(value) end)

    Enum.filter(items, fn item ->
      Enum.all?(filters, fn {field, value} -> Map.fetch!(item, field) == value end)
    end)
  end
end
