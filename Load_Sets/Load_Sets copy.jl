import Random
#Random.seed!(1234)
const reporters = try
    for (key, value) in reporters
        stop(value)
    end
    Bas3GLMakie.GLMakie.closeall()
    reporters
catch
    import Pkg
    Pkg.activate(@__DIR__)
    Pkg.update()
    Pkg.resolve()
    try
        using Revise
    catch
    end

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
    import Base.size
    import Base.length
    import Base.minimum
    import Base.maximum
    using Random
    using Mmap
    using Statistics
    using Bas3ImageSegmentation.JLD2

    using Bas3_EnvironmentTools
    import Bas3_EnvironmentTools.Distributed.RemoteChannel
    Dict()
end
const input_type = @__(Bas3ImageSegmentation.c__Image_Data{Float32,(:red, :green, :blue)})
const raw_output_type = @__(Bas3ImageSegmentation.c__Image_Data{Float32,(:scar, :redness, :hematoma, :necrosis, :background)})
#output_type = raw_output_type
const output_type = @__(Bas3ImageSegmentation.c__Image_Data{Float32,(:foreground, :background)})


import Bas3.convert




base_path = "/mnt/c/Syncthing/Datasets"
const sets = try
    sets
catch
    let
        temp_sets = []

        _length = 10
        _index_array = shuffle(1:_length)
        if false
            println("Loading original sets from disk...")
            for index in 1:_length
                println("  Loading set $(index)/$(_length)")
                @time begin
                    input, output = JLD2.load(joinpath(base_path, "original/$(index).jld2"), "set")
                end
                push!(temp_sets, (memory_map(input), memory_map(output), index))
            end
        else
            println("Generating original sets from source images...")
            for index in 1:_length
                println("  Loading image $(index)/$(_length)")
                @time begin
                    input, output = @__(Bas3ImageSegmentation.load_input_and_output(
                        #"/mnt/f/Woundanalyze/MuHa - Bilder",
                         "/mnt/c/Syncthing/MuHa - Bilder",
                        _index_array[index];
                        input_type=input_type,
                        output_type=raw_output_type,
                        output_collection=true
                    ))
                end
                #output = convert(output_type, output)
                push!(temp_sets, (memory_map(input), memory_map(output)))
            end
            println("Saving original sets to disk...")
            for index in 1:_length
                JLD2.save(joinpath(base_path, "original/$(index).jld2"), "set", temp_sets[index])
            end

        end
        println("Original sets loaded: $(length(temp_sets)) sets")
        [temp_sets...]
    end
end
#throw("")

@__(function generate_sets(; _length, _size, temp_augmented_sets, keywords...)
        #ElasticDistortion(gridheight, [gridwidth]; [scale=0.2], [sigma=2], [iter=1], [border=false], [norm=true])
        input_pipeline = ColorJitter(
            0.8:0.1:1.2,
            -0.2:0.1:0.2,
        ) |> GaussianBlur(
            3:2:7,
            1:0.1:3
        )
        post_pipeline = ElasticDistortion(
            8,
            8,
            0.2,
            2,
            1
        )
        pipeline = Scale(
                       0.9:0.01:1.1
                   ) |> RCropSize(
                       maximum(_size), maximum(_size)
                   ) |> ShearX(
                       -10:0.1:10
                   ) |> ShearY(
                       -10:0.1:10
                   ) |> Rotate(
                       1:0.1:360
                   ) |> CropSize(
                       maximum(_size), maximum(_size)
                   ) |> Either(
                       1 => FlipX(),
                       1 => FlipY(),
                       1 => NoOp()
                   )
        local inputs, outputs

        inputs = Vector{@__(input_type{_size})}(undef, _length)
        outputs = Vector{@__(raw_output_type{_size})}(undef, _length)
        image_indices = Vector{Int}(undef, _length)

        class_indicies = shuffle([1, 1, 1, 1, 1, 1, 2, 2, 2, 2, 2, 3, 4, 4, 4])
        class_indicies_length = length(class_indicies)
        class_indicies_index = 1
        for index in 1:_length
            class = class_indicies[class_indicies_index]
            class_indicies_index += 1
            if class_indicies_index > class_indicies_length
                class_indicies_index = 1
            end

            while true
                try
                    local augmented_input, augmented_output, sample_index
                    while true
                        while true
                            sample_index = rand(1:length(temp_augmented_sets))
                            if sample_index != 8 && sample_index != 16
                                break
                            end
                        end
                        input, output = temp_augmented_sets[sample_index]
                        augmented_input, augmented_output = augment((input, output), pipeline)
                        augmented_input, augmented_output = augment((augmented_input, augmented_output), CropSize(_size...))
                        augmented_output_data = data(augmented_output)

                        #foreground_area = sum(augmented_output_data[:, :, 2] + augmented_output_data[:, :, 3] + augmented_output_data[:, :, 4] + augmented_output_data[:, :, 1])
                        foreground_area = sum(augmented_output_data[:, :, class])
                        background_area = sum(augmented_output_data[:, :, 5])
                        area = foreground_area + background_area
                        if (foreground_area / area) >= 0.05
                            break
                        end
                    end

                    inputs[index] = augment(augmented_input, post_pipeline |> input_pipeline)
                    augmented_output = augment(augmented_output, post_pipeline)
                    augmented_output = convert(raw_output_type, augmented_output)
                    outputs[index] = augmented_output
                    image_indices[index] = sample_index
                    break
                catch error
                    throw(error)
                    println(typeof(error))
                end
            end


        end

        return inputs, outputs, image_indices
    end; Transform=false)

augmented_sets = try
    augmented_sets
catch
    let
        temp_augmented_sets = []
        total_augmented_length = 100

        if false
            println("Loading augmented sets from disk...")
            for index in 1:total_augmented_length
                println("  Loading augmented set $(index)/$(total_augmented_length)")
                @time begin
                    input, output = JLD2.load(joinpath(base_path, "augmented/$(index).jld2"), "set")
                end
                image_index = get(sets[mod1(index, length(sets))], 3, index)
                push!(temp_augmented_sets, (memory_map(input), memory_map(output), image_index))
            end
            println("Augmented sets loaded: $(length(temp_augmented_sets)) sets")
            
        else
            println("Generating augmented sets...")
            augmented_length = 0
            while true
                println("  Generating batch starting at $(augmented_length + 1)/$(total_augmented_length)")
                @time begin
                    augmented_inputs, augmented_outputs, image_indices = @__(generate_sets(; _length=50, _size=(100, 50), temp_augmented_sets=sets))
                end
                for index in 1:length(augmented_inputs)
                    augmented_length += 1
                    println("    Saving augmented set $(augmented_length)/$(total_augmented_length)")
                    JLD2.save(joinpath(base_path, "augmented/$(augmented_length).jld2"), "set", (augmented_inputs[index], augmented_outputs[index]))
                    push!(temp_augmented_sets, (memory_map(augmented_inputs[index]), memory_map(augmented_outputs[index]), image_indices[index]))
                    if augmented_length >= total_augmented_length
                        break
                    end
                end
                if augmented_length >= total_augmented_length
                    break
                end
            end
            println("Augmented sets generated: $(length(temp_augmented_sets)) sets")
        end
        [temp_augmented_sets...]
    end
end


@__(begin
    classes = shape(raw_output_type)
    a = Dict((k => 0.0 for k in classes))
    aa = Dict((k => [] for k in classes))
    #image_indicies_classes = Dict((k=>[] for k in classes))
    local t = 0.0
    #inputs, outputs = _training_sets(; _length=100, _size=(100, 50))
    #inputs = [(training_sets[i][1]) for i in 1:length(training_sets)]
    #outputs = [(training_sets[i][2]) for i in 1:length(training_sets)]
    #inputs, outputs = @__(generate_sets(; _length=100, _size=(128, 64), temp_augmented_sets=augmented_sets))
    #augmented_sets
    inputs = [augmented_sets[i][1] for i in 1:length(augmented_sets)]
    outputs = [augmented_sets[i][2] for i in 1:length(augmented_sets)]
    image_indices = [augmented_sets[i][3] for i in 1:length(augmented_sets)]
    x_image_indices = 1:length(sets)
    y_image_indices = zeros(Int, length(sets))
    for i in image_indices
        y_image_indices[i] += 1
    end
    for o in outputs
        sa = shape_areas(o)
        for k in keys(sa)
            t += sa[k]
            a[k] += sa[k]
            aa[k] = push!(aa[k], sa[k])
        end
    end
    #println(a[:foreground] / (a[:foreground] + a[:background]))
    #m = maximum(values(a))

    ms_ss = (; (k => (; mean=mean((aa[k] ./ t)), std=std((aa[k] ./ t))) for k in keys(aa))...)

    println("Areas: ", a)
    println("Means and Standard Deviations: ", ms_ss)

    #=
    ms = [mean(aa[k]) for k in keys(aa)]
    ss = [std(aa[k]) for k in keys(aa)]
    =#

    fgr = Figure()
    Bas3GLMakie.GLMakie.Label(fgr[0, :], "Dataset Statistics", fontsize=20)
    l = length(classes)
    axs1 = Bas3GLMakie.GLMakie.Axis(fgr[1, 1]; xticks=(1:l, [string.(classes)...]), title="Total Class Areas", ylabel="Proportion", xlabel="Class")
    axs2 = Bas3GLMakie.GLMakie.Axis(fgr[1, 2]; xticks=(1:l, [string.(classes)...]), title="Mean Class Areas with Std Dev", ylabel="Proportion", xlabel="Class")
    axs3 = Bas3GLMakie.GLMakie.Axis(fgr[2, 1:2]; xticks=(1:length(sets)), title="Augmented Sets per Original Image", ylabel="Count", xlabel="Original Image Index")

    #println("Sum of foreground: ", (a[:hematoma] + a[:redness] + a[:scar] + a[:necrosis]) / t)

    local offset = 1
    #make barplot! with errorbars! 
    local nt1 = 0
    for i in 1:l
        k = classes[i]
        #Bas3GLMakie.GLMakie.barplot!(axs, offset, a[k] / t; label=k)
        Bas3GLMakie.scatter!(axs1, offset, a[k] / t; markersize=10)
        nt1 += ms_ss[k].mean
        Bas3GLMakie.GLMakie.errorbars!(axs2, [offset], [ms_ss[k].mean], [ms_ss[k].mean - ms_ss[k].std], [ms_ss[k].mean + ms_ss[k].std]; whiskerwidth=10)
        offset += 1
    end
    Bas3GLMakie.GLMakie.barplot!(axs3, x_image_indices, y_image_indices)
    display(fgr)
    println("Total: ", nt1)
    #throw("")
end)

println("\n=== Testing sets variable ===")
println("Type of sets: ", typeof(sets))
println("Length of sets: ", length(sets))
println("First element type: ", typeof(sets[1]))
