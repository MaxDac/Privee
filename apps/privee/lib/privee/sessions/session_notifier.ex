defmodule Privee.Sessions.SessionNotifier do
  import Swoosh.Email

  alias Privee.Mailer

  # Delivers the email using the application mailer.
  defp deliver(recipient, subject, body) do
    email =
      new()
      |> to(recipient)
      |> from({"Privee", "contact@example.com"})
      |> subject(subject)
      |> text_body(body)

    with {:ok, _metadata} <- Mailer.deliver(email) do
      {:ok, email}
    end
  end

  @doc """
  Deliver instructions to confirm account.
  """
  def deliver_confirmation_instructions(session, url) do
    deliver(session.email, "Confirmation instructions", """

    ==============================

    Hi #{session.email},

    You can confirm your account by visiting the URL below:

    #{url}

    If you didn't create an account with us, please ignore this.

    ==============================
    """)
  end

  @doc """
  Deliver instructions to reset a session password.
  """
  def deliver_reset_password_instructions(session, url) do
    deliver(session.email, "Reset password instructions", """

    ==============================

    Hi #{session.email},

    You can reset your password by visiting the URL below:

    #{url}

    If you didn't request this change, please ignore this.

    ==============================
    """)
  end

  @doc """
  Deliver instructions to update a session email.
  """
  def deliver_update_email_instructions(session, url) do
    deliver(session.email, "Update email instructions", """

    ==============================

    Hi #{session.email},

    You can change your email by visiting the URL below:

    #{url}

    If you didn't request this change, please ignore this.

    ==============================
    """)
  end
end
