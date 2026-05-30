defmodule Escalated.TicketSubject do
  @moduledoc """
  Host-app contract for models attachable as ticket subjects.

  Implement on a host struct (Project, Customer, …) so the ticket UI can render
  title, subtitle, deep link, color, and icon. Resolve structs via
  `config :escalated, ticket_subjects: [resolver: &Mod.fun/2]`.
  """

  @type subject :: struct()

  @callback ticket_subject_title(subject()) :: String.t()
  @callback ticket_subject_subtitle(subject()) :: String.t() | nil
  @callback ticket_subject_url(subject()) :: String.t() | nil
  @callback ticket_subject_color(subject()) :: String.t() | nil
  @callback ticket_subject_icon(subject()) :: String.t() | nil
end
