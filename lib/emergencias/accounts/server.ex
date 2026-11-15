defmodule Emergencias.Accounts.Server do
  @moduledoc """
  GenServer con los usuarios registrados, quiénes están conectados (solo en
  memoria: tras un reinicio nadie queda conectado) y la bitácora de actividad.
  """

  use Emergencias.Server, file: "users"

  alias Emergencias.{Clock, Storage}

  @activity_limit 1_000

  defmodule State do
    @moduledoc false
    defstruct users: %{}, connected: [], activity: []
  end

  defp initial_state, do: %State{}

  def after_load(state), do: Map.put(state, :connected, [])

  def fetch(username), do: call({:fetch, username})
  def insert(user), do: call({:insert, user})
  def connect(username), do: call({:connect, username})
  def disconnect(username), do: call({:disconnect, username})
  def session(username), do: call({:session, username})
  def log(entry), do: GenServer.cast(__MODULE__, {:log, entry})

  @impl true
  def handle_call({:fetch, username}, _from, state),
    do: {:reply, Map.fetch(state.users, username), state}

  def handle_call({:insert, user}, _from, state) do
    if Map.has_key?(state.users, user.username) do
      {:reply, {:error, {:duplicate, :user, user.username}}, state}
    else
      new_state = %{state | users: Map.put(state.users, user.username, user)}
      Storage.commit(@file_name, state, new_state, {:ok, user})
    end
  end

  def handle_call({:connect, username}, _from, state) do
    {:reply, :ok, %{state | connected: Enum.uniq([username | state.connected])}}
  end

  def handle_call({:disconnect, username}, _from, state) do
    if username in state.connected,
      do: {:reply, :ok, %{state | connected: List.delete(state.connected, username)}},
      else: {:reply, {:error, :not_connected}, state}
  end

  def handle_call({:session, username}, _from, state) do
    user = if username in state.connected, do: Map.get(state.users, username)
    {:reply, if(user, do: {:ok, user}, else: :error), state}
  end

  @impl true
  def handle_cast({:log, entry}, state) do
    entry = Map.put(entry, :at, Clock.now())
    new_state = %{state | activity: Enum.take([entry | state.activity], @activity_limit)}
    _ = Storage.save(@file_name, new_state)
    {:noreply, new_state}
  end
end
