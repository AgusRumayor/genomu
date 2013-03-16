defmodule Genomu.Constants do
  defmodule CommitObject do
    defmacro version, do: -1
    defmacro n, do: 0
    defmacro r, do: 1
    defmacro vnodes, do: 2
    defmacro timestamp, do: 3
    defmacro host, do: 4
    defmacro log, do: 5
  end
  defmodule ChannelOptions do
    defmacro n, do: 0
    defmacro r, do: 1
    defmacro vnodes, do: 2
    defmacro timeout, do: 3
  end
end