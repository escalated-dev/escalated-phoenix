# Escalated Phoenix — Docker demo (scaffold, not end-to-end)

Draft Elixir/Phoenix scaffold. Boots a `phx.new` skeleton in the builder stage and tries to depend on the lib via `{:escalated, path: "/package"}`.

**Not end-to-end.** Phoenix project scaffolding with a `path:` dep on the lib is tricky to automate non-interactively — seeds, a /demo controller, LiveView vs plain controller wiring, and the actual router integration are all TODO.
