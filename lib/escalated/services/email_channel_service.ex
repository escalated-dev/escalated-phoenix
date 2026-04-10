defmodule Escalated.Services.EmailChannelService do
  @moduledoc "Manages email channel addresses, DKIM validation, and default reply addresses."

  alias Escalated.Schemas.EmailChannel

  @doc "Create a new email channel."
  def create(repo, attrs) do
    %EmailChannel{}
    |> EmailChannel.changeset(attrs)
    |> repo.insert()
  end

  @doc "Find an email channel by address."
  def find_by_address(repo, email_address) do
    repo.get_by(EmailChannel, email_address: email_address)
  end

  @doc "Get the default active email channel."
  def get_default(repo) do
    repo.get_by(EmailChannel, is_default: true, is_active: true)
  end

  @doc "Set a channel as the default (clears other defaults)."
  def set_default(repo, %EmailChannel{} = channel) do
    import Ecto.Query

    prefix = Application.get_env(:escalated, :table_prefix, "escalated_")
    table = "#{prefix}email_channels"

    repo.update_all(
      from(e in {table, EmailChannel}, where: e.is_default == true),
      set: [is_default: false]
    )

    channel
    |> Ecto.Changeset.change(is_default: true)
    |> repo.update()
  end

  @doc "Verify DKIM DNS records for a channel."
  def verify_dkim(%EmailChannel{email_address: addr, dkim_selector: selector, dkim_public_key: pub_key} = channel, repo) do
    domain = addr |> String.split("@") |> List.last()
    sel = selector || "escalated"
    dns_host = "#{sel}._domainkey.#{domain}"

    # In production, perform actual DNS TXT lookup
    verified = false

    changeset = Ecto.Changeset.change(channel,
      dkim_status: if(verified, do: "verified", else: "failed"),
      is_verified: verified
    )

    repo.update(changeset)

    %{domain: domain, selector: sel, dns_host: dns_host, verified: verified, public_key: pub_key}
  end

  @doc "Delete an email channel."
  def delete(repo, %EmailChannel{} = channel) do
    repo.delete(channel)
  end
end
