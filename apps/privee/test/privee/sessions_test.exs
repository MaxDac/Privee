defmodule Privee.SessionsTest do
  use Privee.DataCase

  alias Privee.Sessions

  import Privee.SessionsFixtures
  alias Privee.Sessions.{Session, SessionToken}

  describe "get_session_by_email/1" do
    test "does not return the session if the email does not exist" do
      refute Sessions.get_session_by_email("unknown@example.com")
    end

    test "returns the session if the email exists" do
      %{id: id} = session = session_fixture()
      assert %Session{id: ^id} = Sessions.get_session_by_email(session.email)
    end
  end

  describe "get_session_by_email_and_password/2" do
    test "does not return the session if the email does not exist" do
      refute Sessions.get_session_by_email_and_password("unknown@example.com", "hello world!")
    end

    test "does not return the session if the password is not valid" do
      session = session_fixture()
      refute Sessions.get_session_by_email_and_password(session.email, "invalid")
    end

    test "returns the session if the email and password are valid" do
      %{id: id} = session = session_fixture()

      assert %Session{id: ^id} =
               Sessions.get_session_by_email_and_password(session.email, valid_session_password())
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
    test "requires email and password to be set" do
      {:error, changeset} = Sessions.register_session(%{})

      assert %{
               password: ["can't be blank"],
               email: ["can't be blank"]
             } = errors_on(changeset)
    end

    test "validates email and password when given" do
      {:error, changeset} = Sessions.register_session(%{email: "not valid", password: "not valid"})

      assert %{
               email: ["must have the @ sign and no spaces"],
               password: ["should be at least 12 character(s)"]
             } = errors_on(changeset)
    end

    test "validates maximum values for email and password for security" do
      too_long = String.duplicate("db", 100)
      {:error, changeset} = Sessions.register_session(%{email: too_long, password: too_long})
      assert "should be at most 160 character(s)" in errors_on(changeset).email
      assert "should be at most 72 character(s)" in errors_on(changeset).password
    end

    test "validates email uniqueness" do
      %{email: email} = session_fixture()
      {:error, changeset} = Sessions.register_session(%{email: email})
      assert "has already been taken" in errors_on(changeset).email

      # Now try with the upper cased email too, to check that email case is ignored.
      {:error, changeset} = Sessions.register_session(%{email: String.upcase(email)})
      assert "has already been taken" in errors_on(changeset).email
    end

    test "registers sessions with a hashed password" do
      email = unique_session_email()
      {:ok, session} = Sessions.register_session(valid_session_attributes(email: email))
      assert session.email == email
      assert is_binary(session.hashed_password)
      assert is_nil(session.confirmed_at)
      assert is_nil(session.password)
    end
  end

  describe "change_session_registration/2" do
    test "returns a changeset" do
      assert %Ecto.Changeset{} = changeset = Sessions.change_session_registration(%Session{})
      assert changeset.required == [:password, :email]
    end

    test "allows fields to be set" do
      email = unique_session_email()
      password = valid_session_password()

      changeset =
        Sessions.change_session_registration(
          %Session{},
          valid_session_attributes(email: email, password: password)
        )

      assert changeset.valid?
      assert get_change(changeset, :email) == email
      assert get_change(changeset, :password) == password
      assert is_nil(get_change(changeset, :hashed_password))
    end
  end

  describe "change_session_email/2" do
    test "returns a session changeset" do
      assert %Ecto.Changeset{} = changeset = Sessions.change_session_email(%Session{})
      assert changeset.required == [:email]
    end
  end

  describe "apply_session_email/3" do
    setup do
      %{session: session_fixture()}
    end

    test "requires email to change", %{session: session} do
      {:error, changeset} = Sessions.apply_session_email(session, valid_session_password(), %{})
      assert %{email: ["did not change"]} = errors_on(changeset)
    end

    test "validates email", %{session: session} do
      {:error, changeset} =
        Sessions.apply_session_email(session, valid_session_password(), %{email: "not valid"})

      assert %{email: ["must have the @ sign and no spaces"]} = errors_on(changeset)
    end

    test "validates maximum value for email for security", %{session: session} do
      too_long = String.duplicate("db", 100)

      {:error, changeset} =
        Sessions.apply_session_email(session, valid_session_password(), %{email: too_long})

      assert "should be at most 160 character(s)" in errors_on(changeset).email
    end

    test "validates email uniqueness", %{session: session} do
      %{email: email} = session_fixture()
      password = valid_session_password()

      {:error, changeset} = Sessions.apply_session_email(session, password, %{email: email})

      assert "has already been taken" in errors_on(changeset).email
    end

    test "validates current password", %{session: session} do
      {:error, changeset} =
        Sessions.apply_session_email(session, "invalid", %{email: unique_session_email()})

      assert %{current_password: ["is not valid"]} = errors_on(changeset)
    end

    test "applies the email without persisting it", %{session: session} do
      email = unique_session_email()
      {:ok, session} = Sessions.apply_session_email(session, valid_session_password(), %{email: email})
      assert session.email == email
      assert Sessions.get_session!(session.id).email != email
    end
  end

  describe "deliver_session_update_email_instructions/3" do
    setup do
      %{session: session_fixture()}
    end

    test "sends token through notification", %{session: session} do
      token =
        extract_session_token(fn url ->
          Sessions.deliver_session_update_email_instructions(session, "current@example.com", url)
        end)

      {:ok, token} = Base.url_decode64(token, padding: false)
      assert session_token = Repo.get_by(SessionToken, token: :crypto.hash(:sha256, token))
      assert session_token.session_id == session.id
      assert session_token.sent_to == session.email
      assert session_token.context == "change:current@example.com"
    end
  end

  describe "update_session_email/2" do
    setup do
      session = session_fixture()
      email = unique_session_email()

      token =
        extract_session_token(fn url ->
          Sessions.deliver_session_update_email_instructions(%{session | email: email}, session.email, url)
        end)

      %{session: session, token: token, email: email}
    end

    test "updates the email with a valid token", %{session: session, token: token, email: email} do
      assert Sessions.update_session_email(session, token) == :ok
      changed_session = Repo.get!(Session, session.id)
      assert changed_session.email != session.email
      assert changed_session.email == email
      assert changed_session.confirmed_at
      assert changed_session.confirmed_at != session.confirmed_at
      refute Repo.get_by(SessionToken, session_id: session.id)
    end

    test "does not update email with invalid token", %{session: session} do
      assert Sessions.update_session_email(session, "oops") == :error
      assert Repo.get!(Session, session.id).email == session.email
      assert Repo.get_by(SessionToken, session_id: session.id)
    end

    test "does not update email if session email changed", %{session: session, token: token} do
      assert Sessions.update_session_email(%{session | email: "current@example.com"}, token) == :error
      assert Repo.get!(Session, session.id).email == session.email
      assert Repo.get_by(SessionToken, session_id: session.id)
    end

    test "does not update email if token expired", %{session: session, token: token} do
      {1, nil} = Repo.update_all(SessionToken, set: [inserted_at: ~N[2020-01-01 00:00:00]])
      assert Sessions.update_session_email(session, token) == :error
      assert Repo.get!(Session, session.id).email == session.email
      assert Repo.get_by(SessionToken, session_id: session.id)
    end
  end

  describe "change_session_password/2" do
    test "returns a session changeset" do
      assert %Ecto.Changeset{} = changeset = Sessions.change_session_password(%Session{})
      assert changeset.required == [:password]
    end

    test "allows fields to be set" do
      changeset =
        Sessions.change_session_password(%Session{}, %{
          "password" => "new valid password"
        })

      assert changeset.valid?
      assert get_change(changeset, :password) == "new valid password"
      assert is_nil(get_change(changeset, :hashed_password))
    end
  end

  describe "update_session_password/3" do
    setup do
      %{session: session_fixture()}
    end

    test "validates password", %{session: session} do
      {:error, changeset} =
        Sessions.update_session_password(session, valid_session_password(), %{
          password: "not valid",
          password_confirmation: "another"
        })

      assert %{
               password: ["should be at least 12 character(s)"],
               password_confirmation: ["does not match password"]
             } = errors_on(changeset)
    end

    test "validates maximum values for password for security", %{session: session} do
      too_long = String.duplicate("db", 100)

      {:error, changeset} =
        Sessions.update_session_password(session, valid_session_password(), %{password: too_long})

      assert "should be at most 72 character(s)" in errors_on(changeset).password
    end

    test "validates current password", %{session: session} do
      {:error, changeset} =
        Sessions.update_session_password(session, "invalid", %{password: valid_session_password()})

      assert %{current_password: ["is not valid"]} = errors_on(changeset)
    end

    test "updates the password", %{session: session} do
      {:ok, session} =
        Sessions.update_session_password(session, valid_session_password(), %{
          password: "new valid password"
        })

      assert is_nil(session.password)
      assert Sessions.get_session_by_email_and_password(session.email, "new valid password")
    end

    test "deletes all tokens for the given session", %{session: session} do
      _ = Sessions.generate_session_session_token(session)

      {:ok, _} =
        Sessions.update_session_password(session, valid_session_password(), %{
          password: "new valid password"
        })

      refute Repo.get_by(SessionToken, session_id: session.id)
    end
  end

  describe "generate_session_session_token/1" do
    setup do
      %{session: session_fixture()}
    end

    test "generates a token", %{session: session} do
      token = Sessions.generate_session_session_token(session)
      assert session_token = Repo.get_by(SessionToken, token: token)
      assert session_token.context == "session"

      # Creating the same token for another session should fail
      assert_raise Ecto.ConstraintError, fn ->
        Repo.insert!(%SessionToken{
          token: session_token.token,
          session_id: session_fixture().id,
          context: "session"
        })
      end
    end
  end

  describe "get_session_by_session_token/1" do
    setup do
      session = session_fixture()
      token = Sessions.generate_session_session_token(session)
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

  describe "delete_session_session_token/1" do
    test "deletes the token" do
      session = session_fixture()
      token = Sessions.generate_session_session_token(session)
      assert Sessions.delete_session_session_token(token) == :ok
      refute Sessions.get_session_by_session_token(token)
    end
  end

  describe "deliver_session_confirmation_instructions/2" do
    setup do
      %{session: session_fixture()}
    end

    test "sends token through notification", %{session: session} do
      token =
        extract_session_token(fn url ->
          Sessions.deliver_session_confirmation_instructions(session, url)
        end)

      {:ok, token} = Base.url_decode64(token, padding: false)
      assert session_token = Repo.get_by(SessionToken, token: :crypto.hash(:sha256, token))
      assert session_token.session_id == session.id
      assert session_token.sent_to == session.email
      assert session_token.context == "confirm"
    end
  end

  describe "confirm_session/1" do
    setup do
      session = session_fixture()

      token =
        extract_session_token(fn url ->
          Sessions.deliver_session_confirmation_instructions(session, url)
        end)

      %{session: session, token: token}
    end

    test "confirms the email with a valid token", %{session: session, token: token} do
      assert {:ok, confirmed_session} = Sessions.confirm_session(token)
      assert confirmed_session.confirmed_at
      assert confirmed_session.confirmed_at != session.confirmed_at
      assert Repo.get!(Session, session.id).confirmed_at
      refute Repo.get_by(SessionToken, session_id: session.id)
    end

    test "does not confirm with invalid token", %{session: session} do
      assert Sessions.confirm_session("oops") == :error
      refute Repo.get!(Session, session.id).confirmed_at
      assert Repo.get_by(SessionToken, session_id: session.id)
    end

    test "does not confirm email if token expired", %{session: session, token: token} do
      {1, nil} = Repo.update_all(SessionToken, set: [inserted_at: ~N[2020-01-01 00:00:00]])
      assert Sessions.confirm_session(token) == :error
      refute Repo.get!(Session, session.id).confirmed_at
      assert Repo.get_by(SessionToken, session_id: session.id)
    end
  end

  describe "deliver_session_reset_password_instructions/2" do
    setup do
      %{session: session_fixture()}
    end

    test "sends token through notification", %{session: session} do
      token =
        extract_session_token(fn url ->
          Sessions.deliver_session_reset_password_instructions(session, url)
        end)

      {:ok, token} = Base.url_decode64(token, padding: false)
      assert session_token = Repo.get_by(SessionToken, token: :crypto.hash(:sha256, token))
      assert session_token.session_id == session.id
      assert session_token.sent_to == session.email
      assert session_token.context == "reset_password"
    end
  end

  describe "get_session_by_reset_password_token/1" do
    setup do
      session = session_fixture()

      token =
        extract_session_token(fn url ->
          Sessions.deliver_session_reset_password_instructions(session, url)
        end)

      %{session: session, token: token}
    end

    test "returns the session with valid token", %{session: %{id: id}, token: token} do
      assert %Session{id: ^id} = Sessions.get_session_by_reset_password_token(token)
      assert Repo.get_by(SessionToken, session_id: id)
    end

    test "does not return the session with invalid token", %{session: session} do
      refute Sessions.get_session_by_reset_password_token("oops")
      assert Repo.get_by(SessionToken, session_id: session.id)
    end

    test "does not return the session if token expired", %{session: session, token: token} do
      {1, nil} = Repo.update_all(SessionToken, set: [inserted_at: ~N[2020-01-01 00:00:00]])
      refute Sessions.get_session_by_reset_password_token(token)
      assert Repo.get_by(SessionToken, session_id: session.id)
    end
  end

  describe "reset_session_password/2" do
    setup do
      %{session: session_fixture()}
    end

    test "validates password", %{session: session} do
      {:error, changeset} =
        Sessions.reset_session_password(session, %{
          password: "not valid",
          password_confirmation: "another"
        })

      assert %{
               password: ["should be at least 12 character(s)"],
               password_confirmation: ["does not match password"]
             } = errors_on(changeset)
    end

    test "validates maximum values for password for security", %{session: session} do
      too_long = String.duplicate("db", 100)
      {:error, changeset} = Sessions.reset_session_password(session, %{password: too_long})
      assert "should be at most 72 character(s)" in errors_on(changeset).password
    end

    test "updates the password", %{session: session} do
      {:ok, updated_session} = Sessions.reset_session_password(session, %{password: "new valid password"})
      assert is_nil(updated_session.password)
      assert Sessions.get_session_by_email_and_password(session.email, "new valid password")
    end

    test "deletes all tokens for the given session", %{session: session} do
      _ = Sessions.generate_session_session_token(session)
      {:ok, _} = Sessions.reset_session_password(session, %{password: "new valid password"})
      refute Repo.get_by(SessionToken, session_id: session.id)
    end
  end

  describe "inspect/2 for the Session module" do
    test "does not include password" do
      refute inspect(%Session{password: "123456"}) =~ "password: \"123456\""
    end
  end
end
