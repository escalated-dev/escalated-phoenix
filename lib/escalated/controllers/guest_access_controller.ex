defmodule Escalated.Controllers.GuestAccessController do
  use Phoenix.Controller, formats: [:json]
  import Plug.Conn
  alias Escalated.Services.GuestAccess

  def challenge(conn, params) do
    case GuestAccess.challenge(params["email"], params["purpose"]) do
      {:ok, id} ->
        conn
        |> put_status(202)
        |> json(%{
          verification_id: id,
          expires_in: 600,
          message: "Check your email for a verification code."
        })

      {:error, reason} ->
        error(conn, reason)
    end
  end

  def lookup(conn, params) do
    case GuestAccess.lookup(params) do
      {:ok, result} -> json(conn, %{"data" => Enum.map(result["data"], &public_grant/1)})
      {:error, reason} -> error(conn, reason)
    end
  end

  def error(conn, :rate_limited),
    do:
      conn
      |> put_resp_header("retry-after", "3600")
      |> put_status(429)
      |> json(%{message: "Please wait before requesting another code."})

  def error(conn, :unavailable),
    do:
      conn
      |> put_status(503)
      |> json(%{message: "Guest verification is temporarily unavailable."})

  def error(conn, :verification),
    do:
      conn
      |> put_status(422)
      |> json(%{
        errors: %{
          verification_code: [
            "This code is invalid, expired or already used. Request a new code."
          ]
        }
      })

  def error(conn, :not_found), do: conn |> put_status(404) |> json(%{message: "Not found."})

  def error(conn, _),
    do: conn |> put_status(422) |> json(%{message: "Check the submitted details."})

  def public_grant(result),
    do: Map.take(result, ["reference", "subject", "guest_access_token", "expires_at"])
end
