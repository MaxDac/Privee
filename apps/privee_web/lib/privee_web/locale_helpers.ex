defmodule PriveeWeb.LocaleHelpers do
  @moduledoc "Explicit locale dependencies for LiveView's template change tracking."

  defmacro lgettext(locale, message, bindings \\ []) do
    quote do
      require Gettext.Macros

      Gettext.with_locale(PriveeWeb.Gettext, unquote(locale), fn ->
        Gettext.Macros.gettext_with_backend(
          PriveeWeb.Gettext,
          unquote(message),
          unquote(bindings)
        )
      end)
    end
  end
end
