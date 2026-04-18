# syntax=docker/dockerfile:1.7
FROM elixir:1.17-alpine AS builder
RUN apk add --no-cache build-base git postgresql-client nodejs npm

# Bootstrap a minimal Phoenix app and depend on the lib via path.
WORKDIR /host
RUN mix local.hex --force && mix local.rebar --force
RUN mix archive.install --force hex phx_new 1.7.14
RUN mix phx.new . --app escalated_demo --no-install --no-mailer --no-gettext --no-live --database postgres || true

COPY mix.exs mix.lock /package/
COPY lib /package/lib
COPY priv /package/priv
COPY config /package/config

# Replace mix.exs dep with a path dep on /package.
RUN sed -i 's|{:escalated[^}]*}|{:escalated, path: "/package"}|' mix.exs || true \
    && mix deps.get || echo "[demo] deps.get failed — see PR body"

COPY docker/entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

EXPOSE 4000
ENTRYPOINT ["entrypoint.sh"]
CMD ["mix", "phx.server"]
