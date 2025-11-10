# AriaGodot

Standalone Elixir module for parsing Godot TSCN (Text SCeNe) and TRES (Text RESource) files.

## Overview

AriaGodot provides native Elixir parsers for Godot Engine's text-based file formats:

* **TSCN Parser** - Parses Godot scene files (.tscn)
* **TRES Parser** - Parses Godot resource files (.tres)
* **Section Parser** - Shared parser for Godot property values and types

## Features

* Native Elixir implementation (no external dependencies for parsing)
* ABNF grammar-based validation
* Supports Godot 2.x, 3.x, and 4.x format versions
* Handles all Godot property types:
  - Primitives: strings, numbers, booleans
  - Vectors: Vector2, Vector3, Vector4
  - Transforms: Transform, Transform2D
  - Colors: Color
  - Arrays and dictionaries
  - Resource references: ExtResource, SubResource

## Installation

Add `aria_godot` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:aria_godot, path: "deps/aria_godot"}
  ]
end
```

Or use a git dependency:

```elixir
def deps do
  [
    {:aria_godot, git: "https://github.com/V-Sekai-fire/aria-godot.git"}
  ]
end
```

## Usage

### Parsing TSCN Files

```elixir
alias AriaGodot.TscnParser

{:ok, tscn_data} = TscnParser.parse_tscn("scene.tscn")
# Returns: %{
#   scene: %{format_version: 3, load_steps: 2, ...},
#   ext_resources: [...],
#   sub_resources: [...],
#   nodes: [...],
#   connections: [...]
# }
```

### Parsing TRES Files

```elixir
alias AriaGodot.TresParser

{:ok, tres_data} = TresParser.parse_tres("resource.tres")
# Returns: %{
#   format_version: 3,
#   resource_type: "Material",
#   ext_resources: [...],
#   sub_resources: [...],
#   resource: %{properties: %{...}}
# }
```

### Parsing Content from Strings

```elixir
tscn_content = File.read!("scene.tscn")
{:ok, tscn_data} = TscnParser.parse_tscn_content(tscn_content)
```

## Requirements

* Elixir ~> 1.18
* abnf_parsec ~> 2.1 (for ABNF grammar parsing)

## License

MIT

