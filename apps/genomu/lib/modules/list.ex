defmodule Genomu.Module.List do
  use Genomu.Module, id: 2, name: :list

  @empty_value MsgPack.pack([])

  @args 0
  def head(MsgPack.fix_array(len: 0, rest: _rest), _no_arg) do
    @empty_value
  end
  def head(MsgPack.fix_array(len: len, rest: rest), _no_arg) do
    {head, _tail} = MsgPack.next(rest)
    head
  end
  def head(MsgPack.array16(len: len, rest: rest), _no_arg) do
    {head, _tail} = MsgPack.next(rest)
    head
  end
  def head(MsgPack.array32(len: len, rest: rest), _no_arg) do
    {head, _tail} = MsgPack.next(rest)
    head
  end

  @args 0
  def tail(MsgPack.fix_array(len: 0, rest: _rest), _no_arg) do
    @empty_value
  end
  def tail(MsgPack.fix_array(len: len, rest: rest), _no_arg) do
    {_, tail} = MsgPack.next(rest)
    MsgPack.fix_array(len: len - 1, rest: tail)
  end
  def tail(MsgPack.array16(len: 16, rest: rest), _no_arg) do
    {_, tail} = MsgPack.next(rest)
    MsgPack.fix_array(len: 15, rest: tail)
  end
  def tail(MsgPack.array16(len: len, rest: rest), _no_arg) do
    {_, tail} = MsgPack.next(rest)
    MsgPack.array16(len: len - 1, rest: tail)
  end
  def tail(MsgPack.array32(len: 0x10000, rest: rest), _no_arg) do
    {_, tail} = MsgPack.next(rest)
    MsgPack.array16(len: 0x10000 - 1, rest: tail)
  end
  def tail(MsgPack.array32(len: len, rest: rest), _no_arg) do
    {_, tail} = MsgPack.next(rest)
    MsgPack.array32(len: len - 1, rest: tail)
  end

  @args 1
  def append(MsgPack.fix_array(len: 15, rest: rest), element) do
    MsgPack.array16(len: 16, rest: rest <> element)
  end
  def append(MsgPack.fix_array(len: len, rest: rest), element) do
    MsgPack.fix_array(len: len + 1, rest: rest <> element)
  end
  def append(MsgPack.array16(len: 0x10000, rest: rest), element) do
    MsgPack.array32(len: 0x10000 + 1, rest: rest <> element)
  end
  def append(MsgPack.array16(len: len, rest: rest), element) do
    MsgPack.array16(len: len + 1, rest: rest <> element)
  end
  def append(MsgPack.array32(len: len, rest: rest), element) do
    MsgPack.array16(len: len + 1, rest: rest <> element)
  end
  def append(MsgPack.atom_nil, element) do
    MsgPack.fix_array(len: 1, rest: element)
  end

  @args 1
  def prepend(MsgPack.fix_array(len: 15, rest: rest), element) do
    MsgPack.array16(len: 16, rest: element <> rest)
  end
  def prepend(MsgPack.fix_array(len: len, rest: rest), element) do
    MsgPack.fix_array(len: len + 1, rest: element <> rest)
  end
  def prepend(MsgPack.array16(len: 0x10000, rest: rest), element) do
    MsgPack.array32(len: 0x10000 + 1, rest: element <> rest)
  end
  def prepend(MsgPack.array16(len: len, rest: rest), element) do
    MsgPack.array16(len: len + 1, rest: element <> rest)
  end
  def prepend(MsgPack.array32(len: len, rest: rest), element) do
    MsgPack.array16(len: len + 1, rest: element <> rest)
  end
  def prepend(MsgPack.atom_nil, element) do
    MsgPack.fix_array(len: 1, rest: element)
  end

  @args 0
  def length(MsgPack.fix_array(len: len), _no_arg) do
    MsgPack.pack(len)
  end

  def length(MsgPack.array16(len: len), _no_arg) do
    MsgPack.pack(len)
  end

  def length(MsgPack.array32(len: len), _no_arg) do
    MsgPack.pack(len)
  end

end