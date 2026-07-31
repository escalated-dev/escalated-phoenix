defmodule Escalated.Controllers.Admin.WebhookControllerTest do
  use ExUnit.Case, async: true

  alias Escalated.Controllers.Admin.WebhookController

  describe "WebhookController module" do
    test "module is defined" do
      assert Code.ensure_loaded?(WebhookController)
    end

    test "exposes CRUD, deliveries log, and retry actions" do
      assert function_exported?(WebhookController, :index, 2)
      assert function_exported?(WebhookController, :create, 2)
      assert function_exported?(WebhookController, :update, 2)
      assert function_exported?(WebhookController, :delete, 2)
      assert function_exported?(WebhookController, :deliveries, 2)
      assert function_exported?(WebhookController, :retry, 2)
    end
  end
end
