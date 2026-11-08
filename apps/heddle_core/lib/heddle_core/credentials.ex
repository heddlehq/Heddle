defmodule HeddleCore.Credentials do
  @moduledoc """
  The secrets nodes need to reach other services.

  Values are encrypted with AES-256-GCM, under a key derived from `SECRET_KEY_BASE`.
  The UI and the worker share that secret, and changing it makes every credential
  unreadable. A flow only stores the credential's name, so a secret never reaches a
  flow, a run's context or its logs.
  """

  import Ecto.Query, warn: false

  alias HeddleCore.Accounts.Scope
  alias HeddleCore.Credentials.Credential
  alias HeddleCore.Repo
  alias HeddleCore.Workspaces

  @version 1
  @encryption [
    %{label: "On, and check the server's certificate", value: "verify"},
    %{label: "On, for a server with its own certificate", value: "require"},
    %{label: "Off", value: "off"}
  ]
  @kinds [
    %{
      id: "slack",
      label: "Slack",
      fields: [%{name: "token", label: "Bot token", secret: true, required: true}]
    },
    %{
      id: "ai",
      label: "AI provider",
      fields: [
        %{
          name: "provider",
          label: "Provider",
          required: true,
          default: "google",
          options: [
            %{label: "Google (Gemini, Nano Banana)", value: "google"},
            %{label: "OpenAI (GPT, GPT Image, Whisper)", value: "openai"},
            %{label: "Anthropic (Claude)", value: "anthropic"},
            %{label: "xAI (Grok)", value: "xai"}
          ]
        },
        %{name: "api_key", label: "API key", secret: true, required: true}
      ]
    },
    %{
      id: "google",
      label: "Google service account",
      fields: [%{name: "json", label: "Service account JSON", secret: true, required: true}]
    },
    %{
      id: "smtp",
      label: "Email (SMTP)",
      fields: [
        %{name: "host", label: "Host", required: true},
        %{name: "port", label: "Port", default: "587"},
        %{name: "username", label: "Username"},
        %{name: "password", label: "Password", secret: true},
        %{name: "from", label: "From address", required: true}
      ]
    },
    %{
      id: "imap",
      label: "Email (IMAP)",
      fields: [
        %{name: "host", label: "Host", required: true},
        %{name: "port", label: "Port", default: "993"},
        %{name: "username", label: "Username", required: true},
        %{name: "password", label: "Password", secret: true, required: true}
      ]
    },
    %{
      id: "s3",
      label: "S3",
      fields: [
        %{name: "access_key_id", label: "Access key ID", required: true},
        %{name: "secret_access_key", label: "Secret access key", secret: true, required: true},
        %{name: "region", label: "Region", default: "us-east-1"},
        %{name: "endpoint", label: "Endpoint, for services other than AWS"}
      ]
    },
    %{
      id: "ftp",
      label: "FTP",
      fields: [
        %{name: "host", label: "Host", required: true},
        %{name: "port", label: "Port", default: "21"},
        %{name: "username", label: "Username", required: true},
        %{name: "password", label: "Password", secret: true, required: true}
      ]
    },
    %{
      id: "sql",
      label: "SQL database",
      fields: [
        %{
          name: "engine",
          label: "Database",
          required: true,
          default: "postgres",
          options: [
            %{label: "PostgreSQL, and compatible ones", value: "postgres"},
            %{label: "MySQL or MariaDB, and compatible ones", value: "mysql"},
            %{label: "SQL Server or Azure SQL", value: "sqlserver"},
            %{label: "Oracle", value: "oracle"},
            %{label: "SQLite", value: "sqlite"}
          ]
        },
        %{name: "host", label: "Host, except for SQLite"},
        %{name: "port", label: "Port, if it isn't the default one"},
        %{name: "database", label: "Database name, or the path of a SQLite file", required: true},
        %{name: "username", label: "Username"},
        %{name: "password", label: "Password", secret: true},
        %{
          name: "ssl",
          label: "Encryption",
          default: "verify",
          options: @encryption
        }
      ]
    },
    %{
      id: "mongodb",
      label: "MongoDB",
      fields: [
        %{name: "url", label: "Connection string", secret: true, required: true},
        %{name: "database", label: "Database", required: true}
      ]
    },
    %{
      id: "redis",
      label: "Redis",
      fields: [
        %{
          name: "url",
          label: "URL, like redis://:password@host:6379/0",
          secret: true,
          required: true
        }
      ]
    },
    %{
      id: "elasticsearch",
      label: "Elasticsearch or OpenSearch",
      fields: [
        %{name: "url", label: "URL", required: true},
        %{name: "api_key", label: "API key", secret: true},
        %{name: "username", label: "Username, without an API key"},
        %{name: "password", label: "Password, without an API key", secret: true}
      ]
    },
    %{
      id: "dynamodb",
      label: "DynamoDB",
      fields: [
        %{name: "access_key_id", label: "Access key ID", required: true},
        %{name: "secret_access_key", label: "Secret access key", secret: true, required: true},
        %{name: "region", label: "Region", default: "us-east-1"},
        %{name: "endpoint", label: "Endpoint, for services other than AWS"}
      ]
    },
    %{
      id: "cassandra",
      label: "Cassandra or ScyllaDB",
      fields: [
        %{name: "hosts", label: "Hosts, separated by commas", required: true},
        %{name: "keyspace", label: "Keyspace"},
        %{name: "username", label: "Username"},
        %{name: "password", label: "Password", secret: true},
        %{name: "ssl", label: "Encryption", default: "off", options: @encryption}
      ]
    },
    %{
      id: "neo4j",
      label: "Neo4j",
      fields: [
        %{name: "url", label: "HTTP URL, like https://host:7473", required: true},
        %{name: "database", label: "Database", default: "neo4j"},
        %{name: "username", label: "Username", required: true},
        %{name: "password", label: "Password", secret: true, required: true}
      ]
    }
  ]

  def kinds, do: @kinds

  def kind(id), do: Enum.find(@kinds, &(&1.id == id))

  @doc """
  The credentials the caller's workspace can use: its own and the shared ones, by name.
  """
  def list_credentials(%Scope{} = scope) do
    workspace_id = scope.workspace && scope.workspace.id

    if Workspaces.can?(scope, :view, workspace_id) do
      Repo.all(
        from c in Credential,
          where: c.workspace_id == ^workspace_id or is_nil(c.workspace_id),
          order_by: [asc: c.name, asc_nulls_last: c.workspace_id]
      )
    else
      []
    end
  end

  @doc "The credentials shared with every workspace, by name."
  def list_shared_credentials do
    Repo.all(from c in Credential, where: is_nil(c.workspace_id), order_by: c.name)
  end

  @doc "Gets a credential the caller's workspace can use, or nil."
  def get_credential(%Scope{} = scope, id) do
    with {id, ""} <- Integer.parse(to_string(id)),
         %Credential{} = credential <- Repo.get(Credential, id),
         true <- visible?(scope, credential) do
      credential
    else
      _other -> nil
    end
  end

  # A shared one is visible to anyone who works in some workspace.
  defp visible?(scope, %Credential{workspace_id: nil}),
    do: Scope.system_admin?(scope) or Workspaces.can?(scope, :view)

  defp visible?(scope, %Credential{workspace_id: id}), do: Workspaces.can?(scope, :view, id)

  @doc """
  Whether the caller may change `credential`: the editors of its workspace, or system
  admins for a shared one.
  """
  def can_change?(%Scope{} = scope, %Credential{workspace_id: nil}),
    do: Scope.system_admin?(scope)

  def can_change?(%Scope{} = scope, %Credential{workspace_id: id}),
    do: Workspaces.can?(scope, :edit, id)

  def change_credential(%Credential{} = credential, attrs \\ %{}) do
    Credential.changeset(credential, attrs, kind_ids())
  end

  @doc """
  Creates a credential from `name`, `kind` and the `values` of that kind's fields, in
  the caller's workspace. With `"shared" => true`, a system admin shares it with every
  workspace instead.
  """
  def create_credential(%Scope{} = scope, attrs) do
    attrs = Map.new(attrs, fn {key, value} -> {to_string(key), value} end)

    cond do
      attrs["shared"] in [true, "true"] and Scope.system_admin?(scope) ->
        save(%Credential{}, attrs, %{})

      attrs["shared"] in [true, "true"] ->
        {:error, :forbidden}

      scope.workspace && Workspaces.can?(scope, :edit, scope.workspace.id) ->
        save(%Credential{workspace_id: scope.workspace.id}, attrs, %{})

      true ->
        {:error, :forbidden}
    end
  end

  @doc """
  Creates a credential in the workspace with `workspace_id`, or a shared one with nil,
  for what isn't a person, such as seeds and tests.
  """
  def insert_credential(attrs, workspace_id) do
    save(%Credential{workspace_id: workspace_id}, attrs, %{})
  end

  @doc """
  Updates a credential. A secret left blank keeps the value it had.
  """
  def update_credential(%Scope{} = scope, %Credential{} = credential, attrs) do
    if can_change?(scope, credential) do
      save(credential, attrs, stored_values(credential))
    else
      {:error, :forbidden}
    end
  end

  def delete_credential(%Scope{} = scope, %Credential{} = credential) do
    if can_change?(scope, credential), do: Repo.delete(credential), else: {:error, :forbidden}
  end

  @doc """
  Returns the values that aren't secret, to fill in a form.
  """
  def public_values(%Credential{} = credential) do
    secrets = for field <- kind(credential.kind).fields, field[:secret], do: field.name

    credential |> stored_values() |> Map.drop(secrets)
  end

  @doc """
  Returns the values of the credential called `name`, which must be of `kind`, as a
  run in the workspace with `workspace_id` sees it: its own first, then the shared
  ones. With a nil `workspace_id`, only the shared ones.
  """
  def fetch(workspace_id, name, kind) when is_binary(name) and is_binary(kind) do
    query =
      from c in Credential,
        where: c.name == ^name,
        order_by: [asc_nulls_last: c.workspace_id],
        limit: 1,
        select: {c.kind, c.data}

    query =
      if is_nil(workspace_id),
        do: where(query, [c], is_nil(c.workspace_id)),
        else: where(query, [c], c.workspace_id == ^workspace_id or is_nil(c.workspace_id))

    case Repo.one(query) do
      nil -> {:error, ~s(There is no credential called "#{name}".)}
      {^kind, data} -> decrypt(name, kind, data)
      {other, _data} -> {:error, ~s(The credential "#{name}" is for #{other}, not #{kind}.)}
    end
  end

  def fetch(_workspace_id, _name, _kind), do: {:error, "Pick a credential for this node."}

  defp save(credential, attrs, current) do
    attrs = Map.new(attrs, fn {key, value} -> {to_string(key), value} end)
    changeset = change_credential(credential, Map.take(attrs, ["name", "kind"]))

    with {:ok, kind} <- fetch_kind(changeset),
         values = merge_values(kind, attrs["values"] || %{}, current),
         :ok <- require_values(kind, values) do
      changeset
      |> Ecto.Changeset.put_change(:data, encrypt(kind.id, values))
      |> Repo.insert_or_update()
    else
      {:error, message} when is_binary(message) ->
        {:error, Ecto.Changeset.add_error(changeset, :kind, message)}

      :invalid_kind ->
        {:error, %{changeset | action: :insert}}
    end
  end

  defp fetch_kind(changeset) do
    case kind(Ecto.Changeset.get_field(changeset, :kind)) do
      nil -> :invalid_kind
      kind -> {:ok, kind}
    end
  end

  defp merge_values(kind, given, current) do
    Map.new(kind.fields, fn field ->
      value = String.trim(to_string(given[field.name] || ""))
      {field.name, if(value == "", do: current[field.name] || field[:default] || "", else: value)}
    end)
  end

  defp require_values(kind, values) do
    case Enum.find(kind.fields, &(&1[:required] && values[&1.name] == "")) do
      nil -> :ok
      field -> {:error, "#{field.label} can't be blank"}
    end
  end

  defp stored_values(%Credential{id: id, kind: kind, name: name}) do
    data = Repo.one!(from c in Credential, where: c.id == ^id, select: c.data)

    case decrypt(name, kind, data) do
      {:ok, values} -> values
      {:error, _message} -> %{}
    end
  end

  defp encrypt(kind, values) do
    iv = :crypto.strong_rand_bytes(12)
    plain = Jason.encode!(values)

    {cipher, tag} = :crypto.crypto_one_time_aead(:aes_256_gcm, key(), iv, plain, kind, true)

    <<@version, iv::binary-12, tag::binary-16, cipher::binary>>
  end

  defp decrypt(name, kind, <<@version, iv::binary-12, tag::binary-16, cipher::binary>>) do
    case :crypto.crypto_one_time_aead(:aes_256_gcm, key(), iv, cipher, kind, tag, false) do
      plain when is_binary(plain) -> {:ok, Jason.decode!(plain)}
      :error -> unreadable(name)
    end
  end

  defp decrypt(name, _kind, _data), do: unreadable(name)

  defp unreadable(name) do
    {:error, ~s(The credential "#{name}" can't be read. SECRET_KEY_BASE may have changed.)}
  end

  defp key do
    secret = Application.fetch_env!(:heddle_core, :credentials_secret)

    :crypto.mac(:hmac, :sha256, secret, "heddle credentials")
  end

  defp kind_ids, do: Enum.map(@kinds, & &1.id)
end
