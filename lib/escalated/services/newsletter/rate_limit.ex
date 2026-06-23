defmodule Escalated.Services.Newsletter.RateLimit do
  @moduledoc false
  @table :escalated_newsletter_sent_buckets

  def sent_this_minute do
    ensure_table()
    key = minute_key()
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
    ensure_table()
    :ets.delete_all_objects(@table)
    :ok
  end

  defp ensure_table do
    if :ets.info(@table) == :undefined do
      :ets.new(@table, [:named_table, :set, :public])
    end

    :ok
  end

  defp minute_key do
    {{y, m, d}, {h, min, _}} = :calendar.universal_time()

    :io_lib.format("~4..0w~2..0w~2..0w~2..0w~2..0w", [y, m, d, h, min])
    |> to_string()
  end
end
