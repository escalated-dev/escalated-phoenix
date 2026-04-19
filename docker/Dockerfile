# syntax=docker/dockerfile:1.7
FROM elixir:1.17-alpine AS builder

RUN apk add --no-cache build-base git postgresql-client nodejs npm inotify-tools

WORKDIR /host

RUN mix local.hex --force && mix local.rebar --force \
    && mix archive.install --force hex phx_new 1.7.14

# Bootstrap a minimal Phoenix app (no LiveView, no assets, no mailer; just core + ecto + Postgres).
RUN yes Y | mix phx.new . --app escalated_demo --no-install --no-mailer --no-gettext --no-live --no-html --no-assets --database postgres

# Mount the lib as a local dep
COPY mix.exs /package/mix.exs
COPY lib /package/lib
COPY priv /package/priv
COPY config /package/config

# Add the gem path dep right after the existing deps list opening bracket
RUN python3 -c "import re,pathlib; p=pathlib.Path('mix.exs'); t=p.read_text(); t=re.sub(r'(\\{:dns_cluster,[^}]+\\},)', r'\\1\\n      {:escalated, path: \"/package\"},', t, count=1); p.write_text(t)" \
    || sed -i 's|{:dns_cluster,[^}]*},|&\n      {:escalated, path: "/package"},|' mix.exs

RUN apk add --no-cache python3 \
    && mix deps.get || echo "[demo] mix deps.get failed - see PR body"

# Patch dev.exs: read DB connection from env (defaults to compose service "db") and bind 0.0.0.0.
RUN sed -i \
    -e 's|hostname: "localhost"|hostname: System.get_env("POSTGRES_HOST", "db")|' \
    -e 's|username: "postgres"|username: System.get_env("POSTGRES_USER", "escalated")|' \
    -e 's|password: "postgres"|password: System.get_env("POSTGRES_PASSWORD", "escalated")|' \
    -e 's|database: "escalated_demo_dev"|database: System.get_env("POSTGRES_DB", "escalated")|' \
    -e 's|http: \[ip: {127, 0, 0, 1}|http: [ip: {0, 0, 0, 0}|' \
    config/dev.exs

# Add a /demo placeholder route so curl can verify the host bootstraps end-to-end.
COPY docker/host-app/demo_router.ex /host/lib/escalated_demo_web/router.ex

COPY docker/entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

ENV MIX_ENV=dev
ENV APP_ENV=demo
EXPOSE 4000

ENTRYPOINT ["entrypoint.sh"]
CMD ["mix", "phx.server"]
