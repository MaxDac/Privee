defmodule Privee.PreKeyFixtures do
  @moduledoc """
  Structurally valid (not cryptographically valid) Signal key material.
  """

  def public_key, do: Base.encode64(<<5>> <> :crypto.strong_rand_bytes(32))

  def kyber_public_key, do: Base.encode64(<<8>> <> :crypto.strong_rand_bytes(1568))

  def signature, do: Base.encode64(:crypto.strong_rand_bytes(64))

  def kyber_prekey(key_id \\ 1),
    do: %{"key_id" => key_id, "public_key" => kyber_public_key(), "signature" => signature()}

  def one_time_prekeys(ids), do: Enum.map(ids, &%{"key_id" => &1, "public_key" => public_key()})

  def bundle_attrs(opts \\ []) do
    %{
      "identity_key" => Keyword.get_lazy(opts, :identity_key, &public_key/0),
      "registration_id" => 1234,
      "signed_prekey" => %{
        "key_id" => 1,
        "public_key" => public_key(),
        "signature" => signature()
      },
      "kyber_prekey" => kyber_prekey(),
      "one_time_prekeys" => one_time_prekeys(Keyword.get(opts, :opk_ids, 1..3))
    }
  end
end
