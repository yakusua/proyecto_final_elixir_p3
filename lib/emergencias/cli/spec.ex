defmodule Emergencias.CLI.Spec do
  @moduledoc """
  Tabla de comandos: rol mínimo requerido, argumentos obligatorios, opcionales y
  opciones `clave=valor`. De aquí salen el análisis de argumentos, la autorización
  por tipo de usuario y el mensaje de uso. Los nombres son los sugeridos en el enunciado;
  `connect`, `disconnect` y `quit` los maneja la consola (`Emergencias.CLI.REPL`).
  """

  alias Emergencias.Types

  # nombre: {rol mínimo, [argumentos], [argumentos opcionales], [opciones]}
  @commands %{
    # Zonas
    register_zone: {:coordinador, [:codigo, :nombre, :nivel], [], [:afectadas]},
    register_sector: {:coordinador, [:padre, :codigo, :nombre, :nivel], [], [:afectadas]},
    register_point: {:coordinador, [:padre, :codigo, :nombre, :nivel], [], [:afectadas]},
    zone_status: {:ciudadano, [:zona], [], []},
    # Necesidades
    register_need:
      {:ciudadano, [:tipo, :cantidad, :prioridad, :zona, :descripcion], [], [:albergue, :persona]},
    list_needs: {:ciudadano, [], [], [:zona, :tipo, :prioridad, :estado, :albergue]},
    pending_needs: {:voluntario, [], [], [:zona]},
    update_need: {:voluntario, [:id, :estado], [], []},
    assign_resource: {:coordinador, [:id, :categoria, :cantidad], [], []},
    # Recursos
    register_resource:
      {:voluntario, [:codigo, :categoria, :cantidad, :unidad, :ubicacion], [], [:zona, :nombre]},
    resource_in: {:voluntario, [:codigo, :ubicacion, :cantidad], [], []},
    resource_out: {:coordinador, [:codigo, :ubicacion, :cantidad], [], []},
    transfer_resource: {:coordinador, [:codigo, :origen, :destino, :cantidad], [], [:zona]},
    list_resources: {:ciudadano, [], [], [:categoria, :zona, :ubicacion, :codigo]},
    critical_resources: {:voluntario, [], [], []},
    # Familiares
    report_person: {:ciudadano, [:documento, :nombre, :zona, :estado], [], [:edad]},
    update_person: {:voluntario, [:documento], [:estado], [:zona]},
    find_person: {:ciudadano, [], [:documento], [:nombre, :zona, :estado]},
    send_family_message: {:ciudadano, [:documento, :mensaje], [], []},
    list_family_messages: {:ciudadano, [:documento], [], [:estado]},
    mark_message: {:voluntario, [:id, :estado], [], []},
    # Mascotas
    report_pet:
      {:ciudadano, [:tipo, :especie, :nombre, :color, :tamano, :zona, :contacto], [],
       [:caracteristicas]},
    list_pets: {:ciudadano, [], [], [:especie, :zona, :estado, :tipo]},
    match_pets: {:voluntario, [], [], []},
    confirm_pet_match: {:coordinador, [:perdida, :encontrada], [], []},
    # Albergues
    register_shelter: {:coordinador, [:codigo, :nombre, :zona, :capacidad], [], []},
    check_shelter: {:ciudadano, [:codigo], [], []},
    register_entry: {:voluntario, [:codigo, :documento], [], []},
    register_exit: {:voluntario, [:codigo, :documento], [], []},
    shelter_report: {:voluntario, [], [], [:limite]},
    # Resumen global
    summary: {:coordinador, [], [], []}
  }

  # En estos comandos el último argumento es texto libre: lo que sobre se une a él.
  @join_rest [:register_need, :send_family_message, :report_pet]

  @lookup Map.new(@commands, fn {name, _} -> {Atom.to_string(name), name} end)

  @doc "Busca un comando por su nombre escrito."
  @spec lookup(String.t()) :: {:ok, atom()} | :error
  def lookup(word), do: Map.fetch(@lookup, String.downcase(word))

  # Texto de uso: `register_need <tipo> <cantidad> ... [documento] [zona=...]`.
  defp usage(name) do
    {_role, args, optional, opts} = Map.fetch!(@commands, name)

    ([Atom.to_string(name)] ++
       Enum.map(args, &"<#{&1}>") ++
       Enum.map(optional, &"[#{&1}]") ++ Enum.map(opts, &"[#{&1}=...]"))
    |> Enum.join(" ")
  end

  @doc "¿Puede el rol ejecutar el comando? (jerarquía ciudadano < voluntario < coordinador < administrador)"
  @spec authorize(atom(), atom()) :: :ok | {:error, term()}
  def authorize(role, name) do
    required = @commands |> Map.fetch!(name) |> elem(0)

    if Types.rank(:role, role) >= Types.rank(:role, required),
      do: :ok,
      else: {:error, {:forbidden, name, required}}
  end

  @doc "Asocia los argumentos con sus nombres y devuelve `%{nombre => texto | nil}`."
  @spec bind(map()) :: {:ok, map()} | {:error, term()}
  def bind(%{name: name, args: args, opts: opts}) do
    {_role, required, optional, option_names} = Map.fetch!(@commands, name)
    names = required ++ optional
    args = if name in @join_rest, do: join_rest(args, length(names)), else: args
    unknown = Map.keys(opts) -- Enum.map(option_names, &Atom.to_string/1)

    cond do
      length(args) < length(required) or length(args) > length(names) ->
        {:error, {:usage, usage(name)}}

      unknown != [] ->
        {:error, {:unknown_option, hd(unknown), usage(name)}}

      true ->
        {:ok,
         Map.new(names, &{&1, nil})
         |> Map.merge(Map.new(Enum.zip(names, args)))
         |> Map.merge(Map.new(option_names, &{&1, opts[Atom.to_string(&1)]}))}
    end
  end

  defp join_rest(args, max) when length(args) > max do
    {head, tail} = Enum.split(args, max - 1)
    head ++ [Enum.join(tail, " ")]
  end

  defp join_rest(args, _max), do: args
end
