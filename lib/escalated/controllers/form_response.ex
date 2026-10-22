defmodule Escalated.Controllers.FormResponse do
  @moduledoc """
  How an admin form write answers, for controllers serving the shared pages.

  An Inertia form visit cannot consume a JSON 422: it needs the errors in the
  session and a redirect back, which `useForm` turns into `form.errors`.
  Requests without the `X-Inertia` header keep the JSON 422 they always had.
  """
  import Plug.Conn
  import Phoenix.Controller, only: [redirect: 2, json: 2]

  @doc "Answers a failed changeset (or an error map) for `conn`."
  def invalid(conn, %Ecto.Changeset{} = changeset, fallback_path),
    do: invalid(conn, errors(changeset), fallback_path)

  def invalid(conn, errors, fallback_path) when is_map(errors) do
    if inertia?(conn) do
      conn
      |> assign_inertia_errors(errors)
      |> redirect(to: back_path(conn, fallback_path))
    else
      conn |> put_status(422) |> json(%{errors: errors})
    end
  end

  @doc "Whether the request is an Inertia visit."
  def inertia?(conn), do: get_req_header(conn, "x-inertia") == ["true"]

  @doc "Changeset errors as `%{field => [message]}`."
  def errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end

  # Inertia shows the first message per field.
  defp assign_inertia_errors(conn, errors) do
    flat =
      Map.new(errors, fn
        {field, [message | _]} -> {field, message}
        {field, message} -> {field, message}
      end)

    if Code.ensure_loaded?(Inertia.Controller) do
      # apply/3 because `inertia` is an optional dependency.
      # credo:disable-for-next-line Credo.Check.Refactor.Apply
      apply(Inertia.Controller, :assign_errors, [conn, flat])
    else
      conn
    end
  end

  # The page the form was submitted from. redirect/2 only accepts a local
  # path, so only the path and query of the Referer are kept.
  defp back_path(conn, fallback) do
    with [referer | _] <- get_req_header(conn, "referer"),
         %URI{path: "/" <> rest = path, query: query} <- URI.parse(referer),
         false <- String.starts_with?(rest, "/") do
      if query, do: "#{path}?#{query}", else: path
    else
      _ -> fallback
    end
  end
end
