# ============================================================================
# Load_Sets__Augment_SampleGallery_UI.jl
# ============================================================================
# Interactive UI component for displaying sample augmented images.
# Features: Button to load new random samples
#
# Usage:
#   include("Load_Sets__Augment_SampleGallery_UI.jl")
#   fig = create_augment_sample_gallery_figure(all_metadata, output_dir; interactive=true)
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
    input_to_rgb_matrix(input_image)

Convert input image to RGB matrix for GLMakie display.
"""
function input_to_rgb_matrix(input_image)
    rgb_data = get_image_data_for_display(input_image)
    img_matrix = [Bas3GLMakie.GLMakie.RGB(rgb_data[i, j, 1], rgb_data[i, j, 2], rgb_data[i, j, 3]) 
                  for i in 1:size(rgb_data, 1), j in 1:size(rgb_data, 2)]
    return Bas3GLMakie.GLMakie.rotr90(img_matrix)
end

"""
    output_to_rgb_matrix(output_image)

Convert output segmentation mask to RGB matrix for display.
Colors: Scar=Red, Redness=Green, Hematoma=Blue, Necrosis=Yellow
"""
function output_to_rgb_matrix(output_image)
    output_data = get_image_data_for_display(output_image)
    mask_matrix = [Bas3GLMakie.GLMakie.RGB(
        output_data[i, j, 1] + output_data[i, j, 4],  # scar (red) + necrosis (dark red)
        output_data[i, j, 2],                          # redness (green) 
        output_data[i, j, 3]                           # hematoma (blue)
    ) for i in 1:size(output_data, 1), j in 1:size(output_data, 2)]
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
    create_augment_sample_gallery_figure(all_metadata, output_dir; interactive=false)

Create a figure showing sample augmented images with metadata.

# Arguments
- `all_metadata::Vector{AugmentationMetadata}` - Metadata for all augmented samples
- `output_dir::String` - Directory containing augmented image files
- `interactive::Bool` - If true, adds button to load new random samples (default: false)

# Returns
GLMakie Figure with 10 sample images (input + mask pairs in 5x4 grid)
"""
function create_augment_sample_gallery_figure(
    all_metadata::Vector{AugmentationMetadata},
    output_dir::String;
    interactive::Bool = false
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
    
    # Create figure
    fig = Bas3GLMakie.GLMakie.Figure(size=(2000, 1500))
    
    # Title
    Bas3GLMakie.GLMakie.Label(
        fig[0, :], 
        "Sample Augmented Images with Parameters", 
        fontsize=24, 
        font=:bold
    )
    
    if interactive
        # Button row
        new_samples_button = Bas3GLMakie.GLMakie.Button(
            fig[1, 2:3], 
            label="Neue Zufällige Samples Laden", 
            fontsize=14
        )
        status_label = Bas3GLMakie.GLMakie.Label(
            fig[1, 4:5], 
            "Samples: $(join(current_indices[1:min(5, length(current_indices))], ", "))...", 
            fontsize=10
        )
        
        # Create Observables for reactive updates
        input_observables = [Bas3GLMakie.GLMakie.Observable(zeros(Bas3GLMakie.GLMakie.RGB{Float32}, 1, 1)) for _ in 1:10]
        mask_observables = [Bas3GLMakie.GLMakie.Observable(zeros(Bas3GLMakie.GLMakie.RGB{Float32}, 1, 1)) for _ in 1:10]
        title_observables = [Bas3GLMakie.GLMakie.Observable("Sample #0") for _ in 1:10]
        
        axes_input = []
        axes_mask = []
        
        for plot_idx in 1:10
            row = div(plot_idx - 1, 5) + 1
            col = mod(plot_idx - 1, 5) + 1
            
            # Input image axis (rows 2, 4)
            ax_input = Bas3GLMakie.GLMakie.Axis(
                fig[row*2, col], 
                aspect=Bas3GLMakie.GLMakie.DataAspect(), 
                title=title_observables[plot_idx], 
                titlesize=10
            )
            Bas3GLMakie.GLMakie.hidedecorations!(ax_input)
            Bas3GLMakie.GLMakie.image!(ax_input, input_observables[plot_idx])
            push!(axes_input, ax_input)
            
            # Mask axis (rows 3, 5)
            ax_mask = Bas3GLMakie.GLMakie.Axis(
                fig[row*2+1, col], 
                aspect=Bas3GLMakie.GLMakie.DataAspect()
            )
            Bas3GLMakie.GLMakie.hidedecorations!(ax_mask)
            Bas3GLMakie.GLMakie.image!(ax_mask, mask_observables[plot_idx])
            push!(axes_mask, ax_mask)
        end
        
        # Update function
        function update_gallery!(indices, samples)
            for (plot_idx, aug_idx) in enumerate(indices[1:min(10, length(indices))])
                if haskey(samples, aug_idx)
                    input_image = samples[aug_idx].input
                    output_image = samples[aug_idx].output
                    m = all_metadata[aug_idx]
                    
                    input_observables[plot_idx][] = input_to_rgb_matrix(input_image)
                    mask_observables[plot_idx][] = output_to_rgb_matrix(output_image)
                    title_observables[plot_idx][] = "#$(aug_idx) $(m.target_class)"
                    
                    Bas3GLMakie.GLMakie.autolimits!(axes_input[plot_idx])
                    Bas3GLMakie.GLMakie.autolimits!(axes_mask[plot_idx])
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
    else
        # Static version (no button)
        for (plot_idx, aug_idx) in enumerate(current_indices[1:min(10, length(current_indices))])
            row = div(plot_idx - 1, 5) + 1
            col = mod(plot_idx - 1, 5) + 1
            
            if haskey(current_samples, aug_idx)
                input_image = current_samples[aug_idx].input
                output_image = current_samples[aug_idx].output
                m = all_metadata[aug_idx]
                
                # Input image
                ax = Bas3GLMakie.GLMakie.Axis(
                    fig[row*2-1, col], 
                    aspect=Bas3GLMakie.GLMakie.DataAspect(),
                    title="Sample #$(aug_idx)", 
                    titlesize=10
                )
                Bas3GLMakie.GLMakie.image!(ax, input_to_rgb_matrix(input_image))
                Bas3GLMakie.GLMakie.hidedecorations!(ax)
                
                # Mask
                ax_mask = Bas3GLMakie.GLMakie.Axis(
                    fig[row*2, col], 
                    aspect=Bas3GLMakie.GLMakie.DataAspect()
                )
                Bas3GLMakie.GLMakie.image!(ax_mask, output_to_rgb_matrix(output_image))
                Bas3GLMakie.GLMakie.hidedecorations!(ax_mask)
                
                # Metadata label
                param_text = "Src:$(m.source_index) | $(m.target_class)\nRot:$(round(m.rotation_angle,digits=0))° | Scale:$(round(m.scale_factor,digits=2))"
                Bas3GLMakie.GLMakie.Label(fig[row*2+1, col], param_text, fontsize=8, halign=:center)
            end
        end
        
        # Legend
        legend_text = "Classes: Scar(Red) | Redness(Green) | Hematoma(Blue) | Necrosis(Yellow) | Background(Black)"
        Bas3GLMakie.GLMakie.Label(fig[end+1, :], legend_text, fontsize=12, halign=:center)
    end
    
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
