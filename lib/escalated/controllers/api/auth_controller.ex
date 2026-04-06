defmodule Escalated.Controllers.Api.AuthController do
  @moduledoc """
  API authentication controller. Validates API tokens for external access.
  """
  use Phoenix.Controller, formats: [:json]
  import Plug.Conn

  def validate(conn, %{"token" => token}) do
    # Token validation is delegated to the host app.
    # This is a placeholder — the host app should configure an auth strategy.
    case validate_token(token) do
      {:ok, user_data} ->
        json(conn, %{valid: true, user: user_data})

      :error ->
        conn |> put_status(401) |> json(%{valid: false, error: "Invalid token"})
    end
  end

  def validate(conn, _params) do
    conn |> put_status(400) |> json(%{error: "Token is required"})
  end

  defp validate_token(_token) do
    # Override via config :escalated, :api_token_validator, &MyApp.validate_api_token/1
    case Escalated.config(:api_token_validator) do
      nil -> :error
      validator when is_function(validator, 1) -> validator.(_token)
      _ -> :error
    end
  end
end
