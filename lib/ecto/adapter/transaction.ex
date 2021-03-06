defmodule Ecto.Adapter.Transaction  do
  @moduledoc """
  Specifies the adapter transactions API.
  """

  @doc """
  Runs the given function inside a transaction.

  Returns `{:ok, value}` if the transaction was successful where `value`
  is the value return by the function or `{:error, value}` if the transaction
  was rolled back where `value` is the value given to `rollback/1`.

  See `Ecto.Repo.transaction/1`.
  """
  @callback transaction(Ecto.Repo.t, Keyword.t, fun) :: {:ok, any} | {:error, any}

  @doc """
  Returns true if the given process is inside a transaction.
  """
  @callback in_transaction?(Ecto.Repo.t) :: boolean

  @doc """
  Rolls back the current transaction.

  The transaction will return the value given as `{:error, value}`.

  See `Ecto.Repo.rollback/1`.
  """
  @callback rollback(Ecto.Repo.t, any) :: no_return
end
