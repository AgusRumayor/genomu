defmodule Genomu.VNode do
   @behaviour :riak_core_vnode
   alias :riak_core_vnode_master, as: Master
   alias :riak_core_vnode, as: VNode
   alias :ets, as: ETS

   @type partition :: non_neg_integer

   @type sender :: {:fsm | :server | :raw, reference, pid} |
                   {:server, :undefined, :undefined} |
                   {:fsm, :undefined, pid} |
                   :ignore

   @type command :: {Genomu.cell, Genomu.revision, Genomu.command,
                     Genomu.Coordinator.ref}
   @type commit :: {:C, ITC.t, binary, [Genomu.Transaction.entry], Genomu.Coordinator.ref}

   @typep fold_req :: {:riak_core_fold_req_v1, ((term, term) -> term), term}

   @nil_value MsgPack.pack(nil)

   require Lager
   require Genomu.Constants.CommitObject
   alias Genomu.Constants.CommitObject, as: CO

   defrecord State, partition: nil,
                    tab: nil, staging_tab: nil, commit_tab: nil do
     record_type    partition: Genomu.VNode.partition,
                    tab: :ets.tid, staging_tab: :ets.tid,
                    commit_tab: :ets.tid
   end

   @spec start_vnode(integer | [integer]) :: {:ok, pid}
   def start_vnode(partition) do
     Master.get_vnode_pid(partition, __MODULE__)
   end

   @spec init([non_neg_integer]) :: {:ok, State.t}
   def init([partition]) do
     :erlang.process_flag(:trap_exit, true)
     tab = ETS.new(__MODULE__, [:ordered_set])
     staging_tab = ETS.new(__MODULE__.Staging, [:ordered_set])
     commit_tab = ETS.new(__MODULE__.Commit, [])
     {:ok, State.new(partition: partition, tab: tab, staging_tab: staging_tab,
                     commit_tab: commit_tab)}
   end

   @spec handle_command(fold_req | command | commit, sender, State.t) ::
         {:reply, term, State.t} |
         {:noreply, State.t} |
         {:async, sender, term, State.t} |
         {:stop, term, State.t}

   def handle_command({:riak_core_fold_req_v1, foldfun, acc0}, _sender, 
                              State[tab: tab, staging_tab: staging] = state) do
     acc = ETS.foldl(fn({k,v}, a) -> foldfun.(k, v, a) end, acc0, tab)
     acc = ETS.foldl(fn({k,v}, a) -> foldfun.({:s, k}, v, a) end, acc, staging)
     {:reply, acc, state}
   end         

   def handle_command({{key, _rev} = cell, new_rev, cmd, ref}, sender,
                      State[] = state) do
     {value, rev, txn_ref} = lookup_cell(cell, state)
     case cmd do
       {cmd_name, operation} when cmd_name in [:apply, :set] ->
         case apply_operation(operation, value) do
           :error -> 
             new_rev = rev
             new_value = @nil_value
           new_value ->  
            serialized = Genomu.Operation.serialize(operation)
            stage({key, new_rev}, serialized, new_value, state)
         end
       {:get = cmd_name, operation} ->
         case apply_operation(operation, value) do
           :error ->
             new_value = @nil_value
           new_value ->
             :ok
         end
     end
     case cmd_name do
       :apply ->
         VNode.reply(sender, {:ok, ref, state.partition, :ok})
       :get ->
         VNode.reply(sender, {:ok, ref, state.partition, {{new_value, rev}, txn_ref}})
       :set ->
         VNode.reply(sender, {:ok, ref, state.partition, {{new_value, new_rev}, txn_ref}})
     end
     {:noreply, state}
   end

   def handle_command({:C, clock, commit_object, entries, ref}, _sender, 
                      State[tab: tab, staging_tab: staging, commit_tab: commit_tab] = state) do
     lc {key, entry_clock} inlist entries do
       case ETS.lookup(tab, key) do
         [] -> history = []; value = @nil_value
         [{^key, {value, history}}] -> :ok
       end
       {MsgPack.Map[map: commit_object_dict], ""} = MsgPack.unpack(commit_object)
       MsgPack.Map[map: log] = commit_object_dict[CO.log]
       value =
       Enum.reduce(log, value,
                   fn({k, r}, v) ->
                     if k == key do
                       [{_, {_, serialized}}] = ETS.lookup(staging, {key, r})
                       {op, ""} = Genomu.Operation.deserialize(serialized)
                       nv = apply_operation(op, v)
                       ETS.insert(staging, {{key, r}, {nv, serialized}})
                       nv
                     else
                       v
                     end
                   end)
       ETS.insert(tab, {key, {value, [{entry_clock, clock}|history]}})
     end
     ETS.insert(commit_tab, {{:C, clock}, {commit_object, [clock]}})
     {:reply, {:ok, ref, state.partition, :ok}, state}
   end

   @spec handle_handoff_command(term, sender, State.t) ::
         {:reply, term, State.t} |
         {:noreply, State.t} |
         {:async, sender, term, State.t} |
         {:stop, term, State.t} |
         {:forward, State.t} |
         {:drop, State.t}
   def handle_handoff_command({:riak_core_fold_req_v1, _, _} = fold_req, sender, state) do
     handle_command(fold_req, sender, state)
   end
   def handle_handoff_command(_, _sender, State[] = state) do
     {:forward, state}
   end

   def handoff_starting(_target, State[] = state) do
     {true, state}
   end

   def handoff_cancelled(State[] = state), do: {:ok, state}

   def handoff_finished(_target, State[] = state), do: {:ok, state}

   def handle_handoff_data(data, State[tab: tab, staging_tab: staging] = state) do
     tab =
     case binary_to_term(data) do
       {{:s, key}, value} -> staging
       {key, value} -> tab
     end
     ETS.insert(tab, {key, value})
     {:reply, :ok, state}
   end

   def encode_handoff_item(key, value) do
     term_to_binary({key, value})
   end

   def is_empty(State[tab: tab] = state) do
     info = ETS.info(tab)
     {info[:size] == 0, state}
   end

   def delete(State[tab: tab] = state) do
     ETS.delete_all_objects(tab)
     {:ok, state}
   end

   def handle_coverage(_, _filter_vnodes, _sender, State[] = state) do
     {:reply, :done, state}
   end


   def handle_exit(_pid, _reason, State[] = state) do
     {:noreply, state}
   end

   def terminate(_, State[]) do
   end

   @spec lookup_cell(Genomu.cell, State.t) :: {term, ITC.t | term, ITC.t | term}
   defp lookup_cell({key, nil}, State[tab: tab]) do
     case ETS.lookup(tab, key) do
       [{^key, {value, [{clock, txn_clock}|_history]}}] -> {value, clock, txn_clock}
       _ -> {@nil_value, "", ""}
     end
   end
   defp lookup_cell({_key, rev} = cell, State[staging_tab: staging] = state) do
     case ETS.lookup(staging, cell) do
       [{^cell, {value, _serialized}}] -> {value, rev, rev}
       [] ->
         lookup_cell_txn(cell, state)
     end
   end

   defp lookup_cell_txn({key, rev}, State[tab: tab, staging_tab: staging]) do
     case ETS.lookup(tab, key) do
       [] ->
         {@nil_value, "", ""}
       [{_key, {value, [{entry_clock, ^rev}|_]}}] ->
         {value, entry_clock, rev}
       [{_key, {_, history}}] ->
         case Enum.find(history, fn({entry_clock, _}) -> 
                                                         entry_clock == rev or
                                                         ITC.decode(entry_clock) |>
                                                         ITC.le(ITC.decode(rev))
                                                     end) do
           {entry_clock, txn_rev} ->
             [{_, {value, _serialized}}] = ETS.lookup(staging, {key, entry_clock})
             {value, entry_clock, txn_rev}
           nil ->
             {@nil_value, "", ""}
         end
     end
   end


   @spec stage(Genomu.cell, Genomu.Operation.serialized, value :: term, State.t) :: State.t
   defp stage(cell, serialized, value, State[staging_tab: tab] = state) do
     ETS.insert(tab, {cell, {value, serialized}})
     state
   end

   defp apply_operation(operation, value) do
     try do
       Genomu.Operation.apply(operation, value)
     catch type, msg -> 
       Lager.error "Error #{inspect {type, msg}} occurred while processing operation #{inspect operation} on #{inspect value}"
       :error
     end
   end

 end