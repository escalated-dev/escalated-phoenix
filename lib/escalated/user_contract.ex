defmodule Escalated.UserContract do
  @moduledoc """
  What Escalated needs from the host's users, checked where staff actions
  resolve a user, so a host that is not set up gets an error that says what to
  change instead of a raw `UndefinedFunctionError` or `Protocol.UndefinedError`
  on the first click.

  The contract:

    * `config :escalated, user_schema:` is an Ecto schema (`use Ecto.Schema`)
      for the host's users with an `:id` field, the key Escalated stores for
      requesters, assignees and authors. `:email`, and `:name` (or a `name/1`
      function), are what the pages show.
    * `conn.assigns.current_user` is a struct or map with that `:id`.
    * Staff are recognised by `config :escalated, agent_check:` and
      `admin_check:` (one-argument functions returning a boolean), or by
      `is_agent` / `is_admin` boolean fields on the user schema, or by active
      Escalated agent profiles.

  `problems/0` lists what is missing (`mix escalated.doctor` prints it).
  """

  defmodule Error do
    @moduledoc "Raised when the host's user setup does not meet `Escalated.UserContract`."
    defexception [:message]
  end

  @contract """
  Set `config :escalated, user_schema: MyApp.Accounts.User` to the Ecto schema of \
  your users (`use Ecto.Schema`, with an `:id` primary key and `:email` and `:name` \
  fields), and assign that user (or a map with its `:id`) to `conn.assigns.current_user`. \
  See Escalated.UserContract and `mix escalated.doctor`.\
  """

  @doc """
  The configured user schema, or raises `Escalated.UserContract.Error` naming
  the contract when it is unset or not an Ecto schema with an `:id` field.
  """
  def schema! do
    case schema_problem(Escalated.config(:user_schema)) do
      nil -> Escalated.config(:user_schema)
      problem -> raise Error, message: "Escalated: #{problem}. #{@contract}"
    end
  end

  @doc """
  Raises `Escalated.UserContract.Error` when `user` (the signed-in user a
  staff route resolved) is not a struct or map carrying an `:id`. `nil` (no
  one signed in) passes; the gates answer 401 for it.
  """
  def check_current_user!(nil), do: :ok

  def check_current_user!(user) when is_map(user) do
    if Map.has_key?(user, :id) or Map.has_key?(user, "id") do
      :ok
    else
      raise Error,
        message:
          "Escalated: conn.assigns.current_user (#{describe(user)}) has no :id field. " <>
            @contract
    end
  end

  def check_current_user!(user) do
    raise Error,
      message:
        "Escalated: conn.assigns.current_user must be your user struct or a map with " <>
          ":id, got #{describe(user)}. " <> @contract
  end

  @doc """
  Setup problems, as `{:error | :warning, message}`. Empty when the user
  schema meets the contract and staff can be recognised.
  """
  def problems do
    schema = Escalated.config(:user_schema)

    case schema_problem(schema) do
      nil -> field_warnings(schema) ++ gate_warnings(schema)
      problem -> [{:error, problem <> ". " <> @contract} | gate_warnings(nil)]
    end
  end

  defp schema_problem(nil), do: "config :escalated, :user_schema is not set"

  defp schema_problem(schema) when is_atom(schema) do
    cond do
      not Code.ensure_loaded?(schema) ->
        "the user schema #{inspect(schema)} is not a module that can be loaded"

      not function_exported?(schema, :__schema__, 1) ->
        "the user schema #{inspect(schema)} is not an Ecto schema"

      :id not in schema.__schema__(:fields) ->
        "the user schema #{inspect(schema)} has no :id field"

      true ->
        nil
    end
  end

  defp schema_problem(schema),
    do: "config :escalated, :user_schema must be a module, got #{inspect(schema)}"

  defp field_warnings(schema) do
    fields = schema.__schema__(:fields)

    name? = :name in fields or function_exported?(schema, :name, 1)

    [
      {:email in fields, "#{inspect(schema)} has no :email field; pages show no address"},
      {name?, "#{inspect(schema)} has no :name field or name/1; pages show the email instead"}
    ]
    |> Enum.reject(&elem(&1, 0))
    |> Enum.map(&{:warning, elem(&1, 1)})
  end

  defp gate_warnings(schema) do
    flags? =
      schema != nil and
        Enum.any?([:is_agent, :is_admin], &(&1 in schema.__schema__(:fields)))

    gates? =
      is_function(Escalated.config(:agent_check), 1) or
        is_function(Escalated.config(:admin_check), 1)

    if gates? or flags? do
      []
    else
      [
        {:warning,
         "no staff gate: neither agent_check nor admin_check is configured and the user " <>
           "schema has no is_agent / is_admin field, so only users with an active Escalated " <>
           "agent profile can reach the agent and admin pages. Set " <>
           "`config :escalated, agent_check: &MyApp.Accounts.agent?/1, " <>
           "admin_check: &MyApp.Accounts.admin?/1`"}
      ]
    end
  end

  defp describe(%{__struct__: module}), do: "a %#{inspect(module)}{}"
  defp describe(user) when is_map(user), do: "a map with keys #{inspect(Map.keys(user))}"
  defp describe(_user), do: "a value that is not a map"
end
