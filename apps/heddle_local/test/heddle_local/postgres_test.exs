defmodule HeddleLocal.PostgresTest do
  use ExUnit.Case, async: true

  alias HeddleLocal.Postgres

  test "connects over loopback on Heddle's own port" do
    assert %URI{host: "127.0.0.1", port: 54_329, userinfo: "heddle:secret"} =
             URI.parse(Postgres.database_url("secret"))
  end

  test "keeps the cluster inside the data directory" do
    assert Postgres.cluster_path("/home/ana/.heddle/data") == "/home/ana/.heddle/data/postgres"
  end
end
