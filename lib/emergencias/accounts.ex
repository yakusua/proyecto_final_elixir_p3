defmodule Emergencias.Accounts do
  @moduledoc """
  Contexto de usuarios. Regla de conexión: si el usuario **no existe se registra
  automáticamente** con el tipo y la zona indicados; si existe se valida la contraseña.
  """

  alias Emergencias.{Types, Validation}
  alias Emergencias.Accounts.{Server, User}

  @iterations 10_000

  @doc "Conecta al usuario (registrándolo si es nuevo). `attrs`: `:role`, `:zone`, `:full_name`."
  @spec connect(String.t(), String.t(), map()) ::
          {:ok, User.t(), :registered | :authenticated} | {:error, term()}
  def connect(username, password, attrs \\ %{}) do
    with {:ok, username} <- Validation.username(username),
         {:ok, password} <- Validation.password(password),
         {:ok, user, status} <- authenticate_or_register(username, password, attrs) do
      :ok = Server.connect(username)
      log(username, :connect, to_string(status), :ok)
      {:ok, User.sanitize(user), status}
    end
  end

  @spec disconnect(String.t()) :: :ok | {:error, :not_connected}
  def disconnect(username) do
    with :ok <- Server.disconnect(username), do: log(username, :disconnect, "", :ok)
  end

  @doc "Usuario con sesión abierta (el que ejecuta comandos)."
  @spec session(String.t()) :: {:ok, User.t()} | :error
  def session(username) when is_binary(username) do
    with {:ok, user} <- Server.session(String.downcase(String.trim(username))),
         do: {:ok, User.sanitize(user)}
  end

  @doc "Registra una acción en la bitácora de actividad (asíncrono)."
  @spec log(String.t(), atom(), String.t(), :ok | :error) :: :ok
  def log(username, action, detail, outcome),
    do: Server.log(%{user: username, action: action, detail: detail, outcome: outcome})

  defp authenticate_or_register(username, password, attrs) do
    case Server.fetch(username) do
      {:ok, user} -> authenticate(user, password)
      :error -> register(username, password, attrs)
    end
  end

  defp authenticate(user, password) do
    if :crypto.hash_equals(hash(password, user.salt), user.password_hash),
      do: {:ok, user, :authenticated},
      else: {:error, :invalid_credentials}
  end

  defp register(username, password, attrs) do
    with {:ok, role} <- Types.parse(:role, attrs[:role] || :ciudadano),
         {:ok, zone} <- Validation.optional(attrs[:zone], &Validation.code(&1, :zone)),
         {:ok, full_name} <- Validation.text(attrs[:full_name] || username, :full_name) do
      salt = :crypto.strong_rand_bytes(16)

      user = %User{
        username: username,
        full_name: full_name,
        role: role,
        zone: zone,
        salt: salt,
        password_hash: hash(password, salt)
      }

      case Server.insert(user) do
        {:ok, user} -> {:ok, user, :registered}
        # Otro proceso lo registró al mismo tiempo: se trata como usuario existente.
        {:error, {:duplicate, :user, _}} -> authenticate_or_register(username, password, attrs)
        error -> error
      end
    end
  end

  defp hash(password, salt), do: :crypto.pbkdf2_hmac(:sha256, password, salt, @iterations, 32)
end
