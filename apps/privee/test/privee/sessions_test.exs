defmodule Privee.SessionsTest do
  use Privee.DataCase

  import Privee.SessionsFixtures

  alias Privee.Sessions
  alias Privee.Sessions.{PriveeForm, Session, SessionToken}

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

  describe "get_session/1" do
    test "returns nil if id is invalid" do
      assert is_nil(Sessions.get_session(-1))
    end

    test "returns the session with the given id" do
      %{id: id} = session = session_fixture()
      assert %Session{id: ^id} = Sessions.get_session(session.id)
    end
  end

  describe "get_session_by_session_name/1" do
    test "returns nil if id is invalid" do
      assert is_nil(Sessions.get_session_by_session_name("non-existent-session-name"))
    end

    test "returns the session with the given id" do
      %{session_name: session_name} = session_fixture()

      assert %Session{session_name: ^session_name} =
               Sessions.get_session_by_session_name(session_name)
    end
  end

  describe "generate_new_available_session_name/0" do
    test "generates a new session name" do
      assert session_name = Sessions.generate_new_available_session_name()
      assert String.match?(session_name, ~r/^[a-z0-9-]{24,72}$/)
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

    test "registers quick sessions without recovery phrase" do
      session_name = unique_session_name()

      {:ok, session} =
        Sessions.register_session(%{
          session_name: session_name,
          public_key: default_public_key(),
          is_quick: true
        })

      assert session.session_name == session_name
      assert session.is_quick == true
      assert is_nil(session.recovery_phrase)
      assert is_nil(session.hashed_recovery_phrase)
    end

    test "validates that quick sessions have empty recovery phrase" do
      session_name = unique_session_name()

      {:error, changeset} =
        Sessions.register_session(%{
          session_name: session_name,
          recovery_phrase: "Some recovery phrase here",
          public_key: default_public_key(),
          is_quick: true
        })

      assert %{
               recovery_phrase: ["must be empty for quick sessions"]
             } = errors_on(changeset)
    end

    test "validates that non-quick sessions require recovery phrase" do
      session_name = unique_session_name()

      {:error, changeset} =
        Sessions.register_session(%{
          session_name: session_name,
          public_key: default_public_key(),
          is_quick: false
        })

      assert %{
               recovery_phrase: ["can't be blank"]
             } = errors_on(changeset)
    end

    test "retrieves quick sessions by session name" do
      quick_session = quick_session_fixture()
      retrieved_session = Sessions.get_session_by_session_name(quick_session.session_name)

      assert retrieved_session.id == quick_session.id
      assert retrieved_session.is_quick == true
      assert is_nil(retrieved_session.hashed_recovery_phrase)
    end

    test "quick sessions cannot be retrieved by recovery phrase" do
      quick_session = quick_session_fixture()

      # Quick sessions should not be retrievable by recovery phrase since they don't have one
      refute Sessions.get_session_by_session_name_and_phrase(
               quick_session.session_name,
               "any recovery phrase"
             )
    end

    test "validates that empty string recovery phrase is allowed for quick sessions" do
      session_name = unique_session_name()

      {:ok, session} =
        Sessions.register_session(%{
          session_name: session_name,
          recovery_phrase: "",
          public_key: default_public_key(),
          is_quick: true
        })

      assert session.session_name == session_name
      assert session.is_quick == true
      assert is_nil(session.recovery_phrase)
      assert is_nil(session.hashed_recovery_phrase)
    end
  end

  describe "change_session_registration/2" do
    test "returns a changeset" do
      assert %Ecto.Changeset{} = changeset = Sessions.change_session_registration(%Session{})
      assert changeset.required == [:public_key, :recovery_phrase, :session_name]
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
      assert get_change(changeset, :recovery_phrase) == recovery_phrase
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

  describe "change_privee_form/2" do
    setup do
      session = session_fixture()
      %{session: session}
    end

    test " identifies an invalid session name" do
      invalid_session_name = "some invalid session name"

      changeset =
        Sessions.change_privee_form(%PriveeForm{}, %{"session_name" => invalid_session_name})

      refute changeset.valid?

      assert Enum.any?(
               errors_on(changeset).session_name,
               &(&1 == "must contain only alphanumeric characters and hyphens")
             )
    end

    test " identifies an non existent session name" do
      invalid_session_name = "non-existent-session-name"

      changeset =
        Sessions.change_privee_form(%PriveeForm{}, %{"session_name" => invalid_session_name})

      refute changeset.valid?

      assert Enum.any?(
               errors_on(changeset).session_name,
               &(&1 == "The session name does not exist")
             )
    end

    test " identifies an existent session name", %{session: %{session_name: session_name}} do
      changeset = Sessions.change_privee_form(%PriveeForm{}, %{"session_name" => session_name})

      assert changeset.valid?
    end
  end

  describe "mark_session_as_logged/1" do
    test "returns error for session without id" do
      # Sessions without id cannot be marked as logged
      session_map = %{is_logged: false, session_name: "test"}

      assert {:error, "Invalid session"} = Sessions.mark_session_as_logged(session_map)
    end

    test "marks a session as logged when it has an id" do
      session = session_fixture(%{has_logged: false})

      {:ok, updated_session} = Sessions.mark_session_as_logged(session)

      assert updated_session.has_logged == true
      assert updated_session.id == session.id
    end

    test "marks a quick session as logged" do
      quick_session = quick_session_fixture(%{has_logged: false})
      assert quick_session.has_logged == false
      assert quick_session.is_quick == true

      {:ok, updated_session} = Sessions.mark_session_as_logged(quick_session)

      assert updated_session.has_logged == true
      assert updated_session.is_quick == true
      assert updated_session.id == quick_session.id
    end

    test "marks session as logged even when already logged" do
      session = session_fixture(%{has_logged: true})
      assert session.has_logged == true

      {:ok, updated_session} = Sessions.mark_session_as_logged(session)

      assert updated_session.has_logged == true
      assert updated_session.id == session.id
    end

    test "returns error for nil input" do
      assert {:error, "Invalid session"} = Sessions.mark_session_as_logged(nil)
    end

    test "returns error for empty map" do
      assert {:error, "Invalid session"} = Sessions.mark_session_as_logged(%{})
    end

    test "returns error for string input" do
      assert {:error, "Invalid session"} = Sessions.mark_session_as_logged("invalid")
    end

    test "returns error for map without id and without is_logged field" do
      session_without_required_fields = %{session_name: "test", has_logged: false}

      assert {:error, "Invalid session"} =
               Sessions.mark_session_as_logged(session_without_required_fields)
    end

    test "handles database constraint errors" do
      # Create a session and then manually delete it from DB to cause update error
      session = session_fixture()
      Repo.delete!(session)

      # Should raise StaleEntryError when trying to update non-existent record
      assert_raise Ecto.StaleEntryError, fn ->
        Sessions.mark_session_as_logged(session)
      end
    end
  end

  describe "is_session_valid/1" do
    test "returns false for quick session that has already logged" do
      session = %{is_quick: true, has_logged: true}

      refute Sessions.is_session_valid(session)
    end

    test "returns true for quick session that has not logged" do
      session = %{is_quick: true, has_logged: false}

      assert Sessions.is_session_valid(session)
    end

    test "returns true for regular session that has logged" do
      session = %{is_quick: false, has_logged: true}

      assert Sessions.is_session_valid(session)
    end

    test "returns true for regular session that has not logged" do
      session = %{is_quick: false, has_logged: false}

      assert Sessions.is_session_valid(session)
    end

    test "returns true for session without is_quick field" do
      session = %{has_logged: true}

      assert Sessions.is_session_valid(session)
    end

    test "returns true for session without has_logged field" do
      session = %{is_quick: true}

      assert Sessions.is_session_valid(session)
    end

    test "returns true for empty map" do
      session = %{}

      assert Sessions.is_session_valid(session)
    end

    test "returns true for nil" do
      assert Sessions.is_session_valid(nil)
    end

    test "full workflow: quick session becomes invalid after being marked as logged" do
      # Create a new quick session
      quick_session = quick_session_fixture(%{has_logged: false})

      # Initially the session should be valid
      assert Sessions.is_session_valid(quick_session)
      assert quick_session.is_quick == true
      assert quick_session.has_logged == false

      # Mark the session as logged
      {:ok, updated_session} = Sessions.mark_session_as_logged(quick_session)

      # Verify it was marked as logged
      assert updated_session.has_logged == true
      assert updated_session.is_quick == true

      # Now the session should be invalid
      refute Sessions.is_session_valid(updated_session)
    end
  end
end
