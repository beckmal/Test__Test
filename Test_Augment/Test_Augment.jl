#=
    const training_sets = []
    const validation_sets = []
=#
const loaded = try
    loaded
catch
    import Random
    import Pkg
    Pkg.activate(@__DIR__)
    Pkg.update()
    Pkg.resolve()
    #TODO: ac_up_re
    try
        using Revise
    catch
    end

    #using Bas3

    using Bas3Plots
    import Bas3Plots.display
    import Bas3Plots.notify
    using Bas3GLMakie
    using Bas3_EnvironmentTools

    using Bas3ImageSegmentation
    using Bas3ImageSegmentation.Bas3
    #using Bas3ImageSegmentation.Bas3QuasiMonteCarlo
    #using Bas3ImageSegmentation.Bas3GaussianProcess
    #using Bas3ImageSegmentation.Bas3SciML_Core
    #using Bas3ImageSegmentation.Bas3Surrogates_Core
    using Bas3ImageSegmentation.Bas3IGABOptimization
    using Bas3ImageSegmentation.RecursiveArrayTools
    import Base.size
    import Base.length
    import Base.minimum
    import Base.maximum
    using Random
    using Mmap

    using Bas3_EnvironmentTools

    import InteractiveUtils
    import InteractiveUtils.@code_warntype
    import InteractiveUtils.@time
    import InteractiveUtils.@allocated

    true
end

#Random.seed!(1234)
const training_sets = try
    training_sets
catch
    _length = 10
    _index_array = shuffle(1:_length)

    #=
    for index in 1:8
        input, output = Bas3ImageSegmentation.load_input_and_output("C:/Users/OsW-x/MuHa - Bilder", _index_array[index])
        push!(training_sets, (memory_map(input), memory_map(output)))
    end
    for index in 9:_length
        input, output = Bas3ImageSegmentation.load_input_and_output("C:/Users/OsW-x/MuHa - Bilder", _index_array[index])
        push!(validation_sets, (memory_map(input), memory_map(output)))
    end
    =#
    input_type = @__(Bas3ImageSegmentation.c__Image_Data{Float32, (:red, :green, :blue)})
    #output_type = @__(Bas3ImageSegmentation.c__Image_Data{Float32, (:foreground, :background)})
    output_type = @__(Bas3ImageSegmentation.c__Image_Data{Float32, (:scar, :redness, :hematoma, :necrosis, :background)})
    println("Input type: ", input_type)
    println("Output type: ", output_type)
    @__(function convert_output(output)
        output_data = data(output)
        #=
        foreground = output_data[:, :, 2] .+ output_data[:, :, 3] .+ output_data[:, :, 4] .+ output_data[:, :, 5]
        background = output_data[:, :, 1]
        return output_type(
            background,
            foreground
        )
        =#
        return output_type(
            output_data[:, :, 1],  # scar
            output_data[:, :, 2],  # redness
            output_data[:, :, 3],  # hematoma
            output_data[:, :, 4],  # necrosis
            output_data[:, :, 5]   # background
        )

    end)

    local training_sets = [
        #memory_map.(Bas3ImageSegmentation.load_input_and_output("C:/Users/OsW-x/MuHa - Bilder", _index_array[index]))
        begin
            input, output = Bas3ImageSegmentation.load_input_and_output("C:/Users/OsW-x/MuHa - Bilder", _index_array[index])
            output = convert_output(output)
            (memory_map(input), memory_map(output))
        end
        for index in 1:_length
    ]
    println(typeof(training_sets))

    training_sets
end
const _size = (256, 256)


import Bas3ImageSegmentation.Augmentor
import Bas3ImageSegmentation.Augmentor.CacheImage
import Bas3ImageSegmentation.Gray
import Bas3ImageSegmentation.RGB
import Bas3ImageSegmentation.Colors.red
import Bas3ImageSegmentation.Colors.green
import Bas3ImageSegmentation.Colors.blue
import Bas3ImageSegmentation.colorview
import Bas3ImageSegmentation.channelview
import Bas3ImageSegmentation.rawview

function _array_training_sets__prepare_inputs(input)
    return (
        colorview(Gray, @view(input.data[:, :, 1])),
        colorview(Gray, @view(input.data[:, :, 2])),
        colorview(Gray, @view(input.data[:, :, 3]))
    )
end
function _array_training_sets__prepare_outputs(output)
    return (
        colorview(Gray, @view(output.data[:, :, 1])),
        colorview(Gray, @view(output.data[:, :, 2])),
        colorview(Gray, @view(output.data[:, :, 3])),
        colorview(Gray, @view(output.data[:, :, 4])),
        colorview(Gray, @view(output.data[:, :, 5]))
    )
end
function _array_training_sets__augment(input, output, pipeline)
    augmented = Augmentor.augment(
        (
            input...,
            output...
        ),
        pipeline
    )
    inputs = augmented[1:length(input)]
    outputs = augmented[(length(input) + 1):end]
    rounded_outputs = (
        round.(Bool, outputs[1]),
        round.(Bool, outputs[2]),
        round.(Bool, outputs[3]),
        round.(Bool, outputs[4]),
        round.(Bool, outputs[5])
    )
    return VectorOfArray([inputs...]), VectorOfArray([rounded_outputs...])
end
function _array_training_sets__write_inputs(inputs, index, augmented)
    #augmented_input = channelview.(augmented[1:3])
    #inputs[:, :, :, index] .= reshape(augmented_input, _size..., 3)
    #=
    inputs[:, :, 1, index] .= augmented_input[1]
    inputs[:, :, 2, index] .= augmented_input[2]
    inputs[:, :, 3, index] .= augmented_input[3]
    =#
    #inputs[:, :, :, index] .= VectorOfArray([augmented_input...])
    inputs[:, :, :, index] .= augmented[1]
end
function _array_training_sets__write_outputs(outputs, index, augmented)
    #augmented_output = channelview.(augmented[4:8])
    #=
    outputs[:, :, 1, index] .= round.(Bool, augmented_output[1])
    outputs[:, :, 2, index] .= round.(Bool, augmented_output[2])
    outputs[:, :, 3, index] .= round.(Bool, augmented_output[3])
    outputs[:, :, 4, index] .= round.(Bool, augmented_output[4])
    outputs[:, :, 5, index] .= round.(Bool, augmented_output[5])
    =#
    #outputs[:, :, :, index] .= VectorOfArray([augmented_output...])
    outputs[:, :, :, index] .= augmented[2]
end
function _array_training_sets(_length, _size, pipeline, training_sets, track_allocations)
    if track_allocations == true
        println("CALL WITH TRACKING ALLOCATIONS")
    else
        println("CALL")
    end
    training_sets_length = length(training_sets)


    inputs = Array{Float32,4}(undef, _size..., 3, _length)
    outputs = Array{Float32,4}(undef, _size..., 5, _length)
    for index in 1:_length
        input, output = training_sets[rand(1:training_sets_length)]
        local input_data
        if track_allocations == true
            println(@allocated begin
                input_data = _array_training_sets__prepare_inputs(input)
            end)
        else
            input_data = _array_training_sets__prepare_inputs(input)
        end
        local output_data
        if track_allocations == true
            println(@allocated begin
                output_data = _array_training_sets__prepare_outputs(output)
            end)
        else
            output_data = _array_training_sets__prepare_outputs(output)
        end

        local augmented
        if track_allocations == true
            println(@allocated begin
                augmented = _array_training_sets__augment(
                    input_data,
                    output_data,
                    pipeline
                )
            end)
        else
            augmented = _array_training_sets__augment(
                input_data,
                output_data,
                pipeline
            )
        end

        if track_allocations == true
            println(@allocated begin
                _array_training_sets__write_inputs(inputs, index, augmented)
            end)
        else
            _array_training_sets__write_inputs(inputs, index, augmented)
        end
        if track_allocations == true
            println(@allocated begin
                _array_training_sets__write_outputs(outputs, index, augmented)
            end)
        else
            _array_training_sets__write_outputs(outputs, index, augmented)
        end
    end

    return inputs, outputs
end

function _struct_training_sets__augment(input, output, pipeline)
    return Augmentor.augment(
        (input, output),
        pipeline
    )
end
function _struct__training_sets__write(inputs, outputs, index, augmented)
    inputs[:, :, :, index] .= data(augmented[1])
    outputs[:, :, :, index] .= data(augmented[2])
end
function _struct_training_sets(_length, _size, pipeline, training_sets, track_allocations)
    if track_allocations == true
        println("CALL WITH TRACKING ALLOCATIONS")
    else
        println("CALL")
    end
    training_sets_length = length(training_sets)

    inputs = Array{Float32,4}(undef, _size..., 3, _length)
    outputs = Array{Float32,4}(undef, _size..., 5, _length)
    for index in 1:_length
        input, output = training_sets[rand(1:training_sets_length)]
        local augmented
        if track_allocations == true
            println(@allocated begin
                augmented = _struct_training_sets__augment(
                    input,
                    output,
                    pipeline
                )
            end)
        else
            augmented = _struct_training_sets__augment(
                input,
                output,
                pipeline
            )
        end

        if track_allocations == true
            println(@allocated begin
                _struct__training_sets__write(inputs, outputs, index, augmented)
            end)
        else
            _struct__training_sets__write(inputs, outputs, index, augmented)
        end
    end

    return inputs, outputs
end

function main()
    _length = 100
    _size = (256, 256)
    pipeline =
        RCropSize(
            _size...
        ) |> Either(
            1 => FlipX(),
            1 => FlipY(),
            2 => NoOp()
        ) |> ShearX(
            -20:20
        ) |> ShearY(
            -20:20
        ) |> Rotate(
            1:1:90
        ) |> Zoom(
            0.8:0.1:1.2
        ) |> CropSize(
            _size...
        )

    println("ARRAY TRAINING SETS")
    @time _array_training_sets(1, _size, pipeline, training_sets, false)
    _array_training_sets(1, _size, pipeline, training_sets, true)
    @time _array_training_sets(_length, _size, pipeline, training_sets, false)

    println()

    println("STRUCT TRAINING SETS")
    @time _struct_training_sets(1, _size, pipeline, training_sets, false)
    _struct_training_sets(1, _size, pipeline, training_sets, true)
    @time _struct_training_sets(_length, _size, pipeline, training_sets, false)
    
    return
end
main()