defmodule Knit do
  @moduledoc """
  Handles populating models.
  """

  @doc """
  Populate a knit struct from a map.
  """
  @spec populate(map, module) :: struct
  def populate(params, module) do
    if !is_atom(module) || !function_exported?(module, :schema, 0) do
      raise "#{inspect(module)} does not implement Knit.Model!"
    end

    schema = module.schema

    populated_map =
      module
      |> struct
      |> ExConstructor.populate_struct(params)
      # Can't enumerate otherwise
      |> Map.from_struct
      |> Enum.map(&(convert(schema, &1)))
      |> Enum.into(%{})

    # Re-convert to struct
    struct(module, populated_map)
  end

  @doc """
  Populate a list of knit structs from a list of maps.
  """
  @spec populate_list(map, module) :: struct
  def populate_list(params, module) do
    params
    |> Enum.map(&(populate(&1, module)))
  end

  defp convert(schema, {field, value}) do
    # Get the data about the field from the schema.
    type = schema[field]

    new_value =
      case type do
        [type] ->
          convert_list_collection(type, value)
        {type} ->
          convert_list_collection(type, value)
          |> Enum.into({})
        %{map: type} ->
          convert_map_collection(type, value)
        type ->
          convert_type(type, value)
      end

    {field, new_value}
  end

  # Convert a list-type collection (list or tuple)
  defp convert_list_collection(_, nil), do: []
  defp convert_list_collection(type, values) do
    # Handle the collection being in a map.
    # TODO: Make sure this is ordered by key.
    values_list = if is_map(values), do: Map.values(values), else: values
    Enum.map(values_list, &(convert_type(type, &1)))
  end

  # If the collection is a map with string keys and model values.
  defp convert_map_collection(_, nil), do: %{}
  defp convert_map_collection(type, values) do
    Enum.map(values, fn {key, value} ->
      {key, convert_type(type, value)}
    end)
    |> Enum.into(%{})
  end

  defp convert_type(_, nil), do: nil
  defp convert_type(type, value) do
    cond do
      is_atom(type) && function_exported?(type, :schema, 0) ->
        # If the type is a model, populate the child struct.
        populate(value, type)
      is_atom(type) && function_exported?(type, :convert, 1) ->
        # If the type is a custom type, use that to convert
        convert_custom_type(type, value)
      true ->
        convert_value(type, value)
    end
  end

  defp convert_value(_, nil), do: nil
  defp convert_value(:string, value), do: Knit.StringType.convert(value)
  defp convert_value(:integer, value), do: Knit.IntegerType.convert(value)
  defp convert_value(:float, value), do:  Knit.FloatType.convert(value)
  defp convert_value(:boolean, value), do:  Knit.BooleanType.convert(value)
  defp convert_value({:enum, opts}, value) when is_list(opts), do: convert_enum(value, opts)
  defp convert_value(:any, value), do: value

  defp convert_enum(value, opts) do
    keyword =
      opts
      |> Enum.find(fn {_, input_value} ->
        input_value == value
      end)

      case keyword do
        {atom, _} -> atom
        nil -> nil
      end
  end

  defp convert_custom_type(type, value) do
    type.convert(value)
  end
end
