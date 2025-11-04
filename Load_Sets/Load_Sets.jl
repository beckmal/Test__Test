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
    println("Loading Random, Mmap, Statistics, LinearAlgebra...")
    using Random
    using Mmap
    using Statistics
    using LinearAlgebra
    println("Loading JLD2...")
    using Bas3ImageSegmentation.JLD2

    println("Loading Bas3_EnvironmentTools (2)...")
    using Bas3_EnvironmentTools
    println("Importing RemoteChannel...")
    import Bas3_EnvironmentTools.Distributed.RemoteChannel
    println("=== Reporters initialized ===")
    Dict()
end

# Import LinearAlgebra.eigen at module level for PCA in extract_white_mask
import LinearAlgebra: eigen
import Base: abs

const input_type = @__(Bas3ImageSegmentation.c__Image_Data{Float32,(:red, :green, :blue)})
const raw_output_type = @__(Bas3ImageSegmentation.c__Image_Data{Float32,(:scar, :redness, :hematoma, :necrosis, :background)})
#output_type = raw_output_type
const output_type = @__(Bas3ImageSegmentation.c__Image_Data{Float32,(:foreground, :background)})


import Bas3.convert

# Function to resolve paths based on operating system
# Converts C:/ paths to /mnt/c/ on WSL and vice versa
function resolve_path(relative_path::String)
    if Sys.iswindows()
        # Running on native Windows
        # Convert /mnt/c/ to C:/ if needed
        if startswith(relative_path, "/mnt/")
            drive_letter = uppercase(relative_path[6])
            rest_of_path = replace(relative_path[8:end], "/" => "\\")
            return "$(drive_letter):\\$(rest_of_path)"
        else
            return relative_path
        end
    else
        # Running on Linux/WSL
        # Convert C:/ to /mnt/c/ if needed
        if occursin(r"^[A-Za-z]:[/\\]", relative_path)
            drive_letter = lowercase(relative_path[1])
            rest_of_path = replace(relative_path[4:end], "\\" => "/")
            return "/mnt/$(drive_letter)/$(rest_of_path)"
        else
            return relative_path
        end
    end
end

# Base path for datasets - will be converted based on OS
base_path = resolve_path("C:/Syncthing/Datasets")
const sets = try
    sets
catch
    let
        regenerate_images = false
        temp_sets = []

        _length = 306  #10Load first 10 images for testing
        _index_array = shuffle(1:_length)
        if regenerate_images == false
            println("Loading original sets from disk (first $((_length)) images)...")
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
                        #resolve_path("F:/Woundanalyze/MuHa - Bilder"),
                         resolve_path("C:/Syncthing/MuHa - Bilder"),
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

begin
    println("\n=== Computing Dataset Statistics ===")
    
    # Extract class names from output type
    local classes = shape(raw_output_type)
    
    # German translations for class names
    local class_names_de = Dict(
        :scar => "Narbe",
        :redness => "Rötung",
        :hematoma => "Hämatom",
        :necrosis => "Nekrose",
        :background => "Hintergrund"
    )
    
    # Helper function to get German class names in order
    local get_german_names(class_list) = [class_names_de[c] for c in class_list]
    
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
    
    # Compute normalized statistics (sum to 1.0)
    local sum_of_means = sum(statistics[class].mean for class in classes)
    local normalized_statistics = Dict(
        class => (
            mean = statistics[class].mean / sum_of_means,
            std = statistics[class].std / sum_of_means
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
    
    println("\nNormalized class statistics (sum to 1.0):")
    local total_normalized = 0.0
    for class in classes
        println("  $class:")
        println("    mean: ", normalized_statistics[class].mean)
        println("    std:  ", normalized_statistics[class].std)
        total_normalized += normalized_statistics[class].mean
    end
    println("Total normalized: ", total_normalized)
    
    # ============================================================================
    # Bounding Box Metrics Computation
    # ============================================================================
    
    println("\n=== Computing Bounding Box Metrics ===")
    
    # Define non-background classes for bounding box analysis
    local bbox_classes = filter(c -> c != :background, classes)
    
    # Initialize storage for bounding box metrics per class (excluding background)
    local bbox_metrics = Dict(
        class => Dict(
            :widths => Float64[],
            :heights => Float64[],
            :aspect_ratios => Float64[]
        )
        for class in bbox_classes
    )
    
    # Process each output image
    println("Analyzing bounding boxes for $(length(outputs)) images (excluding background)...")
    for (img_idx, output_image) in enumerate(outputs)
        local output_data = data(output_image)
        
        # Process each class
        for (class_idx, class) in enumerate(classes)
            # Skip background class
            if class == :background
                continue
            end
            
            # Extract binary mask for this class (threshold at 0.5)
            local class_mask = output_data[:, :, class_idx] .> 0.5
            
            # Skip if no pixels for this class
            if !any(class_mask)
                continue
            end
            
            # Label connected components
            local labeled = Bas3ImageSegmentation.label_components(class_mask)
            local num_components = maximum(labeled)
            
            # Process each connected component
            for component_id in 1:num_components
                # Get mask for this component
                local component_mask = labeled .== component_id
                
                # Find all pixels in this component
                local pixel_coords = findall(component_mask)
                
                if isempty(pixel_coords)
                    continue
                end
                
                # Extract row and column indices
                local row_indices = Float64[p[1] for p in pixel_coords]
                local col_indices = Float64[p[2] for p in pixel_coords]
                
                # Compute centroid
                local centroid_row = sum(row_indices) / length(row_indices)
                local centroid_col = sum(col_indices) / length(col_indices)
                
                # Center the coordinates
                local centered_rows = row_indices .- centroid_row
                local centered_cols = col_indices .- centroid_col
                
                # Compute covariance matrix for PCA
                local n = length(centered_rows)
                local cov_matrix = [
                    sum(centered_rows .* centered_rows) / n   sum(centered_rows .* centered_cols) / n;
                    sum(centered_rows .* centered_cols) / n   sum(centered_cols .* centered_cols) / n
                ]
                
                # Compute eigenvectors (principal directions)
                local eigen_result = eigen(cov_matrix)
                local principal_axes = eigen_result.vectors
                
                # Project points onto principal axes
                local proj_axis1 = centered_rows .* principal_axes[1, 2] .+ centered_cols .* principal_axes[2, 2]
                local proj_axis2 = centered_rows .* principal_axes[1, 1] .+ centered_cols .* principal_axes[2, 1]
                
                # Find min/max along each principal axis
                local min_proj1, max_proj1 = extrema(proj_axis1)
                local min_proj2, max_proj2 = extrema(proj_axis2)
                
                # Calculate oriented bounding box dimensions
                local rotated_width = max_proj1 - min_proj1
                local rotated_height = max_proj2 - min_proj2
                
                # Calculate aspect ratio (avoid division by zero)
                local aspect_ratio = if min(rotated_width, rotated_height) > 0
                    max(rotated_width, rotated_height) / min(rotated_width, rotated_height)
                else
                    1.0  # Default to 1.0 if one dimension is zero
                end
                
                # Store metrics (using rotated bounding box dimensions)
                push!(bbox_metrics[class][:widths], Float64(rotated_width))
                push!(bbox_metrics[class][:heights], Float64(rotated_height))
                push!(bbox_metrics[class][:aspect_ratios], aspect_ratio)
            end
        end
    end
    
    # Compute aggregate statistics for each class
    println("\nBounding Box Statistics by Class:")
    println("="^70)
    
    local bbox_statistics = Dict(
        class => Dict(
            :mean_width => isempty(bbox_metrics[class][:widths]) ? 0.0 : mean(bbox_metrics[class][:widths]),
            :std_width => isempty(bbox_metrics[class][:widths]) ? 0.0 : std(bbox_metrics[class][:widths]),
            :mean_height => isempty(bbox_metrics[class][:heights]) ? 0.0 : mean(bbox_metrics[class][:heights]),
            :std_height => isempty(bbox_metrics[class][:heights]) ? 0.0 : std(bbox_metrics[class][:heights]),
            :mean_aspect_ratio => isempty(bbox_metrics[class][:aspect_ratios]) ? 0.0 : mean(bbox_metrics[class][:aspect_ratios]),
            :std_aspect_ratio => isempty(bbox_metrics[class][:aspect_ratios]) ? 0.0 : std(bbox_metrics[class][:aspect_ratios]),
            :num_components => length(bbox_metrics[class][:widths])
        )
        for class in bbox_classes
    )
    
    for class in bbox_classes
        local stats = bbox_statistics[class]
        println("\n$class:")
        println("  Number of components: ", stats[:num_components])
        println("  Average width:  ", round(stats[:mean_width], digits=2), " ± ", round(stats[:std_width], digits=2), " pixels")
        println("  Average height: ", round(stats[:mean_height], digits=2), " ± ", round(stats[:std_height], digits=2), " pixels")
        println("  Average aspect ratio: ", round(stats[:mean_aspect_ratio], digits=2), " ± ", round(stats[:std_aspect_ratio], digits=2))
    end
    
    println("\n" * "="^70)
    
    # ============================================================================
    # Channel-Wise Statistics: Mean Intensity and Histogram Skewness
    # ============================================================================
    
    println("\n=== Computing Channel-Wise Statistics ===")
    
    # Extract channel names from input type
    local channel_names = shape(input_type)  # (:red, :green, :blue)
    local num_channels = length(channel_names)
    
    # German translations for channel names
    local channel_names_de = Dict(
        :red => "Rot",
        :green => "Grün",
        :blue => "Blau"
    )
    
    # Helper function to get German channel names in order
    local get_german_channel_names(channel_list) = [channel_names_de[c] for c in channel_list]
    
    # Initialize storage for per-image statistics
    local channel_means_per_image = Dict(channel => Float64[] for channel in channel_names)
    local channel_skewness_per_image = Dict(channel => Float64[] for channel in channel_names)
    
    # Manual skewness calculation
    # Skewness = E[((X - μ) / σ)³]
    # Where μ is mean and σ is standard deviation
    function compute_skewness(values::AbstractVector{T}) where T <: Real
        if isempty(values)
            return 0.0
        end
        
        local μ = mean(values)
        local σ = std(values)
        
        # Handle edge case where all values are identical
        if σ == 0.0 || isnan(σ)
            return 0.0
        end
        
        # Compute standardized third moment
        local standardized_cubes = ((values .- μ) ./ σ) .^ 3
        local skew = mean(standardized_cubes)
        
        return skew
    end
    
    # Process each input image
    println("Analyzing $(length(inputs)) input images for channel statistics...")
    for (img_idx, input_image) in enumerate(inputs)
        local input_data = data(input_image)
        
        # Process each channel
        for (channel_idx, channel) in enumerate(channel_names)
            # Extract channel data as a flat vector
            local channel_data = vec(input_data[:, :, channel_idx])
            
            # Compute mean intensity for this channel
            local channel_mean = mean(channel_data)
            push!(channel_means_per_image[channel], channel_mean)
            
            # Compute histogram skewness for this channel
            local channel_skew = compute_skewness(channel_data)
            push!(channel_skewness_per_image[channel], channel_skew)
        end
        
        if img_idx % 5 == 0 || img_idx == length(inputs)
            println("  Processed $img_idx/$(length(inputs)) images...")
        end
    end
    
    # Compute aggregate statistics across all images
    println("\nComputing aggregate statistics across dataset...")
    local channel_statistics = Dict(
        channel => (
            mean_intensity_per_image_mean = mean(channel_means_per_image[channel]),
            mean_intensity_per_image_std = std(channel_means_per_image[channel]),
            skewness_per_image_mean = mean(channel_skewness_per_image[channel]),
            skewness_per_image_std = std(channel_skewness_per_image[channel]),
            overall_mean_intensity = mean(channel_means_per_image[channel]),
            overall_skewness_mean = mean(channel_skewness_per_image[channel])
        )
        for channel in channel_names
    )
    
    # Also compute global statistics by concatenating all pixels from all images
    println("Computing global channel statistics across all pixels...")
    local global_channel_stats = Dict{Symbol, NamedTuple}()
    for (channel_idx, channel) in enumerate(channel_names)
        # Collect all pixel values for this channel from all images
        local all_pixels = Float64[]
        for input_image in inputs
            local input_data = data(input_image)
            append!(all_pixels, vec(input_data[:, :, channel_idx]))
        end
        
        # Compute global statistics
        local global_mean = mean(all_pixels)
        local global_std = std(all_pixels)
        local global_skew = compute_skewness(all_pixels)
        
        global_channel_stats[channel] = (
            mean = global_mean,
            std = global_std,
            skewness = global_skew,
            num_pixels = length(all_pixels)
        )
    end
    
    # Print results
    println("\n" * "="^70)
    println("Channel-Wise Statistics Results")
    println("="^70)
    
    println("\nPer-Image Aggregate Statistics:")
    println("(Average of per-image means and skewness values)")
    println("-"^70)
    for channel in channel_names
        local stats = channel_statistics[channel]
        println("\n$channel:")
        println("  Mean Intensity (averaged over images):")
        println("    Mean: ", round(stats.mean_intensity_per_image_mean, digits=4))
        println("    Std:  ", round(stats.mean_intensity_per_image_std, digits=4))
        println("  Skewness (averaged over images):")
        println("    Mean: ", round(stats.skewness_per_image_mean, digits=4))
        println("    Std:  ", round(stats.skewness_per_image_std, digits=4))
    end
    
    println("\n" * "-"^70)
    println("\nGlobal Statistics Across All Pixels:")
    println("(Statistics computed on all pixels from all images combined)")
    println("-"^70)
    for channel in channel_names
        local stats = global_channel_stats[channel]
        println("\n$channel:")
        println("  Total pixels analyzed: ", stats.num_pixels)
        println("  Global mean intensity: ", round(stats.mean, digits=4))
        println("  Global std deviation:  ", round(stats.std, digits=4))
        println("  Global skewness:       ", round(stats.skewness, digits=4))
        local skew_interpretation = if stats.skewness > 0.5
            "Right-skewed (tail extends right, more dark pixels)"
        elseif stats.skewness < -0.5
            "Left-skewed (tail extends left, more bright pixels)"
        else
            "Approximately symmetric"
        end
        println("  Interpretation:        ", skew_interpretation)
    end
    
    println("\n" * "="^70)
    
    # Create visualizations
    println("\nGenerating visualizations...")
    
    # Figure 1: Class Statistics
    local stats_fig = Figure(size=(1800, 900))
    
    # Add title for statistics figure
    local stats_title = Bas3GLMakie.GLMakie.Label(
        stats_fig[1, 1:3], 
        "Klassenflächenstatistik Gesamtdatensatz ($(length(sets)) Bilder)", 
        fontsize=24,
        font=:bold,
        halign=:center
    )
    
    local num_classes = length(classes)
    
    # Calculate max and min values for non-background classes (for zoomed plots)
    local non_background_classes = filter(c -> c != :background, classes)
    # For axs3: use raw proportions
    local max_total_proportion = maximum(class_totals[class] / total_pixels for class in non_background_classes)
    local min_total_proportion = minimum(class_totals[class] / total_pixels for class in non_background_classes)
    local range_total_proportion = max_total_proportion - min_total_proportion
    local padding_total = range_total_proportion * 0.1
    # For axs4: use normalized statistics with std
    local max_normalized_with_std = maximum(normalized_statistics[class].mean + normalized_statistics[class].std for class in non_background_classes)
    local min_normalized_with_std = minimum(normalized_statistics[class].mean - normalized_statistics[class].std for class in non_background_classes)
    local range_normalized = max_normalized_with_std - min_normalized_with_std
    local padding_normalized = range_normalized * 0.1
    
    println("\nAxis limit calculations:")
    println("Non-background classes: ", non_background_classes)
    println("Max normalized (mean+std): ", max_normalized_with_std)
    println("Min normalized (mean-std): ", min_normalized_with_std)
    println("Range: ", range_normalized, ", Padding (10%): ", padding_normalized)
    println("Axis 4 y-limits: [", min_normalized_with_std - padding_normalized, ", ", max_normalized_with_std + padding_normalized, "]")
    for class in non_background_classes
        local mean_val = normalized_statistics[class].mean
        local std_val = normalized_statistics[class].std
        println("  $class: mean=$mean_val, std=$std_val, mean-std=$(mean_val - std_val), mean+std=$(mean_val + std_val)")
    end
    
    # Axis 1: Total class areas as proportions (bar plot)
    local axs1 = Bas3GLMakie.GLMakie.Axis(
        stats_fig[2, 1]; 
        xticks=(1:num_classes, get_german_names(classes)), 
        title="Gesamtklassenflächen (normalisiert)", 
        ylabel="Anteil der Gesamtpixel", 
        xlabel="Klasse"
    )
    
    # Axis 2: Class area distribution (normalized to sum to 1)
    local axs2 = Bas3GLMakie.GLMakie.Axis(
        stats_fig[2, 2]; 
        xticks=(1:num_classes, get_german_names(classes)), 
        title="Klassenflächenverteilung (normalisiert)", 
        ylabel="Normalisierter Anteil", 
        xlabel="Klasse"
    )
    
    # Axis 5: Mean+Std error bars (normalized) - linked to axs2
    local axs5 = Bas3GLMakie.GLMakie.Axis(
        stats_fig[2, 3]; 
        xticks=(1:num_classes, get_german_names(classes)), 
        title="Klassenfläche Mittelwert ± Std (normalisiert)", 
        ylabel="Normalisierter Anteil", 
        xlabel="Klasse"
    )
    
    # Link axes 2 and 5 (non-zoomed plots)
    Bas3GLMakie.GLMakie.linkyaxes!(axs2, axs5)
    Bas3GLMakie.GLMakie.linkxaxes!(axs2, axs5)
    
    # Axis 3: Total class areas (zoomed to non-background classes, bar plot)
    local axs3 = Bas3GLMakie.GLMakie.Axis(
        stats_fig[3, 1]; 
        xticks=(1:num_classes, get_german_names(classes)), 
        title="Gesamtklassenflächen (normalisiert; gezoomt)",
        ylabel="Anteil der Gesamtpixel", 
        xlabel="Klasse",
        limits=(nothing, nothing, min_total_proportion - padding_total, max_total_proportion + padding_total)
    )
    
    # Axis 4: Class area distribution (zoomed to non-background classes)
    local axs4 = Bas3GLMakie.GLMakie.Axis(
        stats_fig[3, 2]; 
        xticks=(1:num_classes, get_german_names(classes)), 
        title="Klassenflächenverteilung (normalisiert; gezoomt)", 
        ylabel="Normalisierter Anteil", 
        xlabel="Klasse",
        limits=(nothing, nothing, min_normalized_with_std - padding_normalized, max_normalized_with_std + padding_normalized)
    )
    
    # Axis 6: Mean+Std error bars (zoomed to non-background classes) - linked to axs4
    local axs6 = Bas3GLMakie.GLMakie.Axis(
        stats_fig[3, 3]; 
        xticks=(1:num_classes, get_german_names(classes)), 
        title="Klassenfläche Mittelwert ± Std (normalisiert; gezoomt)", 
        ylabel="Normalisierter Anteil", 
        xlabel="Klasse",
        limits=(nothing, nothing, min_normalized_with_std - padding_normalized, max_normalized_with_std + padding_normalized)
    )
    
    # Link axes 4 and 6 (zoomed plots)
    Bas3GLMakie.GLMakie.linkyaxes!(axs4, axs6)
    Bas3GLMakie.GLMakie.linkxaxes!(axs4, axs6)
    
    # Define colors for all classes (matching Bas3ImageSegmentation package)
    # Order: scar, redness, hematoma, necrosis, background
    local stats_class_colors = [:red, :green, :blue, :yellow, :black]
    
    # Prepare data for boxplots
    # Normalized per-image data (for axs2 and axs4): normalize each image's class areas to sum to 1.0
    local normalized_per_image = Dict{Symbol, Vector{Float64}}()
    for class in classes
        normalized_per_image[class] = Float64[]
    end
    
    # Compute per-image normalization
    local num_images = length(class_areas_per_image[classes[1]])
    for img_idx in 1:num_images
        # Get total pixels for this image
        local img_total = sum(class_areas_per_image[class][img_idx] for class in classes)
        
        # Normalize each class area for this image
        for class in classes
            push!(normalized_per_image[class], class_areas_per_image[class][img_idx] / img_total)
        end
    end
    
    # Helper function to identify outliers using IQR method
    function find_outliers(data)
        if length(data) == 0
            return Bool[], 0.0
        end
        
        q1 = quantile(data, 0.25)
        q3 = quantile(data, 0.75)
        iqr = q3 - q1
        lower_bound = q1 - 1.5 * iqr
        upper_bound = q3 + 1.5 * iqr
        
        outlier_mask = (data .< lower_bound) .| (data .> upper_bound)
        outlier_percentage = 100.0 * sum(outlier_mask) / length(data)
        
        return outlier_mask, outlier_percentage
    end
    
    # Store per-class outlier percentages (for normalized data only)
    local class_outlier_percentages_normalized = Dict{Symbol, Float64}()
    
    # Plot data
    for (i, class) in enumerate(classes)
        local color = stats_class_colors[i]
        
        # Get data for this class
        local normalized_data = normalized_per_image[class]
        
        # Calculate total proportion for bar plots
        local total_prop = class_totals[class] / total_pixels
        
        # Find outliers for normalized data (axs2 and axs4)
        local normalized_outlier_mask, normalized_outlier_pct = find_outliers(normalized_data)
        class_outlier_percentages_normalized[class] = normalized_outlier_pct
        
        # Axis 1: Bar plot for total proportions
        Bas3GLMakie.GLMakie.barplot!(axs1, [i], [total_prop]; color=color, width=0.6)
        
        # Axis 3: Bar plot for total proportions (zoomed)
        Bas3GLMakie.GLMakie.barplot!(axs3, [i], [total_prop]; color=color, width=0.6)
        
        # Axis 2: Boxplot for normalized data
        Bas3GLMakie.GLMakie.boxplot!(
            axs2, 
            fill(i, length(normalized_data)), 
            normalized_data; 
            color=(color, 0.6),
            show_outliers=false,
            width=0.6
        )
        # Scatter only outliers for axs2
        if sum(normalized_outlier_mask) > 0
            local outlier_normalized = normalized_data[normalized_outlier_mask]
            Bas3GLMakie.GLMakie.scatter!(
                axs2,
                fill(i, length(outlier_normalized)),
                outlier_normalized;
                markersize=8,
                color=color,
                marker=:circle,
                strokewidth=1,
                strokecolor=:black
            )
        end
        
        # Axis 4: Boxplot for normalized data (zoomed)
        Bas3GLMakie.GLMakie.boxplot!(
            axs4, 
            fill(i, length(normalized_data)), 
            normalized_data; 
            color=(color, 0.6),
            show_outliers=false,
            width=0.6
        )
        # Scatter only outliers for axs4
        if sum(normalized_outlier_mask) > 0
            local outlier_normalized = normalized_data[normalized_outlier_mask]
            Bas3GLMakie.GLMakie.scatter!(
                axs4,
                fill(i, length(outlier_normalized)),
                outlier_normalized;
                markersize=8,
                color=color,
                marker=:circle,
                strokewidth=1,
                strokecolor=:black
            )
        end
        
        # Axis 5: Mean+Std error bars (normalized)
        local mean_val = normalized_statistics[class].mean
        local std_val = normalized_statistics[class].std
        Bas3GLMakie.GLMakie.scatter!(axs5, i, mean_val; markersize=10, color=color)
        Bas3GLMakie.GLMakie.errorbars!(
            axs5, 
            [i], 
            [mean_val], 
            [std_val]; 
            color=color, 
            linewidth=2,
            whiskerwidth=10
        )
        
        # Axis 6: Mean+Std error bars (zoomed)
        Bas3GLMakie.GLMakie.scatter!(axs6, i, mean_val; markersize=10, color=color)
        Bas3GLMakie.GLMakie.errorbars!(
            axs6, 
            [i], 
            [mean_val], 
            [std_val]; 
            color=color, 
            linewidth=2,
            whiskerwidth=10
        )
    end
    
    # Build legend text with per-class outlier percentages for normalized data
    local legend_lines_normalized = String[]
    for class in classes
        push!(legend_lines_normalized, "$(class_names_de[class]): $(round(class_outlier_percentages_normalized[class], digits=1))%")
    end
    
    # Add legend showing per-class outlier percentages for axs2
    Bas3GLMakie.GLMakie.text!(
        axs2,
        0.5, 0.98;
        text=join(legend_lines_normalized, "\n"),
        align=(:center, :top),
        fontsize=10,
        space=:relative,
        color=:black,
        font=:bold
    )
    
    # Add legend showing per-class outlier percentages for axs4
    Bas3GLMakie.GLMakie.text!(
        axs4,
        0.5, 0.98;
        text=join(legend_lines_normalized, "\n"),
        align=(:center, :top),
        fontsize=10,
        space=:relative,
        color=:black,
        font=:bold
    )
    
    # Add mean ± std legends for axs5 and axs6
    local y_position = 0.98
    local y_spacing = 0.05
    for (i, class) in enumerate(classes)
        local color = stats_class_colors[i]
        local mean_val = normalized_statistics[class].mean
        local std_val = normalized_statistics[class].std
        local legend_text = "$(class_names_de[class]): $(round(mean_val, digits=4)) ± $(round(std_val, digits=4))"
        
        # Add to axs5
        Bas3GLMakie.GLMakie.text!(
            axs5,
            0.02, y_position - (i-1) * y_spacing;
            text=legend_text,
            align=(:left, :top),
            fontsize=12,
            space=:relative,
            color=color,
            font=:bold
        )
        
        # Add to axs6
        Bas3GLMakie.GLMakie.text!(
            axs6,
            0.02, y_position - (i-1) * y_spacing;
            text=legend_text,
            align=(:left, :top),
            fontsize=12,
            space=:relative,
            color=color,
            font=:bold
        )
    end
    
    # Display and save statistics figure in its own window
    display(Bas3GLMakie.GLMakie.Screen(), stats_fig)
    local stats_filename = "Full_Dataset_Class_Area_Statistics_$(length(sets))_images.png"
    Bas3GLMakie.GLMakie.save(stats_filename, stats_fig)
    println("Saved class statistics to $(stats_filename)")
    
    # ============================================================================
    # Figure 2: Detailed Bounding Box Metrics Visualization
    # ============================================================================
    
    println("Generating detailed bounding box metrics visualization...")
    
    local bbox_fig = Figure(size=(1600, 1200))
    
    # Add title
    Bas3GLMakie.GLMakie.Label(
        bbox_fig[1, 1:3],
        "Begrenzungsrahmenstatistik Gesamtdatensatz ($(length(sets)) Bilder)",
        fontsize=24,
        font=:bold,
        halign=:center
    )
    
    local num_bbox_classes = length(bbox_classes)
    
    # Row 2: Three boxplot distributions
    # Axis 1: Width distribution
    local bbox_ax1 = Bas3GLMakie.GLMakie.Axis(
        bbox_fig[2, 1]; 
        xticks=(1:num_bbox_classes, get_german_names(bbox_classes)), 
        title="Breitenverteilung pro Klasse", 
        ylabel="Breite [px]", 
        xlabel="Klasse"
    )
    
    # Axis 2: Height distribution
    local bbox_ax2 = Bas3GLMakie.GLMakie.Axis(
        bbox_fig[2, 2]; 
        xticks=(1:num_bbox_classes, get_german_names(bbox_classes)), 
        title="Höhenverteilung pro Klasse", 
        ylabel="Höhe [px]", 
        xlabel="Klasse"
    )
    
    # Axis 3: Aspect ratio distribution
    local bbox_ax3 = Bas3GLMakie.GLMakie.Axis(
        bbox_fig[2, 3]; 
        xticks=(1:num_bbox_classes, get_german_names(bbox_classes)), 
        title="Seitenverhältnisverteilung pro Klasse", 
        ylabel="Seitenverhältnis", 
        xlabel="Klasse"
    )
    
    # Row 3: Mean ± Std plots
    # Axis 6: Width mean ± std
    local bbox_ax6 = Bas3GLMakie.GLMakie.Axis(
        bbox_fig[3, 1]; 
        xticks=(1:num_bbox_classes, get_german_names(bbox_classes)), 
        title="Breite Mittelwert ± Std pro Klasse", 
        ylabel="Breite [px]", 
        xlabel="Klasse"
    )
    
    # Axis 7: Height mean ± std
    local bbox_ax7 = Bas3GLMakie.GLMakie.Axis(
        bbox_fig[3, 2]; 
        xticks=(1:num_bbox_classes, get_german_names(bbox_classes)), 
        title="Höhe Mittelwert ± Std pro Klasse", 
        ylabel="Höhe [px]", 
        xlabel="Klasse"
    )
    
    # Axis 8: Aspect ratio mean ± std
    local bbox_ax8 = Bas3GLMakie.GLMakie.Axis(
        bbox_fig[3, 3]; 
        xticks=(1:num_bbox_classes, get_german_names(bbox_classes)), 
        title="Seitenverhältnis Mittelwert ± Std pro Klasse", 
        ylabel="Seitenverhältnis", 
        xlabel="Klasse"
    )
    
    # Row 4: Bottom plots
    # Axis 4: Width vs Height scatter plot
    local bbox_ax4 = Bas3GLMakie.GLMakie.Axis(
        bbox_fig[4, 1:2]; 
        title="Breite vs Höhe pro Klasse", 
        xlabel="Breite [px]", 
        ylabel="Höhe [px]"
    )
    
    # Axis 5: Number of components per class
    local bbox_ax5 = Bas3GLMakie.GLMakie.Axis(
        bbox_fig[4, 3]; 
        xticks=(1:num_bbox_classes, get_german_names(bbox_classes)), 
        title="Anzahl Begrenzungsrahmen pro Klasse", 
        ylabel="Anzahl", 
        xlabel="Klasse"
    )
    
    # Define colors for each non-background class (matching Bas3ImageSegmentation package)
    # scar: RGB(1,0,0)=red, redness: RGB(0,1,0)=green, hematoma: RGB(0,0,1)=blue, necrosis: RGB(1,1,0)=yellow
    local class_colors = [:red, :green, :blue, :yellow]
    
    # Store per-class outlier percentages for each metric
    local class_outlier_pct_width = Dict{Symbol, Float64}()
    local class_outlier_pct_height = Dict{Symbol, Float64}()
    local class_outlier_pct_aspect = Dict{Symbol, Float64}()
    
    # Store slopes for Width vs Height text annotations
    local class_slopes = Dict{Symbol, Float64}()
    
    # Plot data for each class (non-background only)
    for (i, class) in enumerate(bbox_classes)
        local stats = bbox_statistics[class]
        
        # Skip if no components
        if stats[:num_components] == 0
            continue
        end
        
        local color = class_colors[i]
        
        # Axis 1: Width boxplot
        local widths = bbox_metrics[class][:widths]
        local width_outlier_mask, width_outlier_pct = find_outliers(widths)
        
        # Store per-class outlier percentage
        class_outlier_pct_width[class] = width_outlier_pct
        
        Bas3GLMakie.GLMakie.boxplot!(
            bbox_ax1, 
            fill(i, length(widths)), 
            widths; 
            color=(color, 0.6),
            show_outliers=false,
            width=0.6
        )
        # Scatter only outliers
        if sum(width_outlier_mask) > 0
            local outlier_widths = widths[width_outlier_mask]
            Bas3GLMakie.GLMakie.scatter!(
                bbox_ax1,
                fill(i, length(outlier_widths)),
                outlier_widths;
                markersize=8,
                color=color,
                marker=:circle,
                strokewidth=1,
                strokecolor=:black
            )
        end
        
        # Axis 2: Height boxplot
        local heights = bbox_metrics[class][:heights]
        local height_outlier_mask, height_outlier_pct = find_outliers(heights)
        
        # Store per-class outlier percentage
        class_outlier_pct_height[class] = height_outlier_pct
        
        Bas3GLMakie.GLMakie.boxplot!(
            bbox_ax2, 
            fill(i, length(heights)), 
            heights; 
            color=(color, 0.6),
            show_outliers=false,
            width=0.6
        )
        # Scatter only outliers
        if sum(height_outlier_mask) > 0
            local outlier_heights = heights[height_outlier_mask]
            Bas3GLMakie.GLMakie.scatter!(
                bbox_ax2,
                fill(i, length(outlier_heights)),
                outlier_heights;
                markersize=8,
                color=color,
                marker=:circle,
                strokewidth=1,
                strokecolor=:black
            )
        end
        
        # Axis 3: Aspect ratio boxplot
        local aspect_ratios = bbox_metrics[class][:aspect_ratios]
        local aspect_outlier_mask, aspect_outlier_pct = find_outliers(aspect_ratios)
        
        # Store per-class outlier percentage
        class_outlier_pct_aspect[class] = aspect_outlier_pct
        
        Bas3GLMakie.GLMakie.boxplot!(
            bbox_ax3, 
            fill(i, length(aspect_ratios)), 
            aspect_ratios; 
            color=(color, 0.6),
            show_outliers=false,
            width=0.6
        )
        # Scatter only outliers
        if sum(aspect_outlier_mask) > 0
            local outlier_aspects = aspect_ratios[aspect_outlier_mask]
            Bas3GLMakie.GLMakie.scatter!(
                bbox_ax3,
                fill(i, length(outlier_aspects)),
                outlier_aspects;
                markersize=8,
                color=color,
                marker=:circle,
                strokewidth=1,
                strokecolor=:black
            )
        end
        
        # Axis 4: Width vs Height scatter
        local widths = bbox_metrics[class][:widths]
        local heights = bbox_metrics[class][:heights]
        Bas3GLMakie.GLMakie.scatter!(
            bbox_ax4, 
            widths, 
            heights; 
            markersize=8, 
            color=(color, 0.6),
            label=string(class)
        )
        
        # Add linear regression line for this class
        if length(widths) >= 2  # Need at least 2 points for regression
            # Compute linear regression: height = slope * width + intercept
            # Using least squares: slope = cov(x,y) / var(x)
            local mean_w = mean(widths)
            local mean_h = mean(heights)
            local cov_wh = sum((widths .- mean_w) .* (heights .- mean_h)) / length(widths)
            local var_w = sum((widths .- mean_w).^2) / length(widths)
            
            if var_w > 0  # Avoid division by zero
                local slope = cov_wh / var_w
                local intercept = mean_h - slope * mean_w
                
                # Store slope for text annotation
                class_slopes[class] = slope
                
                # Generate line points
                local w_min = minimum(widths)
                local w_max = maximum(widths)
                local w_range = range(w_min, w_max, length=100)
                local h_pred = slope .* w_range .+ intercept
                
                # Plot regression line (removed label for legend)
                Bas3GLMakie.GLMakie.lines!(
                    bbox_ax4,
                    w_range,
                    h_pred;
                    color=color,
                    linewidth=2,
                    linestyle=:solid
                )
            end
        end
        
        # Axis 5: Number of components
        Bas3GLMakie.GLMakie.barplot!(bbox_ax5, [i], [stats[:num_components]]; color=color, width=0.6)
    end
    
    # Populate Row 3: Mean ± Std plots
    for (i, class) in enumerate(bbox_classes)
        local stats = bbox_statistics[class]
        
        # Skip if no components
        if stats[:num_components] == 0
            continue
        end
        
        local color = class_colors[i]
        
        # Axis 6: Width mean ± std
        local widths = bbox_metrics[class][:widths]
        local width_mean = mean(widths)
        local width_std = std(widths)
        
        Bas3GLMakie.GLMakie.scatter!(
            bbox_ax6,
            [i],
            [width_mean];
            markersize=12,
            color=color,
            marker=:circle
        )
        Bas3GLMakie.GLMakie.errorbars!(
            bbox_ax6,
            [i],
            [width_mean],
            [width_std],
            [width_std];
            whiskerwidth=10,
            color=color,
            linewidth=2
        )
        
        # Axis 7: Height mean ± std
        local heights = bbox_metrics[class][:heights]
        local height_mean = mean(heights)
        local height_std = std(heights)
        
        Bas3GLMakie.GLMakie.scatter!(
            bbox_ax7,
            [i],
            [height_mean];
            markersize=12,
            color=color,
            marker=:circle
        )
        Bas3GLMakie.GLMakie.errorbars!(
            bbox_ax7,
            [i],
            [height_mean],
            [height_std],
            [height_std];
            whiskerwidth=10,
            color=color,
            linewidth=2
        )
        
        # Axis 8: Aspect ratio mean ± std
        local aspect_ratios = bbox_metrics[class][:aspect_ratios]
        local aspect_mean = mean(aspect_ratios)
        local aspect_std = std(aspect_ratios)
        
        Bas3GLMakie.GLMakie.scatter!(
            bbox_ax8,
            [i],
            [aspect_mean];
            markersize=12,
            color=color,
            marker=:circle
        )
        Bas3GLMakie.GLMakie.errorbars!(
            bbox_ax8,
            [i],
            [aspect_mean],
            [aspect_std],
            [aspect_std];
            whiskerwidth=10,
            color=color,
            linewidth=2
        )
    end
    
    # Link axes between boxplots and mean±std plots
    Bas3GLMakie.GLMakie.linkyaxes!(bbox_ax1, bbox_ax6)
    Bas3GLMakie.GLMakie.linkyaxes!(bbox_ax2, bbox_ax7)
    Bas3GLMakie.GLMakie.linkyaxes!(bbox_ax3, bbox_ax8)
    Bas3GLMakie.GLMakie.linkxaxes!(bbox_ax1, bbox_ax6)
    Bas3GLMakie.GLMakie.linkxaxes!(bbox_ax2, bbox_ax7)
    Bas3GLMakie.GLMakie.linkxaxes!(bbox_ax3, bbox_ax8)
    
    # Build legend texts with per-class outlier percentages
    local legend_lines_width = String[]
    local legend_lines_height = String[]
    local legend_lines_aspect = String[]
    
    for class in bbox_classes
        push!(legend_lines_width, "$(class_names_de[class]): $(round(class_outlier_pct_width[class], digits=1))%")
        push!(legend_lines_height, "$(class_names_de[class]): $(round(class_outlier_pct_height[class], digits=1))%")
        push!(legend_lines_aspect, "$(class_names_de[class]): $(round(class_outlier_pct_aspect[class], digits=1))%")
    end
    
    # Add legends showing per-class outlier percentages
    Bas3GLMakie.GLMakie.text!(
        bbox_ax1,
        0.5, 0.98;
        text=join(legend_lines_width, "\n"),
        align=(:center, :top),
        fontsize=10,
        space=:relative,
        color=:black,
        font=:bold
    )
    
    Bas3GLMakie.GLMakie.text!(
        bbox_ax2,
        0.5, 0.98;
        text=join(legend_lines_height, "\n"),
        align=(:center, :top),
        fontsize=10,
        space=:relative,
        color=:black,
        font=:bold
    )
    
    Bas3GLMakie.GLMakie.text!(
        bbox_ax3,
        0.5, 0.98;
        text=join(legend_lines_aspect, "\n"),
        align=(:center, :top),
        fontsize=10,
        space=:relative,
        color=:black,
        font=:bold
    )
    
    # Add slope text annotations to Width vs Height scatter plot
    local y_position = 0.98  # Start from top
    local y_spacing = 0.05   # Spacing between lines
    for (i, class) in enumerate(bbox_classes)
        if haskey(class_slopes, class)
            local color = class_colors[i]
            local slope_text = "Steigung: $(round(class_slopes[class], digits=2))"
            Bas3GLMakie.GLMakie.text!(
                bbox_ax4,
                0.02, y_position - (i-1) * y_spacing;
                text=slope_text,
                align=(:left, :top),
                fontsize=12,
                space=:relative,
                color=color,
                font=:bold
            )
        end
    end
    
    # Add mean ± std legends for bbox_ax6, bbox_ax7, and bbox_ax8
    for (i, class) in enumerate(bbox_classes)
        local stats = bbox_statistics[class]
        
        # Skip if no components
        if stats[:num_components] == 0
            continue
        end
        
        local color = class_colors[i]
        
        # Width mean ± std for bbox_ax6
        local widths = bbox_metrics[class][:widths]
        local width_mean = mean(widths)
        local width_std = std(widths)
        local width_legend_text = "$(class_names_de[class]): $(round(width_mean, digits=1)) ± $(round(width_std, digits=1))"
        
        Bas3GLMakie.GLMakie.text!(
            bbox_ax6,
            0.02, y_position - (i-1) * y_spacing;
            text=width_legend_text,
            align=(:left, :top),
            fontsize=12,
            space=:relative,
            color=color,
            font=:bold
        )
        
        # Height mean ± std for bbox_ax7
        local heights = bbox_metrics[class][:heights]
        local height_mean = mean(heights)
        local height_std = std(heights)
        local height_legend_text = "$(class_names_de[class]): $(round(height_mean, digits=1)) ± $(round(height_std, digits=1))"
        
        Bas3GLMakie.GLMakie.text!(
            bbox_ax7,
            0.02, y_position - (i-1) * y_spacing;
            text=height_legend_text,
            align=(:left, :top),
            fontsize=12,
            space=:relative,
            color=color,
            font=:bold
        )
        
        # Aspect ratio mean ± std for bbox_ax8
        local aspect_ratios = bbox_metrics[class][:aspect_ratios]
        local aspect_mean = mean(aspect_ratios)
        local aspect_std = std(aspect_ratios)
        local aspect_legend_text = "$(class_names_de[class]): $(round(aspect_mean, digits=2)) ± $(round(aspect_std, digits=2))"
        
        Bas3GLMakie.GLMakie.text!(
            bbox_ax8,
            0.02, y_position - (i-1) * y_spacing;
            text=aspect_legend_text,
            align=(:left, :top),
            fontsize=12,
            space=:relative,
            color=color,
            font=:bold
        )
    end
    
    # Add reference line (y=x) to scatter plot
    local all_widths = vcat([bbox_metrics[class][:widths] for class in bbox_classes]...)
    local all_heights = vcat([bbox_metrics[class][:heights] for class in bbox_classes]...)
    local max_dim_all = maximum(vcat(all_widths, all_heights))
    Bas3GLMakie.GLMakie.lines!(bbox_ax4, [0, max_dim_all], [0, max_dim_all]; color=:black, linestyle=:dash, linewidth=1, label="y=x")
    
    # Display and save bounding box figure
    display(Bas3GLMakie.GLMakie.Screen(), bbox_fig)
    local bbox_filename = "Full_Dataset_Bounding_Box_Statistics_$(length(sets))_images.png"
    Bas3GLMakie.GLMakie.save(bbox_filename, bbox_fig)
    println("Saved bounding box metrics to $(bbox_filename)")
    
    # ============================================================================
    # Figure 3: Channel Statistics Visualization (4 plots)
    # ============================================================================
    
    println("\nGenerating channel statistics visualization...")
    
    local channel_fig = Figure(size=(1600, 1200))
    
    # Add title
    Bas3GLMakie.GLMakie.Label(
        channel_fig[1, 1:2],
        "RGB-Kanalstatistik Gesamtdatensatz ($(length(sets)) Bilder)",
        fontsize=24,
        font=:bold,
        halign=:center
    )
    
    # Define RGB colors for visualization
    local rgb_colors = Dict(:red => :red, :green => :green, :blue => :blue)
    
    # Left Column: Channel Correlation Plots (stacked)
    # channel_ax6 at top of left column
    local channel_ax6 = Bas3GLMakie.GLMakie.Axis(
        channel_fig[2, 1]; 
        title="Kanalkorrelationen Grün vs Blau",
        xlabel="Grün Mittelwert", 
        ylabel="Blau Mittelwert"
    )
    
    # channel_ax5 in middle of left column
    local channel_ax5 = Bas3GLMakie.GLMakie.Axis(
        channel_fig[3, 1]; 
        title="Kanalkorrelationen Rot vs Blau",
        xlabel="Rot Mittelwert", 
        ylabel="Blau Mittelwert"
    )
    
    # channel_ax4 at bottom of left column
    local channel_ax4 = Bas3GLMakie.GLMakie.Axis(
        channel_fig[4, 1]; 
        title="Kanalkorrelationen Rot vs Grün", 
        xlabel="Rot Mittelwert", 
        ylabel="Grün Mittelwert"
    )
    
    # Link x-axes for plots with Red on x-axis (ax4 and ax5)
    Bas3GLMakie.GLMakie.linkxaxes!(channel_ax4, channel_ax5)
    
    # Link y-axes for plots with Blue on y-axis (ax5 and ax6)
    Bas3GLMakie.GLMakie.linkyaxes!(channel_ax5, channel_ax6)
    
    # Link y-axis of ax4 (Green) with x-axis of ax6 (Green)
    # Note: Cannot directly link x and y axes, so we'll set limits programmatically
    
    # Right Column: RGB Statistics
    # channel_ax2 at top of right column
    local channel_ax2 = Bas3GLMakie.GLMakie.Axis(
        channel_fig[2, 2]; 
        title="RGB-Kanäle Histogramm", 
        ylabel="Dichte", 
        xlabel="Intensität (0.0-1.0)"
    )
    
    # Collect all pixel values per channel for histogram
    for (channel_idx, channel) in enumerate(channel_names)
        local all_pixels = Float64[]
        for input_image in inputs
            local input_data = data(input_image)
            append!(all_pixels, vec(input_data[:, :, channel_idx]))
        end
        
        local color = rgb_colors[channel]
        # Create histogram with transparency
        Bas3GLMakie.GLMakie.hist!(
            channel_ax2, 
            all_pixels; 
            bins=50, 
            color=(color, 0.5),
            normalization=:pdf,
            label=string(channel)
        )
    end
    
    # channel_ax1 in middle of right column
    local channel_ax1 = Bas3GLMakie.GLMakie.Axis(
        channel_fig[3, 2]; 
        xticks=(1:num_channels, get_german_channel_names(channel_names)), 
        #title="RGB Channels Intensity Mean ± Std",
        title="Mittlere Intensität Mittelwert ± Std pro Kanal",
        ylabel="Mittlere Intensität (0.0-1.0)",
        xlabel="Kanal"
    )
    
    for (i, channel) in enumerate(channel_names)
        local stats = global_channel_stats[channel]
        local color = rgb_colors[channel]
        
        # Scatter point for mean with error bars for std
        Bas3GLMakie.GLMakie.scatter!(
            channel_ax1,
            [i],
            [stats.mean];
            markersize=12,
            color=color,
            marker=:circle
        )
        Bas3GLMakie.GLMakie.errorbars!(
            channel_ax1,
            [i],
            [stats.mean],
            [stats.std],
            [stats.std];
            whiskerwidth=10,
            color=color,
            linewidth=2
        )
    end
    
    # channel_ax3 at bottom of right column
    local channel_ax3 = Bas3GLMakie.GLMakie.Axis(
        channel_fig[4, 2]; 
        xticks=(1:num_channels, get_german_channel_names(channel_names)), 
        #title="RGB Channels Mean Intensity Distribution", 
        title="Mittlere Intensitätsverteilung pro Kanal",
        ylabel="Mittlere Intensität (0.0-1.0)", 
        xlabel="Kanal"
    )
    
    # Helper function to identify outliers using IQR method
    function find_channel_outliers(data)
        if length(data) == 0
            return Bool[], 0.0
        end
        
        q1 = quantile(data, 0.25)
        q3 = quantile(data, 0.75)
        iqr = q3 - q1
        lower_bound = q1 - 1.5 * iqr
        upper_bound = q3 + 1.5 * iqr
        
        outlier_mask = (data .< lower_bound) .| (data .> upper_bound)
        outlier_percentage = 100.0 * sum(outlier_mask) / length(data)
        
        return outlier_mask, outlier_percentage
    end
    
    # Store per-channel outlier percentages
    local channel_outlier_percentages = Dict{Symbol, Float64}()
    
    for (i, channel) in enumerate(channel_names)
        local per_image_means = channel_means_per_image[channel]
        local color = rgb_colors[channel]
        
        # Calculate outliers
        local outlier_mask, outlier_pct = find_channel_outliers(per_image_means)
        channel_outlier_percentages[channel] = outlier_pct
        
        # Use GLMakie's boxplot function (standardized approach)
        Bas3GLMakie.GLMakie.boxplot!(
            channel_ax3,
            fill(i, length(per_image_means)),
            per_image_means;
            color=(color, 0.6),
            show_outliers=true,
            width=0.6
        )
    end
    
    # Build legend text with per-channel outlier percentages
    local legend_lines_channel = String[]
    for channel in channel_names
        push!(legend_lines_channel, "$(channel): $(round(channel_outlier_percentages[channel], digits=1))%")
    end
    
    # Add legend showing per-channel outlier percentages (top center)
    Bas3GLMakie.GLMakie.text!(
        channel_ax3,
        0.5, 0.98;
        text=join(legend_lines_channel, "\n"),
        align=(:center, :top),
        fontsize=10,
        space=:relative,
        color=:black,
        font=:bold
    )
    
    # Red vs Green vs Blue data
    local red_means = channel_means_per_image[:red]
    local green_means = channel_means_per_image[:green]
    local blue_means = channel_means_per_image[:blue]
    
    # Calculate per-channel min/max for specific axis limits
    local red_min = minimum(red_means)
    local red_max = maximum(red_means)
    local red_range = red_max - red_min
    
    local green_min = minimum(green_means)
    local green_max = maximum(green_means)
    local green_range = green_max - green_min
    
    local blue_min = minimum(blue_means)
    local blue_max = maximum(blue_means)
    local blue_range = blue_max - blue_min
    
    # Red vs Green (channel_ax4) - Bottom plot
    # X-axis: Red, Y-axis: Green
    Bas3GLMakie.GLMakie.scatter!(channel_ax4, red_means, green_means; markersize=10, color=(:black, 0.6))
    # Add diagonal reference line using the overlapping range
    local rg_min = max(red_min, green_min)
    local rg_max = min(red_max, green_max)
    if rg_min < rg_max
        Bas3GLMakie.GLMakie.lines!(channel_ax4, [rg_min, rg_max], [rg_min, rg_max]; color=:gray, linestyle=:dash, linewidth=1)
    end
    # Set axis limits - linked x-axis with ax5 (both Red), y-axis uses Green
    Bas3GLMakie.GLMakie.xlims!(channel_ax4, red_min, red_max)
    Bas3GLMakie.GLMakie.ylims!(channel_ax4, green_min, green_max)
    
    # Compute and display correlation coefficient
    local corr_rg = cor(red_means, green_means)
    Bas3GLMakie.GLMakie.text!(
        channel_ax4,
        red_min + 0.05 * red_range,
        green_max - 0.05 * green_range;
        text="r = $(round(corr_rg, digits=3))",
        fontsize=14,
        align=(:left, :top)
    )
    
    # Red vs Blue (channel_ax5) - Middle plot
    # X-axis: Red, Y-axis: Blue
    Bas3GLMakie.GLMakie.scatter!(channel_ax5, red_means, blue_means; markersize=10, color=(:black, 0.6))
    # Add diagonal reference line using the overlapping range
    local rb_min = max(red_min, blue_min)
    local rb_max = min(red_max, blue_max)
    if rb_min < rb_max
        Bas3GLMakie.GLMakie.lines!(channel_ax5, [rb_min, rb_max], [rb_min, rb_max]; color=:gray, linestyle=:dash, linewidth=1)
    end
    # Set axis limits - linked x-axis with ax4 (both Red), linked y-axis with ax6 (both Blue)
    Bas3GLMakie.GLMakie.xlims!(channel_ax5, red_min, red_max)
    Bas3GLMakie.GLMakie.ylims!(channel_ax5, blue_min, blue_max)
    local corr_rb = cor(red_means, blue_means)
    Bas3GLMakie.GLMakie.text!(
        channel_ax5,
        red_min + 0.05 * red_range,
        blue_max - 0.05 * blue_range;
        text="r = $(round(corr_rb, digits=3))",
        fontsize=14,
        align=(:left, :top)
    )
    
    # Green vs Blue (channel_ax6) - Top plot
    # X-axis: Green, Y-axis: Blue
    Bas3GLMakie.GLMakie.scatter!(channel_ax6, green_means, blue_means; markersize=10, color=(:black, 0.6))
    # Add diagonal reference line using the overlapping range
    local gb_min = max(green_min, blue_min)
    local gb_max = min(green_max, blue_max)
    if gb_min < gb_max
        Bas3GLMakie.GLMakie.lines!(channel_ax6, [gb_min, gb_max], [gb_min, gb_max]; color=:gray, linestyle=:dash, linewidth=1)
    end
    # Set axis limits - x-axis uses Green (should match y-axis of ax4), linked y-axis with ax5 (both Blue)
    Bas3GLMakie.GLMakie.xlims!(channel_ax6, green_min, green_max)
    Bas3GLMakie.GLMakie.ylims!(channel_ax6, blue_min, blue_max)
    local corr_gb = cor(green_means, blue_means)
    Bas3GLMakie.GLMakie.text!(
        channel_ax6,
        green_min + 0.05 * green_range,
        blue_max - 0.05 * blue_range;
        text="r = $(round(corr_gb, digits=3))",
        fontsize=14,
        align=(:left, :top)
    )
    
    # Display and save channel statistics figure
    display(Bas3GLMakie.GLMakie.Screen(), channel_fig)
    local channel_filename = "Full_Dataset_RGB_Channel_Statistics_$(length(sets))_images.png"
    Bas3GLMakie.GLMakie.save(channel_filename, channel_fig)
    println("Saved channel statistics to $(channel_filename)")
    
    # Figure 4: Image Visualization with White Region Detection
    # New Layout: Image - Full Image Stats - White Region Stats - Controls
    local fgr = Figure(size=(2000, 1000))

    # Add title for image figure
    local img_title = Bas3GLMakie.GLMakie.Label(
        fgr[1, 1:4], 
        #"Image Visualization with White Region Detection",
        "Interaktive Bildvisualisierung mit Markererkennung",
        fontsize=24,
        font=:bold,
        halign=:center
    )
    
    # Column 1: Input Image with Segmentation Overlay and White Region Detection
    local axs3 = Bas3GLMakie.GLMakie.Axis(
        fgr[2, 1];
        title="Eingabebild mit Segmentierung + Markererkennung",
        aspect=Bas3GLMakie.GLMakie.DataAspect()
    )
    Bas3GLMakie.GLMakie.hidedecorations!(axs3)
    
    # Column 2: Full Image Statistics Plots (stacked vertically)
    # Axis for Mean ± Std per Channel
    local full_mean_ax = Bas3GLMakie.GLMakie.Axis(
        fgr[2, 2][1, 1];
        xticks=(1:3, ["Rot", "Grün", "Blau"]),
        title="Gesamtbild: Intensität Mittelwert ± Std",
        ylabel="Intensität",
        xlabel=""
    )
    
    # Axis for Boxplot per Channel
    local full_box_ax = Bas3GLMakie.GLMakie.Axis(
        fgr[2, 2][2, 1];
        xticks=(1:3, ["Rot", "Grün", "Blau"]),
        title="Gesamtbild: Intensitätsverteilung",
        ylabel="Intensität",
        xlabel=""
    )
    
    # Axis for RGB Histogram
    local full_hist_ax = Bas3GLMakie.GLMakie.Axis(
        fgr[2, 2][3, 1];
        title="Gesamtbild: RGB-Kanäle Histogramm",
        ylabel="Dichte",
        xlabel="Intensität"
    )
    
    # Column 3: White Region Statistics Plots (stacked vertically)
    # Axis for Mean ± Std per Channel
    local region_mean_ax = Bas3GLMakie.GLMakie.Axis(
        fgr[2, 3][1, 1];
        xticks=(1:3, ["Rot", "Grün", "Blau"]),
        title="Marker: Intensität Mittelwert ± Std",
        ylabel="Intensität",
        xlabel=""
    )
    
    # Axis for Boxplot per Channel
    local region_box_ax = Bas3GLMakie.GLMakie.Axis(
        fgr[2, 3][2, 1];
        xticks=(1:3, ["Rot", "Grün", "Blau"]),
        title="Marker: Intensitätsverteilung",
        ylabel="Intensität",
        xlabel=""
    )
    
    # Axis for RGB Histogram
    local region_hist_ax = Bas3GLMakie.GLMakie.Axis(
        fgr[2, 3][3, 1];
        title="Marker: RGB-Kanäle Histogramm",
        ylabel="Dichte",
        xlabel="Intensität"
    )
    
    # Column 4: Parameter control panel
    local param_grid = Bas3GLMakie.GLMakie.GridLayout(fgr[2, 4])
    
    # Set row and column sizes
    Bas3GLMakie.GLMakie.rowsize!(fgr.layout, 1, Bas3GLMakie.GLMakie.Fixed(50))  # Title row
    Bas3GLMakie.GLMakie.colsize!(fgr.layout, 2, Bas3GLMakie.GLMakie.Fixed(300)) # Full image stats column
    Bas3GLMakie.GLMakie.colsize!(fgr.layout, 3, Bas3GLMakie.GLMakie.Fixed(300)) # White region stats column
    
    # Panel title
    Bas3GLMakie.GLMakie.Label(
        param_grid[1, 1:2],
        "Regionsparameter",
        fontsize=18,
        font=:bold,
        halign=:center
    )
    
    # Threshold parameter - label and textbox side by side
    local threshold_textbox = Bas3GLMakie.GLMakie.Textbox(
        param_grid[2, 1],
        placeholder="0.7",
        stored_string="0.7",
        width=80
    )
    Bas3GLMakie.GLMakie.Label(
        param_grid[2, 2],
        "Schwellwert (0.0-1.0)",
        fontsize=14,
        halign=:left
    )
    
    # Min component area parameter - label and textbox side by side
    local min_area_textbox = Bas3GLMakie.GLMakie.Textbox(
        param_grid[3, 1],
        placeholder="8000",
        stored_string="8000",
        width=80
    )
    Bas3GLMakie.GLMakie.Label(
        param_grid[3, 2],
        "Min. Fläche [px]",
        fontsize=14,
        halign=:left
    )
    
    # Preferred aspect ratio parameter - label and textbox side by side
    local aspect_ratio_textbox = Bas3GLMakie.GLMakie.Textbox(
        param_grid[4, 1],
        placeholder="5.0",
        stored_string="5.0",
        width=80
    )
    Bas3GLMakie.GLMakie.Label(
        param_grid[4, 2],
        "Bevorzugtes Seitenverhältnis",
        fontsize=14,
        halign=:left
    )
    
    # Aspect ratio weight parameter - label and textbox side by side
    local aspect_weight_textbox = Bas3GLMakie.GLMakie.Textbox(
        param_grid[5, 1],
        placeholder="0.6",
        stored_string="0.6",
        width=80
    )
    Bas3GLMakie.GLMakie.Label(
        param_grid[5, 2],
        "Seitenverhältnis-Gewichtung (0.0-1.0)",
        fontsize=14,
        halign=:left
    )
    
    # Kernel size for morphological operations
    local kernel_size_textbox = Bas3GLMakie.GLMakie.Textbox(
        param_grid[6, 1],
        placeholder="3",
        stored_string="3",
        width=80
    )
    Bas3GLMakie.GLMakie.Label(
        param_grid[6, 2],
        "Kernelgröße (0-7)",
        fontsize=14,
        halign=:left
    )
    
    # Error/status message label - spans both columns
    local param_status_label = Bas3GLMakie.GLMakie.Label(
        param_grid[7, 1:2],
        "",
        fontsize=12,
        halign=:center,
        color=:red
    )
    
    # Add separator
    Bas3GLMakie.GLMakie.Label(
        param_grid[8, 1:2],
        "─────────────────────",
        fontsize=12,
        halign=:center
    )
    
    # Region Selection Controls
    Bas3GLMakie.GLMakie.Label(
        param_grid[9, 1:2],
        "Regionsauswahl",
        fontsize=16,
        font=:bold,
        halign=:center
    )
    
    local selection_toggle = Bas3GLMakie.GLMakie.Toggle(
        param_grid[10, 1],
        active=false
    )
    Bas3GLMakie.GLMakie.Label(
        param_grid[10, 2],
        "Auswahl aktivieren",
        fontsize=14,
        halign=:left
    )
    
    local clear_selection_button = Bas3GLMakie.GLMakie.Button(
        param_grid[11, 1:2],
        label="Auswahl löschen",
        fontsize=14
    )
    
    local selection_status_label = Bas3GLMakie.GLMakie.Label(
        param_grid[12, 1:2],
        "Auswahl deaktiviert",
        fontsize=11,
        halign=:center,
        color=:gray
    )
    
    # Navigation controls in a separate GridLayout
    local nav_grid = Bas3GLMakie.GLMakie.GridLayout(fgr[3, 1:3])
    # Add navigation buttons and textbox for image selection
    local prev_button = Bas3GLMakie.GLMakie.Button(
        nav_grid[1, 1],
        label="← Vorheriges",
        fontsize=14
    )
    
    local textbox = Bas3GLMakie.GLMakie.Textbox(
        nav_grid[1, 2],
        placeholder="Bildnummer eingeben (1-$(length(sets)))",
        stored_string="1"
    )
    
    local next_button = Bas3GLMakie.GLMakie.Button(
        nav_grid[1, 3],
        label="Nächstes →",
        fontsize=14
    )
    
    local textbox_label = Bas3GLMakie.GLMakie.Label(
        nav_grid[2, 1:3],
        "Bild: 1 / $(length(sets))",
        fontsize=16,
        halign=:center
    )
    #Bas3GLMakie.GLMakie.rowsize!(fgr.layout, 5, Bas3GLMakie.GLMakie.Fixed(10))
    
    # Morphological operations for connectivity improvement
    # These operations fill small gaps and remove noise in binary masks
    
    # Dilate operation: expands white regions by kernel_size pixels
    function morphological_dilate(mask::BitMatrix, kernel_size::Int)
        if kernel_size <= 0
            return mask
        end
        
        h, w = size(mask)
        result = copy(mask)
        
        # For each pixel, if any neighbor within kernel_size is white, make this pixel white
        for i in 1:h
            for j in 1:w
                if !mask[i, j]
                    # Check neighbors within kernel radius
                    for di in -kernel_size:kernel_size
                        for dj in -kernel_size:kernel_size
                            ni, nj = i + di, j + dj
                            if ni >= 1 && ni <= h && nj >= 1 && nj <= w && mask[ni, nj]
                                result[i, j] = true
                                break
                            end
                        end
                        if result[i, j]
                            break
                        end
                    end
                end
            end
        end
        
        return result
    end
    
    # Erode operation: shrinks white regions by kernel_size pixels
    function morphological_erode(mask::BitMatrix, kernel_size::Int)
        if kernel_size <= 0
            return mask
        end
        
        h, w = size(mask)
        result = copy(mask)
        
        # For each white pixel, if any neighbor within kernel_size is black, make this pixel black
        for i in 1:h
            for j in 1:w
                if mask[i, j]
                    # Check if all neighbors within kernel radius are white
                    all_white = true
                    for di in -kernel_size:kernel_size
                        for dj in -kernel_size:kernel_size
                            ni, nj = i + di, j + dj
                            if ni < 1 || ni > h || nj < 1 || nj > w || !mask[ni, nj]
                                all_white = false
                                break
                            end
                        end
                        if !all_white
                            break
                        end
                    end
                    result[i, j] = all_white
                end
            end
        end
        
        return result
    end
    
    # Morphological closing: dilate then erode (fills small gaps, connects nearby regions)
    function morphological_close(mask::BitMatrix, kernel_size::Int)
        if kernel_size <= 0
            return mask
        end
        dilated = morphological_dilate(mask, kernel_size)
        return morphological_erode(dilated, kernel_size)
    end
    
    # Morphological opening: erode then dilate (removes small noise/speckles)
    function morphological_open(mask::BitMatrix, kernel_size::Int)
        if kernel_size <= 0
            return mask
        end
        eroded = morphological_erode(mask, kernel_size)
        return morphological_dilate(eroded, kernel_size)
    end
    
    # White region extraction function - finds best white region with rotated bounding box
    # Uses PCA to find oriented bounding box and selects component with highest combined score
    # based on density and aspect ratio preference
    #
    # Parameters:
    #   - threshold: RGB threshold for white detection (default: 0.7, range: 0.0-1.0)
    #   - min_component_area: minimum area in pixels to consider a component (default: 100)
    #   - preferred_aspect_ratio: target aspect ratio (longer/shorter dimension) (default: 5.0 for 1:5 ratio)
    #   - aspect_ratio_weight: weight for aspect ratio vs density (default: 0.5, range: 0.0-1.0)
    #       * 0.0 = purely density-based selection (ignores aspect ratio)
    #       * 0.5 = balanced between density and aspect ratio
    #       * 1.0 = purely aspect ratio-based selection (ignores density)
    #   - kernel_size: size of morphological structuring element (default: 3)
    #       * 0 = no morphological operations
    #       * 1-2 = minimal gap filling
    #       * 3 = moderate gap filling (recommended, improves connectivity)
    #       * 5+ = aggressive gap filling (may merge separate objects)
    #     Morphological closing fills small gaps and connects nearby regions,
    #     morphological opening removes small noise and speckles.
    #
    # Returns: (mask, size, percentage, num_components, bbox, density, rotated_corners, rotation_angle, aspect_ratio)
    function extract_white_mask(img; threshold=0.7, min_component_area=100, preferred_aspect_ratio=5.0, aspect_ratio_weight=0.5, kernel_size=3, region=nothing)
        rgb_data = data(img)
        
        # Apply region mask if specified
        if !isnothing(region)
            r_min, r_max, c_min, c_max = region
            # Clamp to valid bounds
            r_min = max(1, min(r_min, size(rgb_data, 1)))
            r_max = max(1, min(r_max, size(rgb_data, 1)))
            c_min = max(1, min(c_min, size(rgb_data, 2)))
            c_max = max(1, min(c_max, size(rgb_data, 2)))
            # Create mask for region
            region_mask = falses(size(rgb_data, 1), size(rgb_data, 2))
            region_mask[r_min:r_max, c_min:c_max] .= true
        else
            region_mask = trues(size(rgb_data, 1), size(rgb_data, 2))
        end
        
        # Initial white mask - all pixels with RGB >= threshold AND within region
        white_mask_all = (rgb_data[:,:,1] .>= threshold) .& 
                         (rgb_data[:,:,2] .>= threshold) .& 
                         (rgb_data[:,:,3] .>= threshold) .&
                         region_mask
        
        # Apply morphological operations to improve connectivity
        if kernel_size > 0
            white_mask_all = morphological_close(white_mask_all, kernel_size)
            white_mask_all = morphological_open(white_mask_all, kernel_size)
        end
        
        # Label all connected components
        labeled = Bas3ImageSegmentation.label_components(white_mask_all)
        num_components = maximum(labeled)
        
        if num_components == 0
            # No white regions found
            return white_mask_all, 0, 0.0, 0, (0, 0, 0, 0), 0.0, Float64[], 0.0
        end
        
        # Analyze each connected component
        best_label = 0
        best_score = 0.0  # Combined score (density + aspect ratio match)
        best_density = 0.0
        best_rotated_corners = Float64[]
        best_rotation_angle = 0.0
        best_size = 0
        best_aspect_ratio = 0.0
        
        for label in 1:num_components
            # Get mask for this component
            component_mask = labeled .== label
            component_size = sum(component_mask)
            
            # Skip if below minimum area
            if component_size < min_component_area
                continue
            end
            
            # Get all pixel coordinates for this component
            pixel_coords = findall(component_mask)
            if isempty(pixel_coords)
                continue
            end
            
            # Extract row and column indices
            row_indices = Float64[p[1] for p in pixel_coords]
            col_indices = Float64[p[2] for p in pixel_coords]
            
            # Compute centroid
            centroid_row = sum(row_indices) / length(row_indices)
            centroid_col = sum(col_indices) / length(col_indices)
            
            # Center the coordinates
            centered_rows = row_indices .- centroid_row
            centered_cols = col_indices .- centroid_col
            
            # Compute covariance matrix for PCA
            n = length(centered_rows)
            cov_matrix = [
                sum(centered_rows .* centered_rows) / n   sum(centered_rows .* centered_cols) / n;
                sum(centered_rows .* centered_cols) / n   sum(centered_cols .* centered_cols) / n
            ]
            
            # Compute eigenvectors (principal directions)
            eigen_result = eigen(cov_matrix)
            principal_axes = eigen_result.vectors
            
            # Project points onto principal axes
            proj_axis1 = centered_rows .* principal_axes[1, 2] .+ centered_cols .* principal_axes[2, 2]
            proj_axis2 = centered_rows .* principal_axes[1, 1] .+ centered_cols .* principal_axes[2, 1]
            
            # Find min/max along each principal axis
            min_proj1, max_proj1 = extrema(proj_axis1)
            min_proj2, max_proj2 = extrema(proj_axis2)
            
            # Calculate oriented bounding box area
            rotated_width = max_proj1 - min_proj1
            rotated_height = max_proj2 - min_proj2
            rotated_bbox_area = rotated_width * rotated_height
            
            # Compute density with rotated bounding box
            rotated_density = component_size / rotated_bbox_area
            
            # Calculate rotation angle
            rotation_angle = atan(principal_axes[1, 2], principal_axes[2, 2])
            
            # Compute corners of rotated rectangle in original coordinates
            corners_proj = [
                (min_proj1, min_proj2),
                (max_proj1, min_proj2),
                (max_proj1, max_proj2),
                (min_proj1, max_proj2)
            ]
            
            corners_original = map(corners_proj) do (p1, p2)
                row = centroid_row + p1 * principal_axes[1, 2] + p2 * principal_axes[1, 1]
                col = centroid_col + p1 * principal_axes[2, 2] + p2 * principal_axes[2, 1]
                (row, col)
            end
            
            # Calculate aspect ratio (always >= 1, using longer/shorter dimension)
            aspect_ratio = max(rotated_width, rotated_height) / min(rotated_width, rotated_height)
            
            # Compute aspect ratio score (0 to 1, higher is better match)
            # Uses exponential decay from the preferred aspect ratio
            aspect_ratio_score = exp(-abs(aspect_ratio - preferred_aspect_ratio) / preferred_aspect_ratio)
            
            # Normalize density to 0-1 range (assuming density typically < 1.0)
            normalized_density = min(rotated_density, 1.0)
            
            # Combined score: weighted average of density and aspect ratio match
            combined_score = (1.0 - aspect_ratio_weight) * normalized_density + aspect_ratio_weight * aspect_ratio_score
            
            # Select component with highest combined score
            if combined_score > best_score
                best_score = combined_score
                best_density = rotated_density
                best_label = label
                best_rotated_corners = vcat([[c[1], c[2]] for c in corners_original]...)
                best_rotation_angle = rotation_angle
                best_size = component_size
                best_aspect_ratio = aspect_ratio
            end
        end
        
        if best_label == 0
            # No components met the minimum area requirement
            return white_mask_all, 0, 0.0, num_components, 0.0, Float64[], 0.0, 0.0
        end
        
        # Create mask with only the densest component
        white_mask = labeled .== best_label
        
        total_pixels = size(rgb_data, 1) * size(rgb_data, 2)
        white_percentage = (best_size / total_pixels) * 100
        
        return white_mask, best_size, white_percentage, num_components, best_density, best_rotated_corners, best_rotation_angle, best_aspect_ratio
    end
    
    # Compute channel statistics for white regions only
    function compute_white_region_channel_stats(image, white_mask)
        # Extract RGB data - use data() to get raw array, then permute to (channels, height, width)
        raw_data = data(image)  # Returns (height, width, 3)
        rgb_data = permutedims(raw_data, (3, 1, 2))  # Convert to (3, height, width)
        
        # Initialize result dictionaries
        stats = Dict{Symbol, Dict{Symbol, Float64}}()
        
        # Get channel names
        channel_names = if size(rgb_data, 1) == 3
            [:red, :green, :blue]
        else
            error("Image must have 3 color channels (RGB)")
        end
        
        # Count white pixels
        white_pixel_count = sum(white_mask)
        
        if white_pixel_count == 0
            # No white pixels - return zeros
            for (i, ch) in enumerate(channel_names)
                stats[ch] = Dict(:mean => 0.0, :std => 0.0, :skewness => 0.0)
            end
            return stats, 0
        end
        
        # Extract white pixel values for each channel
        for (i, ch) in enumerate(channel_names)
            channel_data = rgb_data[i, :, :]
            white_values = channel_data[white_mask]
            
            # Compute statistics
            ch_mean = mean(white_values)
            ch_std = std(white_values)
            
            # Compute skewness manually
            n = length(white_values)
            if n > 2 && ch_std > 0
                centered = white_values .- ch_mean
                m3 = sum(centered .^ 3) / n
                ch_skewness = m3 / (ch_std ^ 3)
            else
                ch_skewness = 0.0
            end
            
            stats[ch] = Dict(
                :mean => ch_mean,
                :std => ch_std,
                :skewness => ch_skewness
            )
        end
        
        return stats, white_pixel_count
    end
    
    # Contour extraction using boundary detection
    function extract_contours(mask)
        # Find boundary pixels (pixels adjacent to background)
        h, w = size(mask)
        contour_points = Tuple{Int, Int}[]
        
        for i in 1:h
            for j in 1:w
                if mask[i, j]
                    is_boundary = false
                    
                    # Check 4-connected neighbors (up, down, left, right)
                    for (di, dj) in [(-1,0), (1,0), (0,-1), (0,1)]
                        ni, nj = i + di, j + dj
                        if ni < 1 || ni > h || nj < 1 || nj > w || !mask[ni, nj]
                            is_boundary = true
                            break
                        end
                    end
                    
                    if is_boundary
                        push!(contour_points, (i, j))
                    end
                end
            end
        end
        
        return contour_points
    end
    
    # Helper functions for region selection
    
    # Convert axis coordinates to image pixel coordinates
    # Input axis shows rotr90(image), so need to reverse transform
    function axis_to_pixel(point_axis, img_height, img_width)
        # rotr90 rotates 90 degrees clockwise
        # Original image is H×W (height × width)
        # After rotr90, it becomes W×H (cols become rows, rows become cols)
        # 
        # Forward transform: rotated[orig_col, H - orig_row + 1] = original[orig_row, orig_col]
        # Inverse transform: 
        #   orig_row = H - rot_col + 1
        #   orig_col = rot_row
        #
        # point_axis is in rotated space: (rot_row, rot_col)
        # which corresponds to (x, y) in axis coordinates
        rot_row = round(Int, point_axis[1])
        rot_col = round(Int, point_axis[2])
        
        # Convert to original image coordinates
        orig_row = img_height - rot_col + 1
        orig_col = rot_row
        
        return (orig_row, orig_col)
    end
    
    # Create rectangle polygon from two corners
    function make_rectangle(c1, c2)
        x_min, x_max = minmax(c1[1], c2[1])
        y_min, y_max = minmax(c1[2], c2[2])
        return Bas3GLMakie.GLMakie.Point2f[
            Bas3GLMakie.GLMakie.Point2f(x_min, y_min),
            Bas3GLMakie.GLMakie.Point2f(x_max, y_min),
            Bas3GLMakie.GLMakie.Point2f(x_max, y_max),
            Bas3GLMakie.GLMakie.Point2f(x_min, y_max),
            Bas3GLMakie.GLMakie.Point2f(x_min, y_min)  # Close the loop
        ]
    end
    
    # Initial white region extraction (densest component with configurable min area and aspect ratio preference)
    local init_white_mask, init_white_count, init_white_pct, init_total_components, init_density, init_rotated_corners, init_rotation_angle, init_aspect_ratio = extract_white_mask(sets[1][1]; threshold=0.7, min_component_area=8000, preferred_aspect_ratio=5.0, aspect_ratio_weight=0.6)
    local init_contours = extract_contours(init_white_mask)
    
    # Helper function to create RGBA overlay from boolean mask with contours and rotated bounding boxes
    function create_white_overlay(mask, contours, rotated_corners)
        # Create RGBA overlay: red with 70% opacity for white regions, transparent elsewhere
        overlay = map(mask) do is_white
            if is_white
                Bas3ImageSegmentation.RGBA{Float32}(1.0f0, 0.0f0, 0.0f0, 0.7f0)  # Red with 70% alpha
            else
                Bas3ImageSegmentation.RGBA{Float32}(0.0f0, 0.0f0, 0.0f0, 0.0f0)  # Transparent
            end
        end
        
        # Draw contours in bright yellow for better visibility
        for (i, j) in contours
            overlay[i, j] = Bas3ImageSegmentation.RGBA{Float32}(1.0f0, 1.0f0, 0.0f0, 1.0f0)  # Bright yellow
        end
        
        # Draw rotated bounding box in magenta (100% opacity) using line drawing
        if !isempty(rotated_corners) && length(rotated_corners) >= 8
            h, w = size(overlay)
            # Extract 4 corners from the flat array
            corners = [
                (rotated_corners[1], rotated_corners[2]),
                (rotated_corners[3], rotated_corners[4]),
                (rotated_corners[5], rotated_corners[6]),
                (rotated_corners[7], rotated_corners[8])
            ]
            
            # Draw lines between consecutive corners
            for i in 1:4
                next_i = (i % 4) + 1
                r1, c1 = corners[i]
                r2, c2 = corners[next_i]
                
                # Simple line drawing using interpolation
                steps = max(abs(r2 - r1), abs(c2 - c1))
                if steps > 0
                    for step in 0:Int(ceil(steps))
                        t = step / steps
                        r = Int(round(r1 + t * (r2 - r1)))
                        c = Int(round(c1 + t * (c2 - c1)))
                        if r >= 1 && r <= h && c >= 1 && c <= w
                            overlay[r, c] = Bas3ImageSegmentation.RGBA{Float32}(1.0f0, 0.0f0, 1.0f0, 1.0f0)  # Magenta
                        end
                    end
                end
            end
        end
        
        return rotr90(overlay)
    end
    
    # Function to extract rotated bounding boxes for all classes in an image
    function extract_class_bboxes(output_image)
        local output_data = data(output_image)
        local bboxes_by_class = Dict{Symbol, Vector{Vector{Float64}}}()
        
        # Process each non-background class
        for (class_idx, class) in enumerate(classes)
            if class == :background
                continue
            end
            
            bboxes_by_class[class] = []
            
            # Extract binary mask for this class (threshold at 0.5)
            local class_mask = output_data[:, :, class_idx] .> 0.5
            
            # Skip if no pixels for this class
            if !any(class_mask)
                continue
            end
            
            # Label connected components
            local labeled = Bas3ImageSegmentation.label_components(class_mask)
            local num_components = maximum(labeled)
            
            # Process each connected component
            for component_id in 1:num_components
                # Get mask for this component
                local component_mask = labeled .== component_id
                
                # Find all pixels in this component
                local pixel_coords = findall(component_mask)
                
                if isempty(pixel_coords)
                    continue
                end
                
                # Extract row and column indices
                local row_indices = Float64[p[1] for p in pixel_coords]
                local col_indices = Float64[p[2] for p in pixel_coords]
                
                # Compute centroid
                local centroid_row = sum(row_indices) / length(row_indices)
                local centroid_col = sum(col_indices) / length(col_indices)
                
                # Center the coordinates
                local centered_rows = row_indices .- centroid_row
                local centered_cols = col_indices .- centroid_col
                
                # Compute covariance matrix for PCA
                local n = length(centered_rows)
                local cov_matrix = [
                    sum(centered_rows .* centered_rows) / n   sum(centered_rows .* centered_cols) / n;
                    sum(centered_rows .* centered_cols) / n   sum(centered_cols .* centered_cols) / n
                ]
                
                # Compute eigenvectors (principal directions)
                local eigen_result = eigen(cov_matrix)
                local principal_axes = eigen_result.vectors
                
                # Project points onto principal axes
                local proj_axis1 = centered_rows .* principal_axes[1, 2] .+ centered_cols .* principal_axes[2, 2]
                local proj_axis2 = centered_rows .* principal_axes[1, 1] .+ centered_cols .* principal_axes[2, 1]
                
                # Find min/max along each principal axis
                local min_proj1, max_proj1 = extrema(proj_axis1)
                local min_proj2, max_proj2 = extrema(proj_axis2)
                
                # Compute corners of rotated rectangle in original coordinates
                local corners_proj = [
                    (min_proj1, min_proj2),
                    (max_proj1, min_proj2),
                    (max_proj1, max_proj2),
                    (min_proj1, max_proj2)
                ]
                
                local corners_original = map(corners_proj) do (p1, p2)
                    row = centroid_row + p1 * principal_axes[1, 2] + p2 * principal_axes[1, 1]
                    col = centroid_col + p1 * principal_axes[2, 2] + p2 * principal_axes[2, 1]
                    [row, col]
                end
                
                # Flatten to [r1, c1, r2, c2, r3, c3, r4, c4]
                local rotated_corners = vcat(corners_original...)
                
                push!(bboxes_by_class[class], rotated_corners)
            end
        end
        
        return bboxes_by_class
    end
    
    # Display initial input and output images using the image() function
    local current_input_image = Bas3GLMakie.GLMakie.Observable(rotr90(image(sets[1][1])))
    local current_output_image = Bas3GLMakie.GLMakie.Observable(rotr90(image(sets[1][2])))
    local current_white_overlay = Bas3GLMakie.GLMakie.Observable(create_white_overlay(init_white_mask, init_contours, init_rotated_corners))
    local current_class_bboxes = Bas3GLMakie.GLMakie.Observable(extract_class_bboxes(sets[1][2]))
    
    # Region selection observables
    local selection_active = Bas3GLMakie.GLMakie.Observable(false)
    local selection_corner1 = Bas3GLMakie.GLMakie.Observable(Bas3GLMakie.GLMakie.Point2f(0, 0))
    local selection_corner2 = Bas3GLMakie.GLMakie.Observable(Bas3GLMakie.GLMakie.Point2f(0, 0))
    local selection_complete = Bas3GLMakie.GLMakie.Observable(false)
    local selection_rect = Bas3GLMakie.GLMakie.Observable(Bas3GLMakie.GLMakie.Point2f[])
    local preview_rect = Bas3GLMakie.GLMakie.Observable(Bas3GLMakie.GLMakie.Point2f[])
    
    # White region statistics label
    #=
    local white_stats_label = Bas3GLMakie.GLMakie.Label(
        fgr[3, 1:3],
        "Marker: $(init_white_count) pixels ($(round(init_white_pct, digits=2))%) | Density: $(round(init_density*100, digits=1))% | Components: $(init_total_components) | BBox: $(init_bbox[2]-init_bbox[1]+1)x$(init_bbox[4]-init_bbox[3]+1) | Rotation: $(round(rad2deg(init_rotation_angle), digits=1))° | Aspect: $(round(init_aspect_ratio, digits=2)):1",
        fontsize=14,
        halign=:center
    )
        =#
    
    # Flag to prevent recursive callback triggering
    local updating_from_button = Ref(false)
    
    # Helper function to update the image display (core logic without textbox update)
    function update_image_display_internal(idx, threshold=0.7, min_component_area=8000, preferred_aspect_ratio=5.0, aspect_ratio_weight=0.6, kernel_size=3)
        # Validate the input
        if idx < 1 || idx > length(sets)
            textbox_label.text = "Ungültige Eingabe! Geben Sie eine Zahl zwischen 1 und $(length(sets)) ein"
            return false
        end
        
        # Update label to show current image
        textbox_label.text = "Bild: $idx / $(length(sets))"
        
        # Get input RGB image (sets[idx][1] is the input image)
        input_img = rotr90(image(sets[idx][1]))
        current_input_image[] = input_img
        
        # Get output segmentation image (sets[idx][2] is the output/ground truth)
        output_img = rotr90(image(sets[idx][2]))
        current_output_image[] = output_img
        
        # Extract white regions and contours (densest component with min area filter and aspect ratio preference)
        # Apply region constraint if selection is complete
        local region = nothing
        if selection_complete[]
            img = sets[idx][1]
            img_height = size(data(img), 1)
            img_width = size(data(img), 2)
            
            c1_px = axis_to_pixel(selection_corner1[], img_height, img_width)
            c2_px = axis_to_pixel(selection_corner2[], img_height, img_width)
            
            # Ensure correct ordering (min to max)
            r_min, r_max = minmax(c1_px[1], c2_px[1])
            c_min, c_max = minmax(c1_px[2], c2_px[2])
            
            region = (r_min, r_max, c_min, c_max)
        end
        
        white_mask, white_count, white_pct, total_components, density, rotated_corners, rotation_angle, aspect_ratio = extract_white_mask(sets[idx][1]; threshold=threshold, min_component_area=min_component_area, preferred_aspect_ratio=preferred_aspect_ratio, aspect_ratio_weight=aspect_ratio_weight, kernel_size=kernel_size, region=region)
        contours = extract_contours(white_mask)
        current_white_overlay[] = create_white_overlay(white_mask, contours, rotated_corners)
        
        # Extract class bounding boxes
        current_class_bboxes[] = extract_class_bboxes(sets[idx][2])
        
        # Compute full-image channel statistics
        local input_img_original = sets[idx][1]  # Original image (not rotated)
        local raw_data = data(input_img_original)  # Returns (height, width, 3)
        local rgb_data = permutedims(raw_data, (3, 1, 2))  # Convert to (3, height, width)
        
        # Full image stats
        local full_r_mean = mean(rgb_data[1, :, :])
        local full_g_mean = mean(rgb_data[2, :, :])
        local full_b_mean = mean(rgb_data[3, :, :])
        
        local full_r_std = std(rgb_data[1, :, :])
        local full_g_std = std(rgb_data[2, :, :])
        local full_b_std = std(rgb_data[3, :, :])
        
        # Compute skewness for full image
        function compute_channel_skewness(channel_data)
            ch_mean = mean(channel_data)
            ch_std = std(channel_data)
            n = length(channel_data)
            if n > 2 && ch_std > 0
                centered = channel_data .- ch_mean
                m3 = sum(centered .^ 3) / n
                return m3 / (ch_std ^ 3)
            else
                return 0.0
            end
        end
        
        local full_r_skew = compute_channel_skewness(rgb_data[1, :, :])
        local full_g_skew = compute_channel_skewness(rgb_data[2, :, :])
        local full_b_skew = compute_channel_skewness(rgb_data[3, :, :])
        
        # Plot full image statistics
        # Clear previous plots
        empty!(full_mean_ax)
        empty!(full_box_ax)
        empty!(full_hist_ax)
        
        # Plot 1: Mean ± Std for full image
        local channel_colors = [:red, :green, :blue]
        local full_means = [full_r_mean, full_g_mean, full_b_mean]
        local full_stds = [full_r_std, full_g_std, full_b_std]
        
        for i in 1:3
            Bas3GLMakie.GLMakie.scatter!(
                full_mean_ax,
                [i],
                [full_means[i]];
                markersize=12,
                color=channel_colors[i],
                marker=:circle
            )
            Bas3GLMakie.GLMakie.errorbars!(
                full_mean_ax,
                [i],
                [full_means[i]],
                [full_stds[i]],
                [full_stds[i]];
                whiskerwidth=10,
                color=channel_colors[i],
                linewidth=2
            )
        end
        
        # Plot 2: Boxplot for full image
        local full_red_values = vec(rgb_data[1, :, :])
        local full_green_values = vec(rgb_data[2, :, :])
        local full_blue_values = vec(rgb_data[3, :, :])
        
        Bas3GLMakie.GLMakie.boxplot!(
            full_box_ax,
            fill(1, length(full_red_values)),
            full_red_values;
            color=(:red, 0.6),
            show_outliers=true,
            width=0.6
        )
        Bas3GLMakie.GLMakie.boxplot!(
            full_box_ax,
            fill(2, length(full_green_values)),
            full_green_values;
            color=(:green, 0.6),
            show_outliers=true,
            width=0.6
        )
        Bas3GLMakie.GLMakie.boxplot!(
            full_box_ax,
            fill(3, length(full_blue_values)),
            full_blue_values;
            color=(:blue, 0.6),
            show_outliers=true,
            width=0.6
        )
        
        # Plot 3: RGB Histogram for full image
        Bas3GLMakie.GLMakie.hist!(
            full_hist_ax,
            full_red_values;
            bins=50,
            color=(:red, 0.5),
            normalization=:pdf,
            label="Red"
        )
        Bas3GLMakie.GLMakie.hist!(
            full_hist_ax,
            full_green_values;
            bins=50,
            color=(:green, 0.5),
            normalization=:pdf,
            label="Green"
        )
        Bas3GLMakie.GLMakie.hist!(
            full_hist_ax,
            full_blue_values;
            bins=50,
            color=(:blue, 0.5),
            normalization=:pdf,
            label="Blue"
        )
        
        # Refresh axis limits for full image plots
        Bas3GLMakie.GLMakie.autolimits!(full_mean_ax)
        Bas3GLMakie.GLMakie.autolimits!(full_box_ax)
        Bas3GLMakie.GLMakie.autolimits!(full_hist_ax)
        
        # Compute white region channel statistics
        if white_count > 0
            local white_stats, white_pixel_count = compute_white_region_channel_stats(input_img_original, white_mask)
            
            local white_r_mean = white_stats[:red][:mean]
            local white_g_mean = white_stats[:green][:mean]
            local white_b_mean = white_stats[:blue][:mean]
            
            local white_r_std = white_stats[:red][:std]
            local white_g_std = white_stats[:green][:std]
            local white_b_std = white_stats[:blue][:std]
            
            local white_r_skew = white_stats[:red][:skewness]
            local white_g_skew = white_stats[:green][:skewness]
            local white_b_skew = white_stats[:blue][:skewness]
            
            # Extract pixel values for plotting
            local raw_data_plot = data(input_img_original)  # Returns (height, width, 3)
            local rgb_data_plot = permutedims(raw_data_plot, (3, 1, 2))  # Convert to (3, height, width)
            local red_values = rgb_data_plot[1, :, :][white_mask]
            local green_values = rgb_data_plot[2, :, :][white_mask]
            local blue_values = rgb_data_plot[3, :, :][white_mask]
            
            # Clear previous plots
            empty!(region_mean_ax)
            empty!(region_box_ax)
            empty!(region_hist_ax)
            
            # Plot 1: Mean ± Std
            local channel_colors = [:red, :green, :blue]
            local means = [white_r_mean, white_g_mean, white_b_mean]
            local stds = [white_r_std, white_g_std, white_b_std]
            
            for i in 1:3
                Bas3GLMakie.GLMakie.scatter!(
                    region_mean_ax,
                    [i],
                    [means[i]];
                    markersize=12,
                    color=channel_colors[i],
                    marker=:circle
                )
                Bas3GLMakie.GLMakie.errorbars!(
                    region_mean_ax,
                    [i],
                    [means[i]],
                    [stds[i]],
                    [stds[i]];
                    whiskerwidth=10,
                    color=channel_colors[i],
                    linewidth=2
                )
            end
            
            # Plot 2: Boxplot
            Bas3GLMakie.GLMakie.boxplot!(
                region_box_ax,
                fill(1, length(red_values)),
                red_values;
                color=(:red, 0.6),
                show_outliers=true,
                width=0.6
            )
            Bas3GLMakie.GLMakie.boxplot!(
                region_box_ax,
                fill(2, length(green_values)),
                green_values;
                color=(:green, 0.6),
                show_outliers=true,
                width=0.6
            )
            Bas3GLMakie.GLMakie.boxplot!(
                region_box_ax,
                fill(3, length(blue_values)),
                blue_values;
                color=(:blue, 0.6),
                show_outliers=true,
                width=0.6
            )
            
            # Plot 3: RGB Histogram
            Bas3GLMakie.GLMakie.hist!(
                region_hist_ax,
                red_values;
                bins=50,
                color=(:red, 0.5),
                normalization=:pdf,
                label="Red"
            )
            Bas3GLMakie.GLMakie.hist!(
                region_hist_ax,
                green_values;
                bins=50,
                color=(:green, 0.5),
                normalization=:pdf,
                label="Green"
            )
            Bas3GLMakie.GLMakie.hist!(
                region_hist_ax,
                blue_values;
                bins=50,
                color=(:blue, 0.5),
                normalization=:pdf,
                label="Blue"
            )
            
            # Refresh axis limits to update display
            Bas3GLMakie.GLMakie.autolimits!(region_mean_ax)
            Bas3GLMakie.GLMakie.autolimits!(region_box_ax)
            Bas3GLMakie.GLMakie.autolimits!(region_hist_ax)
        else
            # Clear plots when no region detected
            empty!(region_mean_ax)
            empty!(region_box_ax)
            empty!(region_hist_ax)
        end
        
        # Update statistics label
        #white_stats_label.text = "Marker: $(white_count) pixels ($(round(white_pct, digits=2))%) | Density: $(round(density*100, digits=1))% | Components: $(total_components) | BBox: $(bbox_height)x$(bbox_width) | Rotation: $(round(rad2deg(rotation_angle), digits=1))° | Aspect: $(round(aspect_ratio, digits=2)):1"
        
        return true
    end
    
    # Update images when textbox value changes
    Bas3GLMakie.GLMakie.on(textbox.stored_string) do str
        # Skip if being updated from button click
        if updating_from_button[]
            println("[DEBUG] Textbox callback skipped (button update)")
            return
        end
        
        println("[DEBUG] Textbox callback triggered with value: '$str'")
        # Parse the input string to an integer
        idx = tryparse(Int, str)
        
        if idx !== nothing
            println("[DEBUG] Updating to image $idx")
            # Read parameter values from textboxes
            threshold = tryparse(Float64, threshold_textbox.stored_string[])
            min_area = tryparse(Int, min_area_textbox.stored_string[])
            aspect_ratio = tryparse(Float64, aspect_ratio_textbox.stored_string[])
            aspect_weight = tryparse(Float64, aspect_weight_textbox.stored_string[])
            kernel_size = tryparse(Int, kernel_size_textbox.stored_string[])
            
            # Use defaults if parsing fails
            threshold = threshold === nothing ? 0.7 : threshold
            min_area = min_area === nothing ? 8000 : min_area
            aspect_ratio = aspect_ratio === nothing ? 5.0 : aspect_ratio
            aspect_weight = aspect_weight === nothing ? 0.6 : aspect_weight
            kernel_size = kernel_size === nothing ? 3 : kernel_size
            
            update_image_display_internal(idx, threshold, min_area, aspect_ratio, aspect_weight, kernel_size)
        else
            println("[DEBUG] Invalid input: $str")
            textbox_label.text = "Ungültige Eingabe! Geben Sie eine Zahl zwischen 1 und $(length(sets)) ein"
        end
    end
    
    # Previous button callback
    Bas3GLMakie.GLMakie.on(prev_button.clicks) do n
        println("[DEBUG] Previous button clicked (click #$n)")
        current_idx = tryparse(Int, textbox.stored_string[])
        println("[DEBUG] Current index: $current_idx")
        if current_idx !== nothing && current_idx > 1
            new_idx = current_idx - 1
            println("[DEBUG] Going to image: $new_idx")
            
            # Read parameter values from textboxes
            threshold = tryparse(Float64, threshold_textbox.stored_string[])
            min_area = tryparse(Int, min_area_textbox.stored_string[])
            aspect_ratio = tryparse(Float64, aspect_ratio_textbox.stored_string[])
            aspect_weight = tryparse(Float64, aspect_weight_textbox.stored_string[])
            kernel_size = tryparse(Int, kernel_size_textbox.stored_string[])
            
            # Use defaults if parsing fails
            threshold = threshold === nothing ? 0.7 : threshold
            min_area = min_area === nothing ? 8000 : min_area
            aspect_ratio = aspect_ratio === nothing ? 5.0 : aspect_ratio
            aspect_weight = aspect_weight === nothing ? 0.6 : aspect_weight
            kernel_size = kernel_size === nothing ? 3 : kernel_size
            
            # Update images
            if update_image_display_internal(new_idx, threshold, min_area, aspect_ratio, aspect_weight, kernel_size)
                # Update textbox without triggering callback
                updating_from_button[] = true
                textbox.stored_string[] = string(new_idx)
                updating_from_button[] = false
                println("[DEBUG] Successfully updated to image $new_idx")
            end
        else
            println("[DEBUG] Cannot go previous (at minimum or invalid)")
        end
    end
    
    # Next button callback
    Bas3GLMakie.GLMakie.on(next_button.clicks) do n
        println("[DEBUG] Next button clicked (click #$n)")
        current_idx = tryparse(Int, textbox.stored_string[])
        println("[DEBUG] Current index: $current_idx")
        if current_idx !== nothing && current_idx < length(sets)
            new_idx = current_idx + 1
            println("[DEBUG] Going to image: $new_idx")
            
            # Read parameter values from textboxes
            threshold = tryparse(Float64, threshold_textbox.stored_string[])
            min_area = tryparse(Int, min_area_textbox.stored_string[])
            aspect_ratio = tryparse(Float64, aspect_ratio_textbox.stored_string[])
            aspect_weight = tryparse(Float64, aspect_weight_textbox.stored_string[])
            kernel_size = tryparse(Int, kernel_size_textbox.stored_string[])
            
            # Use defaults if parsing fails
            threshold = threshold === nothing ? 0.7 : threshold
            min_area = min_area === nothing ? 8000 : min_area
            aspect_ratio = aspect_ratio === nothing ? 5.0 : aspect_ratio
            aspect_weight = aspect_weight === nothing ? 0.6 : aspect_weight
            kernel_size = kernel_size === nothing ? 3 : kernel_size
            
            # Update images
            if update_image_display_internal(new_idx, threshold, min_area, aspect_ratio, aspect_weight, kernel_size)
                # Update textbox without triggering callback
                updating_from_button[] = true
                textbox.stored_string[] = string(new_idx)
                updating_from_button[] = false
                println("[DEBUG] Successfully updated to image $new_idx")
            end
        else
            println("[DEBUG] Cannot go next (at maximum or invalid)")
        end
    end
    
    # Helper function to update white detection with current parameters
    function update_white_detection(source="manual")
        # Parse and validate all parameters
        threshold = tryparse(Float64, threshold_textbox.stored_string[])
        min_area = tryparse(Int, min_area_textbox.stored_string[])
        aspect_ratio = tryparse(Float64, aspect_ratio_textbox.stored_string[])
        aspect_weight = tryparse(Float64, aspect_weight_textbox.stored_string[])
        kernel_size = tryparse(Int, kernel_size_textbox.stored_string[])
        
        # Validation checks
        validation_errors = String[]
        
        if threshold === nothing
            push!(validation_errors, "Threshold must be a number")
        elseif threshold < 0.0 || threshold > 1.0
            push!(validation_errors, "Threshold must be 0.0-1.0")
        end
        
        if min_area === nothing
            push!(validation_errors, "Min Area must be a number")
        elseif min_area <= 0
            push!(validation_errors, "Min Area must be > 0")
        end
        
        if aspect_ratio === nothing
            push!(validation_errors, "Aspect Ratio must be a number")
        elseif aspect_ratio < 1.0
            push!(validation_errors, "Aspect Ratio must be >= 1.0")
        end
        
        if aspect_weight === nothing
            push!(validation_errors, "Aspect Weight must be a number")
        elseif aspect_weight < 0.0 || aspect_weight > 1.0
            push!(validation_errors, "Aspect Weight must be 0.0-1.0")
        end
        
        if kernel_size === nothing
            push!(validation_errors, "Kernel Size must be a number")
        elseif kernel_size < 0 || kernel_size > 10
            push!(validation_errors, "Kernel Size must be 0-10")
        end
        
        # If validation fails, show error
        if !isempty(validation_errors)
            param_status_label.text = join(validation_errors, " | ")
            param_status_label.color = :red
            return false
        end
        
        # Get current image index
        current_idx = tryparse(Int, textbox.stored_string[])
        if current_idx === nothing
            param_status_label.text = "Ungültiger Bildindex"
            param_status_label.color = :red
            return false
        end
        
        # Update the display with new parameters
        if update_image_display_internal(current_idx, threshold, min_area, aspect_ratio, aspect_weight, kernel_size)
            param_status_label.text = "Aktualisiert ($source)"
            param_status_label.color = :green
            return true
        else
            param_status_label.text = "Failed to update"
            param_status_label.color = :red
            return false
        end
    end
    
    # Auto-update when textboxes change
    Bas3GLMakie.GLMakie.on(threshold_textbox.stored_string) do val
        update_white_detection("threshold")
    end
    
    Bas3GLMakie.GLMakie.on(min_area_textbox.stored_string) do val
        update_white_detection("min area")
    end
    
    Bas3GLMakie.GLMakie.on(aspect_ratio_textbox.stored_string) do val
        update_white_detection("aspect ratio")
    end
    
    Bas3GLMakie.GLMakie.on(aspect_weight_textbox.stored_string) do val
        update_white_detection("aspect weight")
    end
    
    Bas3GLMakie.GLMakie.on(kernel_size_textbox.stored_string) do val
        update_white_detection("kernel size")
    end
    
    # Selection toggle callback
    Bas3GLMakie.GLMakie.on(selection_toggle.active) do active
        selection_active[] = active
        if active
            selection_status_label.text = "Klicken Sie auf die untere linke Ecke"
            selection_status_label.color = :blue
        else
            selection_status_label.text = "Auswahl deaktiviert"
            selection_status_label.color = :gray
        end
    end
    
    # Clear selection button callback
    Bas3GLMakie.GLMakie.on(clear_selection_button.clicks) do n
        selection_corner1[] = Bas3GLMakie.GLMakie.Point2f(0, 0)
        selection_corner2[] = Bas3GLMakie.GLMakie.Point2f(0, 0)
        selection_complete[] = false
        selection_rect[] = Bas3GLMakie.GLMakie.Point2f[]
        preview_rect[] = Bas3GLMakie.GLMakie.Point2f[]
        selection_status_label.text = "Auswahl gelöscht"
        selection_status_label.color = :gray
        
        # Re-run extraction on full image
        current_idx = tryparse(Int, textbox.stored_string[])
        if current_idx !== nothing && current_idx >= 1 && current_idx <= length(sets)
            threshold = tryparse(Float64, threshold_textbox.stored_string[])
            min_area = tryparse(Int, min_area_textbox.stored_string[])
            aspect_ratio = tryparse(Float64, aspect_ratio_textbox.stored_string[])
            aspect_weight = tryparse(Float64, aspect_weight_textbox.stored_string[])
            kernel_size = tryparse(Int, kernel_size_textbox.stored_string[])
            
            if threshold !== nothing && min_area !== nothing && aspect_ratio !== nothing && aspect_weight !== nothing && kernel_size !== nothing
                update_image_display_internal(current_idx, threshold, min_area, aspect_ratio, aspect_weight, kernel_size)
            end
        end
    end
    
    # Mouse click event handler for region selection
    Bas3GLMakie.GLMakie.on(Bas3GLMakie.GLMakie.events(fgr).mousebutton, priority = 2) do event
        if event.button == Bas3GLMakie.GLMakie.Mouse.left && event.action == Bas3GLMakie.GLMakie.Mouse.press
            if selection_active[]
                # Get mouse position in axis coordinates
                mp = Bas3GLMakie.GLMakie.mouseposition(axs3.scene)
                
                # Check if click is within axis bounds
                # mouseposition returns nothing if outside the axis
                if isnothing(mp)
                    return Bas3GLMakie.GLMakie.Consume(false)
                end
                
                if !selection_complete[]
                    if selection_corner1[] == Bas3GLMakie.GLMakie.Point2f(0, 0)
                        # First click - set bottom-left
                        selection_corner1[] = mp
                        selection_status_label.text = "Klicken Sie auf die obere rechte Ecke"
                        selection_status_label.color = :blue
                        println("[DEBUG] First corner selected: ", mp)
                    else
                        # Second click - set top-right
                        selection_corner2[] = mp
                        selection_complete[] = true
                        
                        # Update rectangle visualization
                        selection_rect[] = make_rectangle(selection_corner1[], selection_corner2[])
                        preview_rect[] = Bas3GLMakie.GLMakie.Point2f[]  # Clear preview
                        
                        selection_status_label.text = "Auswahl abgeschlossen"
                        selection_status_label.color = :green
                        println("[DEBUG] Second corner selected: ", mp)
                        
                        # Re-run white extraction on selected region
                        current_idx = tryparse(Int, textbox.stored_string[])
                        if current_idx !== nothing && current_idx >= 1 && current_idx <= length(sets)
                            threshold = tryparse(Float64, threshold_textbox.stored_string[])
                            min_area = tryparse(Int, min_area_textbox.stored_string[])
                            aspect_ratio = tryparse(Float64, aspect_ratio_textbox.stored_string[])
                            aspect_weight = tryparse(Float64, aspect_weight_textbox.stored_string[])
                            
                            if threshold !== nothing && min_area !== nothing && aspect_ratio !== nothing && aspect_weight !== nothing
                                # Convert axis coordinates to pixel coordinates
                                img = sets[current_idx][1]
                                img_height = size(data(img), 1)
                                img_width = size(data(img), 2)
                                
                                c1_px = axis_to_pixel(selection_corner1[], img_height, img_width)
                                c2_px = axis_to_pixel(selection_corner2[], img_height, img_width)
                                
                                # Ensure correct ordering (min to max)
                                r_min, r_max = minmax(c1_px[1], c2_px[1])
                                c_min, c_max = minmax(c1_px[2], c2_px[2])
                                
                                region = (r_min, r_max, c_min, c_max)
                                println("[DEBUG] Region in pixels: ", region)
                                
                                # Extract white regions with region constraint
                                white_mask, white_count, white_pct, total_components, density, rotated_corners, rotation_angle, aspect_ratio_result = 
                                    extract_white_mask(img; 
                                                      threshold=threshold, 
                                                      min_component_area=min_area,
                                                      preferred_aspect_ratio=aspect_ratio,
                                                      aspect_ratio_weight=aspect_weight,
                                                      region=region)
                                
                                # Update visualization
                                contours = extract_contours(white_mask)
                                current_white_overlay[] = create_white_overlay(white_mask, contours, rotated_corners)
                                
                                println("[DEBUG] White extraction updated with region constraint")
                            end
                        end
                    end
                    return Bas3GLMakie.GLMakie.Consume(true)  # Block axis interactions
                end
            end
        end
        return Bas3GLMakie.GLMakie.Consume(false)
    end
    
    # Mouse move event handler for preview
    Bas3GLMakie.GLMakie.on(Bas3GLMakie.GLMakie.events(fgr).mouseposition, priority = 2) do mp_window
        if selection_active[] && !selection_complete[]
            if selection_corner1[] != Bas3GLMakie.GLMakie.Point2f(0, 0)
                # Get mouse position in axis coordinates
                mp = Bas3GLMakie.GLMakie.mouseposition(axs3.scene)
                
                if !isnothing(mp)
                    # Update preview rectangle
                    preview_rect[] = make_rectangle(selection_corner1[], mp)
                end
            end
        end
        return Bas3GLMakie.GLMakie.Consume(false)
    end
    
    println("\n[INFO] Navigation controls ready:")
    println("  - Type a number (1-$(length(sets))) in the textbox and press Enter")
    println("  - Click '← Previous' to go to previous image")
    println("  - Click 'Next →' to go to next image")
    println("  - Debug output will show when controls are used")
    println("  - Enable region selection to limit white detection area\n")
    
    # Display the input image
    Bas3GLMakie.GLMakie.image!(axs3, current_input_image)
    
    # Overlay the segmentation output with 25% transparency (alpha=0.75)
    Bas3GLMakie.GLMakie.image!(axs3, current_output_image; alpha=0.75)
    
    # Overlay the white region detection with red fill and yellow contours
    Bas3GLMakie.GLMakie.image!(axs3, current_white_overlay)
    
    # Draw selection rectangle (cyan with semi-transparent fill)
    Bas3GLMakie.GLMakie.poly!(axs3, selection_rect, 
        color = (:cyan, 0.2),
        strokecolor = :cyan,
        strokewidth = 3,
        visible = Bas3GLMakie.GLMakie.@lift(!isempty($selection_rect)))
    
    # Draw preview rectangle while selecting (lighter cyan, dashed would be nice but using lighter color)
    Bas3GLMakie.GLMakie.poly!(axs3, preview_rect,
        color = (:cyan, 0.1),
        strokecolor = (:cyan, 0.6),
        strokewidth = 2,
        visible = Bas3GLMakie.GLMakie.@lift(!isempty($preview_rect)))
    
    # Draw bounding boxes for each class with 50% alpha
    # Colors match the segmentation class colors from Bas3ImageSegmentation
    local bbox_colors_map = Dict(
        :scar => (:red, 0.5),        # RGB(1, 0, 0)
        :redness => (:green, 0.5),   # RGB(0, 1, 0)
        :hematoma => (:blue, 0.5),   # RGB(0, 0, 1)
        :necrosis => (:yellow, 0.5)  # RGB(1, 1, 0)
    )
    
    # Store references to bbox plot objects so we can delete them
    local bbox_plot_objects = []
    
    # Function to draw bounding boxes (will be called when observable updates)
    Bas3GLMakie.GLMakie.on(current_class_bboxes) do bboxes_dict
        # Delete all previous bbox drawings
        for plot_obj in bbox_plot_objects
            Bas3GLMakie.GLMakie.delete!(axs3, plot_obj)
        end
        empty!(bbox_plot_objects)
        
        # Get image height for coordinate transformation
        local output_data = data(sets[1][2])
        local img_height = size(output_data, 1)
        
        # Draw new bounding boxes
        for (class, bboxes) in bboxes_dict
            local color = get(bbox_colors_map, class, (:white, 0.5))
            
            for rotated_corners in bboxes
                # rotated_corners is [r1, c1, r2, c2, r3, c3, r4, c4]
                if length(rotated_corners) < 8
                    continue
                end
                
                # Extract 4 corners
                local corners = [
                    (rotated_corners[1], rotated_corners[2]),
                    (rotated_corners[3], rotated_corners[4]),
                    (rotated_corners[5], rotated_corners[6]),
                    (rotated_corners[7], rotated_corners[8])
                ]
                
                # Transform coordinates for rotr90 display
                # rotr90 transforms: (row, col) -> (col, height - row + 1)
                local x_coords = Float64[]
                local y_coords = Float64[]
                
                for (row, col) in corners
                    push!(x_coords, col)
                    push!(y_coords, img_height - row + 1)
                end
                
                # Close the rectangle
                push!(x_coords, corners[1][2])
                push!(y_coords, img_height - corners[1][1] + 1)
                
                local line_plot = Bas3GLMakie.GLMakie.lines!(axs3, x_coords, y_coords; color=color, linewidth=2)
                push!(bbox_plot_objects, line_plot)
            end
        end
    end
    
    # Trigger initial drawing
    Bas3GLMakie.GLMakie.notify(current_class_bboxes)
    
    # Display image visualization figure in its own window
    display(Bas3GLMakie.GLMakie.Screen(), fgr)
    
    # Save the image visualization figure (full image - no selection)
    Bas3GLMakie.GLMakie.save("dataset_with_white_regions.png", fgr)
    println("Saved image visualization to dataset_with_white_regions.png")
    
    println("\nStatistics computation complete.")
    println("Three figures created:")
    println("  1. Class Statistics Figure (dataset_class_statistics.png)")
    println("  2. Bounding Box Metrics Figure (dataset_bounding_box_metrics.png)")
    println("  3. Image Visualization Figure (dataset_with_white_regions.png)")
    
    # ============================================================================
    # DEMONSTRATION: Programmatic Region Selection Test
    # ============================================================================
    println("\n" * "="^80)
    println("DEMONSTRATION: Testing Region Selection Feature")
    println("="^80)
    
    # Save the current state (full image)
    println("\n1. Saving baseline image (full white detection)...")
    Bas3GLMakie.GLMakie.save("demo_before_selection.png", fgr)
    println("   Saved: demo_before_selection.png")
    
    # Programmatically enable selection and set region
    println("\n2. Enabling region selection...")
    selection_active[] = true
    selection_status_label.text = "Programmatic selection active"
    selection_status_label.color = :blue
    
    # Get image dimensions for calculating region
    local demo_img = sets[1][1]
    local demo_img_height = size(data(demo_img), 1)
    local demo_img_width = size(data(demo_img), 2)
    
    println("   Image dimensions: $(demo_img_height) x $(demo_img_width)")
    
    # Define a region in the upper portion of the image where rulers typically are
    # In axis coordinates (after rotr90): axis shows cols x rows
    # Let's select the top-left quadrant where white rulers are more likely
    local region_x1 = demo_img_width * 0.05  # 5% from left
    local region_y1 = demo_img_height * 0.05  # 5% from top
    local region_x2 = demo_img_width * 0.5   # 50% from left
    local region_y2 = demo_img_height * 0.4  # 40% from top
    
    # Set corners in axis coordinates
    selection_corner1[] = Bas3GLMakie.GLMakie.Point2f(region_x1, region_y1)
    selection_corner2[] = Bas3GLMakie.GLMakie.Point2f(region_x2, region_y2)
    selection_complete[] = true
    
    println("   Corner 1 (axis coords): ", selection_corner1[])
    println("   Corner 2 (axis coords): ", selection_corner2[])
    
    # Update rectangle visualization
    selection_rect[] = make_rectangle(selection_corner1[], selection_corner2[])
    println("   Selection rectangle created")
    
    # Convert to pixel coordinates for extraction
    local c1_px = axis_to_pixel(selection_corner1[], demo_img_height, demo_img_width)
    local c2_px = axis_to_pixel(selection_corner2[], demo_img_height, demo_img_width)
    local r_min, r_max = minmax(c1_px[1], c2_px[1])
    local c_min, c_max = minmax(c1_px[2], c2_px[2])
    local region = (r_min, r_max, c_min, c_max)
    
    println("   Region in pixel coords: row[$r_min:$r_max], col[$c_min:$c_max]")
    println("   Region size: $(r_max-r_min+1) x $(c_max-c_min+1) pixels")
    
    # Re-run white extraction with region constraint
    println("\n3. Running white detection in selected region...")
    local threshold_val = 0.7
    local min_area_val = 8000
    local aspect_ratio_val = 5.0
    local aspect_weight_val = 0.6
    
    local white_mask_region, white_count_region, white_pct_region, total_components_region, 
          density_region, rotated_corners_region, rotation_angle_region, aspect_ratio_region = 
        extract_white_mask(demo_img; 
                          threshold=threshold_val, 
                          min_component_area=min_area_val,
                          preferred_aspect_ratio=aspect_ratio_val,
                          aspect_ratio_weight=aspect_weight_val,
                          region=region)
    
    println("   White pixels found: $white_count_region ($(round(white_pct_region, digits=2))%)")
    println("   Components found: $total_components_region")
    println("   Density: $(round(density_region*100, digits=1))%")
    
    # Update visualization
    local contours_region = extract_contours(white_mask_region)
    current_white_overlay[] = create_white_overlay(white_mask_region, contours_region, rotated_corners_region)
    
    selection_status_label.text = "Region selection applied"
    selection_status_label.color = :green
    
    # Give time for observables to update
    sleep(0.5)
    
    # Save with region selection active
    println("\n4. Saving result with region selection...")
    Bas3GLMakie.GLMakie.save("demo_with_selection.png", fgr)
    println("   Saved: demo_with_selection.png")
    
    # Create comparison info
    println("\n" * "="^80)
    println("DEMONSTRATION COMPLETE!")
    println("="^80)
    println("\nGenerated files:")
    println("  • demo_before_selection.png - Full image white detection")
    println("  • demo_with_selection.png   - Region-constrained detection (cyan rectangle)")
    println("\nThe cyan rectangle shows the selected region where white detection was limited.")
    println("You can see that only white areas within this region are detected and highlighted.")
    println("="^80 * "\n")
    
    # Clean up - reset to full image for normal use
    println("Resetting to full image detection for normal use...")
    selection_corner1[] = Bas3GLMakie.GLMakie.Point2f(0, 0)
    selection_corner2[] = Bas3GLMakie.GLMakie.Point2f(0, 0)
    selection_complete[] = false
    selection_rect[] = Bas3GLMakie.GLMakie.Point2f[]
    selection_active[] = false
    selection_status_label.text = "Auswahl deaktiviert"
    selection_status_label.color = :gray
    
    # Restore original detection
    local white_mask_full, white_count_full, white_pct_full, total_components_full, 
          density_full, rotated_corners_full, rotation_angle_full, aspect_ratio_full = 
        extract_white_mask(demo_img; 
                          threshold=threshold_val, 
                          min_component_area=min_area_val,
                          preferred_aspect_ratio=aspect_ratio_val,
                          aspect_ratio_weight=aspect_weight_val)
    
    local contours_full = extract_contours(white_mask_full)
    current_white_overlay[] = create_white_overlay(white_mask_full, contours_full, rotated_corners_full)
    
    sleep(0.2)
    
    # ============================================================================
    # DEMONSTRATION: Navigate to next image to populate Row 5 plots
    # ============================================================================
    println("\n" * "="^80)
    println("DEMONSTRATION: Navigating to image 2 to show Row 5 plots")
    println("="^80)
    
    # Simulate clicking "Next" button by updating to image 2
    println("\nNavigating to image 2...")
    local threshold_val = 0.7
    local min_area_val = 8000
    local aspect_ratio_val = 5.0
    local aspect_weight_val = 0.6
    local kernel_size_val = 3
    
    update_image_display_internal(2, threshold_val, min_area_val, aspect_ratio_val, aspect_weight_val, kernel_size_val)
    
    # Give time for the display to update
    sleep(0.5)
    
    # Save the updated figure showing Row 5 with plots
    println("Saving updated figure with Row 5 plots visible...")
    Bas3GLMakie.GLMakie.save("dataset_with_white_regions_image2.png", fgr)
    println("   Saved: dataset_with_white_regions_image2.png")
    
    println("\n" * "="^80)
    println("DEMONSTRATION COMPLETE!")
    println("="^80)
    println("\nYou can now see Row 5 plots populated with data from image 2.")
    println("="^80 * "\n")

    
    println("\n[INFO] Window is now open. Interact with the UI.")
    println("[INFO] The window will stay open. Close it manually when done.")
end  # end of begin block

println("\n=== Testing sets variable ===")
println("Type of sets: ", typeof(sets))
println("Length of sets: ", length(sets))
println("First element type: ", typeof(sets[1]))

