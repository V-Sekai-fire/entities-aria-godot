# entities-aria-godot

An Elixir library that parses Godot's text scene (`.tscn`) and text resource (`.tres`) files.

## What it is for

It reads scenes and resources into Elixir data without running the engine, validating each file against an ABNF grammar of its format.

## Build

    mix deps.get
    mix compile

As a dependency: `{:aria_godot, git: "https://github.com/V-Sekai-fire/entities-aria-godot.git"}`.

## Licence

MIT. See [LICENSE](LICENSE).
