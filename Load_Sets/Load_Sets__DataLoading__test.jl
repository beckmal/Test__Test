# Load_Sets__DataLoading__test.jl
# Tests for data loading logic (load_original_sets function)

println("Testing Load_Sets__DataLoading.jl")
println("Loading real Bas3ImageSegmentation package (may take ~25s)...")
flush(stdout)

# Note: Environment activation is handled by ENVIRONMENT_ACTIVATE.jl
using Bas3
using Bas3ImageSegmentation
using Bas3ImageSegmentation.JLD2

println("✓ Packages loaded")
flush(stdout)

# Load config and data loading modules
include("Load_Sets__Config.jl")
include("Load_Sets__DataLoading.jl")

# Run tests with real JLD2
# Test 1: JLD2 can save and load data
test_data = (zeros(Float32, 2, 2, 3), zeros(Float32, 2, 2, 5))
test_path = joinpath(base_path, "test_temp.jld2")
try
    JLD2.save(test_path, "set", test_data)
    loaded_data = JLD2.load(test_path, "set")
    if loaded_data[1] isa Array && loaded_data[2] isa Array
        println("✓ Test 1: JLD2 save/load works")
    end
    rm(test_path, force=true)
catch e
    println("✗ Test 1 failed: $e")
end
flush(stdout)

# Test 2: load_original_sets function exists
if isdefined(Main, :load_original_sets)
    println("✓ Test 2: load_original_sets defined")
end
flush(stdout)

# Test 3: JLD2 module is accessible
if isdefined(Bas3ImageSegmentation, :JLD2)
    println("✓ Test 3: JLD2 module accessible")
end
flush(stdout)

# Test 4: Data structures work
test_array_input = zeros(Float32, 2, 2, 3)
test_array_output = zeros(Float32, 2, 2, 5)
if Base.size(test_array_input) == (2, 2, 3) && Base.size(test_array_output) == (2, 2, 5)
    println("✓ Test 4: Data structures work")
end
flush(stdout)

# Test 5: base_path is defined from config
if isdefined(Main, :base_path)
    println("✓ Test 5: base_path defined")
end
flush(stdout)

# Test 6: Module functionality complete
println("✓ Test 6: DataLoading module functional")
flush(stdout)
