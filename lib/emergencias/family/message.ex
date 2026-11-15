defmodule Emergencias.Family.Message do
  @moduledoc "Mensaje dirigido a una persona o familia (identificada por documento o dato de referencia)."

  alias Emergencias.Text

  @enforce_keys [:id, :from, :to, :content, :status, :at]
  defstruct [:id, :from, :to, :content, :status, :at, :delivered_at]

  @type t :: %__MODULE__{}

  @spec create(pos_integer(), String.t(), String.t(), String.t(), DateTime.t()) :: t()
  def create(seq, from, to, content, at),
    do: %__MODULE__{
      id: Text.sequence_id("M", seq),
      from: from,
      to: to,
      content: content,
      status: :pendiente,
      at: at
    }

  @doc "Marca el mensaje como `:entregado` o `:pendiente` (se puede revertir)."
  @spec mark(t(), :pendiente | :entregado, DateTime.t()) :: t()
  def mark(%__MODULE__{} = message, :entregado, at),
    do: %{message | status: :entregado, delivered_at: at}

  def mark(%__MODULE__{} = message, :pendiente, _at),
    do: %{message | status: :pendiente, delivered_at: nil}
end
