defmodule Privee.PreKeyStore do
  @moduledoc """
  Manages Signal Protocol prekey bundles with database persistence.

  Each session registers a prekey bundle containing:
  - identity_key (public)
  - registration_id
  - signed_prekey (keyId, publicKey, signature)
  - one_time_prekeys (list of {keyId, publicKey})

  Bundles are stored in the sessions table (prekey_bundle column).
  One-time prekeys are consumed (popped) after being served.
  """

  alias Privee.Repo
  alias Privee.Sessions.Session
  import Ecto.Query

  @type prekey :: %{key_id: non_neg_integer(), public_key: String.t()}

  @type signed_prekey :: %{
          key_id: non_neg_integer(),
          public_key: String.t(),
          signature: String.t()
        }

  @type prekey_bundle :: %{
          identity_key: String.t(),
          registration_id: non_neg_integer(),
          signed_prekey: signed_prekey(),
          one_time_prekeys: list(prekey())
        }

  @doc """
  Registers a prekey bundle for a session. Persists to database.
  """
  @spec register_bundle(non_neg_integer(), prekey_bundle()) :: :ok
  def register_bundle(session_id, bundle) do
    normalized = normalize_bundle(bundle)
    persist_bundle(session_id, normalized)
    :ok
  end

  @doc """
  Gets the prekey bundle for a session, consuming one one-time prekey.
  Returns the bundle with a single one-time prekey (or none if exhausted).
  Uses a row lock to prevent race conditions on one-time prekey consumption.
  """
  @spec get_bundle(non_neg_integer()) :: {:ok, map()} | {:error, :not_found}
  def get_bundle(session_id) do
    Repo.transaction(fn ->
      query =
        from s in Session,
          where: s.id == ^session_id,
          select: s.prekey_bundle,
          lock: "FOR UPDATE"

      case Repo.one(query) do
        nil ->
          Repo.rollback(:not_found)

        bundle ->
          {one_time_prekey, remaining} = consume_one_time_prekey(bundle["one_time_prekeys"] || [])

          updated_bundle = Map.put(bundle, "one_time_prekeys", remaining)
          persist_bundle(session_id, updated_bundle)

          %{
            identity_key: bundle["identity_key"],
            registration_id: bundle["registration_id"],
            signed_prekey: atomize_keys(bundle["signed_prekey"]),
            one_time_prekey: atomize_keys(one_time_prekey)
          }
      end
    end)
  end

  @doc """
  Checks whether a prekey bundle exists for a given session.
  """
  @spec has_bundle?(non_neg_integer()) :: boolean()
  def has_bundle?(session_id) do
    query = from s in Session, where: s.id == ^session_id, select: s.prekey_bundle
    Repo.one(query) != nil
  end

  @doc """
  Removes the prekey bundle for a session.
  """
  @spec remove_bundle(non_neg_integer()) :: :ok
  def remove_bundle(session_id) do
    persist_bundle(session_id, nil)
    :ok
  end

  @doc """
  Replenishes one-time prekeys for a session.
  """
  @spec replenish_prekeys(non_neg_integer(), list(prekey())) :: :ok | {:error, :not_found}
  def replenish_prekeys(session_id, new_prekeys) do
    Repo.transaction(fn ->
      query =
        from s in Session,
          where: s.id == ^session_id,
          select: s.prekey_bundle,
          lock: "FOR UPDATE"

      case Repo.one(query) do
        nil ->
          Repo.rollback(:not_found)

        bundle ->
          existing = bundle["one_time_prekeys"] || []
          updated = Map.put(bundle, "one_time_prekeys", existing ++ stringify_keys(new_prekeys))
          persist_bundle(session_id, updated)
      end
    end)
    |> case do
      {:ok, _} -> :ok
      {:error, :not_found} -> {:error, :not_found}
    end
  end

  # Private helpers

  defp persist_bundle(session_id, bundle) do
    from(s in Session, where: s.id == ^session_id)
    |> Repo.update_all(set: [prekey_bundle: bundle])
  end

  defp consume_one_time_prekey([]), do: {nil, []}
  defp consume_one_time_prekey([first | rest]), do: {first, rest}

  defp atomize_keys(nil), do: nil

  defp atomize_keys(map) when is_map(map) do
    Map.new(map, fn {k, v} -> {String.to_atom(k), v} end)
  end

  defp stringify_keys(list) when is_list(list) do
    Enum.map(list, fn map ->
      Map.new(map, fn {k, v} -> {to_string(k), v} end)
    end)
  end

  defp normalize_bundle(bundle) do
    bundle
    |> Map.new(fn {k, v} -> {to_string(k), v} end)
    |> Map.update("signed_prekey", nil, fn
      nil -> nil
      spk -> Map.new(spk, fn {k, v} -> {to_string(k), v} end)
    end)
    |> Map.update("one_time_prekeys", [], fn
      nil -> []
      prekeys -> stringify_keys(prekeys)
    end)
  end
end
