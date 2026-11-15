defmodule Emergencias.SupervisionTest do
  use Emergencias.DataCase

  import ExUnit.CaptureLog

  defp kill_and_wait(name) do
    old = Process.whereis(name)
    capture_log(fn -> Process.exit(old, :kill) end)
    wait_until(fn -> (new = Process.whereis(name)) && new != old && Process.alive?(new) end)
  end

  test "el árbol de supervisión está armado como se documenta" do
    children =
      Supervisor.which_children(Emergencias.Supervisor)
      |> Enum.map(fn {id, _, type, _} -> {id, type} end)

    for server <- [
          Accounts.Server,
          Zones.Server,
          Resources.Server,
          Needs.Server,
          Family.Server,
          Pets.Server
        ] do
      assert {server, :worker} in children
    end

    assert {Emergencias.Shelters.Supervisor, :supervisor} in children

    shelter_children =
      Supervisor.which_children(Emergencias.Shelters.Supervisor) |> Enum.map(&elem(&1, 0))

    assert Emergencias.Shelters.Pool in shelter_children
  end

  test "si cae un servidor, el supervisor lo reinicia con su estado guardado" do
    zone!("centro")
    need!("agua", 10, "alta")

    kill_and_wait(Emergencias.Needs.Server)

    assert {:ok, [%{id: "N001", priority: :alta}]} = Needs.list()
    assert %{id: "N002"} = need!("agua", 5)
  end

  test "un servidor caído no arrastra a los demás" do
    zone!("centro")
    resource!("R001", "agua", 10)
    zones_pid = Process.whereis(Emergencias.Zones.Server)

    kill_and_wait(Emergencias.Resources.Server)

    assert Process.whereis(Emergencias.Zones.Server) == zones_pid
    assert available("agua") == 10
  end

  test "cada albergue es un proceso supervisado que recupera su estado tras caerse" do
    zone!("centro")
    {:ok, _} = Shelters.register(%{code: "A01", name: "Uno", zone: "centro", capacity: 10})
    {:ok, _} = Shelters.register(%{code: "A02", name: "Dos", zone: "centro", capacity: 10})
    {:ok, _} = Shelters.enter("A01", "1")
    {:ok, _} = Shelters.enter("A01", "2")
    {:ok, _} = Shelters.enter("A02", "3")

    [{old_pid, _}] = Registry.lookup(Emergencias.Shelters.Registry, "A01")
    [{other_pid, _}] = Registry.lookup(Emergencias.Shelters.Registry, "A02")
    assert old_pid != other_pid

    capture_log(fn -> Process.exit(old_pid, :kill) end)

    wait_until(fn ->
      match?(
        [{pid, _}] when pid != old_pid,
        Registry.lookup(Emergencias.Shelters.Registry, "A01")
      )
    end)

    assert {:ok, shelter} = Shelters.get("A01")
    assert Emergencias.Shelters.Shelter.occupancy(shelter) == 2
    assert [{^other_pid, _}] = Registry.lookup(Emergencias.Shelters.Registry, "A02")
    assert {:error, {:already_in_shelter, "A01"}} = Shelters.enter("A01", "1")
  end

  test "mientras un servidor se reinicia, quien lo necesita recibe un error controlado" do
    assert {:error, :unavailable} = Emergencias.Server.safe(fn -> exit(:noproc) end)
    assert :ok = Emergencias.Server.safe(fn -> :ok end)
  end
end
