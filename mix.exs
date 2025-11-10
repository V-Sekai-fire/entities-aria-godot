# SPDX-License-Identifier: MIT
# Copyright (c) 2025-present K. S. Ernest (iFire) Lee

defmodule AriaGodot.MixProject do
  use Mix.Project

  def project do
    [
      app: :aria_godot,
      version: "0.1.0-dev1",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:abnf_parsec, "~> 2.1", runtime: false}
    ]
  end
end

