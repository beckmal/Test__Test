# ============================================================================
# Load_Sets__Augment_SampleGallery_UI.jl
# ============================================================================
# Interactive UI component for displaying sample augmented images.
# Features: 
#   - Button to load new random samples
#   - Input image with overlaid segmentation mask (50% transparency)
#   - Equal image spacing with uniform axis sizes
#
# Usage:
#   include("Load_Sets__Augment_SampleGallery_UI.jl")
#   fig = create_augment_sample_gallery_figure(all_metadata, output_dir)
#   display(fig)
# ============================================================================

"""
    get_image_data_for_display(img)

Extract raw data array from image type for display.
"""
function get_image_data_for_display(img)
    if hasfield(typeof(img), :data)
        return img.data
    else
        return data(img)
    end
end

"""
    input_to_rgba_matrix(input_image)

Convert input image to RGBA matrix for GLMakie display.
"""
function input_to_rgba_matrix(input_image)
    rgb_data = get_image_data_for_display(input_image)
    img_matrix = [Bas3GLMakie.GLMakie.RGBA(
        rgb_data[i, j, 1], 
        rgb_data[i, j, 2], 
        rgb_data[i, j, 3],
        1.0f0  # Full opacity
    ) for i in 1:size(rgb_data, 1), j in 1:size(rgb_data, 2)]
    return Bas3GLMakie.GLMakie.rotr90(img_matrix)
end

"""
    output_to_rgba_matrix(output_image; alpha=0.5f0)

Convert output segmentation mask to RGBA matrix with transparency.
Colors: Scar=Red, Redness=Green, Hematoma=Blue, Necrosis=Yellow
Background pixels (all zeros) are fully transparent.
"""
function output_to_rgba_matrix(output_image; alpha::Float32=0.5f0)
    output_data = get_image_data_for_display(output_image)
    mask_matrix = [begin
        r = output_data[i, j, 1] + output_data[i, j, 4]  # scar (red) + necrosis (dark red)
        g = output_data[i, j, 2]                          # redness (green) 
        b = output_data[i, j, 3]                          # hematoma (blue)
        # Only show alpha where there's actual mask content (non-background)
        has_content = (r > 0 || g > 0 || b > 0)
        Bas3GLMakie.GLMakie.RGBA(r, g, b, has_content ? alpha : 0.0f0)
    end for i in 1:size(output_data, 1), j in 1:size(output_data, 2)]
    return Bas3GLMakie.GLMakie.rotr90(mask_matrix)
end

"""
    select_gallery_samples(target_classes, n_samples=10)

Select random samples: one from each class + random samples to fill.

# Arguments
- `target_classes` - Vector of target class symbols for all samples
- `n_samples` - Total number of samples to select (default: 10)

# Returns
Vector of sample indices
"""
function select_gallery_samples(target_classes::Vector{Symbol}, n_samples::Int=10)
    indices = Int[]
    
    # One from each class
    for tc in AUGMENT_CLASS_ORDER
        class_indices = findall(==(tc), target_classes)
        if !isempty(class_indices)
            push!(indices, rand(class_indices))
        end
    end
    
    # Fill remaining with random samples
    n_total = length(target_classes)
    while length(indices) < n_samples
        idx = rand(1:n_total)
        if !(idx in indices)
            push!(indices, idx)
        end
    end
    
    return indices
end

"""
    create_augment_sample_gallery_figure(all_metadata, output_dir)

Create a figure showing sample augmented images with overlaid segmentation masks.
Always includes button to load new random samples.

# Arguments
- `all_metadata::Vector{AugmentationMetadata}` - Metadata for all augmented samples
- `output_dir::String` - Directory containing augmented image files

# Returns
GLMakie Figure with 10 sample images (input with 50% transparent mask overlay) in 2x5 grid
"""
function create_augment_sample_gallery_figure(
    all_metadata::Vector{AugmentationMetadata},
    output_dir::String;
    interactive::Bool = true  # Kept for backwards compatibility, always interactive now
)
    target_classes = [m.target_class for m in all_metadata]
    n_total = length(all_metadata)
    
    # Select initial samples
    current_indices = select_gallery_samples(target_classes)
    
    # Load sample data
    function load_gallery_samples(indices)
        samples = Dict{Int, Any}()
        for idx in indices
            filepath = joinpath(output_dir, "$(idx).jld2")
            if isfile(filepath)
                set_data = JLD2.load(filepath)["set"]
                samples[idx] = (input=set_data[1], output=set_data[2])
            end
        end
        return samples
    end
    
    current_samples = load_gallery_samples(current_indices)
    
    # Create figure with fixed size and explicit column gaps
    fig = Bas3GLMakie.GLMakie.Figure(size=(2000, 900))
    
    # Title - spans all 5 columns
    Bas3GLMakie.GLMakie.Label(
        fig[1, 1:5], 
        "Sample Augmented Images (Input + 50% Mask Overlay)", 
        fontsize=24, 
        font=:bold
    )
    
    # Button row - centered
    new_samples_button = Bas3GLMakie.GLMakie.Button(
        fig[2, 2:3], 
        label="Load New Random Samples", 
        fontsize=14
    )
    status_label = Bas3GLMakie.GLMakie.Label(
        fig[2, 4:5], 
        "Samples: $(join(current_indices[1:min(5, length(current_indices))], ", "))...", 
        fontsize=10
    )
    
    # Create Observables for reactive updates
    input_observables = [Bas3GLMakie.GLMakie.Observable(zeros(Bas3GLMakie.GLMakie.RGBA{Float32}, 1, 1)) for _ in 1:10]
    mask_observables = [Bas3GLMakie.GLMakie.Observable(zeros(Bas3GLMakie.GLMakie.RGBA{Float32}, 1, 1)) for _ in 1:10]
    title_observables = [Bas3GLMakie.GLMakie.Observable("Sample #0") for _ in 1:10]
    label_observables = [Bas3GLMakie.GLMakie.Observable("") for _ in 1:10]
    # Observables for image coordinate ranges (tuple format: (start, stop))
    x_range_observables = [Bas3GLMakie.GLMakie.Observable((0.5, 1.5)) for _ in 1:10]
    y_range_observables = [Bas3GLMakie.GLMakie.Observable((0.5, 1.5)) for _ in 1:10]
    
    axes_list = []
    
    # Fixed axis size for uniform spacing
    axis_width = 360
    axis_height = 180
    
    # Set uniform column widths
    for col in 1:5
        Bas3GLMakie.GLMakie.colsize!(fig.layout, col, Bas3GLMakie.GLMakie.Fixed(400))
    end
    
    for plot_idx in 1:10
        row = div(plot_idx - 1, 5)  # 0 or 1
        col = mod(plot_idx - 1, 5) + 1  # 1 to 5
        
        # Row 3 for first row of images, Row 5 for second row
        fig_row = row == 0 ? 3 : 5
        
        # Single axis per sample with overlaid images - uniform size
        ax = Bas3GLMakie.GLMakie.Axis(
            fig[fig_row, col], 
            title=title_observables[plot_idx], 
            titlesize=11,
            width=axis_width,
            height=axis_height
        )
        Bas3GLMakie.GLMakie.hidedecorations!(ax)
        Bas3GLMakie.GLMakie.hidespines!(ax)
        
        # Input image (bottom layer, full opacity) - use explicit coordinate ranges
        Bas3GLMakie.GLMakie.image!(ax, x_range_observables[plot_idx], y_range_observables[plot_idx], input_observables[plot_idx])
        # Mask overlay (top layer, 50% transparency on non-background)
        Bas3GLMakie.GLMakie.image!(ax, x_range_observables[plot_idx], y_range_observables[plot_idx], mask_observables[plot_idx])
        
        push!(axes_list, ax)
        
        # Metadata label below each image (row 4 for first row, row 6 for second)
        label_row = row == 0 ? 4 : 6
        Bas3GLMakie.GLMakie.Label(
            fig[label_row, col], 
            label_observables[plot_idx], 
            fontsize=9, 
            halign=:center
        )
    end
    
    # Update function
    function update_gallery!(indices, samples)
        for (plot_idx, aug_idx) in enumerate(indices[1:min(10, length(indices))])
            if haskey(samples, aug_idx)
                input_image = samples[aug_idx].input
                output_image = samples[aug_idx].output
                m = all_metadata[aug_idx]
                
                input_rgba = input_to_rgba_matrix(input_image)
                mask_rgba = output_to_rgba_matrix(output_image; alpha=0.5f0)
                
                # Get image dimensions (after rotr90, height is cols, width is rows)
                img_height, img_width = size(input_rgba)
                
                # Update coordinate ranges to match image size (tuple format for ImageLike)
                x_range_observables[plot_idx][] = (0.5, img_width + 0.5)
                y_range_observables[plot_idx][] = (0.5, img_height + 0.5)
                
                # Update image data
                input_observables[plot_idx][] = input_rgba
                mask_observables[plot_idx][] = mask_rgba
                
                # Update axis limits to match image
                ax = axes_list[plot_idx]
                Bas3GLMakie.GLMakie.xlims!(ax, 0.5, img_width + 0.5)
                Bas3GLMakie.GLMakie.ylims!(ax, 0.5, img_height + 0.5)
                
                # Title with growth metrics
                title_observables[plot_idx][] = "#$(aug_idx) $(m.target_class) | $(m.size_multiplier)× ($(m.patch_height)×$(m.patch_width))"
                
                # Detailed label
                label_observables[plot_idx][] = "Src:$(m.source_index) | FG:$(round(m.actual_fg_percentage,digits=1))% | Rot:$(round(Int,m.rotation_angle))° | Scale:$(round(m.scale_factor,digits=2))"
            end
        end
    end
    
    # Initial update
    update_gallery!(current_indices, current_samples)
    
    # Button callback
    Bas3GLMakie.GLMakie.on(new_samples_button.clicks) do _
        println("Loading new random samples...")
        new_indices = select_gallery_samples(target_classes)
        new_samples = load_gallery_samples(new_indices)
        update_gallery!(new_indices, new_samples)
        status_label.text[] = "Samples: $(join(new_indices[1:min(5, length(new_indices))], ", "))..."
        println("  Loaded samples: $(new_indices)")
    end
    
    # Legend at bottom (row 7)
    legend_text = "Mask Colors: Scar(Red) | Redness(Green) | Hematoma(Blue) | Necrosis(Yellow)"
    Bas3GLMakie.GLMakie.Label(fig[7, 1:5], legend_text, fontsize=12, halign=:center)
    
    return fig
end

"""
    save_augment_sample_gallery_figure(fig, output_path)

Save the sample gallery figure to a file.
"""
function save_augment_sample_gallery_figure(fig, output_path::String)
    Bas3GLMakie.GLMakie.save(output_path, fig)
    println("Saved: $(output_path)")
end

println("  Load_Sets__Augment_SampleGallery_UI loaded")
