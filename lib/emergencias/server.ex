defmodule Emergencias.Server do
  @moduledoc """
  Base común de los GenServer del dominio. Con `use Emergencias.Server, file: "x"`
  el módulo recibe `start_link/1` (registrado con su propio nombre), `init/1`
  (carga el estado desde `data/x.txt`) y `call/1`.

  El módulo que lo usa debe definir `initial_state/0` y puede redefinir
  `after_load/1` para ajustar el estado recién leído del disco.
  """

  defmacro __using__(opts) do
    file = Keyword.fetch!(opts, :file)

    quote do
      use GenServer

      @file_name unquote(file)

      def start_link(_opts \\ []), do: GenServer.start_link(__MODULE__, :ok, name: __MODULE__)

      @impl true
      def init(:ok),
        do: {:ok, after_load(Emergencias.Storage.load_or(@file_name, initial_state()))}

      def after_load(state), do: state
      defoverridable after_load: 1

      defp call(message), do: GenServer.call(__MODULE__, message, 10_000)
    end
  end

  @doc "Ejecuta una llamada a otro proceso y convierte su caída en `{:error, :unavailable}`."
  @spec safe((-> result)) :: result | {:error, :unavailable} when result: term()
  def safe(fun) do
    fun.()
  catch
    :exit, _ -> {:error, :unavailable}
  end
end
