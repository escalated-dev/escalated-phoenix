defmodule Escalated.Controllers.Api.MobileGuestController do
  @moduledoc """
  The mobile guest API, `{prefix}/api/v1/mobile/guest/*`, as fixed by the
  shared contract (`domain-model/mobile-guest-api.md` in
  escalated-developer-context; escalated-laravel's `routes/mobile-api.php`).

  It is the mobile face of verified guest access: `verification` and `lookup`
  are the same handlers as the browser, API and widget guest routes, and
  create, show and reply use the same proof consumption
  (`Escalated.Services.GuestAccess`), grants and guest ticket creation
  (`TicketService.create_guest/2`). A grant from any surface opens the others.
  Any bad, expired, rotated or chat grant is a 404.
  """
  use Phoenix.Controller, formats: [:json]
  import Plug.Conn

  alias Escalated.Controllers.GuestAccessController, as: AccessController
  alias Escalated.Rendering.MobileTicketPresenter
  alias Escalated.Schemas.{Department, Ticket}
  alias Escalated.Services.{GuestAccess, TicketService}

  @priorities ~w(low medium high urgent critical)
  @email ~r/^[^\s@]+@[^\s@]+\.[^\s@]+$/u

  @doc "POST /guest/verification: the shared code request, behind the feature switches."
  def verification(conn, params) do
    cond do
      params["purpose"] in ["ticket", "lookup"] and not guest_tickets_enabled?() ->
        guest_tickets_disabled(conn)

      params["purpose"] == "chat" and not chat_enabled?() ->
        conn |> put_status(403) |> json(%{message: "Live chat is not enabled."})

      true ->
        AccessController.challenge(conn, params)
    end
  end

  @doc "POST /guest/lookup: the shared lookup, while guest tickets are on."
  def lookup(conn, params) do
    if guest_tickets_enabled?(),
      do: AccessController.lookup(conn, params),
      else: guest_tickets_disabled(conn)
  end

  @doc "POST /guest/tickets"
  def create(conn, params) do
    with :ok <- if(guest_tickets_enabled?(), do: :ok, else: :disabled),
         :ok <- validate(create_rules(), params) do
      attrs = %{
        subject: params["subject"],
        description: params["description"],
        guest_name: params["name"],
        guest_email: params["email"],
        priority: present(params["priority"]) || default_priority(),
        department_id: present(params["department_id"]),
        channel: "web"
      }

      case TicketService.create_guest(params, attrs) do
        {:ok, ticket, result} ->
          data =
            MobileTicketPresenter.ticket(
              ticket,
              result["guest_access_token"],
              result["expires_at"]
            )

          conn |> put_status(201) |> json(%{data: data, message: "Ticket created."})

        {:error, %Ecto.Changeset{} = changeset} ->
          invalid(conn, changeset_errors(changeset))

        {:error, reason} ->
          AccessController.error(conn, reason)
      end
    else
      :disabled -> guest_tickets_disabled(conn)
      {:invalid, errors} -> invalid(conn, errors)
    end
  end

  @doc "GET /guest/tickets/:token"
  def show(conn, %{"token" => token}) do
    case GuestAccess.resolve(token) do
      {:ok, ticket, grant} ->
        data =
          MobileTicketPresenter.ticket(ticket, token, grant.expires_at,
            grant: grant,
            replies: true
          )

        json(conn, %{data: data})

      _ ->
        AccessController.error(conn, :not_found)
    end
  end

  @doc "POST /guest/tickets/:token/replies"
  def reply(conn, %{"token" => token} = params) do
    with {:ok, ticket, _grant} <- GuestAccess.resolve(token),
         :ok <- if(ticket.status == "closed", do: :closed, else: :ok),
         :ok <- validate(reply_rules(), params),
         :ok <- same_mailbox(ticket, params["email"]),
         {:ok, _reply} <-
           TicketService.reply(ticket, %{body: params["body"], is_internal: false}) do
      conn |> put_status(201) |> json(%{message: "Reply sent."})
    else
      :closed ->
        conn |> put_status(422) |> json(%{message: "This ticket is closed."})

      {:invalid, errors} ->
        invalid(conn, errors)

      :mismatch ->
        conn
        |> put_status(403)
        |> json(%{message: "The provided email does not match this ticket."})

      {:error, %Ecto.Changeset{} = changeset} ->
        invalid(conn, changeset_errors(changeset))

      _ ->
        AccessController.error(conn, :not_found)
    end
  end

  @doc """
  Whether guests may file and look up tickets (`config :escalated,
  guest_tickets_enabled:`, default `true`).
  """
  def guest_tickets_enabled?,
    do: Escalated.config(:guest_tickets_enabled, true) not in [false, nil]

  # Guest chat starts from the widget, so it follows the widget's switch.
  defp chat_enabled?,
    do: Map.get(Escalated.config(:widget_settings, %{}), :enabled, true) not in [false, nil]

  defp guest_tickets_disabled(conn),
    do: conn |> put_status(403) |> json(%{message: "Guest tickets are not enabled."})

  defp same_mailbox(%Ticket{guest_email: stored}, given) do
    expected = GuestAccess.email(stored)
    given = GuestAccess.email(given)

    if expected != "" and Plug.Crypto.secure_compare(expected, given),
      do: :ok,
      else: :mismatch
  end

  # -- validation ------------------------------------------------------------

  defp create_rules,
    do: [
      {"name", [:required, :string, {:max, 255}]},
      {"email", [:required, :email, {:max, 255}]},
      {"subject", [:required, :string, {:max, 255}]},
      {"description", [:required, :string, {:max, 65_535}]},
      {"verification_id", [:required, :uuid]},
      {"verification_code", [:required, :string, {:max, 16}]},
      {"priority", [{:in, @priorities}]},
      {"department_id", [:department]}
    ]

  defp reply_rules,
    do: [
      {"body", [:required, :string, {:max, 65_535}]},
      {"email", [:required, :email, {:max, 255}]}
    ]

  defp validate(rules, params) do
    errors =
      for {field, checks} <- rules,
          message = first_error(checks, params[field], field),
          into: %{},
          do: {field, [message]}

    if errors == %{}, do: :ok, else: {:invalid, errors}
  end

  defp first_error(checks, value, field) do
    if blank?(value) do
      if :required in checks, do: "The #{label(field)} field is required."
    else
      Enum.find_value(checks, &check(&1, value, field))
    end
  end

  defp check(:required, _value, _field), do: nil

  defp check(:string, value, field),
    do: unless(is_binary(value), do: "The #{label(field)} field must be a string.")

  defp check(:email, value, field) do
    unless is_binary(value) and Regex.match?(@email, String.trim(value)),
      do: "The #{label(field)} field must be a valid email address."
  end

  defp check({:max, max}, value, field) do
    if is_binary(value) and String.length(value) > max,
      do: "The #{label(field)} field must not be greater than #{max} characters."
  end

  defp check(:uuid, value, field) do
    unless is_binary(value) and match?({:ok, _}, Ecto.UUID.cast(value)),
      do: "The #{label(field)} field must be a valid UUID."
  end

  defp check({:in, allowed}, value, field),
    do: unless(value in allowed, do: "The selected #{label(field)} is invalid.")

  defp check(:department, value, field) do
    exists? =
      case Integer.parse(to_string(value)) do
        {id, ""} -> not is_nil(Escalated.repo().get(Department, id))
        _ -> false
      end

    unless exists?, do: "The selected #{label(field)} is invalid."
  end

  defp label(field), do: String.replace(field, "_", " ")

  defp blank?(value), do: is_nil(value) or (is_binary(value) and String.trim(value) == "")

  defp present(value) when value in [nil, ""], do: nil
  defp present(value), do: value

  defp default_priority do
    priority = to_string(Escalated.config(:default_priority, :medium))
    if priority in @priorities, do: priority, else: "medium"
  end

  defp invalid(conn, errors),
    do:
      conn
      |> put_status(422)
      |> json(%{message: "Check the submitted details.", errors: errors})

  defp changeset_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Enum.reduce(opts, message, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
  end
end
