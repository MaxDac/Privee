defmodule Privee.Chats do
  @moduledoc """
  Ephemeral, node-local storage for encrypted chat messages, implemented as plain
  functions over public ETS tables owned by `Privee.Chats.TableOwner`.

  Messages are grouped by conversation (the unordered pair of session ids) and by
  *epoch*. An epoch identifies one lifetime of a conversation: when the
  conversation expires (inactivity `ttl`, absolute `max_age`, or `max_messages`
  reached), it rotates to a new epoch and all messages of the previous epoch are
  dropped. Clients bind their Signal sessions to an epoch, so an expired
  conversation always restarts with a fresh PreKey message.

  History is held in memory on the local node only: it is lost on restart and is
  not shared across a cluster. Chat must therefore be served by a single node.

  ## Tables

    * `:chat_messages` (`ordered_set`) - `{{conv_key, epoch, seq}, inserted_at_ms, %Message{}}`
    * `:chat_conversations` (`set`) - `{conv_key, epoch, created_at_ms, last_at_ms, count}`
    * `:chat_nonces` (`set`) -
      `{{from, nonce}, state, conv_key, epoch, message_id, seq, owner_pid, claimed_at_ms}`

  `seq` values come from `System.unique_integer([:monotonic, :positive])`: they are
  node-global, restart after a node restart and are only meaningful within a
  `{conv_key, epoch}`. Do not replace them with a per-conversation counter.
  """

  alias Privee.Sessions.Message

  @messages :chat_messages
  @conversations :chat_conversations
  @nonces :chat_nonces

  @default_ttl_ms :timer.hours(24)
  @default_max_age_ms :timer.hours(24 * 7)
  @default_max_messages 1000
  @default_page_size 200
  @max_retries 3

  @type conv_key :: {non_neg_integer(), non_neg_integer()}
  @type epoch :: String.t()

  @doc false
  def create_tables do
    ensure_table(@messages, [:ordered_set, :public, :named_table, read_concurrency: true])
    ensure_table(@conversations, [:set, :public, :named_table, read_concurrency: true])
    ensure_table(@nonces, [:set, :public, :named_table])
    :ok
  end

  defp ensure_table(name, opts) do
    if :ets.whereis(name) == :undefined, do: :ets.new(name, opts)
  end

  @doc "Retention configuration, read from `config :privee, Privee.Chats`."
  def config do
    env = Application.get_env(:privee, __MODULE__, [])

    %{
      ttl_ms: Keyword.get(env, :ttl_ms, @default_ttl_ms),
      max_age_ms: Keyword.get(env, :max_age_ms, @default_max_age_ms),
      max_messages: Keyword.get(env, :max_messages, @default_max_messages)
    }
  end

  @doc "Returns the conversation key for two session ids."
  @spec conv_key(non_neg_integer(), non_neg_integer()) :: conv_key()
  def conv_key(a, b), do: {min(a, b), max(a, b)}

  @doc """
  Returns the current epoch of the conversation between `a` and `b`, creating the
  conversation or rotating it first if any retention predicate is met.
  """
  @spec open_conversation(non_neg_integer(), non_neg_integer(), integer()) ::
          {:ok, epoch()} | {:error, :unavailable}
  def open_conversation(a, b, now \\ now()) do
    if available?() do
      {:ok, do_open(conv_key(a, b), now, @max_retries)}
    else
      {:error, :unavailable}
    end
  end

  defp do_open(key, now, retries) do
    case :ets.lookup(@conversations, key) do
      [] ->
        epoch = new_epoch()

        if :ets.insert_new(@conversations, {key, epoch, now, now, 0}) or retries == 0 do
          epoch
        else
          do_open(key, now, retries - 1)
        end

      [{^key, epoch, _, _, _} = row] ->
        if expired?(row, now, config()) and retries > 0 do
          rotated = {key, new_epoch(), now, now, 0}

          case :ets.select_replace(@conversations, [{row, [], [{:const, rotated}]}]) do
            1 -> elem(rotated, 1)
            0 -> do_open(key, now, retries - 1)
          end
        else
          epoch
        end
    end
  end

  @doc "Returns the current epoch without creating or rotating the conversation."
  @spec current_epoch(non_neg_integer(), non_neg_integer()) :: epoch() | nil
  def current_epoch(a, b) do
    with true <- available?(),
         [{_, epoch, _, _, _}] <- :ets.lookup(@conversations, conv_key(a, b)) do
      epoch
    else
      _ -> nil
    end
  end

  @doc """
  Stores a message for the given `epoch`.

  `from`, `to`, `sender_session_name`, `type`, `body` and `client_nonce` must be
  set on the message; `id`, `seq` and `epoch` are assigned here.

  Returns:

    * `{:ok, message}` - stored; the caller should broadcast it.
    * `{:duplicate, message}` - the nonce was already committed; do not broadcast.
    * `{:error, {:stale_epoch, current_epoch}}` - the client must rebuild its session.
    * `{:error, :in_flight}` - another live process holds the nonce; retry later.
    * `{:error, :unavailable}` - storage is not running.
  """
  @spec create_message(Message.t(), epoch(), integer()) ::
          {:ok, Message.t()}
          | {:duplicate, Message.t()}
          | {:error, {:stale_epoch, epoch()} | :in_flight | :unavailable}
  def create_message(%Message{} = message, epoch, now \\ now()) do
    with true <- available?() || {:error, :unavailable},
         key = conv_key(message.from, message.to),
         current = do_open(key, now, @max_retries),
         true <- current == epoch || {:error, {:stale_epoch, current}} do
      claim_and_insert(message, key, epoch, now, @max_retries)
    end
  end

  defp claim_and_insert(_message, _key, _epoch, _now, -1), do: {:error, :in_flight}

  defp claim_and_insert(message, key, epoch, now, retries) do
    nonce_key = {message.from, message.client_nonce}
    claim = new_claim(nonce_key, key, epoch, now)

    if :ets.insert_new(@nonces, claim) do
      insert_claimed(message, claim, now)
    else
      case :ets.lookup(@nonces, nonce_key) do
        [] -> claim_and_insert(message, key, epoch, now, retries - 1)
        [existing] -> resolve_existing(message, existing, key, epoch, now, retries)
      end
    end
  end

  defp resolve_existing(message, existing, key, epoch, now, retries) do
    {nonce_key, state, c_key, c_epoch, _id, c_seq, owner, _at} = existing

    case {state, find_message(c_key, c_epoch, c_seq)} do
      {:committed, {:ok, stored}} ->
        {:duplicate, stored}

      {:committed, nil} ->
        :ets.delete_object(@nonces, existing)
        claim_and_insert(message, key, epoch, now, retries - 1)

      {:pending, found} ->
        cond do
          owner != self() and Process.alive?(owner) ->
            {:error, :in_flight}

          match?({:ok, _}, found) ->
            committed = put_elem(existing, 1, :committed)
            :ets.select_replace(@nonces, [{existing, [], [{:const, committed}]}])
            {:ok, stored} = found
            {:duplicate, stored}

          true ->
            reclaimed = new_claim(nonce_key, key, epoch, now)

            case :ets.select_replace(@nonces, [{existing, [], [{:const, reclaimed}]}]) do
              1 -> insert_claimed(message, reclaimed, now)
              0 -> claim_and_insert(message, key, epoch, now, retries - 1)
            end
        end
    end
  end

  defp insert_claimed(%Message{} = message, claim, now) do
    {nonce_key, :pending, key, epoch, id, seq, _owner, _at} = claim
    stored = %{message | id: id, seq: seq, epoch: epoch}

    :ets.insert(@messages, {{key, epoch, seq}, now, stored})
    touch_conversation(key, epoch, now)
    :ets.update_element(@nonces, nonce_key, {2, :committed})

    case current_epoch_for(key) do
      ^epoch ->
        {:ok, stored}

      current ->
        :ets.delete(@messages, {key, epoch, seq})
        :ets.delete(@nonces, nonce_key)
        {:error, {:stale_epoch, current}}
    end
  end

  defp touch_conversation(key, epoch, now) do
    # Only touch the row when it still belongs to our epoch.
    case :ets.lookup(@conversations, key) do
      [{^key, ^epoch, _, _, _}] ->
        :ets.update_element(@conversations, key, {4, now})
        :ets.update_counter(@conversations, key, {5, 1})

      _ ->
        :ok
    end
  rescue
    ArgumentError -> :ok
  end

  defp current_epoch_for(key) do
    case :ets.lookup(@conversations, key) do
      [{_, epoch, _, _, _}] -> epoch
      [] -> nil
    end
  end

  defp new_claim(nonce_key, key, epoch, now) do
    seq = System.unique_integer([:monotonic, :positive])
    {nonce_key, :pending, key, epoch, Ecto.UUID.generate(), seq, self(), now}
  end

  defp find_message(key, epoch, seq) do
    case :ets.lookup(@messages, {key, epoch, seq}) do
      [{_, _, message}] -> {:ok, message}
      [] -> nil
    end
  end

  @doc """
  Returns `{epoch, messages}` with the latest `limit` messages of the current epoch,
  in ascending order. Returns `{nil, []}` if there is no conversation.
  """
  @spec latest_messages(non_neg_integer(), non_neg_integer(), pos_integer()) ::
          {epoch() | nil, list(Message.t())}
  def latest_messages(a, b, limit \\ @default_page_size) do
    key = conv_key(a, b)

    case current_epoch(a, b) do
      nil ->
        {nil, []}

      epoch ->
        spec = [{{{key, epoch, :_}, :_, :"$1"}, [], [:"$1"]}]

        messages =
          case :ets.select_reverse(@messages, spec, limit) do
            {list, _cont} -> Enum.reverse(list)
            :"$end_of_table" -> []
          end

        {epoch, messages}
    end
  end

  @doc """
  Returns `{messages, next_cursor}` with up to `limit` messages of `epoch` whose
  `seq` is greater than `after_seq`, in ascending order. `next_cursor` is `nil`
  when there are no further pages.
  """
  @spec messages_after(non_neg_integer(), non_neg_integer(), epoch(), integer(), pos_integer()) ::
          {list(Message.t()), integer() | nil}
  def messages_after(a, b, epoch, after_seq, limit \\ @default_page_size) do
    if available?() do
      key = conv_key(a, b)
      spec = [{{{key, epoch, :"$1"}, :_, :"$2"}, [{:>, :"$1", after_seq}], [:"$2"]}]

      case :ets.select(@messages, spec, limit) do
        {list, _cont} when length(list) == limit -> {list, List.last(list).seq}
        {list, _cont} -> {list, nil}
        :"$end_of_table" -> {[], nil}
      end
    else
      {[], nil}
    end
  end

  @doc """
  Ends every conversation of `session_id`, deleting its messages.

  Called when the session resets its Signal identity: the peers' sessions are bound
  to the old identity, so their next send fails with `:stale_epoch` and they
  rebuild against the new bundle. History encrypted to the old identity could
  not be decrypted anymore and is dropped.
  """
  @spec end_conversations(non_neg_integer()) :: :ok
  def end_conversations(session_id) do
    if available?() do
      @conversations
      |> :ets.select([
        {{{:"$1", :"$2"}, :_, :_, :_, :_},
         [{:orelse, {:==, :"$1", session_id}, {:==, :"$2", session_id}}], [:"$_"]}
      ])
      |> Enum.each(fn {key, epoch, _, _, _} = row ->
        :ets.delete_object(@conversations, row)
        :ets.select_delete(@messages, [{{{key, epoch, :_}, :_, :_}, [], [true]}])
      end)
    end

    :ok
  end

  @doc """
  Deletes expired conversations, their messages and nonces, and abandoned claims.
  """
  def sweep(now \\ now()) do
    if available?() do
      cfg = config()

      @conversations
      |> :ets.tab2list()
      |> Enum.filter(&expired?(&1, now, cfg))
      |> Enum.each(&:ets.delete_object(@conversations, &1))

      @messages
      |> :ets.select([{{{:"$1", :"$2", :_}, :_, :_}, [], [{{:"$1", :"$2"}}]}])
      |> Enum.uniq()
      |> Enum.reject(&current_epoch?/1)
      |> Enum.each(fn {key, epoch} ->
        :ets.select_delete(@messages, [{{{key, epoch, :_}, :_, :_}, [], [true]}])
      end)

      @nonces
      |> :ets.tab2list()
      |> Enum.each(&sweep_nonce/1)
    end

    :ok
  end

  defp sweep_nonce({_, state, key, epoch, _id, seq, owner, _at} = row) do
    cond do
      not current_epoch?({key, epoch}) ->
        :ets.delete_object(@nonces, row)

      state == :pending and not Process.alive?(owner) ->
        # Reconcile before dropping: a message may exist without its commit mark.
        case find_message(key, epoch, seq) do
          {:ok, _} ->
            committed = put_elem(row, 1, :committed)
            :ets.select_replace(@nonces, [{row, [], [{:const, committed}]}])

          nil ->
            :ets.delete_object(@nonces, row)
        end

      true ->
        :ok
    end
  end

  # Checked per row at deletion time, so an epoch opened while the sweep runs is
  # never treated as orphaned. Epochs are unique and never reused.
  defp current_epoch?({key, epoch}) do
    match?([{^key, ^epoch, _, _, _}], :ets.lookup(@conversations, key))
  end

  defp expired?({_key, _epoch, created_at, last_at, count}, now, cfg) do
    now - last_at > cfg.ttl_ms or now - created_at > cfg.max_age_ms or
      count >= cfg.max_messages
  end

  defp available?, do: :ets.whereis(@messages) != :undefined

  defp new_epoch, do: Ecto.UUID.generate()

  defp now, do: System.system_time(:millisecond)
end
