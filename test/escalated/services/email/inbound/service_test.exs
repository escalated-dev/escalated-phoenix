defmodule Escalated.Services.Email.Inbound.ServiceTest do
  use ExUnit.Case, async: true
  alias Escalated.Services.Email.Inbound.Service

  defmodule FakeTicket do
    defstruct [:id, :reference]
  end

  defmodule FakeReply do
    defstruct [:id, :ticket_id, :body]
  end

  defp writer(opts \\ []) do
    created_ticket = Keyword.get(opts, :created_ticket, %FakeTicket{id: 101})
    created_reply = Keyword.get(opts, :created_reply, %FakeReply{id: 202})
    create_err = Keyword.get(opts, :create_err)
    reply_err = Keyword.get(opts, :reply_err)

    agent = Agent.start_link(fn -> %{create_calls: [], reply_calls: []} end)
    {:ok, pid} = agent

    %{
      pid: pid,
      create: fn attrs ->
        Agent.update(pid, fn s -> %{s | create_calls: s.create_calls ++ [attrs]} end)
        if create_err, do: {:error, create_err}, else: {:ok, created_ticket}
      end,
      add_reply: fn ticket, attrs ->
        Agent.update(pid, fn s ->
          %{s | reply_calls: s.reply_calls ++ [{ticket, attrs}]}
        end)

        if reply_err, do: {:error, reply_err}, else: {:ok, created_reply}
      end
    }
  end

  defp lookup(tickets_by_id \\ %{}) do
    %{
      get_ticket_by_id: fn id -> Map.get(tickets_by_id, id) end,
      get_ticket_by_reference: fn _ref -> nil end
    }
  end

  defp message(overrides \\ %{}) do
    defaults = %{
      from_email: "customer@example.com",
      from_name: "Customer",
      to_email: "support@example.com",
      subject: "hello",
      body_text: "body"
    }

    Map.merge(defaults, overrides)
  end

  describe "process/4" do
    test "matched ticket → adds reply, outcome :replied_to_existing" do
      ticket = %FakeTicket{id: 42}
      l = lookup(%{42 => ticket})
      w = writer()
      m = message(%{in_reply_to: "<ticket-42@support.example.com>"})

      assert {:ok, result} = Service.process(m, l, w)

      assert result.outcome == :replied_to_existing
      assert result.ticket_id == 42
      assert result.reply_id == 202
      state = Agent.get(w.pid, & &1)
      assert length(state.reply_calls) == 1
      assert state.create_calls == []

      {called_ticket, reply_attrs} = hd(state.reply_calls)
      assert called_ticket == ticket
      assert reply_attrs.body == "body"
      assert reply_attrs.author_type == "inbound_email"
    end

    test "no match + real content → creates new ticket" do
      w = writer()
      m = message(%{subject: "New issue", body_text: "real"})

      assert {:ok, result} = Service.process(m, lookup(), w)

      assert result.outcome == :created_new
      assert result.ticket_id == 101
      assert result.reply_id == nil

      state = Agent.get(w.pid, & &1)
      assert length(state.create_calls) == 1
      assert state.reply_calls == []

      attrs = hd(state.create_calls)
      assert attrs.subject == "New issue"
      assert attrs.description == "real"
      assert attrs.guest_email == "customer@example.com"
      assert attrs.guest_name == "Customer"
    end

    test "empty subject falls back to (no subject)" do
      w = writer()
      m = message(%{subject: "", body_text: "has content"})

      assert {:ok, _} = Service.process(m, lookup(), w)
      attrs = w.pid |> Agent.get(& &1) |> Map.get(:create_calls) |> hd()
      assert attrs.subject == "(no subject)"
    end

    test "SNS confirmation → skipped" do
      w = writer()
      m =
        message(%{from_email: "no-reply@sns.amazonaws.com", subject: "SubscriptionConfirmation"})

      assert {:ok, result} = Service.process(m, lookup(), w)
      assert result.outcome == :skipped
      state = Agent.get(w.pid, & &1)
      assert state.create_calls == []
      assert state.reply_calls == []
    end

    test "empty body and subject → skipped" do
      w = writer()
      m = message(%{subject: "", body_text: ""})

      assert {:ok, result} = Service.process(m, lookup(), w)
      assert result.outcome == :skipped
    end

    test "propagates writer errors" do
      w = writer(create_err: :db_offline)
      m = message(%{subject: "new", body_text: "content"})

      assert {:error, :db_offline} = Service.process(m, lookup(), w)
    end

    test "surfaces only provider-hosted attachments in pending downloads" do
      w = writer()

      m =
        message(%{
          subject: "With attachments",
          body_text: "See attached",
          attachments: [
            %{
              name: "large.pdf",
              content_type: "application/pdf",
              size_bytes: 10_000_000,
              download_url: "https://mailgun.example/att/large"
            },
            %{
              name: "inline.txt",
              content_type: "text/plain",
              content: "hello"
            }
          ]
        })

      assert {:ok, result} = Service.process(m, lookup(), w)

      assert [%{name: "large.pdf", download_url: "https://mailgun.example/att/large"}] =
               result.pending_attachment_downloads
    end

    test "accepts string-keyed message maps (webhook pass-through)" do
      w = writer()

      m = %{
        "from_email" => "x@y.com",
        "from_name" => "X",
        "to_email" => "support@example.com",
        "subject" => "string-key",
        "body_text" => "via string keys"
      }

      assert {:ok, result} = Service.process(m, lookup(), w)
      assert result.outcome == :created_new
    end
  end

  describe "noise_email?/1" do
    test "true for SNS confirmations" do
      assert Service.noise_email?(%{from_email: "no-reply@sns.amazonaws.com"})
    end

    test "true for empty body+subject" do
      assert Service.noise_email?(%{from_email: "a@b", subject: "", body_text: ""})
    end

    test "false for real content" do
      refute Service.noise_email?(message())
    end
  end
end
