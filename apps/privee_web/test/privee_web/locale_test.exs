defmodule PriveeWeb.LocaleTest do
  use PriveeWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Privee.SessionsFixtures

  alias PriveeWeb.Locale

  test "negotiates base/regional tags, quality and fallback" do
    for {header, expected} <- [
          {"", "en"},
          {"de", "en"},
          {"it-IT", "it"},
          {"PT", "pt-PT"},
          {"pt-BR", "pt-PT"},
          {"es-MX", "es"},
          {"fr-CA", "fr"},
          {"fr;q=0.4, it;q=0.8", "it"},
          {"de;q=1, es;q=0.8", "es"},
          {"it;q=0, fr;q=0.5", "fr"},
          {"fr;q=bad, es;q=0.5", "es"},
          {"fr;q=2", "en"}
        ] do
      assert Locale.negotiate(header) == expected
    end
  end

  test "unknown HTML routes use the browser preference before router matching", %{conn: conn} do
    conn =
      conn |> put_req_cookie("privee_locale", "fr") |> put_req_header("accept", "text/html")

    conn = get(conn, "/unknown-language-test-route")
    assert html_response(conn, 404) == "Page introuvable"
  end

  test "browser starts English even with an Italian Accept-Language", %{conn: conn} do
    conn = conn |> put_req_header("accept-language", "it") |> get("/")
    assert conn.assigns.locale == "en"

    assert conn
           |> html_response(200)
           |> LazyHTML.from_document()
           |> LazyHTML.filter("html[lang='en']")
           |> Enum.count() == 1
  end

  test "cookie is allowlisted and establishes HTTP and LiveView locale", %{conn: conn} do
    for {cookie, expected} <- [{"it", "it"}, {"pt-PT", "pt-PT"}, {"xx", "en"}, {"it-IT", "en"}] do
      conn = conn |> recycle() |> put_req_cookie("privee_locale", cookie) |> get("/")
      assert conn.assigns.locale == expected
      {:ok, view, _} = live(conn)
      assert has_element?(view, "#language-settings[data-locale='#{expected}']")
    end
  end

  test "connected locale overrides the stale signed LiveView session", %{conn: conn} do
    conn = conn |> put_req_cookie("privee_locale", "it") |> get("/")
    {:ok, view, _} = conn |> put_connect_params(%{"locale" => "fr"}) |> live()
    assert has_element?(view, "#language-settings[data-locale='fr']")
    assert has_element?(view, "#settings-toggle", "Paramètres")
  end

  test "switches all five languages in the same LiveView preserving registration fields", %{
    conn: conn
  } do
    {:ok, view, _} = live(conn, "/")
    name = unique_session_name()
    phrase = "a recovery phrase kept exactly as entered"

    view
    |> form("#registration_form", session: %{session_name: name, recovery_phrase: phrase})
    |> render_change()

    for {locale, label} <- [
          {"it", "Lingua"},
          {"pt-PT", "Idioma"},
          {"es", "Idioma"},
          {"fr", "Langue"},
          {"en", "Language"}
        ] do
      view |> form("#language-form", %{locale: locale}) |> render_change()
      assert has_element?(view, "label[for='language-select']", label)
      assert has_element?(view, "#session_session_name[value='#{name}']")
      assert has_element?(view, "#session_recovery_phrase", phrase)
      assert_push_event(view, "locale_changed", %{locale: ^locale})
    end
  end

  test "rejects invalid selection without changing locale", %{conn: conn} do
    {:ok, view, _} = live(conn, "/")
    render_hook(view, "set_locale", %{locale: "xx"})
    assert has_element?(view, "#language-settings[data-locale='en']")
    assert has_element?(view, "#flash-error", "This language is not supported.")
  end

  test "clears old errors but retains drafts and validates in the new language", %{conn: conn} do
    {:ok, view, _} = live(conn, "/")
    params = %{session_name: "short", recovery_phrase: "short"}
    view |> form("#registration_form", session: params) |> render_change()
    assert has_element?(view, "#registration_form p", "should be at least 24")

    view |> form("#language-form", %{locale: "it"}) |> render_change()
    refute has_element?(view, "#registration_form p", "should be at least 24")
    assert has_element?(view, "#session_session_name[value='short']")
    view |> form("#registration_form", session: params) |> render_change()
    assert has_element?(view, "#registration_form p", "deve contenere almeno 24")
  end

  test "preserves login fields and checkbox while updating labels", %{conn: conn} do
    {:ok, view, _} = live(conn, "/login")

    view
    |> form("#login_form",
      session: %{session_name: "draft-name", recovery_phrase: "my citation", remember_me: "true"}
    )
    |> render_change()

    view |> form("#language-form", %{locale: "fr"}) |> render_change()
    assert has_element?(view, "#session_session_name[value='draft-name']")
    assert has_element?(view, "#session_recovery_phrase", "my citation")
    assert has_element?(view, "#session_remember_me[checked]")
    assert has_element?(view, "#login_form label", "Phrase de récupération")
  end

  test "cookie survives logout and authentication session renewal", %{conn: conn} do
    session = session_fixture()
    conn = conn |> put_req_cookie("privee_locale", "it") |> log_in_session(session)
    conn = get(conn, "/privee")
    assert conn.assigns.locale == "it"
    conn = conn |> recycle() |> delete("/sessions/log_out")
    assert conn.assigns.locale == "it"
    refute Map.has_key?(conn.resp_cookies, "privee_locale")
    conn = conn |> recycle() |> get("/")
    assert conn.assigns.locale == "it"
  end

  test "API validation translates human errors but not machine codes", %{conn: conn} do
    for {locale, text} <- [
          {"en", "can't be blank"},
          {"it-IT", "non può essere vuoto"},
          {"pt", "não pode estar em branco"},
          {"es-MX", "no puede estar en blanco"},
          {"fr-CA", "ne peut pas être vide"},
          {"xx", "can't be blank"}
        ] do
      conn =
        conn
        |> recycle()
        |> put_req_header("accept-language", locale)
        |> post("/api/app/sessions", %{session_name: "short"})

      assert %{"error" => "invalid", "errors" => errors} = json_response(conn, 422)
      assert text in errors["recovery_phrase"]
      refute Enum.any?(errors["session_name"], &String.contains?(&1, "%{count}"))
    end

    conn =
      conn
      |> recycle()
      |> put_req_header("accept-language", "fr")
      |> post("/api/app/sessions/log_in", %{})

    assert json_response(conn, 401) == %{"error" => "invalid_credentials"}
  end

  test "all client keys translate in every non-English language" do
    english = PriveeWeb.ClientTexts.translations("en")

    for locale <- ~w(it pt-PT es fr) do
      translated = PriveeWeb.ClientTexts.translations(locale)
      assert Map.keys(translated) == Map.keys(english)

      for {key, value} <- translated do
        assert value != ""
        assert value != english[key] or key in [:close, :messageLabel]
      end
    end
  end

  test "error interpolation uses translated singular and plural forms" do
    Gettext.with_locale(PriveeWeb.Gettext, "it", fn ->
      assert PriveeWeb.CoreComponents.translate_error(
               {"should be %{count} character(s)", count: 1}
             ) == "deve contenere 1 carattere"

      assert PriveeWeb.CoreComponents.translate_error(
               {"should be %{count} character(s)", count: 2}
             ) == "deve contenere 2 caratteri"
    end)
  end
end
