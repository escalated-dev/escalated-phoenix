defmodule Escalated.Gettext do
  @moduledoc """
  Gettext backend for Escalated translations.

  Translations are sourced from the central `:escalated_locale` Hex package,
  which ships canonical `.po` files at
  `priv/gettext/{locale}/LC_MESSAGES/escalated.po`.

  Local overrides can be placed under `priv/gettext/overrides/{locale}/LC_MESSAGES/escalated.po`
  in this repository — overrides are merged on top of the central catalog at
  compile time, so a host application embedding `escalated_phoenix` only needs
  to depend on this package.

  ## Adding a per-host override

  1. Create the matching directory under `priv/gettext/overrides`.
  2. Copy the canonical `.po` from `:escalated_locale` and adjust the strings
     you want to override.
  3. Recompile.

  ## Direct re-export

  If no override is needed, this module behaves identically to the upstream
  `EscalatedLocale.Gettext` backend.
  """

  use Gettext.Backend,
    otp_app: :escalated,
    priv: "priv/gettext/overrides",
    default_locale: "en",
    locales: ~w(ar de en es fr it ja ko nl pl pt_BR ru tr zh_CN)
end
