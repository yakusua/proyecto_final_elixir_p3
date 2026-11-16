# Emergencias

Aplicación de consola para coordinar zonas, necesidades, recursos, personas, mascotas y albergues durante una emergencia. Está implementada en Elixir y usa archivos de texto en `data/` para persistir la información.

## Requisitos

- Elixir `~> 1.14` y Erlang/OTP.
- Ejecutar los comandos desde la carpeta del proyecto, donde está `mix.exs`.

## Comandos de Mix

| Comando | Qué hace |
| --- | --- |
| `mix --version` | Muestra las versiones instaladas de Mix, Elixir y Erlang/OTP. |
| `mix help` | Muestra las tareas Mix disponibles en el entorno. |
| `mix help emergencias` | Muestra la ayuda de la tarea de esta aplicación. |
| `mix deps.get` | Descarga las dependencias declaradas. Actualmente el proyecto no declara dependencias externas, por lo que no hay paquetes que descargar. |
| `mix compile` | Compila la aplicación. |
| `mix test` | Ejecuta todas las pruebas. |
| `mix test test/emergencias/core_test.exs` | Ejecuta solo el archivo de pruebas indicado; se puede reemplazar por cualquier archivo dentro de `test/`. |
| `mix format` | Formatea los archivos Elixir incluidos en `.formatter.exs`. |
| `mix format --check-formatted` | Comprueba el formato sin modificar archivos. |
| `mix clean` | Elimina los archivos compilados; no borra los datos persistidos en `data/`. |
| `mix run -e "IO.puts(:ok)"` | Arranca la aplicación, ejecuta la expresión Elixir y termina. Se puede sustituir la expresión por otra. |
| `iex -S mix` | Inicia IEx (la consola interactiva de Elixir) con la aplicación cargada. Consulta los ejemplos de la sección [Usar desde IEx](#usar-desde-iex). |
| `mix emergencias` | Inicia la consola interactiva de gestión de emergencias. Es la forma habitual de usar la aplicación. |

La aplicación no define alias Mix adicionales. Para consultar las tareas incorporadas por Mix y sus opciones, usa `mix help` y `mix help <tarea>`.

### Windows y PowerShell

Si PowerShell bloquea la ejecución del script de Mix, puedes usar `mix.bat` en lugar de `mix`. Si prefieres permitir scripts locales para tu usuario, consulta primero la política actual con `Get-ExecutionPolicy -List`; el cambio limitado al usuario actual es `Set-ExecutionPolicy -Scope CurrentUser RemoteSigned`.

## Consola de emergencias

Inicia la consola con:

```shell
mix emergencias
```

Al comenzar aparece el prompt `emergencias>`. Primero inicia sesión con `connect`; una cuenta nueva se registra automáticamente. Si no se especifica un tipo, se crea como `ciudadano`. Una cuenta existente debe autenticarse con su contraseña y conserva el tipo y la zona con los que fue creada.

```text
connect <usuario> <contraseña> [tipo] [zona] [nombre="Nombre completo"]
```

Tipos disponibles, de menor a mayor permiso: `ciudadano`, `voluntario`, `coordinador` y `administrador`. Los permisos son jerárquicos: cada tipo puede ejecutar comandos que requieran su mismo tipo o uno inferior. Los comandos de consulta suelen requerir `ciudadano`; las operaciones de voluntariado, `voluntario`; las operaciones de coordinación, `coordinador`.

Controles propios de la consola:

| Comando | Qué hace |
| --- | --- |
| `connect <usuario> <contraseña> [tipo] [zona] [nombre="Nombre completo"]` | Registra y conecta una cuenta nueva, o inicia sesión en una cuenta existente. El campo `nombre` es opcional y solo se usa al crear la cuenta. |
| `disconnect` | Cierra la sesión actual y vuelve al prompt `emergencias>`. |
| `quit` o `exit` | Cierra la sesión actual, si existe, y sale de la consola. |

Los argumentos con espacios deben ir entre comillas simples o dobles. Las opciones se escriben como `clave=valor`; el valor también puede ir entre comillas, por ejemplo `zona="zona centro"`. En los comandos con texto libre al final, las palabras restantes se juntan en ese último argumento. Los nombres de comandos no distinguen mayúsculas de minúsculas.

## Comandos disponibles en la consola

`<...>` indica un argumento obligatorio; `[...]`, uno opcional. Las opciones se pueden indicar como `clave=valor`. El rol mostrado es el mínimo requerido.

### Zonas

| Comando | Rol mínimo | Qué hace |
| --- | --- | --- |
| `register_zone <codigo> <nombre> <nivel> [afectadas=...]` | coordinador | Registra una zona raíz y, opcionalmente, el número de personas afectadas. |
| `register_sector <padre> <codigo> <nombre> <nivel> [afectadas=...]` | coordinador | Añade un sector dentro de la zona o nodo indicado por `padre`. |
| `register_point <padre> <codigo> <nombre> <nivel> [afectadas=...]` | coordinador | Añade un punto de atención bajo el nodo indicado por `padre`. |
| `zone_status <zona>` | ciudadano | Muestra el estado y el resumen del árbol de una zona. |

### Necesidades

| Comando | Rol mínimo | Qué hace |
| --- | --- | --- |
| `register_need <tipo> <cantidad> <prioridad> <zona> <descripcion> [albergue=...] [persona=...]` | ciudadano | Registra una necesidad. La descripción puede contener espacios. |
| `list_needs [zona=...] [tipo=...] [prioridad=...] [estado=...] [albergue=...]` | ciudadano | Lista necesidades, opcionalmente filtradas por zona, tipo, prioridad, estado o albergue. |
| `pending_needs [zona=...]` | voluntario | Lista necesidades pendientes, opcionalmente filtradas por zona. |
| `update_need <id> <estado>` | voluntario | Cambia el estado de una necesidad. |
| `assign_resource <id> <categoria> <cantidad>` | coordinador | Asigna existencias de una categoría de recursos a una necesidad. |

### Recursos

| Comando | Rol mínimo | Qué hace |
| --- | --- | --- |
| `register_resource <codigo> <categoria> <cantidad> <unidad> <ubicacion> [zona=...] [nombre=...]` | voluntario | Registra un recurso en el inventario. Si se omite `zona`, se usa la zona asociada a la cuenta. |
| `resource_in <codigo> <ubicacion> <cantidad>` | voluntario | Suma existencias de un recurso en una ubicación. |
| `resource_out <codigo> <ubicacion> <cantidad>` | coordinador | Retira existencias de un recurso de una ubicación. |
| `transfer_resource <codigo> <origen> <destino> <cantidad> [zona=...]` | coordinador | Transfiere existencias entre ubicaciones. |
| `list_resources [categoria=...] [zona=...] [ubicacion=...] [codigo=...]` | ciudadano | Consulta recursos, opcionalmente filtrados. |
| `critical_resources` | voluntario | Muestra las categorías de recursos con déficit frente a las necesidades pendientes. |

### Personas y mensajes familiares

| Comando | Rol mínimo | Qué hace |
| --- | --- | --- |
| `report_person <documento> <nombre> <zona> <estado> [edad=...]` | ciudadano | Registra una persona afectada. |
| `update_person <documento> [estado] [zona=...]` | voluntario | Actualiza el estado o la zona de una persona. |
| `find_person [documento] [nombre=...] [zona=...] [estado=...]` | ciudadano | Busca personas con los filtros indicados. |
| `send_family_message <documento> <mensaje>` | ciudadano | Envía un mensaje asociado al reporte de una persona. El mensaje admite espacios. |
| `list_family_messages <documento> [estado=...]` | ciudadano | Lista los mensajes familiares de una persona, opcionalmente por estado. |
| `mark_message <id> <estado>` | voluntario | Cambia el estado de un mensaje familiar. |

### Mascotas

| Comando | Rol mínimo | Qué hace |
| --- | --- | --- |
| `report_pet <tipo> <especie> <nombre> <color> <tamano> <zona> <contacto> [caracteristicas=...]` | ciudadano | Registra una mascota perdida o encontrada. `nombre` puede ser `-` si no se conoce; `caracteristicas` admite espacios. |
| `list_pets [especie=...] [zona=...] [estado=...] [tipo=...]` | ciudadano | Lista reportes de mascotas, opcionalmente filtrados. |
| `match_pets` | voluntario | Busca posibles coincidencias entre mascotas perdidas y encontradas. |
| `confirm_pet_match <perdida> <encontrada>` | coordinador | Confirma la coincidencia entre los identificadores de dos reportes. |

### Albergues y resumen

| Comando | Rol mínimo | Qué hace |
| --- | --- | --- |
| `register_shelter <codigo> <nombre> <zona> <capacidad>` | coordinador | Registra un albergue con su capacidad. |
| `check_shelter <codigo>` | ciudadano | Muestra ocupación, cupos, necesidades y recursos asociados al albergue. |
| `register_entry <codigo> <documento>` | voluntario | Registra la entrada de una persona al albergue. |
| `register_exit <codigo> <documento>` | voluntario | Registra la salida de una persona del albergue. |
| `shelter_report [limite=...]` | voluntario | Muestra los albergues con mayor ocupación; el límite predeterminado es 5. |
| `summary` | coordinador | Muestra un resumen global de zonas, necesidades, recursos, personas, mensajes, mascotas y albergues. |

### Valores aceptados

- **Nivel de zona:** `critico`, `alto`, `medio`, `bajo`.
- **Tipo de necesidad:** `agua`, `alimentos`, `medicamentos`, `primeros_auxilios`, `refugio`, `transporte`, `rescate`, `otra`.
- **Prioridad:** `critica`, `alta`, `media`, `baja`.
- **Estado de necesidad:** `pendiente`, `asignada`, `en_atencion`, `atendida`, `cancelada`.
- **Estado de persona:** `sin_informacion`, `reportada`, `localizada`, `trasladada`, `en_albergue`, `reunificada`.
- **Estado de mensaje:** `pendiente`, `entregado`.
- **Tipo de reporte de mascota:** `perdida`, `encontrada`.
- **Estado de mascota:** `activa`, `posible_coincidencia`, `resuelta`.
- **Tamaño de mascota:** `grande`, `mediano`, `pequeno`.

Los valores se aceptan sin distinguir mayúsculas y minúsculas; se admiten las formas con acento cuando corresponda (por ejemplo, `crítica`). Si un comando requiere una categoría de recurso, esta debe corresponder al tipo de necesidad que se atenderá.

## Ejemplos de sesión

```text
mix emergencias
emergencias> connect laura 1234 coordinador centro nombre="Laura Gómez"
laura> register_zone centro "Centro" critico afectadas=25
laura> register_sector centro s1 "Sector 1" alto
laura> zone_status centro
laura> summary
laura> disconnect
emergencias> quit
```

Los datos que la aplicación genere se guardan bajo `data/` en la carpeta desde la que se inicia Mix. No ejecutes `mix clean` esperando borrar estos datos: esa tarea solo limpia archivos de compilación.

## Usar desde IEx

También se puede cargar la aplicación en la consola estándar de Elixir:

```shell
iex -S mix
```

Desde IEx se pueden llamar las funciones públicas de entrada de la aplicación:

```elixir
{:ok, _usuario, _estado} =
  Emergencias.connect("laura", "1234", %{role: "coordinador", zone: "centro"})

Emergencias.execute("laura", ~s(register_zone centro "Centro" critico))
Emergencias.disconnect("laura")
```

Para salir de IEx, usa `Ctrl+C` dos veces o `System.stop()`. Para consultar ayuda de Elixir desde IEx, usa `h()` o `h Nombre.del.modulo`.
