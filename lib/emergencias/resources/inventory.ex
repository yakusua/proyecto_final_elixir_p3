defmodule Emergencias.Resources.Inventory do
  @moduledoc """
  Núcleo **puro** del inventario: recibe un `%Inventory{}` y devuelve otro, sin
  procesos ni disco. Aquí viven las reglas de "no negativos", "no sobre-asignar" y
  transferencias; la atomicidad entre procesos la da `Emergencias.Resources.Server`.

  Las existencias se indexan por `{codigo, ubicacion}` y cada cambio deja un
  movimiento en el historial (el más reciente primero).
  """

  alias Emergencias.{Clock, Filter}
  alias Emergencias.Resources.Resource

  defstruct stocks: %{}, movements: [], next_movement: 1

  @type allocation :: %{
          code: String.t(),
          location: String.t(),
          zone: String.t(),
          quantity: pos_integer()
        }
  @type t :: %__MODULE__{}

  @doc "Registra un recurso nuevo; el código no puede repetirse."
  @spec register(t(), Resource.t(), String.t()) :: {:ok, t()} | {:error, term()}
  def register(%__MODULE__{} = inv, %Resource{} = resource, actor) do
    if Enum.any?(inv.stocks, fn {{code, _}, _} -> code == resource.code end) do
      {:error, {:duplicate, :resource, resource.code}}
    else
      key = {resource.code, resource.location}
      inv = %{inv | stocks: Map.put(inv.stocks, key, %{resource | quantity: 0})}
      {:ok, change(inv, key, resource.quantity, :registro, nil, actor)}
    end
  end

  @doc "Entrada de inventario; si no hay existencias en `location` se crea el registro."
  @spec add(t(), String.t(), String.t(), pos_integer(), String.t()) ::
          {:ok, t()} | {:error, term()}
  def add(inv, code, location, quantity, actor) do
    with {:ok, template} <- template(inv, code) do
      stock = Map.get(inv.stocks, {code, location}, %{template | location: location, quantity: 0})
      inv = %{inv | stocks: Map.put(inv.stocks, {code, location}, stock)}
      {:ok, change(inv, {code, location}, quantity, :entrada, nil, actor)}
    end
  end

  @doc "Salida de inventario; falla si no hay existencias suficientes (nunca queda en negativo)."
  @spec remove(t(), String.t(), String.t(), pos_integer(), String.t()) ::
          {:ok, t()} | {:error, term()}
  def remove(inv, code, location, quantity, actor) do
    with {:ok, stock} <- fetch_stock(inv, code, location),
         :ok <- ensure_enough(stock, quantity) do
      {:ok, change(inv, {code, location}, -quantity, :salida, nil, actor)}
    end
  end

  @doc "Transfiere existencias entre dos ubicaciones; `to_zone` es la zona del destino (si es nuevo)."
  @spec transfer(
          t(),
          String.t(),
          String.t(),
          String.t(),
          pos_integer(),
          String.t() | nil,
          String.t()
        ) ::
          {:ok, t()} | {:error, term()}
  def transfer(_inv, _code, location, location, _quantity, _zone, _actor),
    do: {:error, :same_location}

  def transfer(inv, code, from, to, quantity, to_zone, actor) do
    with {:ok, source} <- fetch_stock(inv, code, from),
         :ok <- ensure_enough(source, quantity) do
      destination =
        Map.get(inv.stocks, {code, to}, %{
          source
          | location: to,
            zone: to_zone || source.zone,
            quantity: 0
        })

      inv =
        %{inv | stocks: Map.put(inv.stocks, {code, to}, destination)}
        |> change({code, from}, -quantity, :transferencia_salida, to, actor)
        |> change({code, to}, quantity, :transferencia_entrada, from, actor)

      {:ok, inv}
    end
  end

  @doc """
  Descuenta `quantity` unidades de la categoría tomando primero lotes de la zona
  indicada. Es **todo o nada**: si no alcanza, devuelve error y no cambia nada.
  """
  @spec allocate(t(), String.t(), pos_integer(), String.t(), String.t(), String.t()) ::
          {:ok, [allocation()], t()} | {:error, {:insufficient_stock, map()}}
  def allocate(inv, category, quantity, zone, need_id, actor) do
    lots =
      inv.stocks
      |> Map.values()
      |> Enum.filter(&(&1.category == category and &1.quantity > 0))
      |> Enum.sort_by(&{&1.zone != zone, -&1.quantity, &1.code, &1.location})

    case take(lots, quantity, []) do
      {:ok, allocations} ->
        inv =
          Enum.reduce(allocations, inv, fn a, acc ->
            change(acc, {a.code, a.location}, -a.quantity, :asignacion, need_id, actor)
          end)

        {:ok, allocations, inv}

      {:error, missing} ->
        {:error, {:insufficient_stock, %{requested: quantity, available: quantity - missing}}}
    end
  end

  # Recorre los lotes (recursión sobre la lista) tomando de cada uno lo necesario
  # hasta cubrir lo pedido; si se acaban los lotes devuelve lo que faltó.
  defp take(_lots, 0, acc), do: {:ok, Enum.reverse(acc)}
  defp take([], missing, _acc), do: {:error, missing}

  defp take([lot | rest], remaining, acc) do
    taken = min(lot.quantity, remaining)

    take(rest, remaining - taken, [
      %{code: lot.code, location: lot.location, zone: lot.zone, quantity: taken} | acc
    ])
  end

  @doc "Devuelve al inventario lo asignado (al cancelar una necesidad)."
  @spec release(t(), [allocation()], String.t(), String.t()) :: t()
  def release(inv, allocations, need_id, actor) do
    Enum.reduce(
      allocations,
      inv,
      &change(&2, {&1.code, &1.location}, &1.quantity, :devolucion, need_id, actor)
    )
  end

  @doc "Existencias filtradas por `:category`, `:zone`, `:location` y/o `:code`."
  @spec list(t(), keyword()) :: [Resource.t()]
  def list(%__MODULE__{} = inv, filters \\ []) do
    inv.stocks |> Map.values() |> Filter.by(filters) |> Enum.sort_by(&{&1.code, &1.location})
  end

  @doc "Total disponible por categoría (opcionalmente de una zona)."
  @spec totals_by_category(t(), String.t() | nil) :: %{String.t() => non_neg_integer()}
  def totals_by_category(inv, zone \\ nil) do
    inv
    |> list(zone: zone)
    |> Enum.reduce(%{}, &Map.update(&2, &1.category, &1.quantity, fn q -> q + &1.quantity end))
  end

  defp template(inv, code) do
    case Enum.find(inv.stocks, fn {{c, _}, _} -> c == code end) do
      {_key, stock} -> {:ok, stock}
      nil -> {:error, {:not_found, :resource, code}}
    end
  end

  defp fetch_stock(inv, code, location) do
    case Map.fetch(inv.stocks, {code, location}) do
      {:ok, stock} -> {:ok, stock}
      :error -> {:error, {:not_found, :stock, "#{code}@#{location}"}}
    end
  end

  defp ensure_enough(%Resource{quantity: available}, requested) when requested <= available,
    do: :ok

  defp ensure_enough(%Resource{quantity: available}, requested),
    do: {:error, {:insufficient_stock, %{requested: requested, available: available}}}

  # Único punto donde cambia una cantidad: aplica el delta y anota el movimiento.
  defp change(inv, key, delta, type, reference, actor) do
    stock = Map.fetch!(inv.stocks, key)
    balance = stock.quantity + delta

    movement = %{
      id: inv.next_movement,
      code: stock.code,
      location: stock.location,
      type: type,
      quantity: abs(delta),
      balance: balance,
      reference: reference,
      actor: actor,
      at: Clock.now()
    }

    %{
      inv
      | stocks: Map.put(inv.stocks, key, %{stock | quantity: balance}),
        movements: [movement | inv.movements],
        next_movement: inv.next_movement + 1
    }
  end
end
