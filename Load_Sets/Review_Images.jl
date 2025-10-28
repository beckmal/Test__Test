import Pkg
Pkg.activate(@__DIR__)

println("Loading packages...")
using Bas3ImageSegmentation.JLD2
using Printf

base_path = "/mnt/c/Syncthing/Datasets/original"

# Function to check image integrity and get basic stats
function review_image(index::Int)
    file_path = joinpath(base_path, "$(index).jld2")
    
    if !isfile(file_path)
        println("  ❌ File missing: $(file_path)")
        return false
    end
    
    try
        # Load the image
        input, output = JLD2.load(file_path, "set")
        
        # Get dimensions
        input_size = size(input)
        output_size = size(output)
        
        # Get data arrays
        input_data = input.data
        output_data = output.data
        
        # Check for NaN or Inf values
        input_invalid = any(isnan.(input_data)) || any(isinf.(input_data))
        output_invalid = any(isnan.(output_data)) || any(isinf.(output_data))
        
        # Get value ranges
        input_min, input_max = extrema(input_data)
        output_min, output_max = extrema(output_data)
        
        # Get annotation channel sums
        if ndims(output_data) == 3
            scar_sum = sum(output_data[:, :, 1])
            redness_sum = sum(output_data[:, :, 2])
            hematoma_sum = sum(output_data[:, :, 3])
            necrosis_sum = sum(output_data[:, :, 4])
            background_sum = sum(output_data[:, :, 5])
            
            println("  Image $(index):")
            println("    Input size: $(input_size)")
            println("    Output size: $(output_size)")
            println("    Input range: [$(round(input_min, digits=4)), $(round(input_max, digits=4))]")
            println("    Output range: [$(round(output_min, digits=4)), $(round(output_max, digits=4))]")
            println("    Invalid values: Input=$(input_invalid), Output=$(output_invalid)")
            println("    Annotations:")
            println("      Scar:       $(round(scar_sum, digits=2)) pixels")
            println("      Redness:    $(round(redness_sum, digits=2)) pixels")
            println("      Hematoma:   $(round(hematoma_sum, digits=2)) pixels")
            println("      Necrosis:   $(round(necrosis_sum, digits=2)) pixels")
            println("      Background: $(round(background_sum, digits=2)) pixels")
        end
        
        return true
    catch e
        println("  ❌ Error loading $(index): $(e)")
        return false
    end
end

println("\n=== Reviewing Sample Images ===\n")

# Review a sample of images
sample_indices = [1, 2, 3, 10, 50, 100, 150, 200, 250, 300, 306]

for idx in sample_indices
    review_image(idx)
    println()
end

println("\n=== Quick Integrity Check of All Images ===\n")

# Quick check all images exist and can be loaded
total_images = 306
successful = 0
failed = []

for idx in 1:total_images
    file_path = joinpath(base_path, "$(idx).jld2")
    
    if !isfile(file_path)
        push!(failed, (idx, "Missing file"))
        continue
    end
    
    try
        JLD2.load(file_path, "set")
        successful += 1
        if idx % 50 == 0
            println("  Checked $(idx)/$(total_images)...")
        end
    catch e
        push!(failed, (idx, "Load error: $(e)"))
    end
end

println("\n=== Summary ===")
println("Total images: $(total_images)")
println("Successfully loaded: $(successful)")
println("Failed: $(length(failed))")

if length(failed) > 0
    println("\nFailed images:")
    for (idx, reason) in failed
        println("  Image $(idx): $(reason)")
    end
else
    println("\n✓ All images loaded successfully!")
end
