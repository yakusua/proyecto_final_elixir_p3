defmodule Mix.Tasks.Emergencias do
  @shortdoc "Abre la consola interactiva del sistema de emergencias"

  @moduledoc """
  Abre la consola: `mix emergencias`. Los datos se guardan en la carpeta `data/`.
  """

  use Mix.Task

  @impl Mix.Task
  def run(_args) do
    Mix.Task.run("app.start")
    Emergencias.CLI.REPL.run()
  end
end
