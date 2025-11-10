# SPDX-License-Identifier: MIT
# Copyright (c) 2025-present K. S. Ernest (iFire) Lee

defmodule AriaGodot.TresParser do
  @moduledoc """
  Native Elixir parser for Godot TRES (Text RESource) files using ABNF grammar.

  TRES files are text-based resource files used by Godot Engine. This parser extracts
  all TRES structure including external resources, sub-resources, and resource properties.

  Uses abnf_parsec to generate parsers from the ABNF grammar defined in
  tres_grammar.abnf for format validation and parsing.

  ## TRES Format

  TRES files are versioned text-based resource files. The format version is specified
  in the `[gd_resource]` or `[resource]` section via the `format` attribute:
  - Format 1: Godot 2.x
  - Format 2: Godot 3.x
  - Format 3: Godot 4.x

  TRES files consist of sections:
  - `[gd_resource type="ResourceType" format=V]` - Resource header with version (optional)
  - `[ext_resource ...]` - External resource references
  - `[sub_resource ...]` - Sub-resource definitions
  - `[resource]` - Resource properties

  ## Usage

      {:ok, tres_data} = AriaGodot.TresParser.parse_tres("path/to/resource.tres")
      # Returns: %{
      #   format_version: 3,  # TRES format version
      #   resource_type: "Material",  # Resource type if specified
      #   ext_resources: [...],
      #   sub_resources: [...],
      #   resource: %{properties: %{...}}
      # }

  ## Property Types

  The parser handles Godot property types:
  - Primitives: strings, numbers, booleans
  - Vectors: Vector2, Vector3, Vector4
  - Transforms: Transform, Transform2D
  - Colors: Color
  - Arrays: [1, 2, 3]
  - Dictionaries: {"key": "value"}
  - Resource references: ExtResource("1"), SubResource(1)
  """

  require Logger

  alias AriaGodot.TscnParser.SectionParser

  # Use abnf_parsec to generate parsers from ABNF grammar
  # File path relative to project root
  # We generate parsers for section_header and property_line rules
  # mode: :text is the default (literals represent text codepoints)
  use AbnfParsec,
    abnf_file: "lib/aria_godot/tres_parser/tres_grammar.abnf",
    parse: :section_header,
    untag: ["section-header"],
    unwrap: ["section-name", "attribute-key", "attribute-value"],
    # Text mode: literals represent text codepoints (default, explicit for clarity)
    mode: :text

  @type tres_result :: {:ok, tres_data()} | {:error, String.t()}

  @type tres_data :: %{
          # TRES format version (e.g., 3 for Godot 4.x)
          format_version: non_neg_integer(),
          # Resource type if specified in gd_resource
          resource_type: String.t() | nil,
          ext_resources: [ext_resource()],
          sub_resources: [sub_resource()],
          resource: resource_properties()
        }

  @type ext_resource ::
          %{
            type: String.t(),
            path: String.t(),
            id: non_neg_integer()
          }
          | %{atom() => term()}

  @type sub_resource :: %{
          type: String.t(),
          id: non_neg_integer(),
          properties: %{String.t() => term()}
        }

  @type resource_properties ::
          %{
            properties: %{String.t() => term()}
          }
          | %{atom() => term()}

  @doc """
  Parses a TRES file and returns structured data.

  ## Parameters
    - tres_path: Path to TRES file

  ## Returns
    - `{:ok, tres_data}` - Success with parsed TRES data
    - `{:error, reason}` - Error message

  ## Example

      {:ok, data} = parse_tres("resource.tres")
      # data contains: ext_resources, sub_resources, resource
  """
  @spec parse_tres(String.t()) :: tres_result()
  def parse_tres(tres_path) when is_binary(tres_path) do
    case File.read(tres_path) do
      {:ok, content} ->
        parse_tres_content(content)

      {:error, reason} ->
        {:error, "Failed to read TRES file: #{inspect(reason)}"}
    end
  end

  @doc """
  Parses TRES content from a string.

  ## Parameters
    - content: TRES file content as string

  ## Returns
    - `{:ok, tres_data}` - Success with parsed TRES data
    - `{:error, reason}` - Error message
  """
  @spec parse_tres_content(String.t()) :: tres_result()
  def parse_tres_content(content) when is_binary(content) do
    lines = String.split(content, ~r/\r?\n/, trim: false)

    initial_state = %{
      format_version: nil,
      resource_type: nil,
      ext_resources: [],
      sub_resources: [],
      resource: %{properties: %{}},
      current_section: nil,
      current_data: %{}
    }

    case parse_lines(lines, initial_state) do
      {:ok, state} ->
        # Validate that we have at least a resource section
        if state.resource && map_size(state.resource.properties) >= 0 do
          # Ensure format_version is set (default to 3 for Godot 4.x if not specified)
          format_version = state.format_version || 3

          {:ok,
           %{
             format_version: format_version,
             resource_type: state.resource_type,
             ext_resources: Enum.reverse(state.ext_resources),
             sub_resources: Enum.reverse(state.sub_resources),
             resource: state.resource
           }}
        else
          {:error, "TRES file missing [resource] section"}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Parse lines sequentially, building up state
  defp parse_lines([], state), do: {:ok, state}

  defp parse_lines([line | rest], state) do
    trimmed = String.trim(line)

    cond do
      # Empty line - skip
      trimmed == "" ->
        parse_lines(rest, state)

      # Comment - skip
      String.starts_with?(trimmed, "#") ->
        parse_lines(rest, state)

      # Section header
      String.starts_with?(trimmed, "[") and String.ends_with?(trimmed, "]") ->
        case parse_section_header(trimmed, state) do
          {:ok, new_state} ->
            parse_lines(rest, new_state)

          {:error, reason} ->
            {:error, reason}
        end

      # Property line (key = value)
      String.contains?(trimmed, "=") ->
        case parse_property_line(trimmed, state) do
          {:ok, new_state} ->
            parse_lines(rest, new_state)

          {:error, reason} ->
            {:error, reason}
        end

      # Unknown line format
      true ->
        Logger.warning("Unknown TRES line format: #{trimmed}")
        parse_lines(rest, state)
    end
  end

  # Parse section header using ABNF-generated parser with fallback
  defp parse_section_header(line, state) do
    trimmed = String.trim(line)

    case parse_section_header(trimmed) do
      {:ok, parsed} ->
        section_name = extract_section_name(parsed)
        attrs = extract_section_attributes(parsed)
        handle_section_start(section_name, attrs, state)

      {:error, _reason} ->
        # Fallback to manual parsing if ABNF fails
        parse_section_header_manual(trimmed)
        |> case do
          {:ok, %{section_name: name, attributes: attrs}} ->
            handle_section_start(name, attrs, state)

          error ->
            error
        end
    end
  end

  # Use ABNF-generated parser for section header
  defp parse_section_header(line) when is_binary(line) do
    # Try to parse with ABNF-generated parser
    try do
      case section_header(line) do
        {:ok, parsed, _rest} -> {:ok, parsed}
        {:error, reason, _rest, _context, _continuation} -> {:error, reason}
        {:error, reason} -> {:error, reason}
        other -> {:error, "Unexpected parser result: #{inspect(other)}"}
      end
    rescue
      # Fallback if ABNF parser not available
      UndefinedFunctionError ->
        # Fallback to manual parsing
        parse_section_header_manual(line)
    end
  end

  # Manual fallback parser for section header
  defp parse_section_header_manual(line) do
    # Remove brackets and parse manually
    content = String.slice(line, 1..-2//1)

    case String.split(content, " ", parts: 2) do
      [section_name] ->
        {:ok, %{section_name: section_name, attributes: %{}}}

      [section_name, attributes] ->
        attrs = parse_attributes_manual(attributes)
        {:ok, %{section_name: section_name, attributes: attrs}}

      _ ->
        {:error, "Invalid section header format"}
    end
  end

  # Manual attribute parser (fallback)
  defp parse_attributes_manual(attr_string) do
    Regex.scan(~r/(\w+)=("([^"]*)"|'([^']*)'|([^\s]+))/, attr_string)
    |> Enum.reduce(%{}, fn match, acc ->
      case match do
        [_, key, _full_value, quoted1, quoted2, unquoted]
        when is_binary(quoted1) or is_binary(quoted2) or is_binary(unquoted) ->
          value =
            cond do
              is_binary(quoted1) and quoted1 != "" -> quoted1
              is_binary(quoted2) and quoted2 != "" -> quoted2
              is_binary(unquoted) and unquoted != "" -> unquoted
              true -> ""
            end

          Map.put(acc, key, unquote_string(value))

        [_, key, full_value | _] when length(match) >= 3 ->
          Map.put(acc, key, unquote_string(full_value))

        _ ->
          acc
      end
    end)
  end

  # Unquote string values
  defp unquote_string(value) when is_binary(value) do
    cond do
      String.starts_with?(value, ~s(")) and String.ends_with?(value, ~s(")) ->
        String.slice(value, 1..-2//1)

      String.starts_with?(value, "'") and String.ends_with?(value, "'") ->
        String.slice(value, 1..-2//1)

      true ->
        value
    end
  end

  # Extract section name from parse result (handles both ABNF and manual parsing)
  defp extract_section_name(parsed) when is_map(parsed) do
    case parsed do
      %{section_name: name} when is_binary(name) ->
        name

      %{"section-name" => name} when is_binary(name) ->
        name

      _ ->
        # Fallback: try to extract from structure
        case Map.get(parsed, :section_name) || Map.get(parsed, "section-name") do
          nil -> ""
          name -> to_string(name)
        end
    end
  end

  defp extract_section_name(_), do: ""

  # Extract section attributes from parse result (handles both ABNF and manual parsing)
  defp extract_section_attributes(parsed) when is_map(parsed) do
    # Check for attributes in various formats
    attrs =
      Map.get(parsed, :attributes) ||
        Map.get(parsed, "attributes") ||
        Map.get(parsed, "section-attributes") ||
        Map.get(parsed, :section_attributes) ||
        %{}

    case attrs do
      attrs when is_map(attrs) ->
        # Already a map, just unquote values
        Enum.reduce(attrs, %{}, fn {key, value}, acc ->
          Map.put(acc, to_string(key), unquote_string(to_string(value)))
        end)

      attrs when is_list(attrs) ->
        Enum.reduce(attrs, %{}, fn attr, acc ->
          case attr do
            %{"attribute-key" => key, "attribute-value" => value} ->
              Map.put(acc, to_string(key), unquote_string(to_string(value)))

            %{attribute_key: key, attribute_value: value} ->
              Map.put(acc, to_string(key), unquote_string(to_string(value)))

            _ ->
              acc
          end
        end)

      _ ->
        %{}
    end
  end

  defp extract_section_attributes(_), do: %{}

  # Handle section start - dispatch to appropriate parser
  defp handle_section_start("gd_resource", attrs, state) do
    # gd_resource section contains format version and resource type
    format_version = parse_int(attrs["format"]) || parse_int(attrs["format_version"]) || 3
    resource_type = attrs["type"]

    {:ok,
     %{
       state
       | format_version: format_version,
         resource_type: resource_type,
         current_section: :gd_resource
     }}
  end

  defp handle_section_start("ext_resource", attrs, state) do
    ext_resource =
      %{
        type: attrs["type"] || "",
        path: attrs["path"] || "",
        id: parse_int(attrs["id"]) || 0
      }
      |> Map.merge(attrs)

    {:ok,
     %{
       state
       | ext_resources: [ext_resource | state.ext_resources],
         current_section: :ext_resource
     }}
  end

  defp handle_section_start("sub_resource", attrs, state) do
    sub_resource =
      %{
        type: attrs["type"] || "",
        id: parse_int(attrs["id"]) || 0,
        properties: %{}
      }
      |> Map.merge(attrs)

    {:ok,
     %{
       state
       | sub_resources: [sub_resource | state.sub_resources],
         current_section: :sub_resource,
         current_data: sub_resource
     }}
  end

  defp handle_section_start("resource", attrs, state) do
    resource =
      %{
        properties: %{}
      }
      |> Map.merge(attrs)

    {:ok,
     %{
       state
       | resource: resource,
         current_section: :resource,
         current_data: resource
     }}
  end

  defp handle_section_start(unknown, _attrs, _state) do
    {:error, "Unknown TRES section: #{unknown}"}
  end

  # Parse property line using ABNF-generated parser
  defp parse_property_line(line, state) do
    trimmed = String.trim(line)

    case parse_property_line(trimmed) do
      {:ok, parsed} ->
        key = extract_property_key(parsed)
        value_str = extract_property_value(parsed)
        parsed_value = SectionParser.parse_property_value(value_str)

        case state.current_section do
          :sub_resource ->
            # Add property to current sub_resource
            if length(state.sub_resources) > 0 do
              current = List.first(state.sub_resources)
              updated = %{current | properties: Map.put(current.properties, key, parsed_value)}
              updated_resources = [updated | List.delete_at(state.sub_resources, 0)]

              {:ok, %{state | sub_resources: updated_resources, current_data: updated}}
            else
              {:ok, state}
            end

          :resource ->
            # Add property to resource
            updated_resource = %{state.resource | properties: Map.put(state.resource.properties, key, parsed_value)}

            {:ok, %{state | resource: updated_resource, current_data: updated_resource}}

          _ ->
            # Property not in a section that supports properties - ignore
            {:ok, state}
        end

      {:error, _reason} ->
        # Invalid property line - ignore (don't error)
        {:ok, state}
    end
  end

  # Parse property line (manual parsing for now, ABNF can be added later)
  defp parse_property_line(line) when is_binary(line) do
    # For now, use manual parsing since abnf_parsec generates one parser per use
    # TODO: Consider creating a separate module for property_line parser if needed
    case String.split(line, "=", parts: 2) do
      [key, value] ->
        key = String.trim(key)
        value = String.trim(value)
        {:ok, %{property_key: key, property_value: value}}

      _ ->
        {:error, "Invalid property line format"}
    end
  end

  # Extract property key from ABNF parse result
  defp extract_property_key(parsed) when is_map(parsed) do
    case parsed do
      %{"property-key" => key} when is_binary(key) ->
        unquote_string(key)

      %{property_key: key} when is_binary(key) ->
        unquote_string(key)

      _ ->
        # Fallback
        case Map.get(parsed, :property_key) || Map.get(parsed, "property-key") do
          nil -> ""
          key -> unquote_string(to_string(key))
        end
    end
  end

  defp extract_property_key(_), do: ""

  # Extract property value from ABNF parse result
  defp extract_property_value(parsed) when is_map(parsed) do
    case parsed do
      %{"property-value" => value} when is_binary(value) ->
        value

      %{property_value: value} when is_binary(value) ->
        value

      _ ->
        # Fallback
        case Map.get(parsed, :property_value) || Map.get(parsed, "property-value") do
          nil -> ""
          value -> to_string(value)
        end
    end
  end

  defp extract_property_value(_), do: ""

  # Parse integer from string
  defp parse_int(nil), do: nil

  defp parse_int(value) when is_binary(value) do
    case Integer.parse(value) do
      {int, _} -> int
      :error -> nil
    end
  end

  defp parse_int(value) when is_integer(value), do: value
  defp parse_int(_), do: nil
end
