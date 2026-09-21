defmodule SystemOneBumblebee.Models.Laya.EncoderLoader do
  @moduledoc """
  Strict loader for Laya's ModernBERT encoder.

  The Laya checkpoint is a combined SafeTensors state containing the
  ModernBERT encoder and the Laya-specific decision head. This module exposes
  only the 170 `encoder.*` source tensors to Bumblebee while leaving the
  original checkpoint unchanged.

  Loading is deliberately fail-closed:

    * the complete 206-tensor checkpoint is validated before model allocation;
    * exactly 170 encoder source tensors must be exposed;
    * the loaded Axon parameter tree must contain exactly the reviewed
      254 ModernBERT destination tensors;
    * every destination name, shape and dtype is checked.

  EXLA is intentionally not referenced here. The caller supplies any desired
  Nx backend.
  """

  alias CrucibleSafetensors.{Reader, TensorInfo}

  alias SystemOneBumblebee.Models.Laya.{
    CheckpointAccounting,
    CheckpointTensor
  }

  @encoder_source_count 170
  @encoder_destination_count 254
  @params_filename "model.safetensors"

  @type parameter_type ::
          :f16
          | :bf16
          | :f32
          | {:f, 16}
          | {:bf, 16}
          | {:f, 32}

  @type loaded :: %{
          required(:model) => Axon.t(),
          required(:params) => term(),
          required(:spec) => struct(),
          required(:checkpoint_accounting) => map(),
          required(:destination_accounting) => map()
        }

  @doc """
  Loads the reviewed Laya ModernBERT encoder.

  `encoder_dir` must contain the encoder `config.json`.
  `checkpoint_path` is the combined Laya SafeTensors checkpoint.

  The parameter type is mandatory. This prevents the physical F16 checkpoint
  storage from being silently conflated with the runtime computation policy.

  ## Options

    * `:type` - required; `:f32`, `:bf16`, or `:f16`
    * `:backend` - Nx backend used by Bumblebee; defaults to `Nx.BinaryBackend`
    * `:log_params_diff` - forwarded to Bumblebee; defaults to `false`
  """
  @spec load(Path.t(), Path.t(), keyword()) ::
          {:ok, loaded()} | {:error, term()}
  def load(encoder_dir, checkpoint_path, opts \\ [])
      when is_binary(encoder_dir) and
             is_binary(checkpoint_path) and
             is_list(opts) do
    opts =
      Keyword.validate!(
        opts,
        [:type, backend: Nx.BinaryBackend, log_params_diff: false]
      )

    with {:ok, parameter_type} <-
           fetch_parameter_type(opts),
         :ok <-
           validate_input_paths(
             encoder_dir,
             checkpoint_path
           ),
         {:ok, checkpoint_accounting} <-
           CheckpointAccounting.validate_file(checkpoint_path),
         {:ok, view_dir} <-
           create_local_repository_view(
             encoder_dir,
             checkpoint_path
           ) do
      try do
        do_load(
          view_dir,
          parameter_type,
          checkpoint_accounting,
          opts
        )
      after
        File.rm_rf(view_dir)
      end
    end
  end

  @doc """
  Returns the reviewed Axon destination contract for the encoder.

  This is useful for release tooling and tests without loading model weights.
  """
  @spec destination_contract(parameter_type()) ::
          {:ok,
           %{
             required(String.t()) => %{
               required(:shape) => [pos_integer()],
               required(:type) => Nx.Type.t(),
               required(:transform) => atom()
             }
           }}
          | {:error, term()}
  def destination_contract(parameter_type) do
    with {:ok, nx_type} <-
           normalize_parameter_type(parameter_type) do
      destinations =
        CheckpointAccounting.expected_tensors()
        |> Enum.filter(&(&1.family == :encoder))
        |> Enum.flat_map(& &1.destinations)

      contract =
        Map.new(
          destinations,
          fn destination ->
            {
              destination.parameter,
              %{
                shape: destination.shape,
                type: nx_type,
                transform: destination.transform
              }
            }
          end
        )

      cond do
        length(destinations) !=
            @encoder_destination_count ->
          {:error,
           {:encoder_destination_count_mismatch,
            %{
              expected: @encoder_destination_count,
              actual: length(destinations)
            }}}

        map_size(contract) !=
            @encoder_destination_count ->
          {:error,
           {:duplicate_encoder_destination,
            %{
              expected: @encoder_destination_count,
              unique: map_size(contract)
            }}}

        true ->
          {:ok, contract}
      end
    end
  end

  @doc false
  @spec validate_loaded_params(
          term(),
          parameter_type()
        ) ::
          {:ok, map()} | {:error, term()}
  def validate_loaded_params(
        %Axon.ModelState{data: data},
        parameter_type
      ) do
    with {:ok, expected} <-
           destination_contract(parameter_type) do
      actual =
        data
        |> flatten_tensors([])
        |> Map.new()

      issues =
        []
        |> destination_count_issues(actual)
        |> destination_name_issues(
          actual,
          expected
        )
        |> Kernel.++(
          destination_value_issues(
            actual,
            expected
          )
        )

      report = %{
        parameter_count: map_size(actual),
        expected_parameter_count: @encoder_destination_count,
        source_tensor_count: @encoder_source_count,
        issues: issues
      }

      if issues == [] do
        {:ok, report}
      else
        {:error, {:encoder_destination_validation_failed, report}}
      end
    end
  end

  def validate_loaded_params(
        params,
        _parameter_type
      ) do
    {:error, {:invalid_axon_model_state, params}}
  end

  @doc false
  @spec read_encoder_state!(
          Path.t(),
          term()
        ) ::
          %{
            String.t() => CheckpointTensor.t()
          }
  def read_encoder_state!(
        path,
        backend
      )
      when is_binary(path) do
    header =
      Reader.open!(path)

    state =
      header.tensors
      |> Enum.flat_map(fn
        {"encoder." <> name, %TensorInfo{} = tensor_info} ->
          [
            {
              name,
              CheckpointTensor.new(
                header,
                tensor_info,
                backend
              )
            }
          ]

        {_name, _tensor_info} ->
          []
      end)
      |> Map.new()

    if map_size(state) !=
         @encoder_source_count do
      raise ArgumentError,
            "expected #{@encoder_source_count} Laya encoder tensors, " <>
              "got #{map_size(state)}"
    end

    state
  end

  defp do_load(
         view_dir,
         parameter_type,
         checkpoint_accounting,
         opts
       ) do
    backend =
      Keyword.fetch!(
        opts,
        :backend
      )

    load_opts = [
      module: Bumblebee.Text.ModernBert,
      architecture: :base,
      params_filename: @params_filename,
      safetensors_reader:
        &read_encoder_state!(
          &1,
          backend
        ),
      backend: backend,
      type: parameter_type,
      log_params_diff:
        Keyword.fetch!(
          opts,
          :log_params_diff
        )
    ]

    case Bumblebee.load_model(
           {:local, view_dir},
           load_opts
         ) do
      {:ok,
       %{
         params: params
       } = model_info} ->
        with {:ok, destination_accounting} <-
               validate_loaded_params(
                 params,
                 parameter_type
               ) do
          {:ok,
           model_info
           |> Map.put(
             :checkpoint_accounting,
             checkpoint_accounting
           )
           |> Map.put(
             :destination_accounting,
             destination_accounting
           )}
        end

      {:error, reason} ->
        {:error, {:bumblebee_encoder_load_failed, reason}}
    end
  rescue
    error ->
      {:error, {:bumblebee_encoder_load_failed, Exception.message(error)}}
  end

  defp fetch_parameter_type(opts) do
    case Keyword.fetch(opts, :type) do
      {:ok, parameter_type} ->
        normalize_parameter_type(parameter_type)

      :error ->
        {:error, :missing_laya_parameter_type}
    end
  end

  defp normalize_parameter_type(:f16),
    do: {:ok, {:f, 16}}

  defp normalize_parameter_type(:bf16),
    do: {:ok, {:bf, 16}}

  defp normalize_parameter_type(:f32),
    do: {:ok, {:f, 32}}

  defp normalize_parameter_type({:f, 16}),
    do: {:ok, {:f, 16}}

  defp normalize_parameter_type({:bf, 16}),
    do: {:ok, {:bf, 16}}

  defp normalize_parameter_type({:f, 32}),
    do: {:ok, {:f, 32}}

  defp normalize_parameter_type(other),
    do: {:error, {:unsupported_laya_parameter_type, other}}

  defp validate_input_paths(
         encoder_dir,
         checkpoint_path
       ) do
    config_path =
      Path.join(
        encoder_dir,
        "config.json"
      )

    cond do
      not File.dir?(encoder_dir) ->
        {:error, {:missing_laya_encoder_directory, encoder_dir}}

      not File.regular?(config_path) ->
        {:error, {:missing_laya_encoder_config, config_path}}

      not File.regular?(checkpoint_path) ->
        {:error, {:missing_laya_checkpoint, checkpoint_path}}

      true ->
        :ok
    end
  end

  defp create_local_repository_view(
         encoder_dir,
         checkpoint_path
       ) do
    suffix =
      System.unique_integer([:positive, :monotonic])

    view_dir =
      Path.join(
        System.tmp_dir!(),
        "system_one_laya_encoder_#{suffix}"
      )

    config_source =
      Path.join(
        encoder_dir,
        "config.json"
      )

    config_destination =
      Path.join(
        view_dir,
        "config.json"
      )

    checkpoint_destination =
      Path.join(
        view_dir,
        @params_filename
      )

    with :ok <- File.mkdir_p(view_dir),
         :ok <-
           File.cp(
             config_source,
             config_destination
           ),
         :ok <-
           link_checkpoint(
             checkpoint_path,
             checkpoint_destination
           ) do
      {:ok, view_dir}
    else
      {:error, reason} ->
        File.rm_rf(view_dir)

        {:error, {:laya_encoder_view_failed, reason}}
    end
  end

  defp link_checkpoint(
         source,
         destination
       ) do
    case File.ln(
           source,
           destination
         ) do
      :ok ->
        :ok

      {:error, _hardlink_reason} ->
        File.ln_s(
          source,
          destination
        )
    end
  end

  defp flatten_tensors(
         %Nx.Tensor{} = tensor,
         path
       ) do
    [
      {
        Enum.join(path, "."),
        tensor
      }
    ]
  end

  defp flatten_tensors(
         map,
         path
       )
       when is_map(map) do
    Enum.flat_map(
      map,
      fn {key, value} ->
        flatten_tensors(
          value,
          path ++ [to_string(key)]
        )
      end
    )
  end

  defp flatten_tensors(
         _value,
         _path
       ),
       do: []

  defp destination_count_issues(
         issues,
         actual
       ) do
    if map_size(actual) ==
         @encoder_destination_count do
      issues
    else
      [
        %{
          code: :encoder_destination_count_mismatch,
          expected: @encoder_destination_count,
          actual: map_size(actual)
        }
        | issues
      ]
    end
  end

  defp destination_name_issues(
         issues,
         actual,
         expected
       ) do
    actual_names =
      actual
      |> Map.keys()
      |> MapSet.new()

    expected_names =
      expected
      |> Map.keys()
      |> MapSet.new()

    missing =
      expected_names
      |> MapSet.difference(actual_names)
      |> MapSet.to_list()
      |> Enum.sort()

    unexpected =
      actual_names
      |> MapSet.difference(expected_names)
      |> MapSet.to_list()
      |> Enum.sort()

    issues
    |> maybe_add_names(
      :missing_encoder_destinations,
      missing
    )
    |> maybe_add_names(
      :unexpected_encoder_destinations,
      unexpected
    )
  end

  defp destination_value_issues(
         actual,
         expected
       ) do
    expected
    |> Enum.flat_map(fn {name, contract} ->
      case Map.fetch(actual, name) do
        :error ->
          []

        {:ok, tensor} ->
          shape =
            tensor
            |> Nx.shape()
            |> Tuple.to_list()

          type =
            Nx.type(tensor)

          []
          |> maybe_add_value_mismatch(
            :encoder_destination_shape_mismatch,
            name,
            contract.shape,
            shape
          )
          |> maybe_add_value_mismatch(
            :encoder_destination_type_mismatch,
            name,
            contract.type,
            type
          )
      end
    end)
  end

  defp maybe_add_names(
         issues,
         _code,
         []
       ),
       do: issues

  defp maybe_add_names(
         issues,
         code,
         names
       ) do
    issues ++
      [
        %{
          code: code,
          names: names
        }
      ]
  end

  defp maybe_add_value_mismatch(
         issues,
         _code,
         _name,
         value,
         value
       ),
       do: issues

  defp maybe_add_value_mismatch(
         issues,
         code,
         name,
         expected,
         actual
       ) do
    issues ++
      [
        %{
          code: code,
          parameter: name,
          expected: expected,
          actual: actual
        }
      ]
  end
end
