defmodule Emergencias.FlowTest do
  @moduledoc "Flujo del enunciado y reglas de cada módulo, ejecutados por comandos como lo haría un usuario real."

  use Emergencias.DataCase

  alias Emergencias.Needs.Need
  alias Emergencias.Shelters.Shelter

  setup do
    connect!("laura", :coordinador)
    connect!("carlos", :ciudadano, "zona_norte")
    connect!("juan", :voluntario, "zona_norte")
    :ok
  end

  test "flujo completo del enunciado" do
    run!("laura", ~s(register_zone centro "Centro" critico afectadas=1200))
    run!("laura", ~s(register_zone zona_norte "Zona Norte" alto))
    run!("laura", ~s(register_sector centro sector_3 "Sector 3" alto afectadas=300))
    run!("laura", ~s(register_point sector_3 punto_3a "Punto sector 3" critico afectadas=80))

    # Necesidad crítica de 30 litros y recurso con 50; otro usuario pide 25 del mismo recurso
    assert %Need{id: "N001", priority: :critica} =
             run!("laura", "register_need agua 30 critica centro Punto de atención sector 3")

    assert %{quantity: 50} =
             run!("laura", "register_resource R001 agua 50 litros centro_acopio_1")

    assert %Need{id: "N002"} =
             run!("carlos", "register_need agua 25 alta centro Familias del sector 3")

    assert %Need{status: :asignada} = run!("laura", "assign_resource N001 agua 30")

    assert {:error, {:insufficient_stock, %{requested: 25, available: 20}}} =
             Emergencias.execute("laura", "assign_resource N002 agua 25")

    # Persona localizada, mensaje y albergue
    run!("laura", ~s(register_shelter A01 "Albergue Norte" zona_norte 150))

    assert %{status: :localizada} =
             run!("carlos", ~s(report_person 1001 "Andrés Gómez" zona_norte localizada))

    assert %{id: "M001", status: :pendiente} =
             run!("carlos", ~s(send_family_message 1001 "Estoy bien, estoy en el albergue norte"))

    assert %Shelter{} = shelter = run!("juan", "register_entry A01 1001")
    assert Shelter.occupancy(shelter) == 1

    # Mascotas
    run!("carlos", ~s(report_pet lost perro "Luna" negra mediana zona_norte 3001234567))
    run!("juan", "report_pet found perro desconocido negra mediana zona_norte 3109876543")

    assert {:matches, [%{lost: "PET001", found: "PET002", total: total}]} =
             run!("juan", "match_pets")

    assert total >= 50

    assert [%{status: :posible_coincidencia}, %{status: :posible_coincidencia}] =
             run!("juan", "list_pets")

    assert {:confirmed, %{lost: "PET001", found: "PET002"}} =
             run!("laura", "confirm_pet_match PET001 PET002")

    # Resumen global del coordinador
    assert {:summary, summary} = run!("laura", "summary")
    assert summary.resources == %{"agua" => 20}
    assert summary.needs.pending == 1
    assert summary.persons == %{localizada: 1}
    assert summary.messages == %{total: 1, pending: 1}
    assert summary.pets == %{resuelta: 2}
    assert summary.zones.affected == 1580
    assert summary.shelters.occupancy == 1
  end

  test "los permisos restringen las operaciones por tipo de usuario" do
    zone!("centro")
    resource!("R001", "agua", 10)
    need!("agua", 5)

    assert {:error, {:forbidden, :assign_resource, :coordinador}} =
             Emergencias.execute("carlos", "assign_resource N001 agua 5")

    assert {:error, {:forbidden, :summary, :coordinador}} = Emergencias.execute("juan", "summary")

    assert {:error, {:forbidden, :register_zone, :coordinador}} =
             Emergencias.execute("juan", "register_zone x X alto")

    assert {:ok, _} = Emergencias.execute("juan", "list_needs")
    assert {:ok, _} = Emergencias.execute("laura", "assign_resource N001 agua 5")
  end

  test "consultas de necesidades: filtros y orden por prioridad" do
    zone!("centro")
    zone!("norte", "alto")
    need!("agua", 10, "baja")
    need!("alimentos", 10, "critica")
    need!("agua", 10, "alta", "norte")
    need!("agua", 10, "critica", "norte")

    assert run!("laura", "list_needs") |> Enum.map(& &1.id) == ["N002", "N004", "N003", "N001"]
    assert [%{id: "N004"}] = run!("laura", "list_needs zona=norte prioridad=crítica")
    assert [_, _, _] = run!("laura", "list_needs tipo=agua")
    assert [%{id: "N002"}, %{id: "N004"}] = run!("laura", "list_needs prioridad=critica")

    assert {:error, {:invalid_value, :priority, "extrema"}} =
             Emergencias.execute("laura", "list_needs prioridad=extrema")
  end

  test "pending_needs lista solo las pendientes en orden de prioridad" do
    zone!("centro")
    resource!("R001", "agua", 100)
    need!("agua", 5, "baja")
    need!("agua", 5, "critica")
    need!("agua", 5, "alta")
    run!("laura", "assign_resource N003 agua 5")

    assert run!("juan", "pending_needs") |> Enum.map(& &1.id) == ["N002", "N001"]
  end

  test "las entradas inválidas se rechazan antes de modificar el estado" do
    zone!("centro")

    assert {:error, {:invalid_field, :quantity, :must_be_positive}} =
             Emergencias.execute("laura", "register_need agua 0 alta centro algo")

    assert {:error, {:invalid_field, :quantity, :not_a_number}} =
             Emergencias.execute("laura", "register_need agua muchos alta centro algo")

    assert {:error, {:not_found, :zone, "marte"}} =
             Emergencias.execute("laura", "register_need agua 5 alta marte algo")

    assert {:error, {:invalid_value, :need_type, "oro"}} =
             Emergencias.execute("laura", "register_need oro 5 alta centro algo")

    assert {:error, {:invalid_field, :quantity, :must_not_be_negative}} =
             Emergencias.execute("laura", "register_resource R1 agua -5 litros c1 zona=centro")

    assert {:error, {:duplicate, :zone, "centro"}} =
             Emergencias.execute("laura", "register_zone centro Otra bajo")

    assert {:error, {:usage, _}} = Emergencias.execute("laura", "register_need agua")
    assert {:error, {:unknown_command, "bailar"}} = Emergencias.execute("laura", "bailar")
    assert {:ok, []} = Needs.list()
  end

  test "ciclo de vida de una necesidad: parcial, estados y no reconsumo" do
    zone!("centro")
    resource!("R001", "agua", 100)
    need!("agua", 30, "critica")

    assert {:error, {:invalid_transition, :need, :pendiente, :atendida}} =
             Emergencias.execute("laura", "update_need N001 atendida")

    assert %Need{status: :pendiente} = run!("laura", "assign_resource N001 agua 10")
    assert %Need{status: :asignada} = run!("laura", "assign_resource N001 agua 20")
    assert available("agua") == 70

    assert {:error, {:need_not_assignable, :asignada}} =
             Emergencias.execute("laura", "assign_resource N001 agua 1")

    assert %Need{status: :en_atencion} = run!("laura", "update_need N001 en_atencion")
    assert %Need{status: :atendida} = run!("laura", "update_need N001 atendida")

    assert {:error, {:need_not_assignable, :atendida}} =
             Emergencias.execute("laura", "assign_resource N001 agua 1")

    assert {:error, {:invalid_transition, :need, :atendida, :cancelada}} =
             Emergencias.execute("laura", "update_need N001 cancelada")

    assert available("agua") == 70
  end

  test "cancelar una necesidad asignada devuelve el inventario y no se cancela dos veces" do
    zone!("centro")
    resource!("R001", "agua", 50)
    need!("agua", 30)

    run!("laura", "assign_resource N001 agua 30")
    assert available("agua") == 20

    assert %Need{status: :cancelada, assignments: []} =
             run!("laura", "update_need N001 cancelada")

    assert available("agua") == 50

    assert {:error, {:invalid_transition, :need, :cancelada, :cancelada}} =
             Emergencias.execute("laura", "update_need N001 cancelada")
  end

  test "recursos: entradas, salidas, transferencia, duplicados y disponibilidad por zona" do
    zone!("centro")
    zone!("norte", "alto")
    resource!("R001", "agua", 100)

    assert %{quantity: 130} = run!("laura", "resource_in R001 centro_acopio_1 30")
    assert %{quantity: 110} = run!("laura", "resource_out R001 centro_acopio_1 20")

    assert {:error, {:insufficient_stock, _}} =
             Emergencias.execute("laura", "resource_out R001 centro_acopio_1 500")

    assert %{location: "albergue_2", zone: "norte", quantity: 30} =
             run!("laura", "transfer_resource R001 centro_acopio_1 albergue_2 30 zona=norte")

    assert [_, _] = run!("laura", "list_resources categoria=agua")
    assert [%{zone: "norte", quantity: 30}] = run!("laura", "list_resources zona=norte")

    assert [%{location: "centro_acopio_1", quantity: 80}] =
             run!("laura", "list_resources ubicacion=centro_acopio_1")

    movements = Emergencias.Resources.Server.query(& &1.movements)

    assert Enum.map(movements, & &1.type) == [
             :transferencia_entrada,
             :transferencia_salida,
             :salida,
             :entrada,
             :registro
           ]

    assert {:error, {:duplicate, :resource, "R001"}} =
             Emergencias.execute("laura", "register_resource R001 agua 5 litros otra zona=centro")
  end

  test "recursos críticos: déficit entre demanda pendiente e inventario" do
    zone!("centro")
    resource!("R001", "agua", 10)
    resource!("R002", "alimentos", 500)
    need!("agua", 30)
    need!("agua", 20)
    need!("alimentos", 10)

    assert {:critical, [%{category: "agua", available: 10, demand: 50, deficit: 40}]} =
             run!("laura", "critical_resources")

    Resources.add_stock("R001", "centro_acopio_1", 100, "t")
    assert {:critical, []} = run!("laura", "critical_resources")
  end

  test "familiares: búsqueda, historial, mensajes y transiciones válidas" do
    zone!("centro")
    zone!("norte", "alto")
    run!("carlos", ~s(report_person 1 "Ana Pérez" centro reportada edad=30))
    run!("carlos", ~s(report_person 2 "Andrés Gómez" norte localizada))

    assert {:error, {:duplicate, :person, "1"}} =
             Emergencias.execute("carlos", ~s(report_person 1 "Otra" centro reportada))

    assert [%{document: "2"}] = run!("carlos", "find_person nombre=andres")
    assert [%{document: "1"}] = run!("carlos", "find_person zona=centro")
    assert [%{document: "1"}] = run!("carlos", "find_person estado=reportada")
    assert [%{document: "2"}] = run!("carlos", "find_person 2")
    assert [] = run!("carlos", "find_person 99")

    assert %{status: :localizada} = run!("juan", "update_person 1 localizada")
    assert %{status: :reunificada, history: history} = run!("juan", "update_person 1 reunificada")
    assert Enum.map(history, & &1.to) == [:reunificada, :localizada, :reportada]

    assert {:error, {:invalid_transition, :person, :reunificada, :reportada}} =
             Emergencias.execute("juan", "update_person 1 reportada")

    assert {:error, {:forbidden, :update_person, :voluntario}} =
             Emergencias.execute("carlos", "update_person 1 localizada")

    run!("carlos", ~s(send_family_message 1 "Te esperamos"))
    run!("carlos", ~s(send_family_message 1 "Llámanos"))
    assert [%{id: "M001"}, %{id: "M002"}] = run!("carlos", "list_family_messages 1")

    assert %{status: :entregado, delivered_at: %DateTime{}} =
             run!("juan", "mark_message M001 entregado")

    assert [%{id: "M002"}] = run!("carlos", "list_family_messages 1 estado=pendiente")
    assert %{status: :pendiente, delivered_at: nil} = run!("juan", "mark_message M001 pendiente")

    assert {:error, {:not_found, :message, "M999"}} =
             Emergencias.execute("juan", "mark_message M999 entregado")
  end

  test "albergues: ingreso, salida, cupos, reglas y reporte de ocupación" do
    zone!("centro")
    run!("laura", ~s(register_shelter A01 "Albergue Uno" centro 2))
    run!("laura", ~s(register_shelter A02 "Albergue Dos" centro 4))

    assert {:error, {:duplicate, :shelter, "A01"}} =
             Emergencias.execute("laura", ~s(register_shelter a01 "Otro" centro 5))

    assert {:error, {:invalid_field, :capacity, :must_be_positive}} =
             Emergencias.execute("laura", ~s(register_shelter A03 "Cero" centro 0))

    assert {:error, {:not_found, :zone, "luna"}} =
             Emergencias.execute("laura", ~s(register_shelter A03 "Luna" luna 5))

    run!("juan", "register_entry A01 1")
    run!("juan", "register_entry A01 2")
    assert {:error, {:shelter_full, "A01"}} = Emergencias.execute("juan", "register_entry A01 3")

    assert {:error, {:already_in_shelter, "A01"}} =
             Emergencias.execute("juan", "register_entry A01 1")

    assert {:error, {:not_found, :shelter, "ZZ"}} =
             Emergencias.execute("juan", "register_entry ZZ 1")

    assert %Shelter{} = shelter = run!("juan", "register_exit A01 1")
    assert Shelter.available(shelter) == 1
    assert {:error, {:not_in_shelter, "A01"}} = Emergencias.execute("juan", "register_exit A01 1")

    run!("juan", "register_entry A02 7")
    assert [%{code: "A01"}, %{code: "A02"}] = run!("laura", "shelter_report")
    assert [%{code: "A01"}] = run!("laura", "shelter_report limite=1")
  end

  test "un albergue muestra sus necesidades y recursos asociados" do
    zone!("centro")
    run!("laura", ~s(register_shelter A01 "Albergue Uno" centro 10))
    run!("laura", ~s(register_need agua 10 alta centro "Para el albergue" albergue=A01))
    run!("laura", "register_resource R9 agua 5 litros a01 zona=centro")

    assert {:shelter_status,
            %{shelter: %{code: "A01"}, needs: [%{id: "N001"}], resources: [%{code: "R9"}]}} =
             run!("laura", "check_shelter A01")

    assert {:error, {:not_found, :shelter, "ZZ"}} =
             Emergencias.execute("laura", "register_need agua 1 alta centro x albergue=zz")
  end

  test "zonas: estructura jerárquica, códigos únicos y estadísticas acumuladas" do
    run!("laura", ~s(register_zone centro "Centro" medio afectadas=100))
    run!("laura", ~s(register_sector centro s1 "Sector 1" alto afectadas=50))
    run!("laura", ~s(register_point s1 p1 "Punto 1" bajo afectadas=5))

    assert {:error, {:invalid_child, :zona, :punto_atencion}} =
             Emergencias.execute("laura", ~s(register_point centro x "X" bajo))

    assert {:error, {:duplicate, :zone, "p1"}} =
             Emergencias.execute("laura", ~s(register_sector centro p1 "Repetido" bajo))

    assert {:error, {:not_found, :zone, "nada"}} =
             Emergencias.execute("laura", ~s(register_sector nada s9 "S" bajo))

    run!("laura", "register_need agua 5 alta centro algo")
    assert {:zone_status, status} = run!("laura", "zone_status centro")
    assert %{affected: 155, depth: 3, nodes: 3, needs: %{total: 1}} = status

    assert [{0, %{code: "centro"}, 155}, {1, %{code: "s1"}, 55}, {2, %{code: "p1"}, 5}] =
             status.tree
  end
end
