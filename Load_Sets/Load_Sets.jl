import Random
#Random.seed!(1234)
const reporters = try
    for (key, value) in reporters
        stop(value)
    end
    Bas3GLMakie.GLMakie.closeall()
    reporters
catch
    println("=== Initializing reporters ===")
    import Pkg
    Pkg.activate(@__DIR__)
    println("Updating packages...")
    Pkg.update()
    println("Resolving dependencies...")
    Pkg.resolve()
    println("Skipping Revise for faster loading...")
    #try
    #    using Revise
    #    println("  Revise loaded")
    #catch
    #    println("  Revise not available")
    #end

    println("Loading Bas3Plots...")
    using Bas3Plots
    import Bas3Plots.display
    import Bas3Plots.notify
    println("Loading Bas3GLMakie...")
    using Bas3GLMakie
    println("Loading Bas3_EnvironmentTools (1)...")
    using Bas3_EnvironmentTools

    println("Loading Bas3ImageSegmentation...")
    using Bas3ImageSegmentation
    println("Loading Bas3ImageSegmentation.Bas3...")
    using Bas3ImageSegmentation.Bas3
    #using Bas3ImageSegmentation.Bas3QuasiMonteCarlo
    #using Bas3ImageSegmentation.Bas3GaussianProcess
    #using Bas3ImageSegmentation.Bas3SciML_Core
    #using Bas3ImageSegmentation.Bas3Surrogates_Core
    println("Loading Bas3ImageSegmentation.Bas3IGABOptimization...")
    using Bas3ImageSegmentation.Bas3IGABOptimization
    println("Importing Base functions...")
    import Base.size
    import Base.length
    import Base.minimum
    import Base.maximum
    println("Loading Random, Mmap, Statistics...")
    using Random
    using Mmap
    using Statistics
    println("Loading JLD2...")
    using Bas3ImageSegmentation.JLD2

    println("Loading Bas3_EnvironmentTools (2)...")
    using Bas3_EnvironmentTools
    println("Importing RemoteChannel...")
    import Bas3_EnvironmentTools.Distributed.RemoteChannel
    println("=== Reporters initialized ===")
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
        regenerate_images = false
        temp_sets = []

        _length = 306
        _index_array = shuffle(1:_length)
        if regenerate_images == false
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

# Augmentation disabled - focusing on original images only
#=
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
=#

# ============================================================================
# Statistics and Visualization for Original Images
# ============================================================================

@__(begin
    println("\n=== Computing Dataset Statistics ===")
    
    # Extract class names from output type
    local classes = shape(raw_output_type)
    
    # Extract inputs and outputs from sets
    local inputs = [sets[i][1] for i in 1:length(sets)]
    local outputs = [sets[i][2] for i in 1:length(sets)]
    
    # Initialize accumulators for statistics
    local total_pixels = 0.0
    local class_totals = Dict(class => 0.0 for class in classes)
    local class_areas_per_image = Dict(class => Float64[] for class in classes)
    
    # Compute areas for each class across all images
    println("Analyzing $(length(outputs)) images...")
    for output_image in outputs
        local areas = shape_areas(output_image)
        for class in classes
            local area = areas[class]
            total_pixels += area
            class_totals[class] += area
            push!(class_areas_per_image[class], area)
        end
    end
    
    # Compute statistics (mean and std as proportions of total pixels)
    local statistics = Dict(
        class => (
            mean = mean(class_areas_per_image[class] ./ total_pixels),
            std = std(class_areas_per_image[class] ./ total_pixels)
        )
        for class in classes
    )
    
    # Print results
    println("\nTotal pixels across all images: ", total_pixels)
    println("\nClass totals (absolute):")
    for class in classes
        println("  $class: ", class_totals[class])
    end
    
    println("\nClass statistics (as proportions):")
    local total_proportion = 0.0
    for class in classes
        println("  $class:")
        println("    mean: ", statistics[class].mean)
        println("    std:  ", statistics[class].std)
        total_proportion += statistics[class].mean
    end
    println("Total proportion: ", total_proportion)
    
    # Create visualizations
    println("\nGenerating visualizations...")
    local fgr = Figure(size=(1600, 900))
    
    # Add title using Label in proper grid position
    local title_label = Bas3GLMakie.GLMakie.Label(
        fgr[1, 1:3], 
        "Original Dataset Statistics ($(length(sets)) images)", 
        fontsize=24,
        font=:bold,
        halign=:center
    )
    
    local num_classes = length(classes)
    
    # Axis 1: Total class areas as proportions
    local axs1 = Bas3GLMakie.GLMakie.Axis(
        fgr[2, 1]; 
        xticks=(1:num_classes, [string.(classes)...]), 
        title="Total Class Areas", 
        ylabel="Proportion of Total Pixels", 
        xlabel="Class"
    )
    
    # Axis 2: Mean class areas with standard deviation
    local axs2 = Bas3GLMakie.GLMakie.Axis(
        fgr[2, 2]; 
        xticks=(1:num_classes, [string.(classes)...]), 
        title="Mean Class Areas with Std Dev", 
        ylabel="Proportion of Total Pixels", 
        xlabel="Class"
    )
    
    # Axis 3: Image viewer
    local axs3 = Bas3GLMakie.GLMakie.Axis(
        fgr[2, 3];
        title="Image Viewer",
        aspect=Bas3GLMakie.GLMakie.DataAspect()
    )
    Bas3GLMakie.GLMakie.hidedecorations!(axs3)
    
    # Plot data
    for (i, class) in enumerate(classes)
        # Plot total proportions
        Bas3GLMakie.scatter!(axs1, i, class_totals[class] / total_pixels; markersize=10)
        
        # Plot means with error bars
        mean_val = statistics[class].mean
        std_val = statistics[class].std
        Bas3GLMakie.GLMakie.errorbars!(
            axs2, 
            [i], 
            [mean_val], 
            [std_val], 
            [std_val]; 
            whiskerwidth=10
        )
    end
    
    # Add slider for image selection
    local slider = Bas3GLMakie.GLMakie.Slider(
        fgr[3, 1:3],
        range=1:length(sets),
        startvalue=1
    )
    
    local slider_label = Bas3GLMakie.GLMakie.Label(
        fgr[4, 1:3],
        Bas3GLMakie.GLMakie.lift(i -> "Image: $i / $(length(sets))", slider.value),
        fontsize=16,
        halign=:center
    )
    
    # Display initial image using the image() function
    local current_image = Bas3GLMakie.GLMakie.Observable(rotr90(image(sets[1][1])))
    
    # Update image when slider changes
    Bas3GLMakie.GLMakie.on(slider.value) do idx
        # Get RGB image using the image() function and rotate for correct orientation
        img_data = rotr90(image(sets[idx][1]))
        current_image[] = img_data
    end
    
    # Display the image
    Bas3GLMakie.GLMakie.image!(axs3, current_image)
    
    display(fgr)  # Comment out to avoid GUI blocking
    println("\nStatistics computation complete.")
end)

println("\n=== Testing sets variable ===")
println("Type of sets: ", typeof(sets))
println("Length of sets: ", length(sets))
println("First element type: ", typeof(sets[1]))
