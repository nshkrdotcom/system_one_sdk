defmodule SystemOneContracts do
  @moduledoc """
  Provider-neutral System One protocol contracts.

  The current protocol identifier is `system-one/v1`.
  """

  @version "0.1.0"
  @protocol "system-one/v1"

  @spec version() :: String.t()
  def version, do: @version

  @spec protocol() :: String.t()
  def protocol, do: @protocol
end
