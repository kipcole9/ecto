# This Fork supports Inherited tables in Postgres

Use at your own risk, but all Ecto tests are passing so you're probably ok.  But don't use this fork unless you specifically want to use inherited tables in Postgres and you're ok with the maintenance and support risk of a private fork.

This fork supports:

  * Creating inherited tables in migrations
  * Inheriting tables or including them in your schemas
  * Querying inherited tables and polymorphically returning the correct schema

See the relevant module (Ecto.Schema, Ecto.Migration) for further information.

# Ecto

[![Build Status](https://travis-ci.org/elixir-lang/ecto.svg?branch=master)](https://travis-ci.org/elixir-lang/ecto)
[![Inline docs](http://inch-ci.org/github/elixir-lang/ecto.svg?branch=master&style=flat)](http://inch-ci.org/github/elixir-lang/ecto)

Ecto is a domain specific language for writing queries and interacting with databases in Elixir. Here is an example:

```elixir
# In your config/config.exs file
config :my_app, ecto_repos: [Sample.Repo]

config :my_app, Sample.Repo,
  adapter: Ecto.Adapters.Postgres,
  database: "ecto_simple",
  username: "postgres",
  password: "postgres",
  host: "localhost",
  port: "5432"

# In your application code
defmodule Sample.Repo do
  use Ecto.Repo,
    otp_app: :my_app
end

defmodule Sample.Weather do
  use Ecto.Schema

  schema "weather" do
    field :city     # Defaults to type :string
    field :temp_lo, :integer
    field :temp_hi, :integer
    field :prcp,    :float, default: 0.0
  end
end

defmodule Sample.App do
  import Ecto.Query
  alias Sample.Weather
  alias Sample.Repo

  def keyword_query do
    query = from w in Weather,
         where: w.prcp > 0 or is_nil(w.prcp),
         select: w
    Repo.all(query)
  end

  def pipe_query do
    Weather
    |> where(city: "Kraków")
    |> order_by(:temp_lo)
    |> limit(10)
    |> Repo.all
  end
end
```

See the [getting started guide](http://hexdocs.pm/ecto/getting-started.html) and the [online documentation](http://hexdocs.pm/ecto).

## Included and Inherited Tables

### Inclusion

Any schema module may copy the fields and associations from another module
by `include`-ing it in another schema.  Since this is a copy of the
definitions it will include any primary keys set on the included module
and hence it is likely you will want to set `@primary_key false` for the
including module to prevent errors.

For example:

    # Defines a schema with the default primary key
    # definition
    defmodule Contact do
      use Ecto.Schema

      schema "contacts" do
        field :name, :string
        has_many :comments, Comment
      end
    end

    # Defines a schema that will copy the fields
    # and associations from Contact into Person.
    # Note we set @primary_key to false since the
    # `id` field will be copied from the Contact
    # module.
    @primary_key false
    defmodule Person do
      use Ecto.Schema

      schema "people" do
        include Contact
        field :age, :integer, default: 0
      end
    end

    # Also copies the field and association definitions
    # from Contact.
    @primary_key false
    defmodule Organization do
      use Ecto.Schema

      schema "organizations" do
        include Contact
        field :revenue, :integer
      end
    end

### Inheritance

Schema inheritance has two elements that, together, support inherited
tables on supported adapters (currently only Postgres).

First we declare a schema to be `inheritable`.  This macro creates a
field called `_type` which is used at runtime to discriminate a row retrieved
in a query and to determine which table it is derived from and therefore which
schema should be populated for that row.  This is a form of polymorphism but
limited to the case of inherited tables.

Secondly, we `inherit` a schema from an `inheritable` one (or from another schema that itself inherits from an `inheritable` one).

For example:

    # Defines a schema to be inheritable. This creates a field
    # called _type that is used at runtime to discriminate amongst
    # rows retrieved from different inherited tables.
    defmodule Contact do
      use Ecto.Schema

      schema "contacts" do
        inheritable()
        field :name, :string
        has_many :comments, Comment
      end
    end

    # Defines a schema that inherits from Contact.
    # Note that inherit is exactly the same as include
    # but named to better express intent.  The key is
    # that it inherits (or includes) from a schema
    # marked as inheritable.  We set @primary_key false
    # because we'll inherit the primary key from the
    # parent table.
    @primary_key false
    defmodule Person do
      use Ecto.Schema

      schema "people" do
        inherit Contact
        field :age, :integer, default: 0
      end
    end

    # include is the same as inherit and will therefore
    # also demonstrate the same behaviour at runtime since
    # the Contact schema is marked as inheritable.
    @primary_key false
    defmodule Organization do
      use Ecto.Schema

      schema "organizations" do
        include Contact
        field :revenue, :integer
      end
    end

### Query Support for Inherited Tables

The Ecto query language doesn't change at all however there are some points to understand about what this fork does under the covers:

* It will append a column `_type` to any wildcard query (ie a query that doesn't have a `select()` in it) on an inherited table.  This `_type` column returns the underlying table name of each retrieved row of a query.  This fork of ecto uses the `_type` column to work out which `Ecto.Schemo` should be populated per row.  There's a fair bit of optimization to this process so in testing the performance characteristics change immaterially.  But more benchmarking of this area would be a good idea and certainly its an area to watch.

* If you do your own `select()` to retrieve only some required columns (which is a good practise) then in order for inherited tables to work as polymorphic tables you'll need to make sure you include the `_type` column in the `select()` list yourself.  If you don't include it then all rows will be populated into the schema representing the table you queried.

* The `_type` column is created for each inherited table and is defined as:

    `field :_type, :string,
      alias_for: fragment("%{table}.\"tableoid\"::regclass::text")`

* This defines the field as being an ecto `fragment()` that retrieves the Postgres OID in text form.  You will see it also adds an option to the `field` macro called `:alias_for`.  This macro can be used in other parts of your `Ecto.Schema` code as well.

### Implementation Details To Consider

One of the most performance sensitive parts of the process is being able to map the `_type` column to an Ecto schema.  There are two considerations:

1. *How to decide which schema to use for a given row.*  This is defined for each schema and is available via a metadata function invoked as `MySchema.__schema__(:source) and if required `MySchema.__schema__(:prefix)`

2. *How to look up the right schema for each row at runtime.*  This is done via a module created at compile time called `Ecto.Schema.Map`. This code is located at `Ecto.Repo.Supervisor.build_source_map/1` and is invoked in `Ecto.Repo.Supervisor.init/4`.  It builds a set of functions that map a `_type` column to the previously defined schema mapping.


## Usage

You need to add both Ecto and the database adapter as a dependency to your `mix.exs` file. The supported databases and their adapters are:

Database   | Ecto Adapter           | Dependency                   | Ecto 2.0 compatible?
:----------| :--------------------- | :----------------------------| :-------------------
PostgreSQL | Ecto.Adapters.Postgres | [postgrex][postgrex]         | Yes
MySQL      | Ecto.Adapters.MySQL    | [mariaex][mariaex]           | Yes
MSSQL      | Tds.Ecto               | [tds_ecto][tds_ecto]         | No
SQLite3    | Sqlite.Ecto            | [sqlite_ecto][sqlite_ecto]   | No
MongoDB    | Mongo.Ecto             | [mongodb_ecto][mongodb_ecto] | No

[postgrex]: http://github.com/ericmj/postgrex
[mariaex]: http://github.com/xerions/mariaex
[tds_ecto]: https://github.com/livehelpnow/tds_ecto
[sqlite_ecto]: https://github.com/jazzyb/sqlite_ecto
[mongodb_ecto]: https://github.com/michalmuskala/mongodb_ecto

For example, if you want to use PostgreSQL, add to your `mix.exs` file:

```elixir
defp deps do
  [{:postgrex, ">= 0.0.0"},
   {:ecto, "~> 2.0.0"}]
end
```

and update your applications list to include both projects:

```elixir
def application do
  [applications: [:postgrex, :ecto]]
end
```

Then run `mix deps.get` in your shell to fetch the dependencies. If you want to use another database, just choose the proper dependency from the table above.

Finally, in the repository configuration, you will need to specify the `adapter:` respective to the chosen dependency. For PostgreSQL it is:

```elixir
config :my_app, Repo,
  adapter: Ecto.Adapters.Postgres,
  ...
```

We are currently looking for contributions to add support for other SQL databases and folks interested in exploring non-relational databases too.

## Important links

  * [Documentation](http://hexdocs.pm/ecto)
  * [Mailing list](https://groups.google.com/forum/#!forum/elixir-ecto)
  * [Examples](https://github.com/elixir-ecto/ecto/tree/master/examples)

## Contributing

Contributions are welcome! In particular, remember to:

* Do not use the issues tracker for help or support requests (try Stack Overflow, IRC or mailing lists, etc).
* For proposing a new feature, please start a discussion on [elixir-ecto](https://groups.google.com/forum/#!forum/elixir-ecto).
* For bugs, do a quick search in the issues tracker and make sure the bug has not yet been reported.
* Finally, be nice and have fun! Remember all interactions in this project follow the same [Code of Conduct as Elixir](https://github.com/elixir-lang/elixir/blob/master/CODE_OF_CONDUCT.md).

### Running tests

Clone the repo and fetch its dependencies:

```
$ git clone https://github.com/elixir-ecto/ecto.git
$ cd ecto
$ mix deps.get
$ mix test
```

Besides the unit tests above, it is recommended to run the adapter integration tests too:

```
# Run only PostgreSQL tests (version of PostgreSQL must be >= 9.4 to support jsonb)
MIX_ENV=pg mix test

# Run all tests (unit and all adapters)
mix test.all
```

### Building docs

```
$ MIX_ENV=docs mix docs
```

## Copyright and License

Copyright (c) 2012, Plataformatec.

Ecto source code is licensed under the [Apache 2 License](LICENSE.md).
