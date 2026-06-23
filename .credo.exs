%{
  configs: [
    %{
      name: "default",
      files: %{
        included: ["lib/", "test/"],
        excluded: []
      },
      strict: true,
      checks: %{
        # Opinionated style checks disabled to match the rest of the codebase.
        # (with/else, inline nested-module references, and explicit try are used
        # throughout; these are stylistic preferences, not correctness issues.)
        disabled: [
          {Credo.Check.Design.AliasUsage, []},
          {Credo.Check.Refactor.WithClauses, []},
          {Credo.Check.Refactor.RedundantWithClauseResult, []}
        ]
      }
    }
  ]
}
