# Documentación del proyecto

Este documento describe la arquitectura y los structs definidos en `lib/`. Los campos con valores por defecto se indican entre paréntesis.

## Arquitectura

### Arquitectura de módulos

```text
mix emergencias
  |
  v
Mix.Tasks.Emergencias
  +-> app.start -> Emergencias.Application -> Emergencias.Supervisor
  |
  v
Emergencias.CLI.REPL
  +-> Emergencias -> Accounts.session
  |                    |
  |                    v
  |              CLI.Commands
  |               +-> CLI.Parser
  |               +-> CLI.Spec
  |               +-> Accounts
  |               +-> Zones
  |               +-> Needs
  |               +-> Resources
  |               +-> Family
  |               +-> Pets
  |               +-> Shelters
  |               +-> Reports
  |
  +-> CLI.Formatter -> salida en consola
```

Los módulos de cada contexto se organizan así:

```text
Accounts  -> Accounts.Server, Accounts.User
Zones     -> Zones.Server -> Zones.Tree -> Zones.Node
Needs     -> Needs.Server -> Needs.Need
Resources -> Resources.Server -> Resources.Inventory -> Resources.Resource
Family    -> Family.Server -> Family.Person, Family.Message
Pets      -> Pets.Server -> Pets.Report -> Pets.Matcher
Shelters  -> Shelters.Supervisor -> Shelters.Server -> Shelters.Shelter
```

Dependencias transversales entre módulos:

```text
CLI.Commands -> los módulos de contexto
CLI.Commands -> Reports -> Zones, Needs, Resources, Family, Pets, Shelters
Needs.Server -> Resources.Server
GenServers de contexto -> Emergencias.Server -> Emergencias.Storage -> data/*.txt
Shelters.Server -------------------------------> Emergencias.Storage
```

`Emergencias.Server` proporciona funciones comunes para los GenServer persistentes. `Shelters.Server` gestiona un proceso por albergue y usa `Storage` directamente. `Types`, `Validation`, `Text`, `Filter` y `Clock` son módulos compartidos por las reglas y contextos que los necesitan.

### Flujo de una operación

```text
Usuario
  |
  v
CLI.REPL -> Emergencias -> Accounts.session
                |
                v
         CLI.Commands -> Parser / Spec
                |
                +-> Accounts
                +-> Zones
                +-> Needs
                +-> Resources
                +-> Family
                +-> Pets
                +-> Shelters
                +-> Reports -> consulta y combina varios contextos
                |
                v
       Servidores del dominio (GenServer)
                |
                +-> módulos de reglas puras (validación y transformación)
                |
                v
       Storage -> archivos data/*.txt
```

Los comandos atraviesan la interfaz de consola, se interpretan y autorizan, y se ejecutan en el contexto correspondiente. Los contextos usan sus GenServer para gestionar estado; las reglas de dominio se mantienen en módulos puros. Los servidores persisten sus cambios mediante `Storage`.

### Supervisión y procesos

```text
Emergencias.Supervisor (one_for_one)
  |
  +-> Accounts.Server
  +-> Zones.Server
  +-> Resources.Server
  +-> Needs.Server
  +-> Family.Server
  +-> Pets.Server
  +-> Shelters.Supervisor (rest_for_one)
        |
        +-> Registry
        +-> DynamicSupervisor -> un proceso por albergue
        +-> tarea de restauración de albergues desde disco
```

Cada servidor principal se reinicia de forma independiente. El supervisor de albergues reinicia sus procesos dependientes en orden y vuelve a restaurar los albergues cuando corresponde.

### Dependencia entre necesidades e inventario

```text
Needs.Server -> valida y asigna una necesidad
      |
      v
Resources.Server -> descuenta y persiste el inventario
      |
      v
Needs.Server -> guarda la asignación y confirma el resultado
```

Las llamadas a cada GenServer se procesan secuencialmente. Si guardar la necesidad falla después de asignar recursos, el sistema los devuelve al inventario.

### Reportes agregados

```text
CLI.Commands -> Reports
                 |
                 +-> Zones
                 +-> Needs
                 +-> Resources
                 +-> Family
                 +-> Pets
                 +-> Shelters
```

`Reports` reúne datos de varios contextos para producir resúmenes globales y estados por zona o albergue; no reemplaza a los servidores que mantienen esos datos.

## Structs

- `Emergencias.Accounts.User`: username, full_name, role, zone, salt, password_hash. Datos de una cuenta de usuario.
- `Emergencias.Accounts.Server.State`: users (por defecto: `%{}`), connected (por defecto: `[]`), activity (por defecto: `[]`). Estado de usuarios, conexiones y actividad.
- `Emergencias.Family.Message`: id, from, to, content, status, at, delivered_at. Mensaje dirigido a una persona o familia.
- `Emergencias.Family.Person`: id, document, name, age, zone, status, reported_by, created_at, history (por defecto: `[]`). Persona afectada y su historial de cambios.
- `Emergencias.Family.Server.State`: persons (por defecto: `%{}`), messages (por defecto: `%{}`), next_person (por defecto: `1`), next_message (por defecto: `1`). Estado de personas, mensajes y secuencias.
- `Emergencias.Needs.Need`: id, seq, type, description, quantity, zone, priority, reporter, shelter, person, created_at, status (por defecto: `:pendiente`), assignments (por defecto: `[]`), history (por defecto: `[]`). Necesidad reportada, asignaciones y cambios de estado.
- `Emergencias.Needs.Server.State`: needs (por defecto: `%{}`), next_seq (por defecto: `1`). Estado de las necesidades registradas.
- `Emergencias.Pets.Report`: id, seq, kind, species, name, color, size, traits, zone, contact, reporter, matched_with, created_at, status (por defecto: `:activa`). Reporte de una mascota perdida o encontrada.
- `Emergencias.Pets.Server.State`: reports (por defecto: `%{}`), matches (por defecto: `[]`), next_seq (por defecto: `1`). Estado de reportes y coincidencias de mascotas.
- `Emergencias.Resources.Inventory`: stocks (por defecto: `%{}`), movements (por defecto: `[]`), next_movement (por defecto: `1`). Existencias de recursos y su historial de movimientos.
- `Emergencias.Resources.Resource`: code, name, category, unit, location, zone, quantity (por defecto: `0`). Recurso y cantidad disponible en una ubicación.
- `Emergencias.Shelters.Shelter`: code, name, zone, capacity, occupants (por defecto: `MapSet.new()`). Albergue, capacidad y personas alojadas.
- `Emergencias.Zones.Node`: code, name, kind, level, affected (por defecto: `0`), children (por defecto: `[]`). Nodo de la jerarquía de zonas y sectores.
