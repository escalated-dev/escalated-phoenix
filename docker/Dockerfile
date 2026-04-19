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

COPY docker/entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

ENV MIX_ENV=dev
ENV APP_ENV=demo
EXPOSE 4000

ENTRYPOINT ["entrypoint.sh"]
CMD ["mix", "phx.server"]
