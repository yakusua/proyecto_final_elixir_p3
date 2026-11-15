defmodule Emergencias.Storage do
  @moduledoc """
  Persistencia en **archivos de texto plano**: cada archivo guarda un término de
  Elixir/Erlang en sintaxis legible (terminado en `.`) y se lee con
  `:file.consult/1`, que solo interpreta datos literales (no ejecuta código).

  La escritura es atómica (archivo temporal + renombrar) y un archivo ilegible se
  aparta como `*.corrupt` en lugar de sobrescribirse.
  """

  require Logger

  @spec data_dir() :: Path.t()
  def data_dir, do: Application.get_env(:emergencias, :data_dir, "data")

  @spec path(String.t()) :: Path.t()
  def path(name), do: Path.join(data_dir(), name <> ".txt")

  @doc "Guarda un término bajo el nombre dado (puede incluir subcarpetas: `\"shelters/A01\"`)."
  @spec save(String.t(), term()) :: :ok | {:error, term()}
  def save(name, term) do
    path = path(name)
    tmp = path <> ".tmp"
    content = IO.chardata_to_string(["%% coding: utf-8\n", :io_lib.format("~tp.~n", [term])])

    with :ok <- File.mkdir_p(Path.dirname(path)),
         :ok <- File.write(tmp, content),
         :ok <- File.rename(tmp, path) do
      :ok
    else
      {:error, reason} ->
        _ = File.rm(tmp)
        {:error, reason}
    end
  end

  @doc "Lee un término guardado o devuelve `default` (apartando archivos corruptos)."
  @spec load_or(String.t(), term()) :: term()
  def load_or(name, default) do
    case :file.consult(String.to_charlist(path(name))) do
      {:ok, [term | _]} ->
        term

      {:ok, []} ->
        default

      {:error, :enoent} ->
        default

      {:error, reason} ->
        Logger.error(
          "Archivo #{path(name)} ilegible (#{inspect(reason)}); se respalda como .corrupt"
        )

        _ = File.rename(path(name), path(name) <> ".corrupt")
        default
    end
  end

  @doc "Nombres (sin extensión) de los archivos de una subcarpeta."
  @spec list(String.t()) :: [String.t()]
  def list(dir) do
    case File.ls(Path.join(data_dir(), dir)) do
      {:ok, files} ->
        for f <- Enum.sort(files), String.ends_with?(f, ".txt"), do: Path.rootname(f)

      {:error, _} ->
        []
    end
  end

  @doc """
  Guarda `new_state` y arma la respuesta de un `handle_call`. Si la escritura
  falla se conserva el estado anterior y se responde `{:error, {:persistence_failed, _}}`,
  de modo que memoria y disco nunca divergen.
  """
  @spec commit(String.t(), state, state, term(), (state -> term())) :: {:reply, term(), state}
        when state: term()
  def commit(name, old_state, new_state, reply, encoder \\ & &1) do
    case save(name, encoder.(new_state)) do
      :ok ->
        {:reply, reply, new_state}

      {:error, reason} ->
        Logger.error("No se pudo guardar #{name}: #{inspect(reason)}")
        {:reply, {:error, {:persistence_failed, reason}}, old_state}
    end
  end
end
