defmodule Escalated.TwoFactorSession do
  @moduledoc """
  Remembers, in the session, which sign-in has passed the two-factor
  challenge.

  The mark holds the user's ID and a fingerprint of the host's sign-in token
  in the session (`"user_token"`, which `mix phx.gen.auth` puts there on
  every login). So a session that passed for one user does not count for
  another, and every new login is challenged again, even when the host keeps
  the rest of the session across it. A host whose login stores something
  else names that key:

      config :escalated, two_factor: [login_session_key: "my_login_token"]

  Hosts can also clear the mark themselves on login and logout with
  `forget/1`.
  """
  import Plug.Conn

  @key "escalated_two_factor_passed"
  @intended "escalated_two_factor_intended"

  @doc "Whether this session passed the challenge for `user` in its current sign-in."
  def passed?(conn, user) do
    case get_session(conn, @key) do
      %{"user" => id, "login" => login} -> id == user_key(user) and login == login(conn)
      _ -> false
    end
  end

  @doc "Marks this session as having passed the challenge for `user`."
  def mark_passed(conn, user) do
    put_session(conn, @key, %{"user" => user_key(user), "login" => login(conn)})
  end

  @doc "Clears the mark. Call it from the host's login and logout if you like."
  def forget(conn), do: delete_session(conn, @key)

  @doc "Remembers the local path to return to after the challenge or enrolment."
  def put_intended(conn) do
    path =
      if conn.query_string == "",
        do: conn.request_path,
        else: "#{conn.request_path}?#{conn.query_string}"

    put_session(conn, @intended, path)
  end

  @doc "Takes the remembered path (only a local one), or `default`."
  def pop_intended(conn, default) do
    path = get_session(conn, @intended)
    conn = delete_session(conn, @intended)

    if local_path?(path), do: {conn, path}, else: {conn, default}
  end

  defp local_path?(path) do
    is_binary(path) and String.starts_with?(path, "/") and
      not String.starts_with?(path, "//") and not String.contains?(path, "\\")
  end

  defp user_key(user), do: user |> Map.get(:id) |> to_string()

  defp login(conn) do
    case get_session(conn, login_session_key()) do
      nil -> nil
      value -> :crypto.hash(:sha256, :erlang.term_to_binary(value)) |> Base.encode16(case: :lower)
    end
  end

  defp login_session_key do
    case Escalated.config(:two_factor, []) do
      opts when is_list(opts) -> Keyword.get(opts, :login_session_key, "user_token")
      opts when is_map(opts) -> Map.get(opts, :login_session_key, "user_token")
      _ -> "user_token"
    end
    |> to_string()
  end
end
