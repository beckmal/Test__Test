# Augment_Sets__SampleGallery_StatisticsUI.jl
# Interactive UI for displaying sample augmented images with metadata
# Displays: 10 sample images with input and segmentation mask, one from each class
# Features: Button to load new random samples

import Random

# ============================================================================
# Environment Setup
# ============================================================================

const _env_gallery = try
    _env_gallery
catch
    println("=== Initializing Sample Gallery UI ===")
    import Pkg
    Pkg.activate(@__DIR__)
    Pkg.resolve()
    println("=== Environment activated ===")
    Dict()
end

# Always import these (outside try/catch to ensure they're available)
println("Loading Bas3GLMakie...")
using Bas3GLMakie
using Bas3GLMakie.GLMakie
const GLM = Bas3GLMakie.GLMakie  # Alias for convenience

println("Loading Bas3ImageSegmentation...")
using Bas3ImageSegmentation
using Bas3ImageSegmentation.JLD2
import Bas3ImageSegmentation.Bas3

println("Loading Statistics...")
using Statistics

# Helper to extract data from image types
function get_image_data(img)
    if hasfield(typeof(img), :data)
        return img.data
    else
        return Bas3.data(img)
    end
end

# ============================================================================
# Data Loading
# ============================================================================

# Platform-independent path resolution
function resolve_data_paths_gal()
    # Try Windows paths first
    win_meta = raw"C:\Syncthing\Datasets\augmented_balanced_metadata"
    win_data = raw"C:\Syncthing\Datasets\augmented_balanced"
    if isdir(win_meta) && isdir(win_data)
        return win_meta, win_data
    end
    
    # Try WSL paths
    wsl_meta = "/mnt/c/Syncthing/Datasets/augmented_balanced_metadata"
    wsl_data = "/mnt/c/Syncthing/Datasets/augmented_balanced"
    if isdir(wsl_meta) && isdir(wsl_data)
        return wsl_meta, wsl_data
    end
    
    error("Could not find data directories. Tried Windows and WSL paths.")
end

const metadata_dir_gal, output_dir_gal = resolve_data_paths_gal()
println("Resolved metadata directory: $(metadata_dir_gal)")
println("Resolved output directory: $(output_dir_gal)")

const summary_file_gal = joinpath(metadata_dir_gal, "augmentation_summary.jld2")
println("Loading: $(summary_file_gal)")

const summary_data_gal = JLD2.load(summary_file_gal)
const all_metadata_gal = summary_data_gal["all_metadata"]
println("Loaded $(length(all_metadata_gal)) metadata entries")

# Extract target classes
const target_classes_gal = [m.target_class for m in all_metadata_gal]
const class_order_gal = [:scar, :redness, :hematoma, :necrosis, :background]
const n_total_samples = length(all_metadata_gal)

# ============================================================================
# Helper Functions
# ============================================================================

# Select new random samples: one from each class + random samples to fill 10
function select_random_samples()
    indices = Int[]
    for tc in class_order_gal
        class_indices = findall(==(tc), target_classes_gal)
        if !isempty(class_indices)
            push!(indices, rand(class_indices))
        end
    end
    
    # Add more random samples until we have 10
    while length(indices) < 10
        idx = rand(1:n_total_samples)
        if !(idx in indices)
            push!(indices, idx)
        end
    end
    return indices
end

# Load sample data for given indices
function load_samples(indices)
    samples = Dict{Int, Any}()
    for idx in indices
        filepath = joinpath(output_dir_gal, "$(idx).jld2")
        if isfile(filepath)
            set_data = JLD2.load(filepath)["set"]
            samples[idx] = (input=set_data[1], output=set_data[2])
        end
    end
    return samples
end

# Convert input image to RGB matrix for display
function input_to_rgb_matrix(input_image)
    rgb_data = get_image_data(input_image)
    img_matrix = [GLM.RGB(rgb_data[i, j, 1], rgb_data[i, j, 2], rgb_data[i, j, 3]) 
                  for i in 1:size(rgb_data, 1), j in 1:size(rgb_data, 2)]
    return GLM.rotr90(img_matrix)
end

# Convert output mask to RGB matrix for display
function output_to_rgb_matrix(output_image)
    output_data = get_image_data(output_image)
    mask_matrix = [GLM.RGB(
        output_data[i, j, 1] + output_data[i, j, 4],  # scar (red) + necrosis (dark red)
        output_data[i, j, 2],                          # redness (green) 
        output_data[i, j, 3]                           # hematoma (blue)
    ) for i in 1:size(output_data, 1), j in 1:size(output_data, 2)]
    return GLM.rotr90(mask_matrix)
end

# ============================================================================
# Initial Sample Selection
# ============================================================================

println("Selecting initial gallery samples...")
current_indices = select_random_samples()
current_samples = load_samples(current_indices)
println("Loaded $(length(current_samples)) sample images")

# ============================================================================
# Figure Creation
# ============================================================================

println("Creating Sample Gallery figure...")

fig = GLM.Figure(size=(2000, 1500))

# Title row
fig[0, :] = GLM.Label(fig, "Sample Augmented Images with Parameters", fontsize=24, font=:bold)

# Button row at the top
new_samples_button = GLM.Button(fig[1, 2:3], label="Neue Zufällige Samples Laden", fontsize=14)
status_label = GLM.Label(fig[1, 4:5], "Samples: $(join(current_indices[1:5], ", "))...", fontsize=10)

# Create Observables for each image slot (10 slots: 5 columns x 2 rows of input+mask pairs)
input_observables = [GLM.Observable(zeros(GLM.RGB{Float32}, 1, 1)) for _ in 1:10]
mask_observables = [GLM.Observable(zeros(GLM.RGB{Float32}, 1, 1)) for _ in 1:10]
title_observables = [GLM.Observable("Sample #0") for _ in 1:10]

# Create axes for the gallery (rows 2-5 for images: 2 rows of input, 2 rows of masks)
axes_input = []
axes_mask = []

for plot_idx in 1:10
    row = div(plot_idx - 1, 5) + 1  # 1 or 2
    col = mod(plot_idx - 1, 5) + 1  # 1-5
    
    # Input image axis (rows 2, 4)
    ax_input = GLM.Axis(fig[row*2, col], aspect=GLM.DataAspect(), title=title_observables[plot_idx], titlesize=10)
    GLM.hidedecorations!(ax_input)
    GLM.image!(ax_input, input_observables[plot_idx])
    push!(axes_input, ax_input)
    
    # Mask axis (rows 3, 5)
    ax_mask = GLM.Axis(fig[row*2+1, col], aspect=GLM.DataAspect())
    GLM.hidedecorations!(ax_mask)
    GLM.image!(ax_mask, mask_observables[plot_idx])
    push!(axes_mask, ax_mask)
end

# Function to update the gallery display
function update_gallery!(indices, samples)
    for (plot_idx, aug_idx) in enumerate(indices[1:min(10, length(indices))])
        if haskey(samples, aug_idx)
            input_image = samples[aug_idx].input
            output_image = samples[aug_idx].output
            m = all_metadata_gal[aug_idx]
            
            # Update observables
            input_observables[plot_idx][] = input_to_rgb_matrix(input_image)
            mask_observables[plot_idx][] = output_to_rgb_matrix(output_image)
            title_observables[plot_idx][] = "#$(aug_idx) $(m.target_class)"
            
            # Reset axis limits
            GLM.autolimits!(axes_input[plot_idx])
            GLM.autolimits!(axes_mask[plot_idx])
        end
    end
end

# Initial gallery update
update_gallery!(current_indices, current_samples)

# ============================================================================
# Button Callback
# ============================================================================

GLM.on(new_samples_button.clicks) do _
    println("Loading new random samples...")
    
    # Select new random samples
    global current_indices = select_random_samples()
    global current_samples = load_samples(current_indices)
    
    # Update the gallery
    update_gallery!(current_indices, current_samples)
    
    # Update status label
    status_label.text[] = "Samples: $(join(current_indices[1:5], ", "))..."
    
    println("  Loaded samples: $(current_indices)")
end

# ============================================================================
# Display
# ============================================================================

println("Displaying Sample Gallery UI...")
display(fig)

println("\n✓ Sample Gallery UI displayed successfully!")
println("  - 10 sample images shown (5 per row)")
println("  - Input images + segmentation masks")
println("  - One sample from each class + random samples")
println("  - Click 'Neue Zufällige Samples Laden' for new random samples")
println("  - Close the window to exit")
