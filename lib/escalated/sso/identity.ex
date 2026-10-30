defmodule Escalated.Sso.Identity do
  @moduledoc """
  What every SSO provider hands to `Escalated.Sso.UserResolver`:
  `%{email: String.t(), name: String.t(), role: String.t()}`. A missing or
  malformed email refuses the sign-in.
  """

  @email ~r/^[^\s@]+@[^\s@]+\.[^\s@]+$/

  @doc "Builds the identity, or `{:error, reason}` without a valid email."
  def build(email, name, role) do
    email = to_string(email || "") |> String.trim()

    if String.length(email) <= 254 and Regex.match?(@email, email) do
      {:ok, %{email: email, name: to_string(name || ""), role: to_string(role || "")}}
    else
      {:error, "no valid email in the identity"}
    end
  end
end
