defmodule Ecto.Repo.Supervisor do
  @moduledoc false
  use Supervisor

  @doc """
  Starts the repo supervisor.
  """
  def start_link(repo, otp_app, adapter, opts) do
    opts = config(repo, otp_app, opts)
    name = opts[:name] || Application.get_env(otp_app, repo)[:name] || repo
    Supervisor.start_link(__MODULE__, {repo, otp_app, adapter, opts}, [name: name])
  end

  @doc """
  Retrieves and normalizes the configuration for `repo` in `otp_app`.
  """
  def config(repo, otp_app, custom) do
    if config = Application.get_env(otp_app, repo) do
      config = Keyword.merge(config, custom)
      {url, config} = Keyword.pop(config, :url)
      [otp_app: otp_app, repo: repo] ++ Keyword.merge(config, parse_url(url || ""))
    else
      raise ArgumentError,
        "configuration for #{inspect repo} not specified in #{inspect otp_app} environment"
    end
  end

  @doc """
  Parses the OTP configuration for compile time.
  """
  def parse_config(repo, opts) do
    otp_app = Keyword.fetch!(opts, :otp_app)
    config  = Application.get_env(otp_app, repo, [])
    adapter = opts[:adapter] || config[:adapter]

    unless adapter do
      raise ArgumentError, "missing :adapter configuration in " <>
                           "config #{inspect otp_app}, #{inspect repo}"
    end

    unless Code.ensure_loaded?(adapter) do
      raise ArgumentError, "adapter #{inspect adapter} was not compiled, " <>
                           "ensure it is correct and it is included as a project dependency"
    end

    {otp_app, adapter, config}
  end

  @doc """
  Parses an Ecto URL allowed in configuration.

  The format must be:

      "ecto://username:password@hostname:port/database"

  or

      {:system, "DATABASE_URL"}

  """
  def parse_url(""), do: []

  def parse_url({:system, env}) when is_binary(env) do
    parse_url(System.get_env(env) || "")
  end

  def parse_url(url) when is_binary(url) do
    info = url |> URI.decode() |> URI.parse()

    if is_nil(info.host) do
      raise Ecto.InvalidURLError, url: url, message: "host is not present"
    end

    if is_nil(info.path) or not (info.path =~ ~r"^/([^/])+$") do
      raise Ecto.InvalidURLError, url: url, message: "path should be a database name"
    end

    destructure [username, password], info.userinfo && String.split(info.userinfo, ":")
    "/" <> database = info.path

    opts = [username: username,
            password: password,
            database: database,
            hostname: info.host,
            port:     info.port]

    Enum.reject(opts, fn {_k, v} -> is_nil(v) end)
  end
  
  # Builds a module and functions that allow us to map an Ecto schema source 
  # (ie table name) back to its relevant schema module in support of inherited tables.
  # There's no way to just get a list of the modules that are Ecto schemas so we iterate
  # over all application modules to inspect them - which has the less than desirable
  # side affect of loading all the application modules up front.
  def build_source_map(otp_app) when is_atom(otp_app) do
    {:ok, app_config} = Application.app_dir(otp_app) <> "/ebin/#{otp_app}.app" |> :file.consult
    {:application, _app_name, config} = List.first(app_config)
    build_source_map(Keyword.get(config, :modules))
  end

  def build_source_map(modules) when is_list(modules) do
    map = 
      modules
      |> Enum.filter(fn(m) -> Keyword.get(m.__info__(:functions), :__schema__) end)
      |> Enum.reject(fn(m) -> m in [Ecto.Schema, Ecto.Migration.SchemaMigration] end)
      |> Enum.map(fn(m) -> 
          "def schema_for_source(:#{m.__schema__(:source)}), do: #{m}" <>
            if m.__schema__(:prefix) do 
              "\ndef schema_for_source(:\"#{m.__schema__(:prefix)}.#{m.__schema__(:source)}\"), do: #{m}"
            else
              ""
            end
         end)
      |> Enum.join("\n")

    Code.eval_string """
      defmodule Ecto.Schema.Map do
        #{map}
      end
    """  
  end

  ## Callbacks

  def init({repo, otp_app, adapter, opts}) do
    children = [adapter.child_spec(repo, opts)]
    if Keyword.get(opts, :query_cache_owner, true) do
      :ets.new(repo, [:set, :public, :named_table, read_concurrency: true])
    end
    unless Code.ensure_loaded?(Ecto.Schema.Map), do: build_source_map(otp_app)
    supervise(children, strategy: :one_for_one)
  end
end
