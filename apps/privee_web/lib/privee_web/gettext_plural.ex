defmodule PriveeWeb.GettextPlural do
  @moduledoc """
  Implements the two-form `n != 1` rule used by all five application catalogs.

  Gettext's built-in English rule is identical to these catalog headers.
  Keeping the rule here avoids embedding Expo's opaque plural AST in the
  compiled Gettext backend.
  """

  @behaviour Gettext.Plural

  @impl true
  def nplurals(_locale), do: 2

  @impl true
  def plural(_locale, count), do: Gettext.Plural.plural("en", count)
end
