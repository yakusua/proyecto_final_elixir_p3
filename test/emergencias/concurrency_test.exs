defmodule Emergencias.ConcurrencyTest do
  @moduledoc "Los conflictos entre procesos simultáneos se resuelven sin inconsistencias."

  use Emergencias.DataCase

  alias Emergencias.Needs.Need
  alias Emergencias.Shelters.Shelter

  setup do
    zone!("centro")
    :ok
  end

  describe "inventario" do
    test "el ejemplo del enunciado: 30 + 25 litros sobre 50 disponibles" do
      resource!("R001", "agua", 50)
      n1 = need!("agua", 30, "critica")
      n2 = need!("agua", 25, "alta")

      results =
        concurrently([{n1.id, 30}, {n2.id, 25}], fn {id, qty} ->
          Needs.assign_resource(id, "agua", qty, "test")
        end)

      assert count_ok(results) == 1
      assert Enum.any?(results, &match?({:error, {:insufficient_stock, _}}, &1))
      assert available("agua") in [20, 25]
    end

    test "nunca se asigna más de lo que existe (40 solicitudes de 5 sobre 50)" do
      resource!("R001", "agua", 50)
      needs = for _ <- 1..40, do: need!("agua", 5)

      results = concurrently(needs, &Needs.assign_resource(&1.id, "agua", 5, "test"))

      assert count_ok(results) == 10
      assert Enum.count(results, &match?({:error, {:insufficient_stock, _}}, &1)) == 30
      assert available("agua") == 0

      {:ok, all} = Needs.list()
      assert all |> Enum.map(&Need.assigned/1) |> Enum.sum() == 50
    end

    test "con varios lotes el total asignado sigue siendo exacto" do
      resource!("R001", "agua", 33, "bodega_a")
      resource!("R002", "agua", 33, "bodega_b")
      resource!("R003", "agua", 34, "bodega_c")
      needs = for _ <- 1..50, do: need!("agua", 4)

      results = concurrently(needs, &Needs.assign_resource(&1.id, "agua", 4, "test"))

      assert count_ok(results) == 25
      assert available("agua") == 0
      assert Enum.all?(Resources.list(), &(&1.quantity >= 0))
    end

    test "una misma necesidad no se sobre-asigna con peticiones simultáneas" do
      resource!("R001", "agua", 100)
      need = need!("agua", 10)

      results = concurrently(1..20, fn _ -> Needs.assign_resource(need.id, "agua", 5, "test") end)

      assert count_ok(results) == 2
      assert available("agua") == 90
      assert [%Need{status: :asignada} = updated] = elem(Needs.list(), 1)
      assert Need.assigned(updated) == 10
    end

    test "transferencias y salidas simultáneas conservan el total y no dejan negativos" do
      resource!("R001", "agua", 100, "origen")

      results =
        concurrently(1..30, fn _ ->
          Resources.transfer("R001", "origen", "destino", 10, nil, "test")
        end)

      assert count_ok(results) == 10
      stocks = Resources.list(code: "R001")
      assert stocks |> Enum.map(& &1.quantity) |> Enum.sum() == 100
      assert Enum.find(stocks, &(&1.location == "destino")).quantity == 100

      results =
        concurrently(1..20, fn _ -> Resources.remove_stock("R001", "destino", 7, "test") end)

      assert count_ok(results) == 14
      assert available("agua") == 2
    end
  end

  describe "albergues, personas y mascotas" do
    test "50 ingresos simultáneos a un albergue de 10 cupos" do
      {:ok, _} = Shelters.register(%{code: "A01", name: "Norte", zone: "centro", capacity: 10})

      results = concurrently(1..50, &Shelters.enter("A01", "doc#{&1}"))

      assert count_ok(results) == 10
      assert Enum.count(results, &match?({:error, {:shelter_full, "A01"}}, &1)) == 40
      assert {:ok, shelter} = Shelters.get("A01")
      assert Shelter.occupancy(shelter) == 10
    end

    test "la misma persona entrando varias veces a la vez se cuenta una sola vez" do
      {:ok, _} = Shelters.register(%{code: "A01", name: "Norte", zone: "centro", capacity: 10})
      results = concurrently(1..10, fn _ -> Shelters.enter("A01", "777") end)

      assert count_ok(results) == 1
      assert Enum.count(results, &match?({:error, {:already_in_shelter, _}}, &1)) == 9
    end

    test "albergues distintos tienen cupos independientes" do
      for code <- ~w(A01 A02 A03),
          do: {:ok, _} = Shelters.register(%{code: code, name: code, zone: "centro", capacity: 4})

      jobs = for code <- ~w(A01 A02 A03), n <- 1..8, do: {code, "#{code}-#{n}"}
      results = concurrently(jobs, fn {code, doc} -> Shelters.enter(code, doc) end)

      assert count_ok(results) == 12
      assert Shelters.list() |> Enum.map(&Shelter.occupancy/1) == [4, 4, 4]
    end

    test "registrar el mismo albergue a la vez crea un solo proceso" do
      results =
        concurrently(1..8, fn _ ->
          Shelters.register(%{code: "A01", name: "N", zone: "centro", capacity: 5})
        end)

      assert count_ok(results) == 1
      assert Enum.count(results, &match?({:error, {:duplicate, :shelter, "A01"}}, &1)) == 7
    end

    test "reportar al mismo documento en paralelo crea un solo registro" do
      results =
        concurrently(1..10, fn _ ->
          Family.report_person(
            %{document: "1001", name: "Andrés", zone: "centro", status: "localizada"},
            "t"
          )
        end)

      assert count_ok(results) == 1
      assert {:ok, [_]} = Family.find(document: "1001")
    end

    test "un reporte de mascota no se resuelve dos veces" do
      pet = %{species: "perro", color: "negra", size: "mediana", zone: "centro", contact: "1"}
      {:ok, lost} = Pets.report(Map.put(pet, :kind, "lost"), "t")
      {:ok, found} = Pets.report(Map.put(pet, :kind, "found"), "t")

      results = concurrently(1..10, fn _ -> Pets.confirm(lost.id, found.id, "coordinador") end)

      assert count_ok(results) == 1
      assert Enum.count(results, &match?({:error, {:already_resolved, _}}, &1)) == 9
    end

    test "cerrar a la vez un mismo reporte con dos pares distintos solo permite uno" do
      pet = %{species: "perro", color: "negra", size: "mediana", zone: "centro", contact: "1"}
      {:ok, lost} = Pets.report(Map.put(pet, :kind, "lost"), "t")
      {:ok, found_1} = Pets.report(Map.put(pet, :kind, "found"), "t")
      {:ok, found_2} = Pets.report(Map.put(pet, :kind, "found"), "t")

      results = concurrently([found_1.id, found_2.id], &Pets.confirm(lost.id, &1, "t"))

      assert count_ok(results) == 1
      assert {:ok, resolved} = Pets.list(status: "resuelta")
      assert length(resolved) == 2
    end

    test "mensajes simultáneos reciben identificadores distintos" do
      ids =
        for {:ok, message} <-
              concurrently(1..20, &Family.send_message("1001", "mensaje #{&1}", "ana")),
            do: message.id

      assert length(Enum.uniq(ids)) == 20
    end
  end

  describe "usuarios" do
    test "dos coordinadores compiten por el mismo recurso desde sus sesiones" do
      connect!("laura", :coordinador)
      connect!("marta", :coordinador)
      resource!("R001", "agua", 50)
      run!("laura", "register_need agua 30 critica centro Punto de atención sector 3")
      run!("marta", "register_need agua 25 alta centro Familias del sector 3")

      jobs = [
        {"laura", "assign_resource N001 agua 30"},
        {"marta", "assign_resource N002 agua 25"}
      ]

      results = concurrently(jobs, fn {user, command} -> Emergencias.execute(user, command) end)

      assert count_ok(results) == 1
      assert available("agua") in [20, 25]
    end

    test "quince usuarios registrando y asignando a la vez" do
      users = for n <- 1..15, do: "brigada#{n}"
      Enum.each(users, &connect!(&1, :coordinador))
      resource!("R001", "alimentos", 60)

      results =
        concurrently(users, fn user ->
          {:ok, %Need{id: id}} =
            Emergencias.execute(user, "register_need alimentos 5 media centro Ración #{user}")

          Emergencias.execute(user, "assign_resource #{id} alimentos 5")
        end)

      assert count_ok(results) == 12
      assert available("alimentos") == 0
    end

    test "dos conexiones simultáneas del mismo usuario nuevo dan un solo registro" do
      results =
        concurrently(1..10, fn _ -> Accounts.connect("laura", "1234", %{role: :ciudadano}) end)

      assert Enum.all?(results, &match?({:ok, _, _}, &1))
      assert Enum.count(results, &match?({:ok, _, :registered}, &1)) == 1
    end
  end
end
