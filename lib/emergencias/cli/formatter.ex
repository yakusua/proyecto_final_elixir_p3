defmodule Emergencias.CLI.Formatter do
  @moduledoc """
  Convierte los resultados de `Emergencias.CLI.Commands` (datos) en texto para la
  terminal y traduce los errores del dominio a mensajes en español. Una estructura
  o lista de estructuras se muestra como tabla; los resultados compuestos
  (`:zone_status`, `:summary`, ...) tienen su propio formato.
  """

  alias Emergencias.Needs.Need
  alias Emergencias.Shelters.Shelter
  alias Emergencias.Types

  @accents %{
    critico: "crítico",
    critica: "crítica",
    en_atencion: "en atención",
    sin_informacion: "sin información",
    pequeno: "pequeño",
    punto_atencion: "punto de atención"
  }

  @score_labels %{
    species: "especie",
    color: "color",
    zone: "zona",
    size: "tamaño",
    traits: "rasgos",
    name: "nombre"
  }

  @spec render({:ok, term()} | {:error, term()}) :: String.t()
  def render({:ok, value}), do: value |> text() |> IO.chardata_to_string()
  def render({:error, reason}), do: "✗ " <> error_message(reason)

  # --- Resultados --------------------------------------------------------------------

  defp text([]), do: "(sin resultados)"
  defp text([%module{} | _] = items), do: table(columns(module), items)
  defp text(%module{} = item), do: table(columns(module), [item])

  defp text({:critical, []}),
    do: "✓ Sin recursos críticos: el inventario cubre la demanda pendiente."

  defp text({:critical, rows}) do
    table(
      [
        {"Categoría", & &1.category},
        {"Disponible", & &1.available},
        {"Demanda pendiente", & &1.demand},
        {"Déficit", & &1.deficit}
      ],
      rows
    )
  end

  defp text({:matches, []}), do: "No hay coincidencias por encima del umbral."

  defp text({:matches, matches}) do
    Enum.map_join(matches, "\n", fn m ->
      "#{m.lost} ↔ #{m.found}: #{m.total}/100  " <>
        (m.breakdown
         |> Enum.sort()
         |> Enum.map_join(" · ", fn {k, v} -> "#{@score_labels[k]} #{v}" end))
    end)
  end

  defp text({:confirmed, match}),
    do:
      "✓ Coincidencia confirmada: #{match.lost} ↔ #{match.found} (puntaje #{match.score}). Ambos reportes quedaron resueltos."

  defp text({:shelter_status, %{shelter: s, needs: needs, resources: resources}}) do
    [
      "ALBERGUE #{s.code} — #{s.name} (zona #{s.zone}): capacidad #{s.capacity}, ocupación #{Shelter.occupancy(s)} (#{Shelter.occupancy_percent(s)}%), cupos disponibles #{Shelter.available(s)}\n",
      "Necesidades asociadas:\n",
      text(needs),
      "\nRecursos en el albergue:\n",
      text(resources)
    ]
  end

  defp text({:zone_status, s}) do
    [
      "ZONA #{s.node.code} — #{s.node.name} (nivel #{label(s.node.level)})\n",
      "  Afectados acumulados: #{s.affected} · nodos: #{s.nodes} (sectores #{s.sectors}, puntos #{s.points}) · profundidad: #{s.depth} · niveles: #{counts(s.by_level)}\n",
      "  Estructura:\n",
      Enum.map_join(s.tree, "\n", fn {depth, node, total} ->
        "    #{String.duplicate("  ", depth)}#{node.code} · #{node.name} [#{label(node.kind)}, #{label(node.level)}] directos #{node.affected} / acumulado #{total}"
      end),
      "\n  Necesidades: #{needs_line(s.needs)}\n",
      "  Recursos: #{totals(s.resources)}\n",
      "  Albergues: #{if s.shelters == [], do: "ninguno", else: Enum.map_join(s.shelters, ", ", &"#{&1.code} #{Shelter.occupancy(&1)}/#{&1.capacity}")}\n",
      "  Personas: #{counts(s.persons)}\n",
      "  Mascotas: #{counts(s.pets)}"
    ]
  end

  defp text({:summary, s}) do
    [
      "RESUMEN GLOBAL\n",
      "  Zonas: #{s.zones.count} · afectados estimados: #{s.zones.affected}\n",
      "  Necesidades: #{needs_line(s.needs)}\n",
      "  Recursos restantes: #{totals(s.resources)}\n",
      "  Personas: #{counts(s.persons)}\n",
      "  Mensajes familiares: #{s.messages.total} (#{s.messages.pending} pendientes)\n",
      "  Mascotas: #{counts(s.pets)}\n",
      "  Albergues: #{s.shelters.count} · ocupación #{s.shelters.occupancy}/#{s.shelters.capacity}"
    ]
  end

  defp needs_line(n),
    do:
      "total #{n.total} · pendientes #{n.pending} (#{n.pending_units} unidades) · por estado: #{counts(n.by_status)}"

  defp totals(map) when map == %{}, do: "ninguno"

  defp totals(map),
    do: map |> Enum.sort() |> Enum.map_join(", ", fn {category, qty} -> "#{category} #{qty}" end)

  defp counts(map) when map == %{}, do: "—"

  defp counts(map),
    do: map |> Enum.sort() |> Enum.map_join(", ", fn {key, n} -> "#{label(key)} #{n}" end)

  # --- Columnas de cada estructura ------------------------------------------------------

  defp columns(Need) do
    [
      {"ID", & &1.id},
      {"Prioridad", &label(&1.priority)},
      {"Tipo", &label(&1.type)},
      {"Cant.", & &1.quantity},
      {"Asig.", &Need.assigned/1},
      {"Zona", & &1.zone},
      {"Estado", &label(&1.status)},
      {"Descripción", & &1.description}
    ]
  end

  defp columns(Emergencias.Resources.Resource) do
    [
      {"Código", & &1.code},
      {"Nombre", & &1.name},
      {"Categoría", & &1.category},
      {"Cantidad", & &1.quantity},
      {"Unidad", & &1.unit},
      {"Ubicación", & &1.location},
      {"Zona", & &1.zone}
    ]
  end

  defp columns(Emergencias.Family.Person) do
    [
      {"ID", & &1.id},
      {"Documento", & &1.document},
      {"Nombre", & &1.name},
      {"Edad", &(&1.age || "—")},
      {"Zona", & &1.zone},
      {"Estado", &label(&1.status)},
      {"Historial",
       &(&1.history |> Enum.reverse() |> Enum.map_join(" > ", fn h -> label(h.to) end))}
    ]
  end

  defp columns(Emergencias.Family.Message) do
    [
      {"ID", & &1.id},
      {"De", & &1.from},
      {"Para", & &1.to},
      {"Estado", &label(&1.status)},
      {"Mensaje", & &1.content}
    ]
  end

  defp columns(Emergencias.Pets.Report) do
    [
      {"ID", & &1.id},
      {"Tipo", &label(&1.kind)},
      {"Especie", & &1.species},
      {"Nombre", &(&1.name || "—")},
      {"Color", & &1.color},
      {"Tamaño", &label(&1.size)},
      {"Zona", & &1.zone},
      {"Estado", &label(&1.status)},
      {"Contacto", & &1.contact}
    ]
  end

  defp columns(Shelter) do
    [
      {"Código", & &1.code},
      {"Nombre", & &1.name},
      {"Zona", & &1.zone},
      {"Capacidad", & &1.capacity},
      {"Ocupación", &Shelter.occupancy/1},
      {"Cupos", &Shelter.available/1},
      {"% ocup.", &Shelter.occupancy_percent/1}
    ]
  end

  defp columns(Emergencias.Zones.Node) do
    [
      {"Código", & &1.code},
      {"Nombre", & &1.name},
      {"Tipo", &label(&1.kind)},
      {"Nivel", &label(&1.level)},
      {"Afectados", & &1.affected}
    ]
  end

  defp table(columns, items) do
    headers = Enum.map(columns, &elem(&1, 0))
    rows = for item <- items, do: for({_header, fun} <- columns, do: to_string(fun.(item)))

    widths =
      Enum.zip_with([headers | rows], fn column ->
        column |> Enum.map(&String.length/1) |> Enum.max()
      end)

    line = fn cells ->
      cells
      |> Enum.zip(widths)
      |> Enum.map_join("  ", fn {cell, width} -> String.pad_trailing(cell, width) end)
      |> String.trim_trailing()
    end

    Enum.join(
      [
        line.(headers),
        Enum.map_join(widths, "  ", &String.duplicate("─", &1)) | Enum.map(rows, line)
      ],
      "\n"
    )
  end

  defp label(value) when is_atom(value),
    do: Map.get(@accents, value, value |> Atom.to_string() |> String.replace("_", " "))

  defp label(value), do: to_string(value)

  # --- Errores -----------------------------------------------------------------------------

  @spec error_message(term()) :: String.t()
  def error_message({:invalid_field, field, reason}),
    do: "El campo '#{field}' #{reason_text(reason)}."

  def error_message({:invalid_value, type, input}),
    do:
      "Valor '#{input}' no válido para #{type}. Opciones: #{type |> Types.values() |> Enum.map_join(", ", &label/1)}."

  def error_message({:not_found, entity, id}), do: "No existe #{entity} '#{id}'."
  def error_message({:duplicate, entity, id}), do: "Ya existe #{entity} '#{id}'."

  def error_message({:insufficient_stock, %{requested: requested, available: available}}),
    do: "Inventario insuficiente: se pidieron #{requested} y solo hay #{available} disponibles."

  def error_message({:invalid_transition, entity, from, to}),
    do: "Transición no válida de #{entity}: de '#{label(from)}' a '#{label(to)}'."

  def error_message({:need_not_assignable, status}),
    do:
      "La necesidad está '#{label(status)}' y ya no puede consumir recursos (solo las pendientes)."

  def error_message({:exceeds_need, remaining}),
    do: "La cantidad excede lo que le falta a la necesidad (faltan #{remaining})."

  def error_message({:category_mismatch, type, category}),
    do: "La necesidad es de tipo '#{label(type)}' y no admite la categoría '#{category}'."

  def error_message({:shelter_full, code}), do: "El albergue #{code} está lleno: no hay cupos."

  def error_message({:already_in_shelter, code}),
    do: "La persona ya se encuentra en el albergue #{code}."

  def error_message({:not_in_shelter, code}), do: "La persona no está en el albergue #{code}."

  def error_message({:already_resolved, id}),
    do: "El reporte #{id} ya está resuelto y no se puede cerrar de nuevo."

  def error_message({:wrong_kinds, a, b}),
    do: "Se necesita una mascota perdida y una encontrada (recibido: #{label(a)} y #{label(b)})."

  def error_message({:species_mismatch, a, b}), do: "Las especies no coinciden: #{a} y #{b}."

  def error_message({:invalid_child, parent, child}),
    do: "Un(a) #{label(parent)} no puede contener un(a) #{label(child)}."

  def error_message({:forbidden, action, role}),
    do: "Permiso denegado: '#{action}' requiere rol #{role} o superior."

  def error_message({:usage, usage}), do: "Uso: #{usage}"

  def error_message({:unknown_option, key, usage}),
    do: "Opción desconocida '#{key}'. Uso: #{usage}"

  def error_message({:unknown_command, word}), do: "Comando desconocido '#{word}'."

  def error_message({:persistence_failed, reason}),
    do: "No se pudo guardar en disco (#{inspect(reason)}); no se hizo ningún cambio."

  def error_message({:internal_error, message}), do: "Error interno: #{message}"
  def error_message(:invalid_credentials), do: "Usuario o contraseña incorrectos."

  def error_message(:not_connected),
    do: "No hay una sesión abierta. Usa: connect <usuario> <contraseña> [tipo] [zona]"

  def error_message(:unclosed_quote), do: "Faltan comillas de cierre."
  def error_message(:empty), do: "Comando vacío."
  def error_message(:same_location), do: "El origen y el destino no pueden ser el mismo."

  def error_message(:unavailable),
    do: "Un componente no responde en este momento; intenta de nuevo."

  def error_message(other), do: "Error: #{inspect(other)}"

  defp reason_text(:blank), do: "no puede estar vacío"

  defp reason_text(:bad_identifier),
    do: "solo admite letras, números, '_', '-' y '.' (máx. 40 caracteres)"

  defp reason_text(:bad_format),
    do: "debe tener 3 a 32 caracteres: letras, números, '_', '-' o '.'"

  defp reason_text(:too_short), do: "es demasiado corto (mínimo 4 caracteres)"
  defp reason_text(:not_a_number), do: "debe ser un número entero"
  defp reason_text(:must_be_positive), do: "debe ser mayor que cero"
  defp reason_text(:must_not_be_negative), do: "no puede ser negativo"
  defp reason_text(other), do: "no es válido (#{inspect(other)})"
end
