defmodule Escalated.Gettext do
  @moduledoc """
  Gettext backend for Escalated translations.

  Canonical `.po` files live at `priv/gettext/{locale}/LC_MESSAGES/escalated.po`
  and are vendored from the central `escalated-dev/escalated-locale` repository.
  When that repo's Hex publish pipeline is online, we'll swap back to a runtime
  dependency on the `:escalated_locale` package.

  ## Adding a per-host override

  Place a `.po` at `priv/gettext/overrides/{locale}/LC_MESSAGES/escalated.po` in
  your host app and configure your own Gettext backend pointing at it.
  """

  use Gettext.Backend,
    otp_app: :escalated,
    priv: "priv/gettext",
    default_locale: "en",
    locales: ~w(ar de en es fr it ja ko nl pl pt_BR ru tr zh_CN)
end
