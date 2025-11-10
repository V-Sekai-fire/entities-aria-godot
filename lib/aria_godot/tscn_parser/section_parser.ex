# SPDX-License-Identifier: MIT
# Copyright (c) 2025-present K. S. Ernest (iFire) Lee

defmodule AriaGodot.TscnParser.SectionParser do
  @moduledoc """
  Parser for TSCN property values and Godot-specific types.

  Handles parsing of:
  - Primitives: strings, numbers, booleans
  - Godot types: Transform, Vector3, Color, etc.
  - Arrays: [1, 2, 3]
  - Dictionaries: {"key": "value"}
  - Resource references: ExtResource("1"), SubResource(1)
  """

  @doc """
  Parses a property value string into an Elixir term.

  Handles:
  - Primitives: strings, numbers, booleans
  - Godot constructors: Transform(...), Vector3(...), Color(...)
  - Arrays: [1, 2, 3]
  - Dictionaries: {"key": "value"}
  - Resource references: ExtResource("1"), SubResource(1)

  ## Examples

      parse_property_value("42")  # => 42
      parse_property_value("true")  # => true
      parse_property_value('"hello"')  # => "hello"
      parse_property_value("Vector3(1, 2, 3)")  # => %{type: "Vector3", x: 1, y: 2, z: 3}
  """
  @spec parse_property_value(String.t()) :: term()
  def parse_property_value(value) when is_binary(value) do
    trimmed = String.trim(value)

    cond do
      # Quoted string
      String.starts_with?(trimmed, ~s(")) and String.ends_with?(trimmed, ~s(")) ->
        String.slice(trimmed, 1..-2//1)

      # Single-quoted string
      String.starts_with?(trimmed, "'") and String.ends_with?(trimmed, "'") ->
        String.slice(trimmed, 1..-2//1)

      # Boolean
      trimmed == "true" ->
        true

      trimmed == "false" ->
        false

      # Null
      trimmed == "null" or trimmed == "Null" ->
        nil

      # Resource reference: ExtResource("1") or SubResource(1) - check before constructors
      String.starts_with?(trimmed, "ExtResource") or String.starts_with?(trimmed, "SubResource") ->
        parse_resource_reference(trimmed)

      # Godot constructor: TypeName(...)
      String.contains?(trimmed, "(") and String.ends_with?(trimmed, ")") ->
        parse_godot_constructor(trimmed)

      # Array: [1, 2, 3]
      String.starts_with?(trimmed, "[") and String.ends_with?(trimmed, "]") ->
        parse_array(trimmed)

      # Dictionary: {"key": "value"}
      String.starts_with?(trimmed, "{") and String.ends_with?(trimmed, "}") ->
        parse_dictionary(trimmed)

      # Number (integer or float)
      Regex.match?(~r/^-?\d+$/, trimmed) ->
        String.to_integer(trimmed)

      Regex.match?(~r/^-?\d+\.\d+$/, trimmed) ->
        String.to_float(trimmed)

      # Default: return as string
      true ->
        trimmed
    end
  end

  # Parse Godot constructor: TypeName(arg1, arg2, ...)
  defp parse_godot_constructor(value) do
    case Regex.run(~r/^(\w+)\((.*)\)$/, value) do
      [_, type_name, args_string] ->
        args = parse_constructor_args(args_string)

        case type_name do
          "Transform" ->
            parse_transform(args)

          "Transform2D" ->
            parse_transform2d(args)

          "Vector2" ->
            parse_vector2(args)

          "Vector3" ->
            parse_vector3(args)

          "Vector4" ->
            parse_vector4(args)

          "Color" ->
            parse_color(args)

          "Quaternion" ->
            parse_quaternion(args)

          "AABB" ->
            parse_aabb(args)

          "Plane" ->
            parse_plane(args)

          "Basis" ->
            parse_basis(args)

          _ ->
            # Unknown constructor - return as map
            %{type: type_name, args: args}
        end

      _ ->
        value
    end
  end

  # Parse constructor arguments (comma-separated)
  defp parse_constructor_args(args_string) do
    args_string
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.map(&parse_property_value/1)
  end

  # Parse Transform: Transform(basis, origin)
  # basis is Basis(3x3 matrix), origin is Vector3
  defp parse_transform([basis, origin]) do
    %{
      type: "Transform",
      basis: basis,
      origin: origin
    }
  end

  defp parse_transform(args) when is_list(args) and length(args) == 12 do
    # Transform from 12 floats (3x4 matrix)
    %{
      type: "Transform",
      matrix: args
    }
  end

  defp parse_transform(_), do: %{type: "Transform", args: []}

  # Parse Transform2D: Transform2D(xx, xy, yx, yy, ox, oy)
  defp parse_transform2d([xx, xy, yx, yy, ox, oy]) do
    %{
      type: "Transform2D",
      xx: xx,
      xy: xy,
      yx: yx,
      yy: yy,
      ox: ox,
      oy: oy
    }
  end

  defp parse_transform2d(_), do: %{type: "Transform2D", args: []}

  # Parse Vector2: Vector2(x, y)
  defp parse_vector2([x, y]) do
    %{type: "Vector2", x: x, y: y}
  end

  defp parse_vector2(_), do: %{type: "Vector2", x: 0, y: 0}

  # Parse Vector3: Vector3(x, y, z)
  defp parse_vector3([x, y, z]) do
    %{type: "Vector3", x: x, y: y, z: z}
  end

  defp parse_vector3(_), do: %{type: "Vector3", x: 0, y: 0, z: 0}

  # Parse Vector4: Vector4(x, y, z, w)
  defp parse_vector4([x, y, z, w]) do
    %{type: "Vector4", x: x, y: y, z: z, w: w}
  end

  defp parse_vector4(_), do: %{type: "Vector4", x: 0, y: 0, z: 0, w: 0}

  # Parse Color: Color(r, g, b, a) or Color(r, g, b)
  defp parse_color([r, g, b, a]) do
    %{type: "Color", r: r, g: g, b: b, a: a}
  end

  defp parse_color([r, g, b]) do
    %{type: "Color", r: r, g: g, b: b, a: 1.0}
  end

  defp parse_color(_), do: %{type: "Color", r: 0, g: 0, b: 0, a: 1.0}

  # Parse Quaternion: Quaternion(x, y, z, w)
  defp parse_quaternion([x, y, z, w]) do
    %{type: "Quaternion", x: x, y: y, z: z, w: w}
  end

  defp parse_quaternion(_), do: %{type: "Quaternion", x: 0, y: 0, z: 0, w: 1}

  # Parse AABB: AABB(position, size)
  defp parse_aabb([position, size]) do
    %{type: "AABB", position: position, size: size}
  end

  defp parse_aabb(_),
    do: %{type: "AABB", position: %{type: "Vector3", x: 0, y: 0, z: 0}, size: %{type: "Vector3", x: 0, y: 0, z: 0}}

  # Parse Plane: Plane(normal, d)
  defp parse_plane([normal, d]) do
    %{type: "Plane", normal: normal, d: d}
  end

  defp parse_plane(_), do: %{type: "Plane", normal: %{type: "Vector3", x: 0, y: 0, z: 1}, d: 0}

  # Parse Basis: Basis(x_axis, y_axis, z_axis) or Basis(9 floats)
  defp parse_basis([x_axis, y_axis, z_axis]) when is_map(x_axis) do
    %{type: "Basis", x_axis: x_axis, y_axis: y_axis, z_axis: z_axis}
  end

  defp parse_basis(args) when is_list(args) and length(args) == 9 do
    %{type: "Basis", matrix: args}
  end

  defp parse_basis(_), do: %{type: "Basis", matrix: [1, 0, 0, 0, 1, 0, 0, 0, 1]}

  # Parse array: [1, 2, 3]
  defp parse_array(value) do
    content =
      String.slice(value, 1..-2//1)
      |> String.trim()

    if content == "" do
      []
    else
      content
      |> String.split(",")
      |> Enum.map(&String.trim/1)
      |> Enum.filter(&(&1 != ""))
      |> Enum.map(&parse_property_value/1)
    end
  end

  # Parse dictionary: {"key": "value", "key2": 42}
  defp parse_dictionary(value) do
    content = String.slice(value, 1..-2//1)

    # Simple dictionary parser - handles "key": "value" pairs
    Regex.scan(~r/"([^"]+)":\s*([^,}]+)/, content)
    |> Enum.reduce(%{}, fn [_, key, val], acc ->
      parsed_val = String.trim(val) |> parse_property_value()
      Map.put(acc, key, parsed_val)
    end)
  end

  # Parse resource reference: ExtResource("1") or SubResource(1)
  defp parse_resource_reference(value) do
    case Regex.run(~r/^(ExtResource|SubResource)\(([^)]+)\)$/, value) do
      [_, type, id_string] ->
        # Parse the id value (could be quoted string or number)
        id = parse_property_value(id_string)
        %{type: type, id: id}

      _ ->
        value
    end
  end
end

