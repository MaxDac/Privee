defmodule Privee.Sessions.JanitorTest do
  use Privee.DataCase, async: true

  import Privee.SessionsFixtures

  alias Privee.Sessions
  alias Privee.Sessions.{Janitor, Session, SessionToken}

  defp days_ago(days) do
    NaiveDateTime.utc_now()
    |> NaiveDateTime.add(-days * 86_400)
    |> NaiveDateTime.truncate(:second)
  end

  defp age_session(session, days) do
    Repo.update_all(from(s in Session, where: s.id == ^session.id),
      set: [inserted_at: days_ago(days), updated_at: days_ago(days)]
    )

    session
  end

  defp token(session, days) do
    token = Sessions.generate_session_token(session)

    Repo.update_all(from(t in SessionToken, where: t.token == ^token),
      set: [inserted_at: days_ago(days)]
    )

    Repo.update_all(from(s in Session, where: s.id == ^session.id),
      set: [last_used_at: days_ago(days)]
    )

    token
  end

  defp new_name, do: generate_new_unique_session_name()

  defp exists?(session), do: Repo.get(Session, session.id) != nil

  test "deletes only expired tokens" do
    session = session_fixture()
    expired = token(session, 61)
    valid = token(session, 59)

    assert Sessions.delete_expired_session_tokens() == 1
    refute Repo.get_by(SessionToken, token: expired)
    assert Sessions.get_session_by_session_token(valid)
  end

  test "deletes sessions without a recent sign-in" do
    never_signed_in = session_fixture(%{session_name: new_name()}) |> age_session(100)
    stale = session_fixture(%{session_name: new_name()}) |> age_session(200)
    token(stale, 95)
    recent = session_fixture(%{session_name: new_name()}) |> age_session(200)
    token(recent, 30)
    young = session_fixture(%{session_name: new_name()}) |> age_session(10)

    assert Sessions.delete_unused_sessions(90) == 2
    refute exists?(never_signed_in)
    refute exists?(stale)
    assert exists?(recent)
    assert exists?(young)
  end

  test "deletes quick sessions that can no longer be used" do
    unused = quick_session_fixture(%{session_name: new_name()}) |> age_session(2)
    expired = quick_session_fixture(%{session_name: new_name()}) |> age_session(70)
    token(expired, 61)
    signed_in = quick_session_fixture(%{session_name: new_name()}) |> age_session(2)
    token(signed_in, 1)
    new = quick_session_fixture(%{session_name: new_name()})

    assert Sessions.delete_unused_sessions(90) == 2
    refute exists?(unused)
    refute exists?(expired)
    assert exists?(signed_in)
    assert exists?(new)
  end

  test "never deletes a session with a valid token, whatever the retention" do
    session = session_fixture() |> age_session(200)
    token(session, 50)

    assert Sessions.delete_unused_sessions(1) == 0
    assert exists?(session)
  end

  test "run/1 removes tokens and sessions" do
    session = session_fixture() |> age_session(200)
    token(session, 100)

    assert Janitor.run(90) == {1, 1}
    refute exists?(session)
  end

  test "run/1 keeps a session whose expired token was deleted within the retention" do
    session = session_fixture() |> age_session(200)
    token(session, 61)

    assert Janitor.run(90) == {1, 0}
    assert exists?(session)
  end

  test "logging out does not make a recently used session deletable" do
    session = session_fixture() |> age_session(200)
    session |> token(1) |> Sessions.delete_session_token()

    assert Janitor.run(90) == {0, 0}
    assert exists?(session)
  end

  test "signing in records last_used_at" do
    session = session_fixture() |> age_session(200)
    assert is_nil(Repo.get!(Session, session.id).last_used_at)

    Sessions.generate_session_token(session)

    assert %NaiveDateTime{} = Repo.get!(Session, session.id).last_used_at
    assert Sessions.delete_unused_sessions(90) == 0
  end

  test "deleting a session removes its tokens, push endpoints and keys" do
    session = session_fixture() |> age_session(200)
    token = token(session, 100)
    :ok = Privee.Push.register_endpoint(token, "https://push.example.com/up/abc")

    Repo.update_all(from(s in Session, where: s.id == ^session.id),
      set: [prekey_bundle: %{"identity_key" => "pub"}]
    )

    assert Sessions.delete_unused_sessions(90) == 1
    refute exists?(session)
    assert Repo.aggregate(Privee.Push.PushEndpoint, :count) == 0

    assert Repo.aggregate(from(t in SessionToken, where: t.session_id == ^session.id), :count) ==
             0
  end

  test "the job can be disabled" do
    pid = start_supervised!({Janitor, name: :janitor_test, interval_ms: :infinity})
    assert Process.alive?(pid)
  end
end
