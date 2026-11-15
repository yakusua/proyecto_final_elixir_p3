defmodule Emergencias.DataCase do
  @moduledoc """
  Plantilla para pruebas de integración: antes de cada prueba se reinicia la
  aplicación con la carpeta de datos vacía (los servidores son globales, por eso
  estas pruebas no son `async`).
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      import Emergencias.DataCase
      alias Emergencias.{Accounts, Family, Needs, Pets, Reports, Resources, Shelters, Zones}
    end
  end

  setup do
    Application.stop(:emergencias)
    File.rm_rf!(Emergencias.Storage.data_dir())
    {:ok, _} = Application.ensure_all_started(:emergencias)
    :ok
  end

  def zone!(code \\ "centro", level \\ "critico") do
    {:ok, _} = Emergencias.Zones.register_zone(%{code: code, name: "Zona " <> code, level: level})
    code
  end

  def resource!(code, category, quantity, location \\ "centro_acopio_1", zone \\ "centro") do
    attrs = %{
      code: code,
      category: category,
      quantity: quantity,
      unit: "unidades",
      location: location,
      zone: zone
    }

    {:ok, resource} = Emergencias.Resources.register(attrs, "test")
    resource
  end

  def need!(type, quantity, priority \\ "media", zone \\ "centro") do
    attrs = %{
      type: type,
      quantity: quantity,
      priority: priority,
      zone: zone,
      description: "Necesidad de prueba"
    }

    {:ok, need} = Emergencias.Needs.register(attrs, "test")
    need
  end

  @doc "Conecta a un usuario (si no existe se registra)."
  def connect!(username, role, zone \\ "centro") do
    {:ok, user, _} = Emergencias.connect(username, "clave-#{username}", %{role: role, zone: zone})
    user
  end

  @doc "Ejecuta un comando y exige éxito."
  def run!(username, command) do
    {:ok, result} = Emergencias.execute(username, command)
    result
  end

  @doc "Unidades disponibles de una categoría."
  def available(category), do: Map.get(Emergencias.Resources.totals(), category, 0)

  @doc "Ejecuta `fun` sobre cada elemento en procesos simultáneos y devuelve los resultados en orden."
  def concurrently(items, fun) do
    items = Enum.to_list(items)

    items
    |> Task.async_stream(fun,
      max_concurrency: max(length(items), 1),
      ordered: true,
      timeout: 30_000
    )
    |> Enum.map(fn {:ok, result} -> result end)
  end

  def count_ok(results), do: Enum.count(results, &match?({:ok, _}, &1))

  @doc "Espera (hasta ~2.5 s) a que `fun` devuelva un valor verdadero."
  def wait_until(fun, tries \\ 50) do
    cond do
      result = fun.() -> result
      tries == 0 -> flunk("la condición no se cumplió a tiempo")
      true -> Process.sleep(50) && wait_until(fun, tries - 1)
    end
  end
end
