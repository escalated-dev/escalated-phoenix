defmodule Escalated.Controllers.Admin.ApiTokenController do
  @moduledoc """
  Admin management of API tokens, serving `Escalated/Admin/ApiTokens/Index`
  with the props escalated-laravel's `Admin\\ApiTokenController` sends:
  `tokens`, `users` (the agents a token can belong to) and `api_enabled`.

  Creating a token redirects back with the plain text in the flash
  (`flash.plain_text_token`, which the page reads), the only time it is
  shown; only its SHA-256 digest is stored. A request without the
  `X-Inertia` header gets `201` with the token row and `plain_text_token`
  instead. Update changes a token's name and abilities; destroy revokes it.

  `api_enabled` is true when the JSON ticket API is mounted and accepts these
  tokens (`config :escalated, api_tokens_enabled: true`).
  """
  use Phoenix.Controller, formats: [:html, :json]
  import Plug.Conn

  alias Escalated.Controllers.FormResponse
  alias Escalated.Plugs.ApiAuthenticate
  alias Escalated.Rendering.{UIRenderer, UserDirectory}
  alias Escalated.Schemas.ApiToken
  alias Escalated.Services.ApiTokenService

  def index(conn, _params) do
    tokens = ApiTokenService.list()
    people = UserDirectory.lookup(Enum.map(tokens, & &1.user_id))

    conn
    |> put_resp_header("cache-control", "no-store")
    |> UIRenderer.render_page("Escalated/Admin/ApiTokens/Index", %{
      tokens: Enum.map(tokens, &token_json(&1, people)),
      users: UserDirectory.agents(),
      api_enabled: ApiAuthenticate.tokens_enabled?() and api_mounted?(conn)
    })
  end

  def create(conn, params) do
    with {:ok, attrs} <- create_attrs(params),
         {:ok, %{token: token, plain_text_token: plain}} <-
           ApiTokenService.create(attrs.user_id, attrs.name, attrs.abilities, attrs.expires_at) do
      if FormResponse.inertia?(conn) do
        conn
        |> put_flash(:success, "API token created.")
        |> put_flash(:plain_text_token, plain)
        |> redirect(to: index_path())
      else
        people = UserDirectory.lookup([token.user_id])

        conn
        |> put_resp_header("cache-control", "no-store")
        |> put_status(201)
        |> json(%{token: token_json(token, people), plain_text_token: plain})
      end
    else
      {:error, errors} -> FormResponse.invalid(conn, errors, index_path())
    end
  end

  def update(conn, %{"id" => id} = params) do
    with %ApiToken{} = token <- ApiTokenService.get(id),
         {:ok, _} <- ApiTokenService.update(token, Map.take(params, ["name", "abilities"])) do
      conn |> put_flash(:success, "Token updated.") |> redirect(to: index_path())
    else
      nil -> not_found(conn)
      {:error, changeset} -> FormResponse.invalid(conn, changeset, index_path())
    end
  end

  def delete(conn, %{"id" => id}) do
    case ApiTokenService.get(id) do
      nil ->
        not_found(conn)

      token ->
        {:ok, _} = ApiTokenService.revoke(token)
        conn |> put_flash(:success, "Token revoked.") |> redirect(to: index_path())
    end
  end

  # The row Laravel sends. Never the digest.
  defp token_json(%ApiToken{} = token, people) do
    owner = UserDirectory.get(people, token.user_id)

    %{
      id: token.id,
      name: token.name,
      user_name: owner && owner.name,
      user_email: owner && owner.email,
      abilities: token.abilities,
      last_used_at: iso(token.last_used_at),
      last_used_ip: token.last_used_ip,
      expires_at: iso(token.expires_at),
      is_expired: ApiToken.expired?(token),
      created_at: iso(token.inserted_at)
    }
  end

  # Laravel's rules: name required (max 255), user_id required, abilities a
  # non-empty list of agent/admin/*, expires_in_days nullable 1..365. The
  # owner must be an existing agent: a token for anyone else could never
  # pass the API's agent check.
  defp create_attrs(params) do
    name = if is_binary(params["name"]), do: String.trim(params["name"]), else: nil
    abilities = params["abilities"]
    days = integer(params["expires_in_days"])
    owner = owner(params["user_id"])

    errors =
      []
      |> add_if(name in [nil, ""], "name", "The name field is required.")
      |> add_if(
        is_binary(name) and String.length(name) > 255,
        "name",
        "The name may not be greater than 255 characters."
      )
      |> add_if(blank?(params["user_id"]), "user_id", "The user id field is required.")
      |> add_if(is_nil(owner), "user_id", "The selected user id is invalid.")
      |> add_if(
        not (is_list(abilities) and abilities != []),
        "abilities",
        "The abilities field is required."
      )
      |> add_if(
        is_list(abilities) and not Enum.all?(abilities, &(&1 in ApiToken.abilities())),
        "abilities",
        "The selected abilities are invalid."
      )
      |> add_if(
        days == :error or (is_integer(days) and (days < 1 or days > 365)),
        "expires_in_days",
        "The expires in days must be between 1 and 365."
      )
      |> Map.new(fn {k, v} -> {k, [v]} end)

    if errors == %{} do
      {:ok,
       %{
         name: name,
         user_id: owner.id,
         abilities: Enum.uniq(abilities),
         expires_at: days && DateTime.add(DateTime.utc_now(), days * 86_400, :second)
       }}
    else
      {:error, errors}
    end
  end

  defp owner(id) when is_integer(id) or (is_binary(id) and id != "") do
    case Escalated.user_repo().get(Escalated.user_schema(), id) do
      nil -> nil
      user -> if Escalated.Permissions.agent?(user), do: user
    end
  rescue
    Ecto.Query.CastError -> nil
  end

  defp owner(_id), do: nil

  defp blank?(value), do: value in [nil, ""]

  defp add_if(errors, true, key, message) do
    if List.keymember?(errors, key, 0), do: errors, else: errors ++ [{key, message}]
  end

  defp add_if(errors, _, _key, _message), do: errors

  defp integer(nil), do: nil
  defp integer(""), do: nil
  defp integer(value) when is_integer(value), do: value

  defp integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {int, ""} -> int
      _ -> :error
    end
  end

  defp integer(_), do: :error

  defp iso(nil), do: nil
  defp iso(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
  defp iso(%NaiveDateTime{} = dt), do: dt |> DateTime.from_naive!("Etc/UTC") |> iso()

  # Whether the host mounted the JSON ticket API (`escalated_routes/2` with
  # `api: true`, or `config :escalated, api_enabled: true`).
  defp api_mounted?(conn) do
    case conn.private[:phoenix_router] do
      nil ->
        false

      router ->
        path = Escalated.config(:route_prefix, "/support") <> "/api/v1/tickets"
        Phoenix.Router.route_info(router, "GET", path, conn.host) != :error
    end
  end

  defp not_found(conn), do: conn |> put_status(404) |> json(%{error: "Token not found"})

  defp index_path, do: Escalated.config(:route_prefix, "/support") <> "/admin/api-tokens"
end
