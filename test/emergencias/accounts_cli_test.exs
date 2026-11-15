defmodule Emergencias.AccountsCliTest do
  use Emergencias.DataCase

  import ExUnit.CaptureIO

  alias Emergencias.CLI.{Formatter, REPL}

  describe "cuentas" do
    test "un usuario nuevo se registra automáticamente con su tipo y zona" do
      assert {:ok, user, :registered} =
               Accounts.connect("Laura", "1234", %{
                 role: "coordinador",
                 zone: "centro",
                 full_name: "Laura Gómez"
               })

      assert %{
               username: "laura",
               role: :coordinador,
               zone: "centro",
               full_name: "Laura Gómez",
               salt: nil,
               password_hash: nil
             } = user
    end

    test "un usuario existente debe validar su contraseña y conserva su rol" do
      {:ok, _, :registered} = Accounts.connect("laura", "1234", %{role: :voluntario})

      assert {:ok, %{role: :voluntario}, :authenticated} =
               Accounts.connect("laura", "1234", %{role: :coordinador})

      assert {:error, :invalid_credentials} = Accounts.connect("laura", "9999")
    end

    test "validaciones de entrada" do
      assert {:error, {:invalid_field, :username, :bad_format}} = Accounts.connect("a b", "1234")
      assert {:error, {:invalid_field, :password, :too_short}} = Accounts.connect("laura", "1")

      assert {:error, {:invalid_value, :role, "rey"}} =
               Accounts.connect("laura", "1234", %{role: "rey"})
    end

    test "conectar y desconectar controla quién puede ejecutar comandos" do
      assert {:error, :not_connected} = Emergencias.execute("laura", "list_needs")
      connect!("laura", :coordinador)
      assert {:ok, _} = Emergencias.execute("laura", "list_needs")

      assert :ok = Emergencias.disconnect("laura")
      assert {:error, :not_connected} = Emergencias.execute("laura", "list_needs")
      assert {:error, :not_connected} = Emergencias.disconnect("laura")
    end

    test "la bitácora registra la actividad del usuario" do
      connect!("laura", :coordinador)
      run!("laura", ~s(register_zone centro "Centro" critico))
      {:error, _} = Emergencias.execute("laura", "register_zone")

      log = :sys.get_state(Emergencias.Accounts.Server).activity

      assert Enum.any?(
               log,
               &(&1.user == "laura" and &1.action == :register_zone and &1.outcome == :ok)
             )

      assert Enum.any?(log, &(&1.action == :connect))
    end
  end

  describe "consola (REPL)" do
    test "sesión interactiva con cambio de usuario y permisos" do
      input = """
      list_needs
      connect laura 1234 coordinador centro
      register_zone centro "Centro" critico
      connect carlos 1111 ciudadano centro
      register_zone otra "Otra" alto
      list_zones
      connect laura 1234
      zone_status centro
      disconnect
      quit
      """

      output = capture_io([input: input], fn -> REPL.run() end)

      assert output =~ "No hay una sesión abierta"
      assert output =~ "laura registrado y conectado como coordinador"
      assert output =~ "Centro"
      assert output =~ "Permiso denegado: 'register_zone' requiere rol coordinador"
      assert output =~ "Comando desconocido 'list_zones'"
      assert output =~ "laura conectado como coordinador"
      assert output =~ "ZONA centro"
      assert output =~ "laura desconectado"
      assert output =~ "Hasta pronto."
      assert {:error, :not_connected} = Emergencias.execute("laura", "list_needs")
      assert {:error, :not_connected} = Emergencias.execute("carlos", "list_needs")
    end

    test "contraseña incorrecta y errores de uso" do
      {:ok, _, _} = Accounts.connect("laura", "1234")

      output =
        capture_io([input: "connect laura mala\nconnect solo\nquit\n"], fn -> REPL.run() end)

      assert output =~ "Usuario o contraseña incorrectos"
      assert output =~ "Uso: connect <usuario>"
    end
  end

  test "el formateador traduce errores comunes" do
    assert Formatter.render({:error, {:insufficient_stock, %{requested: 25, available: 20}}}) =~
             "solo hay 20"

    assert Formatter.render({:error, {:invalid_value, :priority, "x"}}) =~
             "Opciones: crítica, alta, media, baja"

    assert Formatter.render({:error, {:algo, :raro}}) =~ "raro"
  end
end
