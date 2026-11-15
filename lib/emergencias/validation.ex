defmodule Emergencias.Validation do
  @moduledoc """
  Validaciones de entrada. Devuelven `{:ok, valor_normalizado}` o
  `{:error, {:invalid_field, campo, motivo}}`; nunca lanzan por datos del usuario.
  """

  @code_regex ~r/^[A-Za-z0-9][A-Za-z0-9_.\-]{0,39}$/
  @username_regex ~r/^[a-z0-9][a-z0-9_.\-]{2,31}$/

  @doc """
  Código seguro (letras, números, `_`, `-`, `.`; sirve también como nombre de
  archivo), llevado a mayúsculas (`:up`), minúsculas (`:down`) o sin cambios (`:keep`).
  """
  @spec code(term(), atom(), :up | :down | :keep) :: {:ok, String.t()} | {:error, term()}
  def code(value, field, casing \\ :down)

  def code(value, field, casing) when is_binary(value) do
    value = String.trim(value)

    cond do
      not Regex.match?(@code_regex, value) -> invalid(field, :bad_identifier)
      casing == :up -> {:ok, String.upcase(value)}
      casing == :down -> {:ok, String.downcase(value)}
      true -> {:ok, value}
    end
  end

  def code(_value, field, _casing), do: invalid(field, :bad_identifier)

  @doc "Aplica `validator` solo si hay valor (`nil` o `\"\"` devuelven `{:ok, nil}`)."
  @spec optional(term(), (term() -> {:ok, term()} | {:error, term()})) ::
          {:ok, term()} | {:error, term()}
  def optional(value, _validator) when value in [nil, ""], do: {:ok, nil}
  def optional(value, validator), do: validator.(value)

  @spec username(term()) :: {:ok, String.t()} | {:error, term()}
  def username(value) when is_binary(value) do
    value = value |> String.trim() |> String.downcase()

    if Regex.match?(@username_regex, value),
      do: {:ok, value},
      else: invalid(:username, :bad_format)
  end

  def username(_), do: invalid(:username, :bad_format)

  @spec password(term()) :: {:ok, String.t()} | {:error, term()}
  def password(value) when is_binary(value) and byte_size(value) >= 4, do: {:ok, value}
  def password(_), do: invalid(:password, :too_short)

  @doc "Texto no vacío y recortado."
  @spec text(term(), atom()) :: {:ok, String.t()} | {:error, term()}
  def text(value, field) when is_binary(value) do
    case String.trim(value) do
      "" -> invalid(field, :blank)
      trimmed -> {:ok, trimmed}
    end
  end

  def text(_value, field), do: invalid(field, :blank)

  @doc "Entero estrictamente positivo (acepta enteros o cadenas numéricas)."
  @spec positive_integer(term(), atom()) :: {:ok, pos_integer()} | {:error, term()}
  def positive_integer(value, field) do
    with {:ok, n} <- to_integer(value, field) do
      if n > 0, do: {:ok, n}, else: invalid(field, :must_be_positive)
    end
  end

  @doc "Entero mayor o igual a cero."
  @spec non_negative_integer(term(), atom()) :: {:ok, non_neg_integer()} | {:error, term()}
  def non_negative_integer(value, field) do
    with {:ok, n} <- to_integer(value, field) do
      if n >= 0, do: {:ok, n}, else: invalid(field, :must_not_be_negative)
    end
  end

  @doc "Como `non_negative_integer/2`, pero `nil` o vacío devuelven `default`."
  @spec non_negative_integer(term(), atom(), non_neg_integer()) ::
          {:ok, non_neg_integer()} | {:error, term()}
  def non_negative_integer(value, _field, default) when value in [nil, ""], do: {:ok, default}
  def non_negative_integer(value, field, _default), do: non_negative_integer(value, field)

  defp to_integer(value, _field) when is_integer(value), do: {:ok, value}

  defp to_integer(value, field) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {n, ""} -> {:ok, n}
      _ -> invalid(field, :not_a_number)
    end
  end

  defp to_integer(_value, field), do: invalid(field, :not_a_number)

  defp invalid(field, reason), do: {:error, {:invalid_field, field, reason}}
end
