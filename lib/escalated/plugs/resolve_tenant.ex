defmodule Escalated.Plugs.ResolveTenant do
  @moduledoc "Resolves merchant identity through trusted host routing and checks membership."
  @behaviour Plug
  import Plug.Conn
  alias Escalated.Tenancy

  def init(opts), do: opts

  def call(conn, _opts) do
    # A keep-alive request or test must never inherit another request's context.
    Tenancy.clear()

    if Tenancy.enabled?() do
      id =
        case Tenancy.resolve(conn) do
          {:ok, value} -> value
          value -> value
        end

      Tenancy.put!(id)

      if conn.assigns[:current_user] && not Tenancy.member?(conn.assigns.current_user) do
        denied(conn)
      else
        conn
        |> assign(:escalated_tenant_id, Tenancy.current_id!())
        |> register_before_send(fn response ->
          Tenancy.clear()
          response
        end)
      end
    else
      conn
    end
  rescue
    Tenancy.Error -> denied(conn)
  end

  defp denied(conn) do
    Tenancy.clear()
    conn |> put_status(403) |> Phoenix.Controller.json(%{error: "Tenant access denied"}) |> halt()
  end
end
