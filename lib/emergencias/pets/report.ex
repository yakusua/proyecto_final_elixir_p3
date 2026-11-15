defmodule Emergencias.Pets.Report do
  @moduledoc """
  Reporte de mascota perdida o encontrada y reglas puras sobre colecciones de
  reportes. Estados: `:activa`, `:posible_coincidencia` (lo fija el sistema al
  calcular coincidencias) y `:resuelta` (solo al confirmar; es final).
  """

  alias Emergencias.{Text, Types, Validation}
  alias Emergencias.Pets.Matcher

  @unknown_names ~w(desconocido desconocida - ? n/a sin_nombre)

  @enforce_keys [:id, :seq, :kind, :species, :color, :size, :zone, :contact]
  defstruct [
    :id,
    :seq,
    :kind,
    :species,
    :name,
    :color,
    :size,
    :traits,
    :zone,
    :contact,
    :reporter,
    :matched_with,
    :created_at,
    status: :activa
  ]

  @type t :: %__MODULE__{}

  @spec validate(map()) :: {:ok, map()} | {:error, term()}
  def validate(attrs) do
    with {:ok, kind} <- Types.parse(:pet_kind, attrs[:kind]),
         {:ok, species} <- Validation.text(attrs[:species], :species),
         {:ok, color} <- Validation.text(attrs[:color], :color),
         {:ok, size} <- Types.parse(:pet_size, attrs[:size]),
         {:ok, zone} <- Validation.code(attrs[:zone], :zone),
         {:ok, contact} <- Validation.text(attrs[:contact], :contact),
         {:ok, name} <- Validation.optional(attrs[:name], &Validation.text(&1, :name)),
         {:ok, traits} <- Validation.optional(attrs[:traits], &Validation.text(&1, :traits)) do
      name = if name && Text.slug(name) in @unknown_names, do: nil, else: name

      {:ok,
       %{
         kind: kind,
         species: Text.normalize(species),
         name: name,
         color: Text.normalize(color),
         size: size,
         traits: traits,
         zone: zone,
         contact: contact
       }}
    end
  end

  @spec create(map(), pos_integer(), String.t(), DateTime.t()) :: t()
  def create(valid, seq, reporter, at) do
    struct!(
      __MODULE__,
      Map.merge(valid, %{
        id: Text.sequence_id("PET", seq),
        seq: seq,
        reporter: reporter,
        created_at: at
      })
    )
  end

  @doc """
  Marca como `:posible_coincidencia` los reportes abiertos que aparecen en alguna
  coincidencia (`%{lost: id, found: id}`) y como `:activa` al resto de los abiertos.
  """
  @spec refresh_status(%{String.t() => t()}, [map()]) :: %{String.t() => t()}
  def refresh_status(reports, matches) do
    matched = MapSet.new(Enum.flat_map(matches, &[&1.lost, &1.found]))

    Map.new(reports, fn
      {id, %{status: :resuelta} = report} ->
        {id, report}

      {id, report} ->
        {id,
         %{
           report
           | status: if(MapSet.member?(matched, id), do: :posible_coincidencia, else: :activa)
         }}
    end)
  end

  @doc """
  Confirma que `lost_id` y `found_id` son la misma mascota y **cierra ambos**
  reportes. Un reporte no se puede resolver dos veces.
  """
  @spec confirm(%{String.t() => t()}, String.t(), String.t()) ::
          {:ok, %{String.t() => t()}, map()} | {:error, term()}
  def confirm(reports, lost_id, found_id) do
    with {:ok, lost} <- fetch(reports, lost_id),
         {:ok, found} <- fetch(reports, found_id),
         :ok <- check_kinds(lost, found),
         :ok <- check_open(lost),
         :ok <- check_open(found),
         :ok <- check_species(lost, found) do
      resolved =
        reports
        |> Map.put(lost.id, %{lost | status: :resuelta, matched_with: found.id})
        |> Map.put(found.id, %{found | status: :resuelta, matched_with: lost.id})

      {:ok, resolved, %{lost: lost.id, found: found.id, score: Matcher.score(lost, found).total}}
    end
  end

  defp fetch(reports, id) do
    case Map.fetch(reports, id) do
      {:ok, report} -> {:ok, report}
      :error -> {:error, {:not_found, :pet_report, id}}
    end
  end

  defp check_kinds(%{kind: :perdida}, %{kind: :encontrada}), do: :ok
  defp check_kinds(lost, found), do: {:error, {:wrong_kinds, lost.kind, found.kind}}

  defp check_open(%{status: :resuelta, id: id}), do: {:error, {:already_resolved, id}}
  defp check_open(_), do: :ok

  defp check_species(%{species: species}, %{species: species}), do: :ok
  defp check_species(lost, found), do: {:error, {:species_mismatch, lost.species, found.species}}
end
