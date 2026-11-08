[
  import_deps: [:phoenix],
  plugins: [Phoenix.LiveView.HTMLFormatter],
  # Ecto's DSL, used by the walkthrough projects under examples/ and projects/
  # (Ecto isn't a dependency of the site, so `import_deps` can't supply it).
  locals_without_parens: [
    field: 2,
    field: 3,
    add: 2,
    add: 3,
    create: 1,
    create: 2,
    belongs_to: 2,
    belongs_to: 3,
    has_many: 2,
    has_many: 3,
    timestamps: 0,
    timestamps: 1,
    from: 2
  ],
  inputs: [
    "{mix,.formatter}.exs",
    "{config,lib,test}/**/*.{ex,exs,heex}",
    "examples/**/*.exs",
    "projects/**/*.exs",
    "runner/{mix,.formatter}.exs",
    "runner/{config,lib}/**/*.{ex,exs}"
  ]
]
