Code.require_file "../test_helper.exs", __FILE__

defmodule Genomu.Module.CoreTest do
  use Genomu.TestCase

  alias Genomu.Client, as: C
  alias Genomu.API, as: API

  setup_all do
    start_db
    {:ok, [conn: connection]}
  end

  teardown_all do
    stop_db
  end

  test "identity", context do
    conn = context[:conn]

    {:ok, ch} = C.begin(conn)
    assert C.get(ch, ["key"], API.Core.identity) == nil
    assert C.set(ch, ["key"], API.Core.identity("123")) == "123"
    assert C.get(ch, ["key"], API.Core.identity) == "123"
  end

  test "compose", context do
    conn = context[:conn]

    {:ok, ch} = C.begin(conn)
    assert C.get(ch, ["key"], API.Core.compose(API.Core.identity, API.Core.identity("123"))) == "123"
  end

end