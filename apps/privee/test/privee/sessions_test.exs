defmodule Privee.SessionsTest do
  use Privee.DataCase

  alias Privee.Sessions

  import Privee.SessionsFixtures
  alias Privee.Sessions.{Session, SessionToken}

  describe "get_session_by_session_name_and_phrase/2" do
    test "does not return the session if the recovery phrase does not exist" do
      refute Sessions.get_session_by_session_name_and_phrase(
               "askdfjhlsakf-shkaldfhks",
               "The fox and the dog"
             )
    end

    test "does not return the session if the session_name is not valid" do
      session = session_fixture()
      refute Sessions.get_session_by_session_name_and_phrase(session.session_name, "invalid")
    end

    test "returns the session if the recovery phrase and session_name are valid" do
      %{id: id} = session = session_fixture()

      assert %Session{id: ^id} =
               Sessions.get_session_by_session_name_and_phrase(
                 session.session_name,
                 session_recovery_phrase()
               )
    end
  end

  describe "get_session!/1" do
    test "raises if id is invalid" do
      assert_raise Ecto.NoResultsError, fn ->
        Sessions.get_session!(-1)
      end
    end

    test "returns the session with the given id" do
      %{id: id} = session = session_fixture()
      assert %Session{id: ^id} = Sessions.get_session!(session.id)
    end
  end

  describe "register_session/1" do
    test "requires recovery_phrase and session_name to be set" do
      {:error, changeset} = Sessions.register_session(%{})

      assert %{
               session_name: ["can't be blank"],
               recovery_phrase: ["can't be blank"]
             } = errors_on(changeset)
    end

    test "validates recovery_phrase and session_name when given" do
      {:error, changeset} =
        Sessions.register_session(%{recovery_phrase: "not-valid", session_name: "not valid"})

      assert %{
               recovery_phrase: [
                 "must contain only alphabetic characters and punctuation",
                 "should be at least 24 character(s)"
               ],
               session_name: [
                 "must contain only alphanumeric characters and hyphens",
                 "should be at least 24 character(s)"
               ]
             } = errors_on(changeset)
    end

    test "validates maximum values for recovery_phrase and session_name for security" do
      too_long = String.duplicate("db", 100)

      {:error, changeset} =
        Sessions.register_session(%{recovery_phrase: too_long, session_name: too_long})

      assert "should be at most 160 character(s)" in errors_on(changeset).recovery_phrase
      assert "should be at most 72 character(s)" in errors_on(changeset).session_name
    end

    test "registers sessions with a hashed session_name" do
      session_name = unique_session_name()

      {:ok, session} =
        Sessions.register_session(valid_session_attributes(session_name: session_name))

      assert session.session_name == session_name
      assert is_binary(session.session_name)
      assert is_nil(session.recovery_phrase)
    end
  end

  describe "change_session_registration/2" do
    test "returns a changeset" do
      assert %Ecto.Changeset{} = changeset = Sessions.change_session_registration(%Session{})
      assert changeset.required == [:recovery_phrase, :session_name]
    end

    test "allows fields to be set" do
      recovery_phrase = session_recovery_phrase()
      session_name = unique_session_name()

      changeset =
        Sessions.change_session_registration(
          %Session{},
          valid_session_attributes(recovery_phrase: recovery_phrase, session_name: session_name)
        )

      assert changeset.valid?
      assert get_change(changeset, :session_name) == session_name
      assert get_change(changeset, :hashed_recovery_phrase)
    end
  end

  describe "generate_session_token/1" do
    setup do
      %{session: session_fixture()}
    end

    test "generates a token", %{session: session} do
      token = Sessions.generate_session_token(session)
      assert session_token = Repo.get_by(SessionToken, token: token)
      assert session_token.context == "session"

      IO.puts("Passing")

      # Creating the same token for another session should fail
      assert_raise Ecto.ConstraintError, fn ->
        Repo.insert!(%SessionToken{
          token: session_token.token,
          session_id: session_fixture(%{session_name: Ecto.UUID.generate()}).id,
          context: "session"
        })
      end
    end
  end

  describe "get_session_by_session_token/1" do
    setup do
      session = session_fixture()
      token = Sessions.generate_session_token(session)
      %{session: session, token: token}
    end

    test "returns session by token", %{session: session, token: token} do
      assert session_session = Sessions.get_session_by_session_token(token)
      assert session_session.id == session.id
    end

    test "does not return session for invalid token" do
      refute Sessions.get_session_by_session_token("oops")
    end

    test "does not return session for expired token", %{token: token} do
      {1, nil} = Repo.update_all(SessionToken, set: [inserted_at: ~N[2020-01-01 00:00:00]])
      refute Sessions.get_session_by_session_token(token)
    end
  end

  describe "delete_session_token/1" do
    test "deletes the token" do
      session = session_fixture()
      token = Sessions.generate_session_token(session)
      assert Sessions.delete_session_token(token) == :ok
      refute Sessions.get_session_by_session_token(token)
    end
  end

  describe "inspect/2 for the Session module" do
    test "does not include recovery_phrase" do
      recovery_phrase = "Some recovery phrase longer than twentyfour characters"

      refute inspect(%Session{recovery_phrase: recovery_phrase}) =~
               "session_name: \"#{recovery_phrase}\""
    end
  end
end
