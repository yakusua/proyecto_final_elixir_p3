defmodule Emergencias.CLI.Commands do
  @moduledoc """
  Despachador de comandos. Para cada línea de texto: la interpreta (`Parser`),
  comprueba que el rol del usuario permita la acción (`Spec.authorize/2`), asocia los
  argumentos (`Spec.bind/1`), ejecuta la operación en el contexto correspondiente y
  registra el resultado en la bitácora de actividad.

  Devuelve `{:ok, resultado}` o `{:error, razón}`; el resultado es un dato (no texto)
  que `Emergencias.CLI.Formatter` convierte en pantalla.
  """

  require Logger

  alias Emergencias.{
    Accounts,
    Family,
    Needs,
    Pets,
    Reports,
    Resources,
    Shelters,
    Validation,
    Zones
  }

  alias Emergencias.CLI.{Parser, Spec}

  @spec execute(Emergencias.Accounts.User.t(), String.t()) :: {:ok, term()} | {:error, term()}
  def execute(user, input) do
    with {:ok, command} <- Parser.parse(input) do
      result =
        with :ok <- Spec.authorize(user.role, command.name),
             {:ok, args} <- Spec.bind(command) do
          safe_run(command.name, args, user.username, user)
        end

      Accounts.log(
        user.username,
        command.name,
        command.raw,
        if(match?({:ok, _}, result), do: :ok, else: :error)
      )

      result
    end
  end

  # Un fallo inesperado se informa como error en lugar de tumbar al proceso que llama.
  defp safe_run(name, args, actor, user) do
    run(name, args, actor, user)
  rescue
    exception ->
      Logger.error(
        "Fallo inesperado en #{name}: " <> Exception.format(:error, exception, __STACKTRACE__)
      )

      {:error, {:internal_error, Exception.message(exception)}}
  end

  # --- Zonas ---------------------------------------------------------------------

  defp run(:register_zone, a, _actor, _user), do: Zones.register_zone(node_attrs(a))
  defp run(:register_sector, a, _actor, _user), do: Zones.add_sector(a.padre, node_attrs(a))
  defp run(:register_point, a, _actor, _user), do: Zones.add_point(a.padre, node_attrs(a))

  defp run(:zone_status, a, _actor, _user) do
    with {:ok, status} <- Reports.zone_status(a.zona), do: {:ok, {:zone_status, status}}
  end

  # --- Necesidades -----------------------------------------------------------------

  defp run(:register_need, a, actor, _user) do
    Needs.register(
      %{
        type: a.tipo,
        quantity: a.cantidad,
        priority: a.prioridad,
        zone: a.zona,
        description: a.descripcion,
        shelter: a.albergue,
        person: a.persona
      },
      actor
    )
  end

  defp run(:list_needs, a, _actor, _user),
    do:
      Needs.list(
        zone: a.zona,
        type: a.tipo,
        priority: a.prioridad,
        status: a.estado,
        shelter: a.albergue
      )

  defp run(:pending_needs, a, _actor, _user), do: Needs.pending(zone: a.zona)
  defp run(:update_need, a, actor, _user), do: Needs.update_status(a.id, a.estado, actor)

  defp run(:assign_resource, a, actor, _user),
    do: Needs.assign_resource(a.id, a.categoria, a.cantidad, actor)

  # --- Recursos --------------------------------------------------------------------

  defp run(:register_resource, a, actor, user) do
    Resources.register(
      %{
        code: a.codigo,
        category: a.categoria,
        quantity: a.cantidad,
        unit: a.unidad,
        location: a.ubicacion,
        zone: a.zona || user.zone,
        name: a.nombre
      },
      actor
    )
  end

  defp run(:resource_in, a, actor, _user),
    do: Resources.add_stock(a.codigo, a.ubicacion, a.cantidad, actor)

  defp run(:resource_out, a, actor, _user),
    do: Resources.remove_stock(a.codigo, a.ubicacion, a.cantidad, actor)

  defp run(:transfer_resource, a, actor, _user),
    do: Resources.transfer(a.codigo, a.origen, a.destino, a.cantidad, a.zona, actor)

  defp run(:list_resources, a, _actor, _user),
    do:
      {:ok,
       Resources.list(category: a.categoria, zone: a.zona, location: a.ubicacion, code: a.codigo)}

  defp run(:critical_resources, _a, _actor, _user),
    do: {:ok, {:critical, Reports.critical_resources()}}

  # --- Familiares ------------------------------------------------------------------

  defp run(:report_person, a, actor, _user),
    do:
      Family.report_person(
        %{document: a.documento, name: a.nombre, zone: a.zona, status: a.estado, age: a.edad},
        actor
      )

  defp run(:update_person, a, actor, _user),
    do: Family.update_person(a.documento, %{status: a.estado, zone: a.zona}, actor)

  defp run(:find_person, a, _actor, _user),
    do: Family.find(document: a.documento, name: a.nombre, zone: a.zona, status: a.estado)

  defp run(:send_family_message, a, actor, _user),
    do: Family.send_message(a.documento, a.mensaje, actor)

  defp run(:list_family_messages, a, _actor, _user), do: Family.messages(a.documento, a.estado)
  defp run(:mark_message, a, _actor, _user), do: Family.mark_message(a.id, a.estado)

  # --- Mascotas --------------------------------------------------------------------

  defp run(:report_pet, a, actor, _user) do
    Pets.report(
      %{
        kind: a.tipo,
        species: a.especie,
        name: a.nombre,
        color: a.color,
        size: a.tamano,
        zone: a.zona,
        contact: a.contacto,
        traits: a.caracteristicas
      },
      actor
    )
  end

  defp run(:list_pets, a, _actor, _user),
    do: Pets.list(species: a.especie, zone: a.zona, status: a.estado, kind: a.tipo)

  defp run(:match_pets, _a, _actor, _user) do
    with {:ok, matches} <- Pets.match(), do: {:ok, {:matches, matches}}
  end

  defp run(:confirm_pet_match, a, actor, _user) do
    with {:ok, match} <- Pets.confirm(a.perdida, a.encontrada, actor),
         do: {:ok, {:confirmed, match}}
  end

  # --- Albergues -------------------------------------------------------------------

  defp run(:register_shelter, a, _actor, _user),
    do: Shelters.register(%{code: a.codigo, name: a.nombre, zone: a.zona, capacity: a.capacidad})

  defp run(:check_shelter, a, _actor, _user) do
    with {:ok, status} <- Reports.shelter_status(a.codigo), do: {:ok, {:shelter_status, status}}
  end

  defp run(:register_entry, a, _actor, _user), do: Shelters.enter(a.codigo, a.documento)
  defp run(:register_exit, a, _actor, _user), do: Shelters.leave(a.codigo, a.documento)

  defp run(:shelter_report, a, _actor, _user) do
    with {:ok, n} <- limit(a.limite, 5), do: {:ok, Shelters.top_occupancy(n)}
  end

  # --- Resumen ---------------------------------------------------------------------

  defp run(:summary, _a, _actor, _user), do: {:ok, {:summary, Reports.summary()}}

  defp node_attrs(a), do: %{code: a.codigo, name: a.nombre, level: a.nivel, affected: a.afectadas}

  defp limit(nil, default), do: {:ok, default}
  defp limit(value, _default), do: Validation.positive_integer(value, :limit)
end
