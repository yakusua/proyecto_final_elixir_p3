defmodule Emergencias.PersistenceTest do
  use Emergencias.DataCase

  import ExUnit.CaptureLog

  alias Emergencias.Storage

  defp populate do
    zone!("centro")

    {:ok, _} =
      Zones.add_sector("centro", %{code: "s1", name: "Sector 1", level: "alto", affected: 40})

    resource!("R001", "agua", 50)
    need!("agua", 30, "critica")
    {:ok, _} = Needs.assign_resource("N001", "agua", 30, "laura")

    {:ok, _} =
      Family.report_person(
        %{document: "1001", name: "Andrés Gómez", zone: "centro", status: "localizada"},
        "carlos"
      )

    {:ok, _} = Family.send_message("1001", "Estoy bien", "ana")

    {:ok, _} =
      Pets.report(
        %{
          kind: "lost",
          species: "perro",
          name: "Luna",
          color: "negra",
          size: "mediana",
          zone: "centro",
          contact: "300"
        },
        "carlos"
      )

    {:ok, _} =
      Shelters.register(%{code: "A01", name: "Albergue Norte", zone: "centro", capacity: 20})

    {:ok, _} = Shelters.enter("A01", "1001")
    connect!("laura", :coordinador)
  end

  test "los datos se guardan como archivos de texto plano" do
    populate()

    for name <- ~w(zones resources needs family pets users shelters/A01) do
      path = Storage.path(name)
      assert File.exists?(path), "falta #{path}"
      assert path |> File.read!() |> String.printable?()
    end

    assert File.read!(Storage.path("needs")) =~ "Necesidad de prueba"
    assert File.read!(Storage.path("family")) =~ "Andrés Gómez"
    refute File.read!(Storage.path("users")) =~ "clave-laura"
  end

  test "al reiniciar toda la aplicación (arranque en frío) se recupera todo el estado" do
    populate()

    :ok = Application.stop(:emergencias)
    {:ok, _} = Application.ensure_all_started(:emergencias)
    wait_until(fn -> match?({:ok, _}, Shelters.get("A01")) end)

    assert {:ok, %{code: "s1", affected: 40}} = Zones.get("s1")
    assert [%{code: "R001", quantity: 20}] = Resources.list()
    assert {:ok, [%{id: "N001", status: :asignada}]} = Needs.list()
    assert {:ok, [%{status: :localizada, history: [_]}]} = Family.find(document: "1001")
    assert {:ok, [%{id: "M001", content: "Estoy bien"}]} = Family.messages("1001")
    assert {:ok, [%{id: "PET001", name: "Luna"}]} = Pets.list()
    assert {:ok, shelter} = Shelters.get("A01")
    assert MapSet.member?(shelter.occupants, "1001")

    # Nadie queda conectado tras un reinicio, pero las cuentas siguen existiendo
    assert {:error, :not_connected} = Emergencias.execute("laura", "summary")
    assert {:ok, %{role: :coordinador}, :authenticated} = Accounts.connect("laura", "clave-laura")
    assert {:error, :invalid_credentials} = Accounts.connect("laura", "otra-clave")

    # El sistema sigue operando sin repetir identificadores
    assert %{id: "N002"} = need!("agua", 5)

    assert {:ok, %{id: "PET002"}} =
             Pets.report(
               %{
                 kind: "found",
                 species: "perro",
                 color: "negra",
                 size: "mediana",
                 zone: "centro",
                 contact: "1"
               },
               "t"
             )
  end

  test "una falla de escritura no cambia el estado en memoria" do
    zone!("centro")
    resource!("R001", "agua", 10)

    # Un directorio con el nombre del archivo impide reemplazarlo
    blocker = Storage.path("resources")
    File.rm!(blocker)
    File.mkdir_p!(blocker)
    on_exit(fn -> File.rm_rf(blocker) end)

    log =
      capture_log(fn ->
        assert {:error, {:persistence_failed, _}} =
                 Resources.add_stock("R001", "centro_acopio_1", 5, "t")
      end)

    assert log =~ "No se pudo guardar resources"
    assert available("agua") == 10
  end

  test "un archivo ilegible se aparta en lugar de sobrescribirse" do
    File.mkdir_p!(Storage.data_dir())
    File.write!(Storage.path("basura"), "esto no es un término ::: {{{")

    log = capture_log(fn -> assert Storage.load_or("basura", :por_defecto) == :por_defecto end)

    assert log =~ "ilegible"
    assert File.exists?(Storage.path("basura") <> ".corrupt")
  end

  test "guarda y lee términos con Unicode, estructuras y fechas" do
    term = %{
      nombre: "Andrés Gómez – Ñandú",
      lista: [1, {:ok, "x"}],
      fecha: ~U[2026-05-01 10:00:00Z]
    }

    assert :ok = Storage.save("prueba", term)
    assert Storage.load_or("prueba", nil) == term
    assert Storage.load_or("no_existe", 42) == 42
  end
end
