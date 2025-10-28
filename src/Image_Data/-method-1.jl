function decompose_image_to_values(shape, image)
    return decompose_image_to_values(v__Value(shape), image)
end
function decompose_image_to_values(::v__Value{:red}, image)
    return red.(image)
end
function decompose_image_to_values(::v__Value{:green}, image)
    return green.(image)
end
function decompose_image_to_values(::v__Value{:blue}, image)
    return blue.(image)
end
function Base.getproperty(image_data::v__Image_Data{shape_type}, property::Symbol) where {shape_type}
    if property == :shape
        return (shape_type.parameters...,)
    else
        return Base.getfield(image_data, property)
    end
end
function Base.getproperty(image_data::u__{
        v__Image_Data_Static_Channel{type, size_type, shape_type},
        v__Image_Data_Static_Data{type, size_type, shape_type}
    }, property::Symbol) where {type, size_type, shape_type}
    if property == :shape
        return (parameters(shape_type)...,)
    else
        return Base.getfield(image_data, property)
    end
end
function (::v__Type{
        c__Image_Data{Tuple{type, size_type, shape_type, channels_type}} where {size_type, channels_type}
    })(channels...) where {type, shape_type}
    channels_length = length(channels)
    _size = size(channels[1])
    for channel in channels[2:channels_length]
        if size(channel) != _size
            throw(ArgumentError("All channels must have the same size."))
        end
    end
    return @__(v__Image_Data_Static_Channel{type, Tuple{_size...}, shape_type}(channels...); Transform=false)
end
@__(function Bas3.p__NEW(
    ::v__Type{type},
    ::v__Type{element_type},
    size_type,
    shape_type,
) where {
    type<:c__Image_Data,
    element_type
}
    return @__(c__Image_Data{Tuple{
        element_type,
        Tuple{size_type},
        Tuple{shape_type},
        channels_type
    }} where {channels_type}; Transform=false)
end)
@__(function Bas3.p__NEW(
    ::v__Type{type},
    ::v__Type{element_type},
    shape,
) where {
    type<:c__Image_Data,
    element_type
}
    return @__(c__Image_Data{Tuple{
        element_type,
        size_type,
        Tuple{shape...},
        channels_type
    }} where {size_type, channels_type}; Transform=false)
end)
@__(function Bas3.p__NEW(
    ::v__Type{type},
    _size,
) where {
    type<:c__Image_Data{
        Tuple{
            element_type,
            size_type,
            shape_type,
            channels_type
        }
    } where {size_type,channels_type}
} where {
    element_type,
    shape_type
}
    return @__(v__Image_Data_Static_Data{
        element_type,
        Tuple{_size...},
        shape_type,
        Array{element_type,3}
    }; Transform=false)
end)
function image(image_data::u__Image_Data)
    #=
    if image_data.shape == (:red, :green, :blue)
        return colorview(
            v_RGB,
            @view(image_data.data[:, :, 1]),
            @view(image_data.data[:, :, 2]),
            @view(image_data.data[:, :, 3])
        )
    else
        image = Array{v_RGB,2}(undef, size(image_data.data)[1], size(image_data.data)[2])
        for index in 1:length(image_data.shape)
            image += image_data.data[:, :, index] .* shape_color[image_data.shape[index]]
        end
        return image
    end
    =#
    _data = data(image_data)
    _shape = shape(image_data)
    if _shape == (:red, :green, :blue)
        return colorview(
            v_RGB,
            @view(_data[:, :, 1]),
            @view(_data[:, :, 2]),
            @view(_data[:, :, 3])
        )
    else
        #image = Array{v_RGB,2}(undef, size(_data)[1:2])
        image = zeros(v_RGB, size(_data)[1:2]...)
        for index in 1:length(_shape)
            image += _data[:, :, index] .* shape_color[_shape[index]]
        end
        return image
    end
end
export image
function channels(image_data::u__Image_Data)
    return (colorview(Gray, @view(data(image_data)[:, :, index])) for index in 1:length(shape(image_data)))
end
function channels(image_data::v__Image_Data_Static_Channel)
    return image_data.channels
end
export channels
function data(image_data::u__{v__Image_Data, v__Image_Data_Static_Data})
    return image_data.data
end
function data(image_data::v__Image_Data_Static_Channel{type, size_type, shape_type}) where {type, size_type, shape_type}
    return VectorOfArray([image_data.channels...])
end
export data
function shape(::v__Type{v__Image_Data{shape_type}}) where {shape_type}
    return (parameters(shape_type)...,)
end
function shape(::v__Image_Data{shape_type}) where {shape_type}
    return (parameters(shape_type)...,)
end
function shape(::v__Image_Data_Static_Data{type, size_type, shape_type}) where {type, size_type, shape_type}
    return (parameters(shape_type)...,)
end
function shape(::v__Image_Data_Static_Channel{type, size_type, shape_type}) where {type, size_type, shape_type}
    return (parameters(shape_type)...,)
end
function shape(::v__Type{<:c__Image_Data{v__Tuple{type, size_type, shape_type, channels_type}} where {size_type, channels_type}}) where {type, shape_type}
    return (parameters(shape_type)...,)
end
export shape
function element_type(::v__Image_Data)
    return Float32
end
function element_type(::v__Image_Data_Static_Channel{type}) where {type}
    return type
end
function element_type(::v__Image_Data_Static_Data{type}) where {type}
    return type
end
export element_type
function shape_areas(image_data::u__Image_Data)
    sa = ()
    s = shape(image_data)
    d = data(image_data)
    #=
    for i in 1:length(s)
        sa = (sa..., sum(d[:, :, i]))
    end
    return sa
    =#
    return (;
        (s[i] => sum(d[:, :, i]) for i in 1:length(s))...
    )
end
export shape_areas
const memory_map = Mmap.mmap
function memory_map(image_data::v__Image_Data)
    mapped_data = Mmap.mmap(Array{Float32,3}, size(image_data.data)...)
    mapped_data .= image_data.data
    return v__Image_Data(image_data.shape, mapped_data)
end
function memory_map(image_data::v__Image_Data_Static_Channel{type, size_type, shape_type}) where {type, size_type, shape_type}
    mapped_data = Mmap.mmap(Array{Float32,3}, (parameters(size_type)..., length(parameters(shape_type)))...)
    #mapped_data .= image_data.data
    for index in 1:length(image_data.channels)
        mapped_data[:, :, index] .= image_data.channels[index]
    end
    return v__Image_Data_Static_Data(type, size_type, shape_type, mapped_data)
end
function memory_map(image_data::v__Image_Data_Static_Data{type, size_type, shape_type, data_type}) where {type, size_type, shape_type, data_type}
    mapped_data = Mmap.mmap(Array{type,3}, (parameters(size_type)..., length(parameters(shape_type)))...)
    mapped_data .= image_data.data
    return v__Image_Data_Static_Data(type, size_type, shape_type, mapped_data)
end
export memory_map
function Base.convert(
    ::v__Type{type},
    image_data::v__Image_Data_Static_Channel
) where {type <: v__Image_Data_Static_Data{element_type, size_type, shape_type, data_type}} where {element_type, size_type, shape_type, data_type}
    #println(typeof.(image_data.channels))
    return type(cat(image_data.channels...; dims=3))
end
struct t__get_index__Image_Data <: t__ end
function Bas3.t__get_index(::u__Image_Data)
    return t__get_index__Image_Data()
end
function Base.getindex(
        ::t__get_index__Image_Data, image_data,
        indicies...
    )
    indicies = Bas3.unpack_traits(indicies...)
    println("Indicies: ", indicies)
    throw("")
end