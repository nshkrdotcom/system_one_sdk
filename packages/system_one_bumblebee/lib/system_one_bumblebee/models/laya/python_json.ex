defmodule SystemOneBumblebee.Models.Laya.PythonJson do
  @moduledoc false

  @spec encode(term(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def encode(value, opts \\ []) do
    ensure_ascii = Keyword.get(opts, :ensure_ascii, false)

    case Jason.encode(value) do
      {:ok, compact} ->
        json =
          compact
          |> maybe_escape_non_ascii(ensure_ascii)
          |> add_python_spacing()

        {:ok, json}

      {:error, _reason} = error ->
        error
    end
  end

  defp maybe_escape_non_ascii(json, false), do: json
  defp maybe_escape_non_ascii(json, true), do: escape_non_ascii(json)

  defp escape_non_ascii(json) do
    for <<codepoint::utf8 <- json>>, into: "" do
      cond do
        codepoint < 0x80 ->
          <<codepoint>>

        codepoint <= 0xFFFF ->
          "\\u" <> hex4(codepoint)

        true ->
          value = codepoint - 0x10000
          high = 0xD800 + div(value, 0x400)
          low = 0xDC00 + rem(value, 0x400)

          "\\u" <> hex4(high) <> "\\u" <> hex4(low)
      end
    end
  end

  defp hex4(value) do
    value
    |> Integer.to_string(16)
    |> String.downcase()
    |> String.pad_leading(4, "0")
  end

  defp add_python_spacing(json) do
    json
    |> do_add_python_spacing(false, false, [])
    |> Enum.reverse()
    |> IO.iodata_to_binary()
  end

  defp do_add_python_spacing(<<>>, _in_string, _escaped, acc), do: acc

  defp do_add_python_spacing(
         <<char, rest::binary>>,
         true,
         true,
         acc
       ) do
    do_add_python_spacing(rest, true, false, [<<char>> | acc])
  end

  defp do_add_python_spacing(
         <<?\\, rest::binary>>,
         true,
         false,
         acc
       ) do
    do_add_python_spacing(rest, true, true, ["\\" | acc])
  end

  defp do_add_python_spacing(
         <<?", rest::binary>>,
         true,
         false,
         acc
       ) do
    do_add_python_spacing(rest, false, false, ["\"" | acc])
  end

  defp do_add_python_spacing(
         <<?", rest::binary>>,
         false,
         false,
         acc
       ) do
    do_add_python_spacing(rest, true, false, ["\"" | acc])
  end

  defp do_add_python_spacing(
         <<char, rest::binary>>,
         false,
         false,
         acc
       )
       when char in [?,, ?:] do
    do_add_python_spacing(rest, false, false, [" ", <<char>> | acc])
  end

  defp do_add_python_spacing(
         <<char, rest::binary>>,
         in_string,
         false,
         acc
       ) do
    do_add_python_spacing(
      rest,
      in_string,
      false,
      [<<char>> | acc]
    )
  end
end
