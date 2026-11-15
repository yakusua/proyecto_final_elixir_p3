defmodule Emergencias.Pets do
  @moduledoc "Contexto de mascotas perdidas y encontradas."

  alias Emergencias.{Filter, Text, Types, Validation, Zones}
  alias Emergencias.Pets.{Matcher, Report, Server}

  @doc "Registra un reporte. Claves: `:kind`, `:species`, `:name`, `:color`, `:size`, `:zone`, `:contact`, `:traits`."
  @spec report(map(), String.t()) :: {:ok, Report.t()} | {:error, term()}
  def report(attrs, actor) do
    with {:ok, valid} <- Report.validate(attrs),
         :ok <- Zones.ensure_exists(valid.zone) do
      Server.register(valid, actor)
    end
  end

  @doc "Consulta por `:species`, `:zone`, `:status` y `:kind`."
  @spec list(keyword()) :: {:ok, [Report.t()]} | {:error, term()}
  def list(filters \\ []) do
    with {:ok, species} <- Validation.optional(filters[:species], &Validation.text(&1, :species)),
         {:ok, zone} <- Validation.optional(filters[:zone], &Validation.code(&1, :zone)),
         {:ok, status} <- Types.parse_optional(:pet_status, filters[:status]),
         {:ok, kind} <- Types.parse_optional(:pet_kind, filters[:kind]) do
      species = species && Text.normalize(species)

      {:ok,
       Server.reports() |> Filter.by(species: species, zone: zone, status: status, kind: kind)}
    end
  end

  @doc """
  Calcula las posibles coincidencias entre perdidas y encontradas abiertas (puntaje
  >= umbral, de mayor a menor) y marca los reportes involucrados como
  `:posible_coincidencia`. Cada elemento trae ambos reportes y el desglose del puntaje.
  """
  @spec match() :: {:ok, [map()]}
  def match do
    open = Enum.reject(Server.reports(), &(&1.status == :resuelta))

    {lost, found} =
      {Enum.filter(open, &(&1.kind == :perdida)), Enum.filter(open, &(&1.kind == :encontrada))}

    matches =
      for l <- lost,
          f <- found,
          %{total: total} = score <- [Matcher.score(l, f)],
          total >= Matcher.threshold() do
        Map.merge(score, %{lost: l.id, found: f.id, lost_report: l, found_report: f})
      end
      |> Enum.sort_by(&{-&1.total, &1.lost, &1.found})

    :ok = Server.refresh_status(matches)
    {:ok, matches}
  end

  @doc "Confirma una coincidencia y cierra ambos reportes."
  @spec confirm(String.t(), String.t(), String.t()) :: {:ok, map()} | {:error, term()}
  def confirm(lost_id, found_id, actor) do
    with {:ok, lost_id} <- Validation.code(lost_id, :lost_id, :up),
         {:ok, found_id} <- Validation.code(found_id, :found_id, :up) do
      Server.confirm(lost_id, found_id, actor)
    end
  end
end
