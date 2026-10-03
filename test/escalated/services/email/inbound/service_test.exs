defmodule Escalated.Services.Email.Inbound.ServiceTest do
  use ExUnit.Case, async: true
  alias Escalated.Services.Email.Inbound.Service
  alias Escalated.Services.Email.MessageIdUtil

  @secret "test-inbound-secret"
  @domain "support.example.com"

  defmodule FakeTicket do
    defstruct [:id, :reference, :guest_email, :requester_id, status: "open"]
  end

  defmodule FakeReply do
    defstruct [:id, :ticket_id, :body]
  end

  defp writer(opts \\ []) do
    created_ticket = Keyword.get(opts, :created_ticket, %FakeTicket{id: 101})
    created_reply = Keyword.get(opts, :created_reply, %FakeReply{id: 202})
    create_err = Keyword.get(opts, :create_err)
    reply_err = Keyword.get(opts, :reply_err)

    agent = Agent.start_link(fn -> %{create_calls: [], reply_calls: [], reopen_calls: []} end)
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
      end,
      reopen: fn ticket ->
        Agent.update(pid, fn s -> %{s | reopen_calls: s.reopen_calls ++ [ticket]} end)
        {:ok, %{ticket | status: "reopened"}}
      end
    }
  end

  defp lookup(tickets_by_id \\ %{}, opts \\ []) do
    by_ref = Keyword.get(opts, :by_ref, %{})
    requester_emails = Keyword.get(opts, :requester_emails, %{})

    %{
      get_ticket_by_id: fn id -> Map.get(tickets_by_id, id) end,
      get_ticket_by_reference: fn ref -> Map.get(by_ref, ref) end,
      requester_emails: fn ticket ->
        Map.get(requester_emails, ticket.id, [ticket.guest_email])
      end
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
      ticket = %FakeTicket{id: 42, guest_email: "customer@example.com"}
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

  describe "process/4 — who a matched email may post as" do
    test "a stranger quoting a ticket reference in the subject gets a new ticket" do
      ticket = %FakeTicket{id: 7001, reference: "ESC-07001", guest_email: "owner@example.com"}
      w = writer()

      m =
        message(%{
          from_email: "stranger@example.net",
          subject: "RE: [ESC-07001] Your order",
          body_text: "Injected reply."
        })

      assert {:ok, result} =
               Service.process(m, lookup(%{}, by_ref: %{"ESC-07001" => ticket}), w)

      assert result.outcome == :created_new
      assert result.ticket_id == 101
      assert result.reply_id == nil

      state = Agent.get(w.pid, & &1)
      assert state.reply_calls == []
      assert [%{guest_email: "stranger@example.net"}] = state.create_calls
    end

    test "a stranger threading onto a closed ticket neither replies nor reopens it" do
      ticket = %FakeTicket{id: 42, guest_email: "owner@example.com", status: "closed"}
      w = writer()

      m =
        message(%{
          from_email: "stranger@example.net",
          in_reply_to: "<ticket-42@support.example.com>",
          subject: "RE: Closed",
          body_text: "Reopen this."
        })

      assert {:ok, result} = Service.process(m, lookup(%{42 => ticket}), w)

      assert result.outcome == :created_new
      state = Agent.get(w.pid, & &1)
      assert state.reply_calls == []
      assert state.reopen_calls == []
    end

    test "a From header naming an agent is never posted as that agent" do
      ticket = %FakeTicket{id: 42, guest_email: "owner@example.com"}
      w = writer()

      m =
        message(%{
          from_email: "agent@example.com",
          to_email: MessageIdUtil.build_reply_to(42, @secret, @domain),
          in_reply_to: "<ticket-42@support.example.com>",
          subject: "RE: Update",
          body_text: "Refund approved."
        })

      assert {:ok, result} =
               Service.process(m, lookup(%{42 => ticket}), w, %{inbound_secret: @secret})

      assert result.outcome == :created_new
      state = Agent.get(w.pid, & &1)
      assert state.reply_calls == []
      assert [%{guest_email: "agent@example.com"}] = state.create_calls
    end

    test "a signed reply from the requester is accepted as the requester and reopens" do
      ticket = %FakeTicket{id: 42, requester_id: 9, status: "resolved"}
      w = writer()

      m =
        message(%{
          from_email: "Owner@Example.com",
          to_email: MessageIdUtil.build_reply_to(42, @secret, @domain),
          subject: "RE: Question",
          body_text: "Still broken."
        })

      l = lookup(%{42 => ticket}, requester_emails: %{42 => [nil, "owner@example.com"]})

      assert {:ok, result} = Service.process(m, l, w, %{inbound_secret: @secret})

      assert result.outcome == :replied_to_existing
      assert result.ticket_id == 42
      state = Agent.get(w.pid, & &1)
      assert [{^ticket, %{author_id: 9, body: "Still broken."}}] = state.reply_calls
      assert state.reopen_calls == [ticket]
      assert state.create_calls == []
    end

    test "a guest requester's reply is posted without an author and leaves an open ticket alone" do
      ticket = %FakeTicket{id: 42, guest_email: "guest@example.com", status: "open"}
      w = writer()

      m =
        message(%{
          from_email: "GUEST@example.com",
          in_reply_to: "<ticket-42@support.example.com>"
        })

      assert {:ok, %{outcome: :replied_to_existing}} =
               Service.process(m, lookup(%{42 => ticket}), w)

      state = Agent.get(w.pid, & &1)
      assert [{_, %{author_id: nil}}] = state.reply_calls
      assert state.reopen_calls == []
    end

    test "once a secret is set, unsigned headers and subject references do not thread" do
      ticket = %FakeTicket{id: 42, reference: "ESC-00042", guest_email: "owner@example.com"}
      w = writer()

      m =
        message(%{
          from_email: "owner@example.com",
          to_email: "support@support.example.com",
          in_reply_to: "<ticket-42@support.example.com>",
          references: "<ticket-42@support.example.com>",
          subject: "RE: [ESC-00042] Question",
          body_text: "Unsigned follow-up."
        })

      l = lookup(%{42 => ticket}, by_ref: %{"ESC-00042" => ticket})

      assert {:ok, result} = Service.process(m, l, w, %{inbound_secret: @secret})

      assert result.outcome == :created_new
      assert Agent.get(w.pid, & &1).reply_calls == []
    end

    test "a forged Reply-To signature does not thread" do
      ticket = %FakeTicket{id: 42, guest_email: "owner@example.com"}
      w = writer()

      m =
        message(%{
          from_email: "owner@example.com",
          to_email: MessageIdUtil.build_reply_to(42, "wrong-secret", @domain)
        })

      assert {:ok, %{outcome: :created_new}} =
               Service.process(m, lookup(%{42 => ticket}), w, %{inbound_secret: @secret})
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
