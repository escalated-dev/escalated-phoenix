defmodule Escalated.Routes do
  @moduledoc """
  The named routes the shared frontend calls through `route(name, params)`
  (Laravel's Ziggy helper), with the paths this package serves them at.

  Every Escalated Inertia response shares them as the `ziggy` prop, in the
  shape ziggy-js reads (`url`, `port`, `defaults`, `routes`, `location`; each
  route a `uri` without a leading slash, with `{param}` placeholders, and its
  `methods`). The URIs follow `config :escalated, route_prefix:`, which must be
  the prefix you pass to `escalated_routes/2`.

  The host owns the root layout, so it installs the matching `route()` helper
  once with `helper_tag/1` (see the README). The helper does nothing when the
  page already defines `window.route` (ziggy-js, or a shim of your own), and it
  reads `window.Ziggy.routes` before the shared prop.

  ## Overriding a name

  The host's mapping wins:

    * a `ziggy` prop the host shares itself (`Inertia.Controller.assign_prop/3`)
      is left as it is;
    * `config :escalated, route_overrides: %{...}` replaces single names, adds
      new ones (`login` is the host's), or removes one with `nil`. A value is a
      path (`"/users/log_in"`, read as GET) or `%{uri: ..., methods: [...]}`.

  ```elixir
  config :escalated,
    route_overrides: %{
      "login" => "/users/log_in",
      "escalated.customer.tickets.index" => %{uri: "/my/tickets", methods: ["GET"]}
    }
  ```
  """

  @get ["GET", "HEAD"]
  @post ["POST"]
  @put ["PUT", "PATCH"]
  @patch ["PATCH"]
  @delete ["DELETE"]

  # {name, path below the prefix, methods}. Placeholders use escalated-laravel's
  # parameter names so object params (`{ id: ... }`) fill them the same way.
  @routes [
    # Attachments and the two-factor challenge.
    {"escalated.attachments.download", "attachments/{attachment}/download", @get},
    {"escalated.two-factor.challenge", "two-factor/challenge", @get},
    {"escalated.two-factor.verify", "two-factor/challenge", @post},

    # Customer portal.
    {"escalated.customer.tickets.index", "tickets", @get},
    {"escalated.customer.tickets.create", "tickets/new", @get},
    {"escalated.customer.tickets.store", "tickets", @post},
    {"escalated.customer.tickets.show", "tickets/{ticket}", @get},
    {"escalated.customer.tickets.reply", "tickets/{ticket}/reply", @post},
    {"escalated.customer.tickets.close", "tickets/{ticket}/close", @post},
    {"escalated.customer.tickets.reopen", "tickets/{ticket}/reopen", @post},
    {"escalated.customer.tickets.rate", "tickets/{ticket}/rate", @post},
    {"escalated.customer.kb.index", "kb", @get},
    {"escalated.customer.kb.show", "kb/{slug}", @get},
    {"escalated.customer.kb.feedback", "kb/{slug}/feedback", @post},

    # Guest portal.
    {"escalated.guest.tickets.create", "guest/create", @get},
    {"escalated.guest.tickets.store", "guest", @post},
    {"escalated.guest.tickets.show", "guest/{token}", @get},
    {"escalated.guest.tickets.reply", "guest/{token}/reply", @post},
    {"escalated.guest.tickets.rate", "guest/{token}/rate", @post},
    {"escalated.guest.verification", "guest/verification", @post},
    {"escalated.guest.lookup", "guest/lookup", @post},

    # Agent.
    {"escalated.agent.dashboard", "agent/dashboard", @get},
    {"escalated.agent.tickets.index", "agent/tickets", @get},
    {"escalated.agent.tickets.bulk", "agent/tickets/bulk", @post},
    {"escalated.agent.tickets.show", "agent/tickets/{ticket}", @get},
    {"escalated.agent.tickets.update", "agent/tickets/{ticket}", @put},
    {"escalated.agent.tickets.reply", "agent/tickets/{ticket}/reply", @post},
    {"escalated.agent.tickets.note", "agent/tickets/{ticket}/note", @post},
    {"escalated.agent.tickets.assign", "agent/tickets/{ticket}/assign", @post},
    {"escalated.agent.tickets.status", "agent/tickets/{ticket}/status", @post},
    {"escalated.agent.tickets.priority", "agent/tickets/{ticket}/priority", @post},
    {"escalated.agent.tickets.macro", "agent/tickets/{ticket}/macro", @post},
    {"escalated.agent.tickets.custom-action", "agent/tickets/{ticket}/actions/{action}", @post},
    {"escalated.agent.tickets.follow", "agent/tickets/{ticket}/follow", @post},
    {"escalated.agent.tickets.presence", "agent/tickets/{ticket}/presence", @post},
    {"escalated.agent.tickets.pin", "agent/tickets/{ticket}/replies/{reply}/pin", @post},
    {"escalated.agent.tickets.snooze", "agent/tickets/{ticket}/snooze", @post},
    {"escalated.agent.tickets.unsnooze", "agent/tickets/{ticket}/unsnooze", @post},
    {"escalated.agent.tickets.split", "agent/tickets/{ticket}/split", @post},
    # Live chat on the ticket page, keyed by the ChatSession id the page
    # carries as `chat_session_id` (Laravel serves them under /admin/chat).
    {"escalated.admin.chat.end", "agent/chat/{session}/end", @post},
    {"escalated.admin.chat.transfer", "agent/chat/{session}/transfer", @post},
    # Saved views are served in the agent scope here (Laravel: /admin).
    {"escalated.admin.saved-views.index", "agent/saved-views", @get},
    {"escalated.admin.saved-views.store", "agent/saved-views", @post},
    {"escalated.admin.saved-views.update", "agent/saved-views/{savedView}", @put},
    {"escalated.admin.saved-views.destroy", "agent/saved-views/{savedView}", @delete},

    # Admin: tickets.
    {"escalated.admin.tickets.index", "admin/tickets", @get},
    {"escalated.admin.tickets.bulk", "admin/tickets/bulk", @post},
    {"escalated.admin.tickets.merge-search", "admin/tickets/merge-search", @get},
    {"escalated.admin.tickets.show", "admin/tickets/{ticket}", @get},
    {"escalated.admin.tickets.reply", "admin/tickets/{ticket}/reply", @post},
    {"escalated.admin.tickets.note", "admin/tickets/{ticket}/note", @post},
    {"escalated.admin.tickets.assign", "admin/tickets/{ticket}/assign", @post},
    {"escalated.admin.tickets.status", "admin/tickets/{ticket}/status", @post},
    {"escalated.admin.tickets.priority", "admin/tickets/{ticket}/priority", @post},
    {"escalated.admin.tickets.tags", "admin/tickets/{ticket}/tags", @post},
    {"escalated.admin.tickets.department", "admin/tickets/{ticket}/department", @post},
    {"escalated.admin.tickets.macro", "admin/tickets/{ticket}/macro", @post},
    {"escalated.admin.tickets.follow", "admin/tickets/{ticket}/follow", @post},
    {"escalated.admin.tickets.presence", "admin/tickets/{ticket}/presence", @post},
    {"escalated.admin.tickets.pin", "admin/tickets/{ticket}/replies/{reply}/pin", @post},
    {"escalated.admin.tickets.merge", "admin/tickets/{ticket}/merge", @post},
    {"escalated.admin.tickets.snooze", "admin/tickets/{ticket}/snooze", @post},
    {"escalated.admin.tickets.unsnooze", "admin/tickets/{ticket}/unsnooze", @post},
    {"escalated.admin.tickets.split", "admin/tickets/{ticket}/split", @post},
    {"escalated.admin.tickets.subjects.store", "admin/tickets/{ticket}/subjects", @post},
    {"escalated.admin.tickets.subjects.destroy", "admin/tickets/{ticket}/subjects/{subject}",
     @delete},
    {"escalated.admin.tickets.links.index", "admin/tickets/{ticket}/links", @get},
    {"escalated.admin.tickets.links.store", "admin/tickets/{ticket}/links", @post},
    {"escalated.admin.tickets.links.destroy", "admin/tickets/{ticket}/links/{link}", @delete},
    {"escalated.admin.tickets.side-conversations.index",
     "admin/tickets/{ticket}/side-conversations", @get},
    {"escalated.admin.tickets.side-conversations.store",
     "admin/tickets/{ticket}/side-conversations", @post},
    {"escalated.admin.tickets.side-conversations.reply",
     "admin/tickets/{ticket}/side-conversations/{sideConversation}/reply", @post},
    {"escalated.admin.tickets.side-conversations.close",
     "admin/tickets/{ticket}/side-conversations/{sideConversation}/close", @post},
    {"escalated.admin.agents.search", "admin/agents/search", @get},

    # Admin: settings.
    {"escalated.admin.settings", "admin/settings", @get},
    {"escalated.admin.settings.update", "admin/settings", @post},
    {"escalated.admin.settings.csat", "admin/settings/csat", @get},
    {"escalated.admin.settings.csat.update", "admin/settings/csat", @post},
    {"escalated.admin.settings.public-tickets", "admin/settings/public-tickets", @get},
    {"escalated.admin.settings.public-tickets.update", "admin/settings/public-tickets",
     ["POST", "PUT"]},
    {"escalated.admin.settings.sso", "admin/settings/sso", @get},
    {"escalated.admin.settings.sso.update", "admin/settings/sso", @post},
    {"escalated.admin.settings.database", "admin/settings/database", @get},
    {"escalated.admin.settings.database.test", "admin/settings/database/test", @post},
    {"escalated.admin.settings.database.update", "admin/settings/database", @post},
    {"escalated.admin.settings.data-retention", "admin/settings/data-retention", @get},
    {"escalated.admin.settings.data-retention.update", "admin/settings/data-retention", @post},
    {"escalated.admin.settings.email", "admin/settings/email", @get},
    {"escalated.admin.settings.email.update", "admin/settings/email", @post},
    {"escalated.admin.two-factor.index", "admin/settings/two-factor", @get},
    {"escalated.admin.two-factor.setup", "admin/settings/two-factor/setup", @post},
    {"escalated.admin.two-factor.confirm", "admin/settings/two-factor/confirm", @post},
    {"escalated.admin.two-factor.disable", "admin/settings/two-factor/disable", @post},

    # Admin: resources with Laravel's create/edit pages.
    {"escalated.admin.departments.index", "admin/departments", @get},
    {"escalated.admin.departments.create", "admin/departments/new", @get},
    {"escalated.admin.departments.store", "admin/departments", @post},
    {"escalated.admin.departments.edit", "admin/departments/{department}/edit", @get},
    {"escalated.admin.departments.update", "admin/departments/{department}", @put},
    {"escalated.admin.departments.destroy", "admin/departments/{department}", @delete},
    {"escalated.admin.sla-policies.index", "admin/sla-policies", @get},
    {"escalated.admin.sla-policies.create", "admin/sla-policies/create", @get},
    {"escalated.admin.sla-policies.store", "admin/sla-policies", @post},
    {"escalated.admin.sla-policies.edit", "admin/sla-policies/{sla_policy}/edit", @get},
    {"escalated.admin.sla-policies.update", "admin/sla-policies/{sla_policy}", @put},
    {"escalated.admin.sla-policies.destroy", "admin/sla-policies/{sla_policy}", @delete},
    {"escalated.admin.escalation-rules.index", "admin/escalation-rules", @get},
    {"escalated.admin.escalation-rules.create", "admin/escalation-rules/create", @get},
    {"escalated.admin.escalation-rules.store", "admin/escalation-rules", @post},
    {"escalated.admin.escalation-rules.edit", "admin/escalation-rules/{escalation_rule}/edit",
     @get},
    {"escalated.admin.escalation-rules.update", "admin/escalation-rules/{escalation_rule}", @put},
    {"escalated.admin.escalation-rules.destroy", "admin/escalation-rules/{escalation_rule}",
     @delete},
    {"escalated.admin.custom-fields.index", "admin/custom-fields", @get},
    {"escalated.admin.custom-fields.create", "admin/custom-fields/create", @get},
    {"escalated.admin.custom-fields.store", "admin/custom-fields", @post},
    {"escalated.admin.custom-fields.reorder", "admin/custom-fields/reorder", @post},
    {"escalated.admin.custom-fields.edit", "admin/custom-fields/{custom_field}/edit", @get},
    {"escalated.admin.custom-fields.update", "admin/custom-fields/{custom_field}", @put},
    {"escalated.admin.custom-fields.destroy", "admin/custom-fields/{custom_field}", @delete},
    {"escalated.admin.statuses.index", "admin/statuses", @get},
    {"escalated.admin.statuses.create", "admin/statuses/create", @get},
    {"escalated.admin.statuses.store", "admin/statuses", @post},
    {"escalated.admin.statuses.edit", "admin/statuses/{status}/edit", @get},
    {"escalated.admin.statuses.update", "admin/statuses/{status}", @put},
    {"escalated.admin.statuses.destroy", "admin/statuses/{status}", @delete},
    {"escalated.admin.business-hours.index", "admin/business-hours", @get},
    {"escalated.admin.business-hours.create", "admin/business-hours/create", @get},
    {"escalated.admin.business-hours.store", "admin/business-hours", @post},
    {"escalated.admin.business-hours.edit", "admin/business-hours/{business_hour}/edit", @get},
    {"escalated.admin.business-hours.update", "admin/business-hours/{business_hour}", @put},
    {"escalated.admin.business-hours.destroy", "admin/business-hours/{business_hour}", @delete},
    {"escalated.admin.roles.index", "admin/roles", @get},
    {"escalated.admin.roles.create", "admin/roles/create", @get},
    {"escalated.admin.roles.store", "admin/roles", @post},
    {"escalated.admin.roles.edit", "admin/roles/{role}/edit", @get},
    {"escalated.admin.roles.update", "admin/roles/{role}", @put},
    {"escalated.admin.roles.destroy", "admin/roles/{role}", @delete},
    {"escalated.admin.skills.index", "admin/skills", @get},
    {"escalated.admin.skills.create", "admin/skills/new", @get},
    {"escalated.admin.skills.store", "admin/skills", @post},
    {"escalated.admin.skills.edit", "admin/skills/{skill}/edit", @get},
    {"escalated.admin.skills.update", "admin/skills/{skill}", @put},
    {"escalated.admin.skills.destroy", "admin/skills/{skill}", @delete},
    {"escalated.admin.webhooks.index", "admin/webhooks", @get},
    {"escalated.admin.webhooks.create", "admin/webhooks/create", @get},
    {"escalated.admin.webhooks.store", "admin/webhooks", @post},
    {"escalated.admin.webhooks.edit", "admin/webhooks/{webhook}/edit", @get},
    {"escalated.admin.webhooks.update", "admin/webhooks/{webhook}", @put},
    {"escalated.admin.webhooks.destroy", "admin/webhooks/{webhook}", @delete},
    {"escalated.admin.webhooks.deliveries", "admin/webhooks/{webhook}/deliveries", @get},
    {"escalated.admin.webhooks.retry", "admin/webhooks/deliveries/{delivery}/retry", @post},
    {"escalated.admin.kb-articles.index", "admin/kb-articles", @get},
    {"escalated.admin.kb-articles.create", "admin/kb-articles/create", @get},
    {"escalated.admin.kb-articles.store", "admin/kb-articles", @post},
    {"escalated.admin.kb-articles.edit", "admin/kb-articles/{kb_article}/edit", @get},
    {"escalated.admin.kb-articles.update", "admin/kb-articles/{kb_article}", @put},
    {"escalated.admin.kb-articles.destroy", "admin/kb-articles/{kb_article}", @delete},
    {"escalated.admin.kb-categories.index", "admin/kb-categories", @get},
    {"escalated.admin.kb-categories.store", "admin/kb-categories", @post},
    {"escalated.admin.kb-categories.update", "admin/kb-categories/{kb_category}", @put},
    {"escalated.admin.kb-categories.destroy", "admin/kb-categories/{kb_category}", @delete},
    {"escalated.admin.custom-objects.index", "admin/custom-objects", @get},
    {"escalated.admin.custom-objects.create", "admin/custom-objects/create", @get},
    {"escalated.admin.custom-objects.store", "admin/custom-objects", @post},
    {"escalated.admin.custom-objects.edit", "admin/custom-objects/{customObject}/edit", @get},
    {"escalated.admin.custom-objects.update", "admin/custom-objects/{customObject}", @put},
    {"escalated.admin.custom-objects.destroy", "admin/custom-objects/{customObject}", @delete},
    {"escalated.admin.custom-objects.records", "admin/custom-objects/{customObject}/records",
     @get},
    {"escalated.admin.custom-objects.records.store",
     "admin/custom-objects/{customObject}/records", @post},
    {"escalated.admin.custom-objects.records.update",
     "admin/custom-objects/{customObject}/records/{record}", @put},
    {"escalated.admin.custom-objects.records.destroy",
     "admin/custom-objects/{customObject}/records/{record}", @delete},

    # Admin: resources edited on their index page.
    {"escalated.admin.tags.index", "admin/tags", @get},
    {"escalated.admin.tags.store", "admin/tags", @post},
    {"escalated.admin.tags.update", "admin/tags/{tag}", @put},
    {"escalated.admin.tags.destroy", "admin/tags/{tag}", @delete},
    {"escalated.admin.canned-responses.index", "admin/canned-responses", @get},
    {"escalated.admin.canned-responses.store", "admin/canned-responses", @post},
    {"escalated.admin.canned-responses.update", "admin/canned-responses/{cannedResponse}", @put},
    {"escalated.admin.canned-responses.destroy", "admin/canned-responses/{cannedResponse}",
     @delete},
    {"escalated.admin.macros.index", "admin/macros", @get},
    {"escalated.admin.macros.store", "admin/macros", @post},
    {"escalated.admin.macros.update", "admin/macros/{macro}", @put},
    {"escalated.admin.macros.destroy", "admin/macros/{macro}", @delete},
    {"escalated.admin.automations.index", "admin/automations", @get},
    {"escalated.admin.automations.store", "admin/automations", @post},
    {"escalated.admin.automations.update", "admin/automations/{automation}", @put},
    {"escalated.admin.automations.destroy", "admin/automations/{automation}", @delete},
    {"escalated.admin.capacity.index", "admin/capacity", @get},
    {"escalated.admin.capacity.update", "admin/capacity/{capacity}", @put},

    # Admin: users, audit log, plugins.
    {"escalated.admin.users.index", "admin/users", @get},
    {"escalated.admin.users.role", "admin/users/{user}/role", @patch},
    {"escalated.admin.users.roles", "admin/users/{user}/roles", ["PUT"]},
    {"escalated.admin.audit-log", "admin/audit-log", @get},
    {"escalated.admin.plugins.index", "admin/plugins", @get},
    {"escalated.admin.plugins.activate", "admin/plugins/{slug}/activate", @post},
    {"escalated.admin.plugins.deactivate", "admin/plugins/{slug}/deactivate", @post},
    {"escalated.admin.plugins.destroy", "admin/plugins/{slug}", @delete},

    # Admin: workflows (the builder is at /new; GET /{workflow} opens it too).
    {"escalated.admin.workflows.index", "admin/workflows", @get},
    {"escalated.admin.workflows.create", "admin/workflows/new", @get},
    {"escalated.admin.workflows.logs", "admin/workflows/logs", @get},
    {"escalated.admin.workflows.reorder", "admin/workflows/reorder", @post},
    {"escalated.admin.workflows.store", "admin/workflows", @post},
    {"escalated.admin.workflows.edit", "admin/workflows/{workflow}", @get},
    {"escalated.admin.workflows.update", "admin/workflows/{workflow}", @put},
    {"escalated.admin.workflows.destroy", "admin/workflows/{workflow}", @delete},
    {"escalated.admin.workflows.toggle", "admin/workflows/{workflow}/toggle", @post},
    {"escalated.admin.workflows.workflow-logs", "admin/workflows/{workflow}/logs", @get},

    # Admin: import wizard.
    {"escalated.admin.import.index", "admin/import", @get},
    {"escalated.admin.import.connect", "admin/import/{platform}/connect", @get},
    {"escalated.admin.import.test-connection", "admin/import/{platform}/test-connection", @post},
    {"escalated.admin.import.mapping", "admin/import/{platform}/mapping", @get},
    {"escalated.admin.import.review", "admin/import/{platform}/review", @post},
    {"escalated.admin.import.start", "admin/import/{platform}/start", @post},
    {"escalated.admin.import.progress", "admin/import/progress/{jobId}", @get},
    {"escalated.admin.import.status", "admin/import/status/{jobId}", @get},
    {"escalated.admin.import.pause", "admin/import/pause/{jobId}", @post},
    {"escalated.admin.import.resume", "admin/import/resume/{jobId}", @post},
    {"escalated.admin.import.cancel", "admin/import/cancel/{jobId}", @post},

    # Admin: reports.
    {"escalated.admin.reports", "admin/reports", @get},
    {"escalated.admin.reports.dashboard", "admin/reports/dashboard", @get},
    {"escalated.admin.reports.agents", "admin/reports/agents", @get},
    {"escalated.admin.reports.sla", "admin/reports/sla", @get},
    {"escalated.admin.reports.csat", "admin/reports/csat", @get},
    {"escalated.admin.reports.comparison", "admin/reports/comparison", @get},
    {"escalated.admin.reports.frt", "admin/reports/frt", @get},
    {"escalated.admin.reports.response-times", "admin/reports/response-times", @get},
    {"escalated.admin.reports.resolution", "admin/reports/resolution", @get},
    {"escalated.admin.reports.resolution-times", "admin/reports/resolution-times", @get},
    {"escalated.admin.reports.agent-ranking", "admin/reports/agent-ranking", @get},
    {"escalated.admin.reports.agent-detail", "admin/reports/agent/{id}/detail", @get},
    {"escalated.admin.reports.sla-trends", "admin/reports/sla-trends", @get},
    {"escalated.admin.reports.cohorts", "admin/reports/cohorts", @get}
  ]

  @doc """
  The built-in route table for `prefix` (default: the configured
  `route_prefix`), with the host's `route_overrides` applied.
  """
  @spec routes(String.t() | nil) :: %{String.t() => %{uri: String.t(), methods: [String.t()]}}
  def routes(prefix \\ nil) do
    base = prefix |> Kernel.||(Escalated.config(:route_prefix, "/support")) |> trim()

    built_in =
      Map.new(@routes, fn {name, path, methods} ->
        {name, %{uri: join(base, path), methods: methods}}
      end)

    Enum.reduce(overrides(), built_in, fn
      {name, nil}, acc -> Map.delete(acc, to_string(name))
      {name, value}, acc -> Map.put(acc, to_string(name), override(value))
    end)
  end

  @doc "The built-in names, without the host's overrides (for tests and tooling)."
  @spec names() :: [String.t()]
  def names, do: Enum.map(@routes, &elem(&1, 0))

  @doc """
  The `ziggy` shared prop for `conn`: `{url, port: nil, defaults: {}, routes,
  location}`, the shape ziggy-js reads.
  """
  @spec ziggy(Plug.Conn.t()) :: map()
  def ziggy(conn) do
    origin = origin(conn)
    query = if conn.query_string in [nil, ""], do: "", else: "?" <> conn.query_string

    %{
      url: origin,
      port: nil,
      defaults: %{},
      routes: routes(),
      location: origin <> conn.request_path <> query
    }
  end

  @doc """
  Shares the `ziggy` prop on `conn` unless the host already shares one (as
  `:ziggy` or `"ziggy"`); the host's own table wins.
  """
  @spec share(Plug.Conn.t()) :: Plug.Conn.t()
  def share(conn) do
    shared = conn.private[:inertia_shared] || %{}

    if Map.has_key?(shared, :ziggy) or Map.has_key?(shared, "ziggy") do
      conn
    else
      # apply/3: `inertia` is an optional dependency (see UIRenderer).
      # credo:disable-for-next-line Credo.Check.Refactor.Apply
      apply(Inertia.Controller, :assign_prop, [conn, :ziggy, ziggy(conn)])
    end
  end

  @helper """
  (function () {
    if (typeof window.route === 'function') return;
    var cached = null;
    function table() {
      if (cached) return cached;
      try {
        var el = document.querySelector('script[data-page]');
        var page = el ? JSON.parse(el.textContent) : JSON.parse(document.getElementById('app').dataset.page);
        var found = (page.props && page.props.ziggy) || null;
        if (found) cached = found;
        return found || {};
      } catch (e) { return {}; }
    }
    window.route = function (name, params) {
      var routes = (window.Ziggy && window.Ziggy.routes) || table().routes || {};
      var route = routes[name];
      if (!route) {
        if (window.console) console.warn('[escalated] no route named ' + name);
        return '#';
      }
      var list = params == null ? [] : (Array.isArray(params) ? params.slice() : (typeof params === 'object' ? null : [params]));
      var query = {};
      if (list === null) { for (var k in params) query[k] = params[k]; }
      var uri = route.uri.replace(/\\{(\\w+)\\??\\}/g, function (_, key) {
        var value;
        if (list !== null) { value = list.shift(); }
        else { value = query[key]; delete query[key]; }
        if (value != null && typeof value === 'object') value = value.reference != null ? value.reference : value.id;
        return value == null ? '' : encodeURIComponent(value);
      }).replace(/\\/+$/, '');
      var search = Object.keys(query).filter(function (key) { return query[key] != null; })
        .map(function (key) { return encodeURIComponent(key) + '=' + encodeURIComponent(query[key]); }).join('&');
      return '/' + uri + (search ? '?' + search : '');
    };
  })();
  """

  @doc """
  The `route()` helper as JavaScript. It installs `window.route` only when the
  page has none, reads `window.Ziggy.routes` first and then the page's `ziggy`
  prop, and returns `#` (with a console warning) for an unknown name.
  """
  @spec helper_script() :: String.t()
  def helper_script, do: @helper

  @doc """
  `helper_script/0` in a `<script>` tag, safe to render from a HEEx root
  layout: `{Escalated.Routes.helper_tag(nonce: @csp_nonce)}`. Put it in the
  body, before your app's bundle runs.
  """
  @spec helper_tag(keyword()) :: {:safe, iodata()}
  def helper_tag(opts \\ []) do
    nonce =
      case Keyword.get(opts, :nonce) do
        nil -> ""
        value -> ~s( nonce=") <> Plug.HTML.html_escape(to_string(value)) <> ~s(")
      end

    {:safe, ["<script", nonce, ">", @helper, "</script>"]}
  end

  defp overrides do
    case Application.get_env(:escalated, :route_overrides, %{}) do
      map when is_map(map) -> map
      list when is_list(list) -> Map.new(list)
      _ -> %{}
    end
  end

  defp override(uri) when is_binary(uri), do: %{uri: trim(uri), methods: @get}

  defp override(%{} = value) do
    uri = Map.get(value, :uri) || Map.get(value, "uri") || ""
    methods = Map.get(value, :methods) || Map.get(value, "methods") || @get
    %{uri: trim(uri), methods: Enum.map(methods, &(&1 |> to_string() |> String.upcase()))}
  end

  defp trim(path), do: String.trim(to_string(path), "/")

  defp join("", path), do: path
  defp join(base, path), do: base <> "/" <> path

  defp origin(conn) do
    default? =
      (conn.scheme == :https and conn.port == 443) or (conn.scheme == :http and conn.port == 80)

    port = if default? or is_nil(conn.port), do: "", else: ":#{conn.port}"
    "#{conn.scheme}://#{conn.host}#{port}"
  end
end
