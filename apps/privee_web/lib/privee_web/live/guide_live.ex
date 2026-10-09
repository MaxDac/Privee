defmodule PriveeWeb.GuideLive do
  @moduledoc "Explains what Privee is for and how to use it (#42). Public page."
  use PriveeWeb, :live_view

  def mount(_params, _session, socket) do
    navigate_to = if socket.assigns.current_session, do: ~p"/privee", else: ~p"/"
    {:ok, assign(socket, navigate_to: navigate_to)}
  end

  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_session={@current_session}
      navigate_to={@navigate_to}
      locale={@locale}
    >
      <article id="guide" class="mx-auto max-w-2xl space-y-8 pb-10 text-zinc-800 dark:text-zinc-100">
        <.header class="text-center">
          {lgettext(@locale, "How Privee works")}
          <:subtitle>
            {lgettext(
              @locale,
              "Privee is a chat for private conversations that leave no trace: no account, no email, no phone number."
            )}
          </:subtitle>
        </.header>

        <section id="guide-purpose" class="space-y-2">
          <h2 class="text-lg font-semibold">{lgettext(@locale, "Why Privee")}</h2>

          <p>
            {lgettext(
              @locale,
              "Messages are end-to-end encrypted in your browser with the Signal Protocol. The server only relays encrypted text it cannot read, and deletes it after a while."
            )}
          </p>

          <p>
            {lgettext(
              @locale,
              "Unused sessions are deleted automatically, so nothing ties you to past conversations."
            )}
          </p>
        </section>

        <section id="guide-sessions" class="space-y-2">
          <h2 class="text-lg font-semibold">{lgettext(@locale, "Sessions instead of accounts")}</h2>

          <p>
            {lgettext(
              @locale,
              "Create a session to get a session name and a recovery phrase. The session name is how others reach you; the recovery phrase is your password."
            )}
          </p>

          <p>
            {lgettext(
              @locale,
              "To sign in again, use the session name and the recovery phrase. Keep the phrase safe: it cannot be recovered."
            )}
          </p>
        </section>

        <section id="guide-start" class="space-y-2">
          <h2 class="text-lg font-semibold">{lgettext(@locale, "Starting a conversation")}</h2>

          <ol class="list-decimal space-y-1 pl-6">
            <li>
              {lgettext(
                @locale,
                "Copy your session name or your chat link from the top bar and send it to your contact."
              )}
            </li>

            <li>
              {lgettext(
                @locale,
                "Your contact opens the link, or types your session name on the chat selection page."
              )}
            </li>

            <li>
              {lgettext(
                @locale,
                "Compare the safety number with your contact to make sure nobody is in the middle."
              )}
            </li>
          </ol>
        </section>

        <section id="guide-history" class="space-y-2">
          <h2 class="text-lg font-semibold">{lgettext(@locale, "History")}</h2>

          <p>
            {lgettext(
              @locale,
              "There is no history on the server. Messages you read are kept only on this browser, and a new device starts with an empty conversation. You can export them as CSV or delete them at any time."
            )}
          </p>
        </section>

        <section id="guide-commands" class="space-y-2">
          <h2 class="text-lg font-semibold">{lgettext(@locale, "Chat commands")}</h2>

          <p>
            {lgettext(
              @locale,
              "Type : in the message box to see the commands. They run in your browser and are never sent."
            )}
          </p>

          <ul class="space-y-1 pl-2 font-mono text-sm">
            <li>:lock &lt;password&gt; / :unlock &lt;password&gt;</li>

            <li>:export · :safety · :hint · :clear · :vim</li>
          </ul>

          <p>
            {lgettext(
              @locale,
              "Messages support **bold**, *italic*, ~~strikethrough~~, `code` and links."
            )}
          </p>
        </section>

        <div class="flex justify-center">
          <.link
            id="guide-start-link"
            navigate={@navigate_to}
            class="rounded-lg bg-zinc-900 px-4 py-2 text-sm font-semibold text-white transition hover:bg-zinc-700 active:scale-95 dark:bg-zinc-100 dark:text-zinc-900"
          >
            {if @current_session,
              do: lgettext(@locale, "Open a chat"),
              else: lgettext(@locale, "Create a new session")}
          </.link>
        </div>
      </article>
    </Layouts.app>
    """
  end
end
