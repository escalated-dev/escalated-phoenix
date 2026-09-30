defmodule Escalated.Services.Newsletter.RateLimit do
  @moduledoc false
  @table :escalated_newsletter_sent_buckets

  def sent_this_minute do
    key = minute_key()
    lookup_count(key)
  end

  defp lookup_count(key) do
    ensure_table()
    :ets.lookup_element(@table, key, 2, 0)
  rescue
    ArgumentError -> 0
  end

  def increment(count) when is_integer(count) and count >= 0 do
    ensure_table()
    key = minute_key()
    :ets.update_counter(@table, key, count, {key, 0})
  end

  def reset do
    tenant_id = Escalated.Tenancy.current_id!()
    ensure_table()
    :ets.match_delete(@table, {{tenant_id, :_}, :_})
    :ok
  end

  defp ensure_table do
    if :ets.info(@table) == :undefined do
      :ets.new(@table, [:named_table, :set, :public])
    end

    :ok
  end

  defp minute_key do
    tenant_id = Escalated.Tenancy.current_id!()
    {{y, m, d}, {h, min, _}} = :calendar.universal_time()

    minute = :io_lib.format("~4..0w~2..0w~2..0w~2..0w~2..0w", [y, m, d, h, min]) |> to_string()
    {tenant_id, minute}
  end
end
