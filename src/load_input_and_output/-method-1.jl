function img_loader(base_path, Number_of_Dataset; idtype = "raw", filetype = "jpg")
    id_str = lpad(Number_of_Dataset, 3, '0')
    img_path = joinpath([base_path, "MuHa_$(id_str)", "MuHa_$(id_str)_$(idtype).$(filetype)"])
    return ImageMagick.load_(img_path)
end
import Bas3.is_iterable
#=
function load_input_and_output(base_path, data_index; input_shape=input_shape, output_shape=output_shape)
    #=
    input_image = img_loader(base_path, data_index; idtype="raw_adj", filetype="png")
    input_image_size = size(input_image)

    input_images = decompose_image_to_values(input_shape, input_image)
    =#
    local input_image_size
    local input_images = ()
    local canonicalized_input_shape = ()
    for index in 1:length(input_shape)
        if is_iterable(input_shape[index]) == true
        input_image = img_loader(base_path, data_index; idtype="raw_adj", filetype="png")
            input_image = imresize(input_image; ratio=1/4)
            input_image_size = size(input_image)
            input_images = (input_images..., decompose_image_to_values(input_shape[index], input_image)...)
            canonicalized_input_shape = (canonicalized_input_shape..., input_shape[index]...)
        else
            throw(ArgumentError("Input shape must be iterable, got $(input_shape[index])"))
        end
    end
    #=
    input_data = Array{Float32, 3}(undef, size(input_image, 1), size(input_image, 2), length(input_shape))
    for index in 1:length(input_shape)
        if input_shape[index] == :red
            input_data[:, :, index] = red.(input_image)
        elseif input_shape[index] == :green
            input_data[:, :, index] = green.(input_image)
        elseif input_shape[index] == :blue
            input_data[:, :, index] = blue.(input_image)
        end
    end

    data_size = size(input_data)
    _length = length(output_shape)
    output_data = Array{Float32, 3}(undef, data_size[1], data_size[2], _length)
    for index in 1:_length
        output_image = img_loader(base_path, data_index; idtype="seg_$(output_shape[index])", filetype="png")
        output_image_size = size(output_image)
        if output_image_size[1:2] != input_image_size[1:2]
            error("Output image size $(output_image_size) does not match input image size $(input_image_size)")
        end
        output_data[:, :, index] = Gray.(output_image)
    end
    return v__Image_Data(input_data, input_shape), v__Image_Data(output_data, output_shape)
    =#
    
    local output_image_size
    local output_images = ()
    local canonicalized_output_shape = ()
    for index in 1:length(output_shape)
        if is_iterable(output_shape[index]) == true
            throw(ArgumentError("Output cant be iterable, got $(output_shape[index])"))
        else
            output_image = img_loader(base_path, data_index; idtype="seg_$(output_shape[index])", filetype="png")
            output_image = imresize(output_image; ratio=1/4)
            output_image_size = size(output_image)
            if output_image_size[1:2] != input_image_size[1:2]
                error("Output image size $(output_image_size) does not match input image size $(input_image_size)")
            end
            output_images = (output_images..., Gray.(output_image))
            canonicalized_output_shape = (canonicalized_output_shape..., output_shape[index])
        end
    end

    return v__Image_Data(
        canonicalized_input_shape,
        input_image_size[1:2],
        input_images...
    ), v__Image_Data(
        canonicalized_output_shape,
        output_image_size[1:2],
        output_images...
    )
end
=#
@__(function load_input_and_output(base_path, data_index; input_type, input_collection=false, output_type, output_collection=false)
    #=
    input_image = img_loader(base_path, data_index; idtype="raw_adj", filetype="png")
    input_image_size = size(input_image)

    input_images = decompose_image_to_values(input_shape, input_image)
    =#
    local input_image_size
    local input_images = ()
    local canonicalized_input_shape = ()
    input_shape = shape(input_type)
    if input_collection == false
        input_image = img_loader(base_path, data_index; idtype="raw_adj", filetype="png")
        #
        input_image = imresize(input_image; ratio=1/4)
        #
        input_image_size = size(input_image)
        for index in 1:length(input_shape)
            input_images = (input_images..., decompose_image_to_values(input_shape[index], input_image))
            canonicalized_input_shape = (canonicalized_input_shape..., input_shape[index])
        end
    else
        throw("TODO")
    end
    
    local output_image_size
    local output_images = ()
    local canonicalized_output_shape = ()
    output_shape = shape(output_type)
    if output_collection == false
        throw("TODO")
    else
        for index in 1:length(output_shape)
            output_image = img_loader(base_path, data_index; idtype="seg_$(output_shape[index])", filetype="png")
            #
            output_image = imresize(output_image; ratio=1/4)
            #
            output_image_size = size(output_image)
            if output_image_size[1:2] != input_image_size[1:2]
                error("Output image size $(output_image_size) does not match input image size $(input_image_size)")
            end
            output_images = (output_images..., Gray.(output_image))
            canonicalized_output_shape = (canonicalized_output_shape..., output_shape[index])
        end
    end


    #=
    return v__Image_Data(
        canonicalized_input_shape,
        input_image_size[1:2],
        input_images...
    ), v__Image_Data(
        canonicalized_output_shape,
        output_image_size[1:2],
        output_images...
    )
    =#
    return input_type(input_images...), output_type(output_images...)
end)