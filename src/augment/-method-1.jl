#=
import InteractiveUtils.@code_warntype
import InteractiveUtils.@allocated
function Augmentor.augment(
    _data::Tuple{<:v__Image_Data{input_shape},<:v__Image_Data{output_shape}},
    pipeline
) where {input_shape, output_shape}
    input, output = _data
    #return input, output
    input_images = images(input)
    output_images = images(output)
    augmented_data = Augmentor.augment(
        (input_images..., output_images...),
        pipeline
    )
    input_images_length = length(input_images)
    output_images_length = length(output_images)

    augmented_input_images = augmented_data[1:input_images_length]
    augmented_output_images = augmented_data[(input_images_length + 1):(input_images_length + output_images_length)]

    return v__Image_Data(
        input_shape,
        size(first(augmented_input_images))[1:2],
        augment__post_process_image.(((shape_type(shape) for shape in input.shape)...,), augmented_input_images)...
    ), v__Image_Data(
        output_shape,
        size(first(augmented_output_images))[1:2],
        augment__post_process_image.(((shape_type(shape) for shape in output.shape)...,), augmented_output_images)...
    )
end
=#
@__(function Augmentor.augment(
    _data::Tuple{input_type, output_type},
    pipeline
) where {input_type <: u__Image_Data, output_type <: u__Image_Data}
    input, output = _data
    #return input, output
    input_images = channels(input)
    output_images = channels(output)
    augmented_data = Augmentor.augment(
        (input_images..., output_images...),
        pipeline
    )
    input_images_length = length(input_images)
    output_images_length = length(output_images)

    augmented_input_images = augmented_data[1:input_images_length]
    augmented_output_images = augmented_data[(input_images_length + 1):(input_images_length + output_images_length)]
    
    return c__Image_Data{element_type(input), shape(input)}(
        augment__post_process_image.(((shape_type(shape) for shape in input.shape)...,), augmented_input_images)...
    ), c__Image_Data{element_type(output), shape(output)}(
        augment__post_process_image.(((shape_type(shape) for shape in output.shape)...,), augmented_output_images)...
    )
end)
@__(function Augmentor.augment(
    data::type,
    pipeline
) where {type <: u__Image_Data}
    augmented_data = Augmentor.augment(
        channels(data),
        pipeline
    )
    return c__Image_Data{element_type(data), shape(data)}(
        augment__post_process_image.(((shape_type(shape) for shape in data.shape)...,), augmented_data)...
    )
end)
function augment__post_process_image(shape, image)
    
    if shape == Bas3ImageSegmentation.Binary
        return colorview(
            Gray,
            Base.convert.(Float32, round.(Bool, image))
        )
    elseif shape == Bas3ImageSegmentation.Continuous
        return colorview(
            Gray,
            image
        )
    else
        throw(ArgumentError("Unknown shape type for $(shape)"))
    end
    
    #return image
end
#=
function Augmentor.augment!(
    out::Tuple{<:v__Image_Data,<:v__Image_Data},
    _data::Tuple{<:v__Image_Data,<:v__Image_Data},
    pipeline
)
    out_input, out_output = out
    input, output = _data
    Augmentor.augment!(
        (image(out_input), (Gray.(data(out_output)[:, :, index]) for index in 1:length(out_output.shape))...),
        (image(input), (Gray.(data(output)[:, :, index]) for index in 1:length(output.shape))...),
        pipeline
    )
    return out
end
=#
#=
struct t__agument <: t__ end
struct t__augment__Image_Data <: t__ end
function t__augment(::u__Image_Data)
    return t__augment__Image_Data()
end
function augment(positionals...)
    return Augmentor.augment(pack_traits(t__augment, positionals)...)
end
=#