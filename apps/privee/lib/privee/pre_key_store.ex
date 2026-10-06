defmodule Privee.PreKeyStore do
  @moduledoc """
  Stores the public Signal Protocol key material of each session.

  The bundle lives in the `sessions.prekey_bundle` jsonb column with string keys:

      %{
        "identity_key" => base64,        # 33 bytes, 0x05-prefixed Curve25519 key
        "registration_id" => 0..16383,
        "signed_prekey" => %{"key_id" => id, "public_key" => base64, "signature" => base64},
        "one_time_prekeys" => [%{"key_id" => id, "public_key" => base64}],
        "max_opk_id" => id               # highest one-time prekey id ever accepted
      }

  Invariants, enforced on every write:

    * all keys are valid Curve25519 public keys, signatures are 64 bytes;
    * one-time prekey ids are unique, positive and strictly greater than any id
      previously accepted for the current identity, so an id that has already been
      served can never be advertised again;
    * at most #{100} one-time prekeys are stored.

  Every operation runs in a single transaction holding a row lock.
  """

  import Ecto.Query

  alias Privee.Repo
  alias Privee.Sessions.Session

  @max_one_time_prekeys 100
  @max_key_id 0xFFFFFF
  @max_registration_id 0x3FFF

  @type public_bundle :: %{
          identity_key: String.t(),
          registration_id: non_neg_integer(),
          signed_prekey: %{key_id: pos_integer(), public_key: String.t(), signature: String.t()},
          one_time_prekey: %{key_id: pos_integer(), public_key: String.t()} | nil
        }

  @type error ::
          :not_found
          | :invalid_bundle
          | :already_published
          | :identity_mismatch
          | :stale_prekey_ids
          | :too_many_prekeys

  def max_one_time_prekeys, do: @max_one_time_prekeys

  @doc """
  Publishes the initial identity bundle. Fails with `:already_published` if the
  session already has a different identity; publishing the same identity again is
  a no-op.
  """
  @spec publish_identity(non_neg_integer(), map()) :: :ok | {:error, error()}
  def publish_identity(session_id, attrs) do
    with {:ok, %{"identity_key" => identity_key} = bundle} <- validate_full_bundle(attrs) do
      locked(session_id, fn
        nil ->
          {:write, bundle}

        %{"identity_key" => ^identity_key} ->
          :ok

        _other ->
          {:error, :already_published}
      end)
    end
  end

  @doc "Replaces the identity, signed prekey and one-time prekeys of the session."
  @spec reset_identity(non_neg_integer(), map()) :: :ok | {:error, error()}
  def reset_identity(session_id, attrs) do
    with {:ok, bundle} <- validate_full_bundle(attrs) do
      locked(session_id, fn _ -> {:write, bundle} end)
    end
  end

  @doc "Replaces the signed prekey, provided `identity_key` is the current identity."
  @spec rotate_signed_prekey(non_neg_integer(), String.t(), map()) :: :ok | {:error, error()}
  def rotate_signed_prekey(session_id, identity_key, attrs) do
    with {:ok, spk} <- validate_signed_prekey(attrs) do
      with_identity(session_id, identity_key, fn bundle ->
        {:write, Map.put(bundle, "signed_prekey", spk)}
      end)
    end
  end

  @doc """
  Appends one-time prekeys, provided `identity_key` is the current identity.
  Every id must be greater than any id previously accepted.
  """
  @spec add_one_time_prekeys(non_neg_integer(), String.t(), list()) :: :ok | {:error, error()}
  def add_one_time_prekeys(session_id, identity_key, prekeys) do
    with {:ok, new} <- validate_one_time_prekeys(prekeys) do
      with_identity(session_id, identity_key, &append_one_time_prekeys(&1, new))
    end
  end

  defp append_one_time_prekeys(bundle, new) do
    existing = bundle["one_time_prekeys"]
    max_id = bundle["max_opk_id"]

    cond do
      Enum.any?(new, &(&1["key_id"] <= max_id)) ->
        {:error, :stale_prekey_ids}

      length(existing) + length(new) > @max_one_time_prekeys ->
        {:error, :too_many_prekeys}

      true ->
        {:write,
         bundle
         |> Map.put("one_time_prekeys", existing ++ new)
         |> Map.put("max_opk_id", max_key_id(new, max_id))}
    end
  end

  @doc """
  Returns the public bundle of the session and the number of one-time prekeys left.
  When `pop_one_time_prekey` is true (default) one one-time prekey is removed and
  included in the bundle; it is never served again.
  """
  @spec fetch_bundle(non_neg_integer(), keyword()) ::
          {:ok, public_bundle(), non_neg_integer()} | {:error, :not_found}
  def fetch_bundle(session_id, opts \\ []) do
    pop? = Keyword.get(opts, :pop_one_time_prekey, true)

    Repo.transaction(fn ->
      case lock_bundle(session_id) do
        nil -> Repo.rollback(:not_found)
        bundle -> pop_one_time_prekey(session_id, bundle, pop?)
      end
    end)
    |> case do
      {:ok, {bundle, count}} -> {:ok, bundle, count}
      {:error, :not_found} -> {:error, :not_found}
    end
  end

  defp pop_one_time_prekey(session_id, bundle, pop?) do
    {opk, remaining} =
      case {pop?, bundle["one_time_prekeys"]} do
        {true, [first | rest]} -> {first, rest}
        {_, all} -> {nil, all}
      end

    if opk, do: persist(session_id, Map.put(bundle, "one_time_prekeys", remaining))

    {to_public(bundle, opk), length(remaining)}
  end

  @doc """
  Returns `%{identity_key, opk_count, max_opk_id}` for the session; all values are
  `nil`/0 without a bundle.
  """
  @spec status(non_neg_integer()) :: %{
          identity_key: String.t() | nil,
          opk_count: non_neg_integer(),
          max_opk_id: non_neg_integer()
        }
  def status(session_id) do
    case get_bundle(session_id) do
      nil ->
        %{identity_key: nil, opk_count: 0, max_opk_id: 0}

      bundle ->
        bundle = normalize_stored(bundle)

        %{
          identity_key: bundle["identity_key"],
          opk_count: length(bundle["one_time_prekeys"]),
          max_opk_id: bundle["max_opk_id"]
        }
    end
  end

  @doc "Returns the number of stored one-time prekeys, or `nil` without a bundle."
  @spec count_one_time_prekeys(non_neg_integer()) :: non_neg_integer() | nil
  def count_one_time_prekeys(session_id) do
    case get_bundle(session_id) do
      nil -> nil
      bundle -> length(bundle["one_time_prekeys"] || [])
    end
  end

  @doc "Returns the published identity key, or `nil`."
  @spec identity_key(non_neg_integer()) :: String.t() | nil
  def identity_key(session_id) do
    case get_bundle(session_id) do
      nil -> nil
      bundle -> bundle["identity_key"]
    end
  end

  @doc "Checks whether a bundle exists for the session."
  @spec has_bundle?(non_neg_integer()) :: boolean()
  def has_bundle?(session_id), do: get_bundle(session_id) != nil

  @doc "Removes the bundle of the session."
  @spec remove_bundle(non_neg_integer()) :: :ok
  def remove_bundle(session_id) do
    persist(session_id, nil)
    :ok
  end

  # Persistence

  defp get_bundle(session_id) do
    Repo.one(from s in Session, where: s.id == ^session_id, select: s.prekey_bundle)
  end

  defp lock_bundle(session_id) do
    Repo.one(
      from s in Session, where: s.id == ^session_id, select: s.prekey_bundle, lock: "FOR UPDATE"
    )
  end

  defp persist(session_id, bundle) do
    from(s in Session, where: s.id == ^session_id)
    |> Repo.update_all(set: [prekey_bundle: bundle])
  end

  # Runs `fun` with the locked current bundle (or nil). `fun` returns `{:write, bundle}`,
  # `:ok` or `{:error, reason}`. Missing sessions yield `{:error, :not_found}`.
  defp locked(session_id, fun) do
    Repo.transaction(fn ->
      current =
        case Repo.one(
               from s in Session,
                 where: s.id == ^session_id,
                 select: {s.id, s.prekey_bundle},
                 lock: "FOR UPDATE"
             ) do
          nil -> Repo.rollback(:not_found)
          {_id, bundle} -> bundle
        end

      case fun.(current) do
        {:write, bundle} -> persist(session_id, bundle)
        :ok -> :ok
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
    |> case do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp with_identity(session_id, identity_key, fun) do
    locked(session_id, fn
      nil -> {:error, :not_found}
      %{"identity_key" => ^identity_key} = bundle -> fun.(normalize_stored(bundle))
      _ -> {:error, :identity_mismatch}
    end)
  end

  defp normalize_stored(bundle) do
    bundle
    |> Map.put_new("one_time_prekeys", [])
    |> Map.update("max_opk_id", max_key_id(bundle["one_time_prekeys"] || [], 0), & &1)
  end

  defp to_public(bundle, opk) do
    spk = bundle["signed_prekey"]

    %{
      identity_key: bundle["identity_key"],
      registration_id: bundle["registration_id"],
      signed_prekey: %{
        key_id: spk["key_id"],
        public_key: spk["public_key"],
        signature: spk["signature"]
      },
      one_time_prekey: opk && %{key_id: opk["key_id"], public_key: opk["public_key"]}
    }
  end

  defp max_key_id(prekeys, initial) do
    Enum.reduce(prekeys, initial, &max(&1["key_id"], &2))
  end

  # Validation

  defp validate_full_bundle(%{} = attrs) do
    with {:ok, identity_key} <- validate_public_key(field(attrs, "identity_key")),
         {:ok, registration_id} <- validate_registration_id(field(attrs, "registration_id")),
         {:ok, spk} <- validate_signed_prekey(field(attrs, "signed_prekey")),
         {:ok, opks} <- validate_one_time_prekeys(field(attrs, "one_time_prekeys") || []) do
      {:ok,
       %{
         "identity_key" => identity_key,
         "registration_id" => registration_id,
         "signed_prekey" => spk,
         "one_time_prekeys" => opks,
         "max_opk_id" => max_key_id(opks, 0)
       }}
    end
  end

  defp validate_full_bundle(_), do: {:error, :invalid_bundle}

  defp validate_signed_prekey(%{} = attrs) do
    with {:ok, key_id} <- validate_key_id(field(attrs, "key_id")),
         {:ok, public_key} <- validate_public_key(field(attrs, "public_key")),
         {:ok, signature} <- validate_signature(field(attrs, "signature")) do
      {:ok, %{"key_id" => key_id, "public_key" => public_key, "signature" => signature}}
    end
  end

  defp validate_signed_prekey(_), do: {:error, :invalid_bundle}

  defp validate_one_time_prekeys(prekeys) when is_list(prekeys) do
    if length(prekeys) > @max_one_time_prekeys do
      {:error, :too_many_prekeys}
    else
      with {:ok, valid} <- validate_each_one_time_prekey(prekeys) do
        ensure_unique_key_ids(valid)
      end
    end
  end

  defp validate_one_time_prekeys(_), do: {:error, :invalid_bundle}

  defp validate_each_one_time_prekey(prekeys) do
    prekeys
    |> Enum.reduce_while({:ok, []}, fn prekey, {:ok, acc} ->
      case validate_one_time_prekey(prekey) do
        {:ok, valid} -> {:cont, {:ok, [valid | acc]}}
        error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, valid} -> {:ok, Enum.reverse(valid)}
      error -> error
    end
  end

  defp ensure_unique_key_ids(valid) do
    ids = Enum.map(valid, & &1["key_id"])
    if Enum.uniq(ids) == ids, do: {:ok, valid}, else: {:error, :invalid_bundle}
  end

  defp validate_one_time_prekey(%{} = attrs) do
    with {:ok, key_id} <- validate_key_id(field(attrs, "key_id")),
         {:ok, public_key} <- validate_public_key(field(attrs, "public_key")) do
      {:ok, %{"key_id" => key_id, "public_key" => public_key}}
    end
  end

  defp validate_one_time_prekey(_), do: {:error, :invalid_bundle}

  defp validate_public_key(value) do
    case decode(value) do
      {:ok, <<5, _::binary-size(32)>>} -> {:ok, value}
      _ -> {:error, :invalid_bundle}
    end
  end

  defp validate_signature(value) do
    case decode(value) do
      {:ok, <<_::binary-size(64)>>} -> {:ok, value}
      _ -> {:error, :invalid_bundle}
    end
  end

  defp validate_key_id(id) when is_integer(id) and id >= 1 and id <= @max_key_id, do: {:ok, id}
  defp validate_key_id(_), do: {:error, :invalid_bundle}

  defp validate_registration_id(id)
       when is_integer(id) and id >= 0 and id <= @max_registration_id,
       do: {:ok, id}

  defp validate_registration_id(_), do: {:error, :invalid_bundle}

  defp decode(value) when is_binary(value) and byte_size(value) <= 128, do: Base.decode64(value)
  defp decode(_), do: :error

  # Accepts string or atom keys without creating atoms.
  defp field(map, key) do
    case Map.fetch(map, key) do
      {:ok, value} -> value
      :error -> Map.get(map, String.to_existing_atom(key))
    end
  end
end
