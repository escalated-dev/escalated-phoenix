defmodule Escalated.Controllers.NewsletterControllerTest do
  use ExUnit.Case, async: true

  test "newsletter modules load" do
    assert Code.ensure_loaded?(Escalated.Controllers.Admin.NewsletterController)
    assert Code.ensure_loaded?(Escalated.Controllers.Public.NewsletterTrackingController)
    assert Code.ensure_loaded?(Escalated.Controllers.Webhooks.NewsletterEspWebhookController)
    assert Code.ensure_loaded?(Escalated.Services.Newsletter.Dispatcher)
    assert Code.ensure_loaded?(Mix.Tasks.Escalated.Newsletters.Dispatch)
  end
end
