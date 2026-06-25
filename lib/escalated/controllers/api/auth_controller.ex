defmodule Escalated.Controllers.Api.AuthController do
  @moduledoc """
  API authentication controller for the general JSON API consumed by the
  Flutter app and integrations. All credential handling is delegated to
  host-app callbacks via `Escalated.Api.HostAuth` — Escalated owns no
  passwords or sessions.
  """
  use Phoenix.Controller, formats: [:json]
  import Plug.Conn

  alias Escalated.Api.HostAuth

  def login(conn, params), do: respond(conn, HostAuth.authenticate(params))

  def register(conn, params), do: respond(conn, HostAuth.register(params))

  def me(conn, _params) do
    case bearer_token(conn) do
      {:ok, token} -> respond(conn, HostAuth.validate(token))
      :error -> unauthorized(conn)
    end
  end

  def refresh(conn, _params) do
    case bearer_token(conn) do
      {:ok, token} -> respond(conn, HostAuth.refresh(token))
      :error -> unauthorized(conn)
    end
  end

  def profile(conn, params) do
    case bearer_token(conn) do
      {:ok, token} -> respond(conn, HostAuth.update_profile(token, params))
      :error -> unauthorized(conn)
    end
  end

  def logout(conn, _params) do
    token =
      case bearer_token(conn) do
        {:ok, value} -> value
        :error -> nil
      end

    HostAuth.logout(token)
    json(conn, %{data: %{success: true}})
  end

  def validate(conn, %{"token" => token}) do
    case HostAuth.validate(token) do
      {:ok, user} ->
        json(conn, %{valid: true, user: user})

      :not_configured ->
        conn
        |> put_status(501)
        |> json(%{valid: false, error: "Authentication is not configured"})

      _ ->
        conn |> put_status(401) |> json(%{valid: false, error: "Invalid token"})
    end
  end

  def validate(conn, _params) do
    conn |> put_status(400) |> json(%{error: "Token is required"})
  end

  defp respond(conn, {:ok, data}), do: json(conn, %{data: data})

  defp respond(conn, {:error, reason}),
    do: conn |> put_status(422) |> json(%{error: reason})

  defp respond(conn, :unauthorized), do: unauthorized(conn)

  defp respond(conn, :not_configured),
    do: conn |> put_status(501) |> json(%{error: "Authentication is not configured on this host"})

  defp unauthorized(conn),
    do: conn |> put_status(401) |> json(%{error: "Unauthorized"})

  defp bearer_token(conn) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> token | _] -> {:ok, token}
      [token | _] when is_binary(token) and token != "" -> {:ok, token}
      _ -> :error
    end
  end
end
