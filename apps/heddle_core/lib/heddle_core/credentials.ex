defmodule HeddleCore.Credentials do
  @moduledoc """
  The secrets nodes need to reach other services.

  Values are encrypted with AES-256-GCM, under a key derived from `SECRET_KEY_BASE`.
  The UI and the worker share that secret, and changing it makes every credential
  unreadable. A flow only stores the credential's name, so a secret never reaches a
  flow, a run's context or its logs.
  """

  import Ecto.Query, warn: false

  alias HeddleCore.Credentials.Credential
  alias HeddleCore.Repo

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

  def list_credentials do
    Repo.all(from c in Credential, order_by: c.name)
  end

  def get_credential!(id), do: Repo.get!(Credential, id)

  def change_credential(%Credential{} = credential, attrs \\ %{}) do
    Credential.changeset(credential, attrs, kind_ids())
  end

  @doc """
  Creates a credential from `name`, `kind` and the `values` of that kind's fields.
  """
  def create_credential(attrs) do
    save(%Credential{}, attrs, %{})
  end

  @doc """
  Updates a credential. A secret left blank keeps the value it had.
  """
  def update_credential(%Credential{} = credential, attrs) do
    save(credential, attrs, stored_values(credential))
  end

  def delete_credential(%Credential{} = credential), do: Repo.delete(credential)

  @doc """
  Returns the values that aren't secret, to fill in a form.
  """
  def public_values(%Credential{} = credential) do
    secrets = for field <- kind(credential.kind).fields, field[:secret], do: field.name

    credential |> stored_values() |> Map.drop(secrets)
  end

  @doc """
  Returns the values of the credential called `name`, which must be of `kind`.
  """
  def fetch(name, kind) when is_binary(name) and is_binary(kind) do
    case Repo.one(from c in Credential, where: c.name == ^name, select: {c.kind, c.data}) do
      nil -> {:error, ~s(There is no credential called "#{name}".)}
      {^kind, data} -> decrypt(name, kind, data)
      {other, _data} -> {:error, ~s(The credential "#{name}" is for #{other}, not #{kind}.)}
    end
  end

  def fetch(_name, _kind), do: {:error, "Pick a credential for this node."}

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
