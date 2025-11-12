# Load_Sets__Statistics.jl
# Statistical computation functions for dataset analysis

"""
    Load_Sets__Statistics

Statistical analysis module for wound segmentation datasets.
Computes class area statistics, bounding box metrics, and channel statistics.
"""

using Statistics
using LinearAlgebra

# ============================================================================
# Data Structures
# ============================================================================

"""
    ClassAreaStatistics

Stores class area statistics for the dataset.

# Fields
- `classes::Vector{Symbol}`: Class names
- `total_pixels::Float64`: Total pixels across all images
- `class_totals::Dict{Symbol, Float64}`: Total pixels per class
- `class_areas_per_image::Dict{Symbol, Vector{Float64}}`: Area per image per class
- `statistics::Dict{Symbol, NamedTuple}`: Mean and std per class
- `normalized_statistics::Dict{Symbol, NamedTuple}`: Normalized stats
"""
struct ClassAreaStatistics
    classes::Vector{Symbol}
    total_pixels::Float64
    class_totals::Dict{Symbol, Float64}
    class_areas_per_image::Dict{Symbol, Vector{Float64}}
    statistics::Dict{Symbol, NamedTuple}
    normalized_statistics::Dict{Symbol, NamedTuple}
end

"""
    BoundingBoxStatistics

Stores bounding box statistics for wound classes.

# Fields
- `bbox_classes::Vector{Symbol}`: Classes analyzed (excluding background)
- `bbox_metrics::Dict{Symbol, Dict{Symbol, Vector{Float64}}}`: Width, height, aspect ratio per class
- `bbox_statistics::Dict{Symbol, Dict{Symbol, Float64}}`: Aggregate statistics
"""
struct BoundingBoxStatistics
    bbox_classes::Vector{Symbol}
    bbox_metrics::Dict{Symbol, Dict{Symbol, Vector{Float64}}}
    bbox_statistics::Dict{Symbol, Dict{Symbol, Float64}}
end

"""
    ChannelStatistics

Stores RGB channel statistics for the dataset.

# Fields
- `channel_names::Vector{Symbol}`: Channel names (:red, :green, :blue)
- `channel_means_per_image::Dict{Symbol, Vector{Float64}}`: Mean intensity per image
- `channel_skewness_per_image::Dict{Symbol, Vector{Float64}}`: Skewness per image
- `global_channel_stats::Dict{Symbol, NamedTuple}`: Global mean, std, skewness
"""
struct ChannelStatistics
    channel_names::Vector{Symbol}
    channel_means_per_image::Dict{Symbol, Vector{Float64}}
    channel_skewness_per_image::Dict{Symbol, Vector{Float64}}
    global_channel_stats::Dict{Symbol, NamedTuple}
end

# ============================================================================
# Statistical Helper Functions
# ============================================================================

"""
    compute_skewness(values::AbstractVector{T}) where T <: Real -> Float64

Compute skewness (third standardized moment) of a distribution.

# Formula
Skewness = E[(X - μ)³] / σ³

Where μ is mean and σ is standard deviation.

# Returns
- Positive skew: Right tail longer (values concentrated on left)
- Negative skew: Left tail longer (values concentrated on right)
- Zero skew: Symmetric distribution
"""
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

"""
    find_outliers(data::Vector{T}) where T <: Real -> (BitVector, Float64)

Identify outliers using the Interquartile Range (IQR) method.

# Algorithm
1. Compute Q1 (25th percentile) and Q3 (75th percentile)
2. Compute IQR = Q3 - Q1
3. Outliers are values < Q1 - 1.5×IQR or > Q3 + 1.5×IQR

# Returns
- `outlier_mask::BitVector`: True for outlier indices
- `outlier_percentage::Float64`: Percentage of outliers (0-100)
"""
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

# ============================================================================
# Class Area Statistics
# ============================================================================

"""
    compute_class_area_statistics(sets, raw_output_type) -> ClassAreaStatistics

Compute class area statistics across all images in dataset.

# Arguments
- `sets`: Vector of (input, output, index) tuples
- `raw_output_type`: Output image type with class definitions

# Returns
- `ClassAreaStatistics` struct with all computed metrics
"""
function compute_class_area_statistics(sets, raw_output_type)
    local outputs = [sets[i][2] for i in 1:length(sets)]
    local classes = Bas3ImageSegmentation.shape(raw_output_type)
    
    # Initialize accumulators
    local total_pixels = 0.0
    local class_totals = Dict(class => 0.0 for class in classes)
    local class_areas_per_image = Dict(class => Float64[] for class in classes)
    
    # Compute per-image and total statistics
    println("Analyzing $(length(outputs)) output images for class area statistics...")
    for (img_idx, output_image) in enumerate(outputs)
        local output_data = Bas3ImageSegmentation.data(output_image)
        local image_pixels = size(output_data, 1) * size(output_data, 2)
        total_pixels += image_pixels
        
        for (class_idx, class) in enumerate(classes)
            local class_pixels = sum(output_data[:, :, class_idx])
            class_totals[class] += class_pixels
            push!(class_areas_per_image[class], class_pixels)
        end
    end
    
    # Compute statistics (mean and std)
    local statistics = Dict(
        class => (
            mean = mean(class_areas_per_image[class]),
            std = std(class_areas_per_image[class])
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
    
    return ClassAreaStatistics(
        collect(classes),
        total_pixels,
        class_totals,
        class_areas_per_image,
        statistics,
        normalized_statistics
    )
end

# ============================================================================
# Bounding Box Statistics
# ============================================================================

"""
    compute_bounding_box_statistics(sets, raw_output_type) -> BoundingBoxStatistics

Compute PCA-based oriented bounding box statistics for wound classes.

# Arguments
- `sets`: Vector of (input, output, index) tuples
- `raw_output_type`: Output image type with class definitions

# Returns
- `BoundingBoxStatistics` struct with width, height, aspect ratio metrics
"""
function compute_bounding_box_statistics(sets, raw_output_type)
    local outputs = [sets[i][2] for i in 1:length(sets)]
    local classes = Bas3ImageSegmentation.shape(raw_output_type)
    local bbox_classes = filter(c -> c != :background, classes)
    
    # Initialize metrics storage
    local bbox_metrics = Dict(
        class => Dict(
            :widths => Float64[],
            :heights => Float64[],
            :aspect_ratios => Float64[]
        )
        for class in bbox_classes
    )
    
    println("Analyzing $(length(outputs)) images for bounding box statistics...")
    
    # Process each image and class
    for (img_idx, output_image) in enumerate(outputs)
        local output_data = Bas3ImageSegmentation.data(output_image)
        
        for (class_idx, class) in enumerate(classes)
            if class == :background
                continue
            end
            
            # Extract class mask
            local class_mask = output_data[:, :, class_idx] .> 0.5
            
            if sum(class_mask) == 0
                continue
            end
            
            # Label connected components
            local labeled = Bas3ImageSegmentation.label_components(class_mask)
            local num_components = maximum(labeled)
            
            # Process each connected component
            for component_id in 1:num_components
                local component_mask = labeled .== component_id
                local pixel_coords = findall(component_mask)
                
                if isempty(pixel_coords)
                    continue
                end
                
                # Extract coordinates
                local row_indices = Float64[p[1] for p in pixel_coords]
                local col_indices = Float64[p[2] for p in pixel_coords]
                
                # Compute centroid
                local centroid_row = sum(row_indices) / length(row_indices)
                local centroid_col = sum(col_indices) / length(col_indices)
                
                # Center coordinates
                local centered_rows = row_indices .- centroid_row
                local centered_cols = col_indices .- centroid_col
                
                # Compute covariance matrix for PCA
                local n = length(centered_rows)
                local cov_matrix = [
                    sum(centered_rows .* centered_rows) / n   sum(centered_rows .* centered_cols) / n;
                    sum(centered_rows .* centered_cols) / n   sum(centered_cols .* centered_cols) / n
                ]
                
                # Compute eigenvectors (principal axes)
                local eigen_result = eigen(cov_matrix)
                local principal_axes = eigen_result.vectors
                
                # Project onto principal axes
                local proj_axis1 = centered_rows .* principal_axes[1, 2] .+ centered_cols .* principal_axes[2, 2]
                local proj_axis2 = centered_rows .* principal_axes[1, 1] .+ centered_cols .* principal_axes[2, 1]
                
                # Find extents
                local min_proj1, max_proj1 = extrema(proj_axis1)
                local min_proj2, max_proj2 = extrema(proj_axis2)
                
                # Calculate oriented bounding box dimensions
                local rotated_width = max_proj1 - min_proj1
                local rotated_height = max_proj2 - min_proj2
                
                # Calculate aspect ratio
                local aspect_ratio = if min(rotated_width, rotated_height) > 0
                    max(rotated_width, rotated_height) / min(rotated_width, rotated_height)
                else
                    1.0
                end
                
                # Store metrics
                push!(bbox_metrics[class][:widths], Float64(rotated_width))
                push!(bbox_metrics[class][:heights], Float64(rotated_height))
                push!(bbox_metrics[class][:aspect_ratios], aspect_ratio)
            end
        end
    end
    
    # Compute aggregate statistics
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
    
    return BoundingBoxStatistics(
        collect(bbox_classes),
        bbox_metrics,
        bbox_statistics
    )
end

# ============================================================================
# Channel Statistics
# ============================================================================

"""
    compute_channel_statistics(sets, input_type) -> ChannelStatistics

Compute RGB channel statistics across all images.

# Arguments
- `sets`: Vector of (input, output, index) tuples
- `input_type`: Input image type with channel definitions

# Returns
- `ChannelStatistics` struct with mean and skewness metrics
"""
function compute_channel_statistics(sets, input_type)
    local inputs = [sets[i][1] for i in 1:length(sets)]
    local channel_names = Bas3ImageSegmentation.shape(input_type)
    local num_channels = length(channel_names)
    
    # Initialize storage
    local channel_means_per_image = Dict(channel => Float64[] for channel in channel_names)
    local channel_skewness_per_image = Dict(channel => Float64[] for channel in channel_names)
    
    println("Analyzing $(length(inputs)) input images for channel statistics...")
    
    # Process each image
    for (img_idx, input_image) in enumerate(inputs)
        local input_data = Bas3ImageSegmentation.data(input_image)
        
        # Process each channel
        for (channel_idx, channel) in enumerate(channel_names)
            local channel_data = vec(input_data[:, :, channel_idx])
            
            # Compute statistics
            local channel_mean = mean(channel_data)
            local channel_skew = compute_skewness(channel_data)
            
            push!(channel_means_per_image[channel], channel_mean)
            push!(channel_skewness_per_image[channel], channel_skew)
        end
    end
    
    # Compute global statistics
    local global_channel_stats = Dict{Symbol, NamedTuple}()
    for channel in channel_names
        global_channel_stats[channel] = (
            mean = mean(channel_means_per_image[channel]),
            std = std(channel_means_per_image[channel]),
            skewness = mean(channel_skewness_per_image[channel])
        )
    end
    
    return ChannelStatistics(
        collect(channel_names),
        channel_means_per_image,
        channel_skewness_per_image,
        global_channel_stats
    )
end
