defmodule Emergencias.CoreTest do
  @moduledoc "Pruebas unitarias del núcleo puro (sin procesos): reglas, estructuras y algoritmos."

  use ExUnit.Case, async: true

  alias Emergencias.{Text, Types, Validation}
  alias Emergencias.CLI.{Parser, Spec}
  alias Emergencias.Family.Person
  alias Emergencias.Needs.Need
  alias Emergencias.Pets.{Matcher, Report}
  alias Emergencias.Resources.{Inventory, Resource}
  alias Emergencias.Shelters.Shelter
  alias Emergencias.Zones.{Node, Tree}

  @now ~U[2026-01-01 00:00:00Z]

  describe "Text, Types y Validation" do
    test "normalización y similitud" do
      assert Text.normalize("  CRÍTICA   Atención ") == "critica atencion"
      assert Text.slug("Primeros Auxilios") == "primeros_auxilios"
      assert Text.jaccard(["a", "b"], ["b", "c"]) == 1 / 3
      assert Text.contains?("Andrés Gómez", "ANDRES")
      assert Text.sequence_id("N", 7) == "N007"
    end

    test "Types acepta tildes y alias, y rechaza lo desconocido" do
      assert Types.parse(:priority, "Crítica") == {:ok, :critica}
      assert Types.parse(:level, "critica") == {:ok, :critico}
      assert Types.parse(:pet_kind, "lost") == {:ok, :perdida}
      assert Types.parse(:pet_size, "mediana") == {:ok, :mediano}
      assert {:error, {:invalid_value, :priority, "extrema"}} = Types.parse(:priority, "extrema")
      assert Types.rank(:priority, :critica) > Types.rank(:priority, :baja)
    end

    test "Validation" do
      assert Validation.code(" R001 ", :code, :up) == {:ok, "R001"}
      assert {:error, {:invalid_field, :code, :bad_identifier}} = Validation.code("../etc", :code)
      assert Validation.positive_integer("30", :quantity) == {:ok, 30}

      assert {:error, {:invalid_field, :quantity, :must_be_positive}} =
               Validation.positive_integer(0, :quantity)

      assert {:error, {:invalid_field, :quantity, :not_a_number}} =
               Validation.positive_integer("3x", :quantity)

      assert {:error, {:invalid_field, :q, :must_not_be_negative}} =
               Validation.non_negative_integer("-1", :q)

      assert Validation.non_negative_integer(nil, :affected, 0) == {:ok, 0}
      assert {:error, {:invalid_field, :name, :blank}} = Validation.text("  ", :name)
    end
  end

  describe "Zones.Tree (recursivo)" do
    defp node(kind, code, level, affected, children \\ []),
      do: %Node{
        code: code,
        name: code,
        kind: kind,
        level: level,
        affected: affected,
        children: children
      }

    defp tree do
      node(:zona, "centro", :medio, 100, [
        node(:sector, "s1", :alto, 50, [node(:punto_atencion, "p1", :critico, 10)]),
        node(:sector, "s2", :bajo, 20, [node(:punto_atencion, "p2", :bajo, 1)])
      ])
    end

    test "find e insert funcionan en cualquier nivel y no mutan el original" do
      assert {:ok, %Node{code: "p2"}} = Tree.find(tree(), "p2")
      assert Tree.find(tree(), "nada") == :error

      assert {:ok, updated} = Tree.insert(tree(), "s2", node(:punto_atencion, "p3", :alto, 7))
      assert {:ok, %Node{code: "p3"}} = Tree.find(updated, "p3")
      assert Tree.find(tree(), "p3") == :error
    end

    test "insert respeta qué puede contener cada nodo" do
      assert {:error, {:invalid_child, :zona, :punto_atencion}} =
               Tree.insert(tree(), "centro", node(:punto_atencion, "x", :bajo, 0))

      assert {:error, {:invalid_child, :sector, :sector}} =
               Tree.insert(tree(), "s1", node(:sector, "x", :bajo, 0))

      assert {:error, {:not_found, :zone, "ghost"}} =
               Tree.insert(tree(), "ghost", node(:sector, "x", :bajo, 0))
    end

    test "acumulados y estadísticas" do
      assert Tree.total_affected(tree()) == 181
      {:ok, s1} = Tree.find(tree(), "s1")
      assert Tree.total_affected(s1) == 60

      assert %{
               nodes: 5,
               sectors: 2,
               points: 2,
               depth: 3,
               affected: 181,
               by_level: %{medio: 1, alto: 1, critico: 1, bajo: 2}
             } =
               Tree.stats(tree())

      assert [{0, %Node{code: "centro"}}, {1, %Node{code: "s1"}}, {2, %Node{code: "p1"}} | _] =
               Tree.flatten(tree())
    end
  end

  describe "Inventory" do
    defp stock(code, category, quantity, location, zone),
      do: %Resource{
        code: code,
        name: category,
        category: category,
        unit: "u",
        location: location,
        zone: zone,
        quantity: quantity
      }

    defp inventory do
      {:ok, inv} = Inventory.register(%Inventory{}, stock("R1", "agua", 50, "a", "centro"), "t")
      {:ok, inv} = Inventory.register(inv, stock("R2", "agua", 30, "b", "norte"), "t")
      inv
    end

    test "no repite códigos y deja historial" do
      assert {:error, {:duplicate, :resource, "R1"}} =
               Inventory.register(inventory(), stock("R1", "agua", 1, "z", "centro"), "t")

      {:ok, inv} = Inventory.add(inventory(), "R1", "a", 10, "ana")
      {:ok, inv} = Inventory.remove(inv, "R1", "a", 25, "ana")
      assert %{type: :salida, quantity: 25, balance: 35, actor: "ana"} = hd(inv.movements)
    end

    test "nunca queda en negativo" do
      assert {:error, {:insufficient_stock, %{requested: 51, available: 50}}} =
               Inventory.remove(inventory(), "R1", "a", 51, "t")

      assert {:error, {:not_found, :stock, "R1@zzz"}} =
               Inventory.remove(inventory(), "R1", "zzz", 1, "t")

      assert {:error, {:not_found, :resource, "R9"}} =
               Inventory.add(inventory(), "R9", "a", 1, "t")
    end

    test "transfer crea el destino y conserva el total" do
      {:ok, inv} = Inventory.transfer(inventory(), "R1", "a", "albergue_2", 20, "norte", "t")

      assert [%{quantity: 20, zone: "norte"}] =
               Inventory.list(inv, code: "R1", location: "albergue_2")

      assert Inventory.totals_by_category(inv) == %{"agua" => 80}
      assert {:error, :same_location} = Inventory.transfer(inv, "R1", "a", "a", 1, nil, "t")

      assert {:error, {:insufficient_stock, _}} =
               Inventory.transfer(inv, "R1", "a", "x", 31, nil, "t")
    end

    test "allocate toma primero la zona pedida (recursivo), es todo o nada y release devuelve" do
      {:ok, allocations, inv} = Inventory.allocate(inventory(), "agua", 70, "norte", "N1", "t")
      assert [%{code: "R2", quantity: 30}, %{code: "R1", quantity: 40}] = allocations
      assert Inventory.totals_by_category(inv) == %{"agua" => 10}

      assert {:error, {:insufficient_stock, %{requested: 100, available: 80}}} =
               Inventory.allocate(inventory(), "agua", 100, "centro", "N1", "t")

      back = Inventory.release(inv, allocations, "N1", "t")
      assert Inventory.totals_by_category(back) == %{"agua" => 80}
    end
  end

  describe "Need" do
    defp need(overrides \\ []) do
      {:ok, valid} =
        Need.validate(%{
          type: "agua",
          quantity: "30",
          priority: "critica",
          zone: "centro",
          description: "d"
        })

      Need.create(valid, 1, "ana", @now) |> struct(overrides)
    end

    test "validación y creación" do
      assert {:error, {:invalid_value, :need_type, "oro"}} =
               Need.validate(%{
                 type: "oro",
                 quantity: 1,
                 priority: "alta",
                 zone: "z",
                 description: "d"
               })

      assert {:error, {:invalid_field, :quantity, :must_be_positive}} =
               Need.validate(%{
                 type: "agua",
                 quantity: -5,
                 priority: "alta",
                 zone: "z",
                 description: "d"
               })

      assert %Need{id: "N001", status: :pendiente, quantity: 30} = need()
    end

    test "transiciones válidas e inválidas" do
      assert {:ok, %{status: :cancelada}} = Need.transition(need(), :cancelada, "x", @now)

      assert {:error, {:invalid_transition, :need, :pendiente, :atendida}} =
               Need.transition(need(), :atendida, "x", @now)

      assert {:error, {:invalid_transition, :need, :cancelada, :pendiente}} =
               Need.transition(need(status: :cancelada), :pendiente, "x", @now)

      assert {:error, {:invalid_transition, :need, :atendida, :cancelada}} =
               Need.transition(need(status: :atendida), :cancelada, "x", @now)
    end

    test "solo las pendientes consumen recursos" do
      assert :ok = Need.check_assignable(need(), "agua", 30)

      assert {:error, {:need_not_assignable, :atendida}} =
               Need.check_assignable(need(status: :atendida), "agua", 1)

      assert {:error, {:exceeds_need, 30}} = Need.check_assignable(need(), "agua", 31)

      assert {:error, {:category_mismatch, :agua, "alimentos"}} =
               Need.check_assignable(need(), "alimentos", 1)

      assert :ok = Need.check_assignable(need(type: :otra), "cualquiera", 1)
    end

    test "asignación parcial deja pendiente; la total pasa a asignada" do
      partial =
        Need.add_assignments(
          need(),
          [%{code: "R1", location: "a", zone: "z", quantity: 10}],
          "x",
          @now
        )

      assert {partial.status, Need.remaining(partial)} == {:pendiente, 20}

      full =
        Need.add_assignments(
          partial,
          [%{code: "R1", location: "a", zone: "z", quantity: 20}],
          "x",
          @now
        )

      assert {full.status, Need.assigned(full)} == {:asignada, 30}
    end

    test "la prioridad ordena la atención (crítica antes; empate por llegada)" do
      needs = [
        need(id: "N1", seq: 1, priority: :baja),
        need(id: "N2", seq: 2, priority: :critica),
        need(id: "N3", seq: 3, priority: :alta),
        need(id: "N4", seq: 4, priority: :critica)
      ]

      assert needs |> Need.sort_by_priority() |> Enum.map(& &1.id) == ["N2", "N4", "N3", "N1"]
    end
  end

  describe "Person" do
    defp person(status) do
      {:ok, valid} = Person.validate(%{document: "10", name: "Ana", zone: "z", status: status})
      Person.create(valid, 1, "x", @now)
    end

    test "transiciones con historial" do
      {:ok, p} = Person.update(person(:reportada), %{status: :localizada}, "v", @now)
      {:ok, p} = Person.update(p, %{status: :reunificada}, "v", @now)

      assert [
               %{from: :localizada, to: :reunificada},
               %{from: :reportada, to: :localizada},
               %{from: nil}
             ] = p.history

      assert {:error, {:invalid_transition, :person, :reunificada, :reportada}} =
               Person.update(p, %{status: :reportada}, "v", @now)
    end

    test "mismo estado sin cambio de zona es inválido; con cambio de zona se acepta" do
      assert {:error, {:invalid_transition, :person, :localizada, :localizada}} =
               Person.update(person(:localizada), %{status: :localizada}, "v", @now)

      assert {:ok, %{zone: "otra"}} =
               Person.update(person(:localizada), %{zone: "otra"}, "v", @now)
    end
  end

  describe "Shelter" do
    test "ocupación, capacidad y duplicados" do
      shelter = %Shelter{code: "A01", name: "A", zone: "z", capacity: 2}
      {:ok, s} = Shelter.enter(shelter, "1")
      {:ok, s} = Shelter.enter(s, "2")

      assert {Shelter.occupancy(s), Shelter.available(s)} == {2, 0}
      assert {:error, {:shelter_full, "A01"}} = Shelter.enter(s, "3")
      assert {:error, {:already_in_shelter, "A01"}} = Shelter.enter(s, "1")
      assert {:ok, s} = Shelter.leave(s, "1")
      assert {:error, {:not_in_shelter, "A01"}} = Shelter.leave(s, "1")
      assert s |> Shelter.to_record() |> Shelter.from_record() == s
      assert Shelter.occupancy_percent(s) == 50.0
    end
  end

  describe "Mascotas" do
    defp report(kind, attrs \\ []) do
      base = %{
        kind: kind,
        species: "Perro",
        name: nil,
        color: "Negra",
        size: "mediana",
        zone: "norte",
        contact: "300"
      }

      {:ok, valid} = Report.validate(Map.merge(base, Map.new(attrs)))
      Report.create(valid, System.unique_integer([:positive]), "x", @now)
    end

    test "puntaje: especie distinta = 0, coincidencia perfecta = 100" do
      assert Matcher.score(report("lost"), report("found", species: "gato")).total == 0

      lost = report("lost", name: "Luna", traits: "collar rojo")
      found = report("found", name: "luna", traits: "Collar rojo")
      assert Matcher.score(lost, found).total == 100
    end

    test "puntaje parcial según color, tamaño y zona" do
      score =
        Matcher.score(
          report("lost"),
          report("found", color: "blanco", size: "grande", zone: "sur")
        )

      assert {score.breakdown.species, score.breakdown.color, score.breakdown.size,
              score.breakdown.zone} == {20.0, 0.0, 7.5, 0.0}

      assert score.total < Matcher.threshold()
    end

    test "nombres desconocidos se guardan como nil" do
      assert report("found", name: "desconocido").name == nil
      assert report("lost", name: "Luna").name == "Luna"
    end

    test "confirmar cierra ambos reportes y no se puede repetir" do
      {lost, found} = {report("lost"), report("found")}
      reports = %{lost.id => lost, found.id => found}

      assert {:ok, reports, %{score: score}} = Report.confirm(reports, lost.id, found.id)
      assert score > 0
      assert %{status: :resuelta, matched_with: matched} = reports[lost.id]
      assert matched == found.id
      assert {:error, {:already_resolved, _}} = Report.confirm(reports, lost.id, found.id)
    end

    test "confirmar valida tipos y especies" do
      {a, b, c} = {report("lost"), report("lost"), report("found", species: "gato")}
      reports = %{a.id => a, b.id => b, c.id => c}

      assert {:error, {:wrong_kinds, :perdida, :perdida}} = Report.confirm(reports, a.id, b.id)
      assert {:error, {:species_mismatch, "perro", "gato"}} = Report.confirm(reports, a.id, c.id)
      assert {:error, {:not_found, :pet_report, "NOPE"}} = Report.confirm(reports, a.id, "NOPE")
    end

    test "refresh_status marca posible coincidencia solo en los reportes involucrados" do
      {lost, found, other} = {report("lost"), report("found"), report("found")}

      reports =
        Report.refresh_status(%{lost.id => lost, found.id => found, other.id => other}, [
          %{lost: lost.id, found: found.id}
        ])

      assert {reports[lost.id].status, reports[found.id].status, reports[other.id].status} ==
               {:posible_coincidencia, :posible_coincidencia, :activa}
    end
  end

  describe "Parser y Spec" do
    defp bind(line) do
      {:ok, command} = Parser.parse(line)
      Spec.bind(command)
    end

    test "comillas, opciones y Unicode" do
      assert {:ok, %{name: :send_family_message, args: ["1001", "Estoy bien, aquí"]}} =
               Parser.parse(~s(send_family_message 1001 "Estoy bien, aquí"))

      assert {:ok, %{opts: %{"zona" => "centro", "prioridad" => "critica"}}} =
               Parser.parse("list_needs zona=centro prioridad=critica")

      assert {:ok, %{args: ["z1", "Zona Uno", "alto"], opts: %{"afectadas" => "1200"}}} =
               Parser.parse(~s(register_zone z1 "Zona Uno" alto afectadas="1200"))

      assert {:ok, %{args: ["1", "a=b"], opts: opts}} =
               Parser.parse(~s(send_family_message 1 "a=b"))

      assert opts == %{}

      assert {:ok, %{args: ["1", "Andrés Gómez" | _]}} =
               Parser.parse("report_person 1 'Andrés Gómez' zona_norte localizada")
    end

    test "errores de sintaxis" do
      assert {:error, :unclosed_quote} = Parser.parse(~s(send_family_message 1 "abierta))
      assert {:error, :empty} = Parser.parse("   ")
      assert {:error, {:unknown_command, "bailar"}} = Parser.parse("bailar ya")
    end

    test "asocia argumentos, texto libre y opciones" do
      assert {:ok, %{codigo: "R001", ubicacion: "c1", zona: nil}} =
               bind("register_resource R001 agua 200 litros c1")

      assert {:ok, %{descripcion: "Punto de atención sector 3"}} =
               bind("register_need agua 30 critica centro Punto de atención sector 3")

      assert {:ok, %{documento: nil, nombre: "ana"}} = bind("find_person nombre=ana")

      assert {:error, {:usage, "assign_resource <id> <categoria> <cantidad>"}} =
               bind("assign_resource N001 agua")

      assert {:error, {:unknown_option, "color", _}} = bind("list_needs color=azul")
    end

    test "los comandos del enunciado existen" do
      for word <-
            ~w(register_zone register_need list_needs assign_resource register_resource list_resources transfer_resource report_person find_person send_family_message list_family_messages report_pet match_pets register_shelter check_shelter register_entry register_exit summary critical_resources pending_needs) do
        assert {:ok, _} = Spec.lookup(word), "falta #{word}"
      end
    end

    test "autorización jerárquica por rol" do
      assert :ok = Spec.authorize(:ciudadano, :register_need)

      assert {:error, {:forbidden, :assign_resource, :coordinador}} =
               Spec.authorize(:voluntario, :assign_resource)

      assert :ok = Spec.authorize(:administrador, :assign_resource)
    end
  end
end
