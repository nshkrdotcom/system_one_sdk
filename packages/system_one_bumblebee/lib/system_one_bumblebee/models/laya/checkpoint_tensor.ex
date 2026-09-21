defmodule SystemOneBumblebee.Models.Laya.CheckpointTensor do
  @moduledoc false

  alias CrucibleSafetensors.{Header, Reader, Slice, TensorInfo}

  @enforce_keys [:header, :tensor_info, :backend]
  defstruct [:header, :tensor_info, :backend]

  @type t :: %__MODULE__{
          header: Header.t(),
          tensor_info: TensorInfo.t(),
          backend: term()
        }

  @spec new(Header.t(), TensorInfo.t(), term()) :: t()
  def new(
        %Header{} = header,
        %TensorInfo{} = tensor_info,
        backend
      ) do
    %__MODULE__{
      header: header,
      tensor_info: tensor_info,
      backend: backend
    }
  end

  @spec template(t()) :: Nx.Tensor.t()
  def template(%__MODULE__{
        tensor_info: %TensorInfo{
          dtype: dtype,
          shape: shape
        }
      }) do
    Nx.template(
      List.to_tuple(shape),
      nx_type!(dtype)
    )
  end

  @spec materialize!(t()) :: Nx.Tensor.t()
  def materialize!(%__MODULE__{
        header: %Header{} = header,
        tensor_info: %TensorInfo{} = tensor_info,
        backend: backend
      }) do
    slice =
      case Reader.read_tensor(
             header,
             tensor_info
           ) do
        {:ok, %Slice{} = value} ->
          value

        {:error, exception} ->
          raise exception
      end

    slice.data
    |> Nx.from_binary(nx_type!(tensor_info.dtype))
    |> Nx.reshape(List.to_tuple(tensor_info.shape))
    |> Nx.backend_transfer(backend)
  end

  defp nx_type!(:f16),
    do: {:f, 16}

  defp nx_type!(:bf16),
    do: {:bf, 16}

  defp nx_type!(:f32),
    do: {:f, 32}

  defp nx_type!(:i32),
    do: {:s, 32}

  defp nx_type!(:i64),
    do: {:s, 64}
end

defimpl Nx.LazyContainer,
  for: SystemOneBumblebee.Models.Laya.CheckpointTensor do
  alias SystemOneBumblebee.Models.Laya.CheckpointTensor

  def traverse(
        lazy_tensor,
        acc,
        fun
      ) do
    template =
      CheckpointTensor.template(lazy_tensor)

    load = fn ->
      CheckpointTensor.materialize!(lazy_tensor)
    end

    fun.(
      template,
      load,
      acc
    )
  end
end
