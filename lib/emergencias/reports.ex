defmodule Emergencias.Reports do
  @moduledoc "Consultas agregadas que cruzan varios contextos: resumen global, estado de zona y de albergue, recursos críticos."

  alias Emergencias.{Family, Needs, Pets, Resources, Shelters, Zones}
  alias Emergencias.Needs.Need
  alias Emergencias.Shelters.Shelter
  alias Emergencias.Zones.Tree

  @doc "Resumen global de la emergencia."
  @spec summary() :: map()
  def summary do
    {:ok, needs} = Needs.list()
    {:ok, persons} = Family.find([])
    {:ok, pets} = Pets.list()
    messages = Family.all_messages()
    shelters = Shelters.list()
    zones = Zones.list() |> Enum.map(&Tree.stats/1)

    %{
      zones: %{count: length(zones), affected: zones |> Enum.map(& &1.affected) |> Enum.sum()},
      needs: needs_summary(needs),
      resources: Resources.totals(),
      persons: Enum.frequencies_by(persons, & &1.status),
      messages: %{
        total: length(messages),
        pending: Enum.count(messages, &(&1.status == :pendiente))
      },
      pets: Enum.frequencies_by(pets, & &1.status),
      shelters: %{
        count: length(shelters),
        capacity: shelters |> Enum.map(& &1.capacity) |> Enum.sum(),
        occupancy: shelters |> Enum.map(&Shelter.occupancy/1) |> Enum.sum()
      }
    }
  end

  @doc "Estado general de una zona: árbol acumulado, necesidades, recursos, albergues, personas y mascotas."
  @spec zone_status(String.t()) :: {:ok, map()} | {:error, term()}
  def zone_status(code) do
    with {:ok, stats} <- Zones.stats(code) do
      zone = stats.node.code
      {:ok, needs} = Needs.list(zone: zone)
      {:ok, persons} = Family.find(zone: zone)
      {:ok, pets} = Pets.list(zone: zone)

      {:ok,
       Map.merge(stats, %{
         needs: needs_summary(needs),
         resources: Resources.totals(zone),
         shelters: Enum.filter(Shelters.list(), &(&1.zone == zone)),
         persons: Enum.frequencies_by(persons, & &1.status),
         pets: Enum.frequencies_by(pets, & &1.status)
       })}
    end
  end

  @doc "Albergue con las necesidades y los recursos asociados a él (recursos cuya ubicación es su código)."
  @spec shelter_status(String.t()) :: {:ok, map()} | {:error, term()}
  def shelter_status(code) do
    with {:ok, shelter} <- Shelters.get(code),
         {:ok, needs} <- Needs.list(shelter: shelter.code) do
      {:ok, %{shelter: shelter, needs: needs, resources: Resources.list(location: shelter.code)}}
    end
  end

  @doc "Categorías con déficit: más demanda pendiente que inventario. De mayor a menor déficit."
  @spec critical_resources() :: [map()]
  def critical_resources do
    {:ok, pending} = Needs.pending()
    available = Resources.totals()

    pending
    |> Enum.reject(&(&1.type == :otra))
    |> Enum.group_by(&Atom.to_string(&1.type), &Need.remaining/1)
    |> Enum.map(fn {category, amounts} ->
      demand = Enum.sum(amounts)
      have = Map.get(available, category, 0)
      %{category: category, available: have, demand: demand, deficit: demand - have}
    end)
    |> Enum.filter(&(&1.deficit > 0))
    |> Enum.sort_by(&{-&1.deficit, &1.category})
  end

  defp needs_summary(needs) do
    pending = Enum.filter(needs, &(&1.status == :pendiente))

    %{
      total: length(needs),
      by_status: Enum.frequencies_by(needs, & &1.status),
      pending: length(pending),
      pending_units: pending |> Enum.map(&Need.remaining/1) |> Enum.sum()
    }
  end
end
