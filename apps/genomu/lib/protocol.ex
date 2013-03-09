defmodule Genomu.Protocol do

  use GenServer.Behaviour
 
  def start_link(listener_pid, socket, transport, opts) do
    :proc_lib.start_link(__MODULE__, :init, [listener_pid, socket, transport, opts])
  end

  defrecord State, socket: nil, transport: nil, 
                   buffer: "",
                   channels: nil

  def init(listener_pid, socket, transport, _opts) do
    :erlang.process_flag(:trap_exit, true)
    :ok = :proc_lib.init_ack({:ok, self})
    :ok = :ranch.accept_ack(listener_pid)
    :ok = transport.setopts(socket, active: true, packet: 4)
    state = State.new(socket: socket, transport: transport,
                      channels: :ets.new(__MODULE__.Channels, [:ordered_set]))
    :gen_server.enter_loop(__MODULE__, [], state)
  end

  def handle_info({:tcp, socket, data}, State[buffer: buffer, socket: socket] = state) do
    {state, rest} = handle_packet(buffer <> data, state)
    {:noreply, state.buffer(rest)}
  end

  def handle_info({:tcp_closed, socket}, State[socket: socket] = state) do
    {:stop, :normal, state}
  end

  def handle_info({:'EXIT', pid, _reason}, State[channels: channels] = state) do
    case :ets.lookup(channels, pid) do
      [] ->
        {:stop, :normal, state}
      [{_, channel}] ->
        # Remove the channel and continue on
        :ets.delete(channels, pid)
        :ets.delete(channels, channel)
        {:noreply, state}
    end
  end

  def handle_cast({channel, response}, State[transport: transport, socket: socket] = state) do
    transport.send(socket, channel <> handle_response(response))
    {:noreply, state}
  end

  @true_value MsgPack.pack(true)

  @spec handle_packet(binary, State.t) :: {State.t, binary}
  defp handle_packet(data, State[channels: channels] = state) do
    {channel, rest} = MsgPack.next(data)
    case :ets.lookup(channels, channel) do
      [] ->
        {:ok, ch} = Genomu.Channel.start
        Process.link(ch)
        {_options, rest} = MsgPack.unpack(rest)
        # TODO: pass options to the channel
        :ets.insert(channels, [{channel, ch}, {ch, channel}])
      [{_, ch}] ->
        me = self
        {key, rest} = MsgPack.unpack(rest)
        case key do
          true -> 
             spawn(fn -> 
                response = Genomu.Channel.commit(ch)
                :gen_server.cast(me, {channel, response})
              end)
          _ ->
            case key do
              MsgPack.Map[map: [{0, [key, rev]}]] -> addr = {key, rev}
              _ -> addr = key
            end
            {type, rest} = MsgPack.unpack(rest)
            {op, rest} = Genomu.Operation.deserialize(rest)
            cmd = command(type, op)
            spawn(fn -> 
                    response = Genomu.Channel.execute(ch, addr, cmd, [])
                    :gen_server.cast(me, {channel, response})
                  end)
        end
    end
    {state, rest}
  end

  defp handle_response(:ok) do
    @true_value
  end
  defp handle_response({{value, clock}, txn}) do
    value <> MsgPack.pack(clock) <> MsgPack.pack(txn)
  end
  defp handle_response(value) do
    value
  end

  defp command(0, op), do: Genomu.Command.get(op)
  defp command(1, op), do: Genomu.Command.set(op)
  defp command(2, op), do: Genomu.Command.apply(op)

end