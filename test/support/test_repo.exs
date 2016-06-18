defmodule Ecto.TestAdapter do
  @behaviour Ecto.Adapter

  alias Ecto.Migration.SchemaMigration

  defmacro __before_compile__(_opts), do: :ok

  def ensure_all_started(_, _) do
    {:ok, []}
  end

  def child_spec(_repo, opts) do
    :ecto   = opts[:otp_app]
    "user"  = opts[:username]
    "pass"  = opts[:password]
    "hello" = opts[:database]
    "local" = opts[:hostname]

    Supervisor.Spec.worker(Task, [fn -> :timer.sleep(:infinity) end])
  end

  ## Types

  def loaders(:binary_id, type), do: [Ecto.UUID, type]
  def loaders(_primitive, type), do: [type]

  def dumpers(:binary_id, type), do: [type, Ecto.UUID]
  def dumpers(_primitive, type), do: [type]

  def autogenerate(:id), do: nil
  def autogenerate(:embed_id), do: Ecto.UUID.autogenerate
  def autogenerate(:binary_id), do: Ecto.UUID.autogenerate

  ## Queryable

  def prepare(operation, query), do: {:nocache, {operation, query}}

  def execute(_repo, _, {:nocache, {:all, %{from: {_, SchemaMigration}}}}, _, _, _) do
    {length(migrated_versions()),
     Enum.map(migrated_versions(), &List.wrap/1)}
  end

  def execute(_repo, _, {:nocache, {:all, _}}, _, _, _) do
    {1, [[1]]}
  end

  def execute(_repo, _meta, {:nocache, {:delete_all, %{from: {_, SchemaMigration}}}}, [version], _, _) do
    Process.put(:migrated_versions, List.delete(migrated_versions(), version))
    {1, nil}
  end

  def execute(_repo, meta, {:nocache, {op, %{from: {source, _}}}}, _params, _preprocess, _opts) do
    send self(), {op, {meta.prefix,source}}
    {1, nil}
  end

  ## Schema

  def insert_all(_repo, %{source: source}, _header, rows, _on_conflict, _returning, _opts) do
    send self(), {:insert_all, source, rows}
    {1, nil}
  end

  def insert(_repo, %{source: {nil, "schema_migrations"}}, val, _, _, _) do
    version = Keyword.fetch!(val, :version)
    Process.put(:migrated_versions, [version|migrated_versions()])
    {:ok, [version: 1]}
  end

  def insert(_repo, %{context: nil, source: source}, _fields, _on_conflict, return, _opts),
    do: send(self(), {:insert, source}) && {:ok, Enum.zip(return, 1..length(return))}
  def insert(_repo, %{context: {:invalid, _}=res}, _fields, _on_conflict, _return, _opts),
    do: res

  # Notice the list of changes is never empty.
  def update(_repo, %{context: nil, source: source}, [_|_], _filters, return, _opts),
    do: send(self(), {:update, source}) && {:ok, Enum.zip(return, 1..length(return))}
  def update(_repo, %{context: {:invalid, _}=res}, [_|_], _filters, _return, _opts),
    do: res

<<<<<<< e4e8fe8d16b596d0f72764e2b84d91b35706c943
  def delete(_repo, meta, _filter, _opts),
    do: send(self(), {:delete, meta.source}) && {:ok, []}
=======
  def delete(_repo, _model_meta, _filter, _opts),
    do: send(self(), :delete) && {:ok, []}
>>>>>>> Adds inherited table support for Ecto migrations.

  def primary_keys_from(_table),
    do: ["id"]

  def index_definitions_from(_table),
    do: []

  def trigger_definitions_from(_table),
    do: []

  # def primary_keys_from(table),
  #   do: Ecto.Adapters.Postgres.Connection.primary_keys_from(table)
  #
  # def index_definitions_from(table),
  #   do: Ecto.Adapters.Postgres.Connection.index_definitions_from(table)
  #
  # def trigger_definitions_from(table),
  #   do: Ecto.Adapters.Postgres.Connection.trigger_definitions_from(table)

  ## Transactions

  def transaction(_repo, _opts, fun) do
    # Makes transactions "trackable" in tests
    send self(), {:transaction, fun}
    try do
      {:ok, fun.()}
    catch
      :throw, {:ecto_rollback, value} ->
        {:error, value}
    end
  end

  def in_transaction?(_repo), do: false

  def rollback(_repo, value) do
    send self(), {:rollback, value}
    throw {:ecto_rollback, value}
  end

  ## Inheritance Queries
  @trigger """
    CREATE TRIGGER tsvector_update
    BEFORE INSERT OR UPDATE OF name, description, tags, search_language
    ON things
    FOR EACH ROW EXECUTE PROCEDURE things_search_trigger()
  """
  @index "CREATE UNIQUE INDEX things_index ON things USING btree (id)"
  def query(_repo, sql, _params, _opts) do
    cond do
      sql =~ "SELECT a.attname::varchar" ->
        {:ok, %{rows: [[:id]]}}
      sql =~ "pg_get_indexdef" ->
        {:ok, %{rows: [[@index]]}}
      sql =~ "pg_get_triggerdef" ->
        {:ok, %{rows: [[@trigger |> remove_newlines]]}}
    end
  end

  ## Migrations

  def supports_ddl_transaction? do
    Process.get(:supports_ddl_transaction?) || false
  end

  def supports_inherited_tables? do
    Process.get(:supports_inherited_tables?) || false
  end

  def execute_ddl(_repo, command, _) do
    Process.put(:last_command, command)
    :ok
  end

  defp migrated_versions do
    Process.get(:migrated_versions) || []
  end

  defp remove_newlines(string) do
    string |> String.strip |> String.replace("\n", " ") |> String.replace(~r" +"," ")
  end
end

Application.put_env(:ecto, Ecto.TestRepo, [user: "invalid"])

defmodule Ecto.TestRepo do
  use Ecto.Repo, otp_app: :ecto, adapter: Ecto.TestAdapter

end

Ecto.TestRepo.start_link(url: "ecto://user:pass@local/hello")
