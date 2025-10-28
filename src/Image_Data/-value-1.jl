import Mmap
#=
function decompose_image_to_values(shape, image)
    #=
    input_images = ()
    for index in 1:length(shape)
        if shape[index] == :red
            input_images = (input_images..., red.(image))
        elseif shape[index] == :green
            input_images = (input_i mages..., green.(image))
        elseif shape[index] == :blue
            input_images = (input_images..., blue.(image))
        end
    end
    return input_images
    =#
    return (red.(image), green.(image), blue.(image))
end
=#

struct v__Image_Data{shape_type,data_type} 
    data::data_type
    function v__Image_Data(::v__Type{shape}, size, data_vector...) where {shape}
        #=
        data = Array{Float32,3}(undef, size..., length(shape.parameters))
        for index in 1:length(shape.parameters)
            data[:, :, index] = data_vector[index]
        end
        =#
        #data = cat(data_vector...; dims=3)
        data = VectorOfArray([data_vector...])
        return new{shape,typeof(data)}(data)
    end
    function v__Image_Data(::v__Type{shape}, data) where {shape}
        return new{shape,typeof(data)}(data)
    end
    function v__Image_Data{shape_type, data_type}(channels...) where {shape_type, data_type}
        return new{shape_type, data_type}(VectorOfArray([channels...]))
    end
end
function v__Image_Data(shape, values...)
    return v__Image_Data(Tuple{shape...}, values...)
end
const ImgData = v__Image_Data
export v__Image_Data, ImgData





abstract type c__Image_Data{tuple} end; export c__Image_Data
struct v__Image_Data_Static_Channel{type, size_type, shape_type, channels_type}
    channels::channels_type
    function v__Image_Data_Static_Channel{type, size_type, shape_type}(channels...) where {type, size_type, shape_type}
        return new{type, size_type, shape_type, typeof(channels)}(channels)
    end
    function v__Image_Data_Static_Channel(
        ::v__Type{type},
        ::v__Type{size_type},
        ::v__Type{shape_type},
        channels::channels_type
    ) where {type, size_type, shape_type, channels_type}
        return new{type, size_type, shape_type, typeof(channels)}(channels)
    end
end
export v__Image_Data_Static_Channel

struct v__Image_Data_Static_Data{type, size_type, shape_type, data_type}
    data::data_type
    function v__Image_Data_Static_Data(
        ::v__Type{type},
        ::v__Type{size_type},
        ::v__Type{shape_type},
        data::data_type
    ) where {type, size_type, shape_type, data_type}
        return new{type, size_type, shape_type, data_type}(data)
    end
    function v__Image_Data_Static_Data{type, size_type, shape_type, data_type}(data) where {type, size_type, shape_type, data_type}
        return new{type, size_type, shape_type, data_type}(data)
    end
end
export v__Image_Data_Static_Data




const u__Image_Data = u__{v__Image_Data, v__Image_Data_Static_Channel, v__Image_Data_Static_Data}



