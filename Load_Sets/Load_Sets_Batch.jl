import Random
Random.seed!(1234)

println("=== Initializing packages ===")
import Pkg
Pkg.activate(@__DIR__)

println("Loading Bas3ImageSegmentation...")
using Bas3ImageSegmentation
using Bas3ImageSegmentation.Bas3
using Bas3ImageSegmentation.JLD2
import Base.size, Base.length, Base.minimum, Base.maximum
using Random
using Mmap
using Statistics

println("=== Packages loaded ===")

const input_type = @__(Bas3ImageSegmentation.c__Image_Data{Float32,(:red, :green, :blue)})
const raw_output_type = @__(Bas3ImageSegmentation.c__Image_Data{Float32,(:scar, :redness, :hematoma, :necrosis, :background)})
const output_type = @__(Bas3ImageSegmentation.c__Image_Data{Float32,(:foreground, :background)})

import Bas3.convert

base_path = "/mnt/c/Syncthing/Datasets"
source_path = "/mnt/c/Syncthing/MuHa - Bilder"
_total_length = 306
_index_array = shuffle(1:_total_length)

# Determine which images still need processing
existing_files = Set{Int}()
for i in 1:_total_length
    filepath = joinpath(base_path, "original/$(i).jld2")
    if isfile(filepath)
        push!(existing_files, i)
    end
end

images_to_process = [i for i in 1:_total_length if !(i in existing_files)]

if length(images_to_process) == 0
    println("\n=== All 306 images already exist! ===")
    exit(0)
end

println("\n=== Processing Status ===")
println("Total images: $_total_length")
println("Already processed: $(length(existing_files))")
println("Remaining: $(length(images_to_process))")
println("Starting batch processing...\n")

# Process images in batches and save immediately
batch_size = 50
total_batches = ceil(Int, length(images_to_process) / batch_size)

for batch_num in 1:total_batches
    batch_start = (batch_num - 1) * batch_size + 1
    batch_end = min(batch_num * batch_size, length(images_to_process))
    batch_indices = images_to_process[batch_start:batch_end]
    
    println("=== Batch $batch_num/$total_batches (images $(batch_start) to $(batch_end)) ===")
    
    for (idx, image_num) in enumerate(batch_indices)
        global_idx = batch_start + idx - 1
        println("  Loading image $(image_num)/$(_total_length) ($(global_idx)/$(length(images_to_process)) remaining)")
        
        try
            @time begin
                input, output = @__(Bas3ImageSegmentation.load_input_and_output(
                    source_path,
                    _index_array[image_num];
                    input_type=input_type,
                    output_type=raw_output_type,
                    output_collection=true
                ))
            end
            
            # Save immediately after loading
            output_file = joinpath(base_path, "original/$(image_num).jld2")
            println("    Saving to: $(basename(output_file))")
            JLD2.save(output_file, "set", (input, output))
            println("    ✓ Saved successfully")
            
        catch e
            println("    ERROR loading image $(image_num): $e")
            continue
        end
    end
    
    println("Batch $batch_num/$total_batches complete\n")
end

println("\n=== Processing Complete ===")
println("Total images processed: $(length(images_to_process))")
println("Verifying all files exist...")

missing_files = []
for i in 1:_total_length
    filepath = joinpath(base_path, "original/$(i).jld2")
    if !isfile(filepath)
        push!(missing_files, i)
    end
end

if length(missing_files) == 0
    println("✓ SUCCESS: All 306 images are present!")
else
    println("⚠ WARNING: Missing $(length(missing_files)) images: $missing_files")
end
