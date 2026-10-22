defmodule Escalated.Import.Context do
  @moduledoc """
  Import mode, as escalated-laravel's `Support\\ImportContext`. While an import
  runs, SLA attachment and breach and warning checks, escalation rules and
  automations stand down, so imported history does not fire as if it were new.

  The flag lives in the process dictionary of the process running the import
  (a supervised task), so live requests are never in import mode.
  """

  @key {__MODULE__, :importing}

  @doc "True inside `suppress/1`."
  def importing?, do: Process.get(@key, 0) > 0

  @doc "Runs `fun` in import mode and returns its result."
  def suppress(fun) when is_function(fun, 0) do
    Process.put(@key, Process.get(@key, 0) + 1)

    try do
      fun.()
    after
      Process.put(@key, Process.get(@key, 1) - 1)
    end
  end
end
