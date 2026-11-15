defmodule Emergencias.Accounts.User do
  @moduledoc "Usuario del sistema. `salt` y `password_hash` nunca salen del contexto (ver `sanitize/1`)."

  @enforce_keys [:username, :role]
  defstruct [:username, :full_name, :role, :zone, :salt, :password_hash]

  @type t :: %__MODULE__{}

  @spec sanitize(t()) :: t()
  def sanitize(%__MODULE__{} = user), do: %{user | salt: nil, password_hash: nil}
end
