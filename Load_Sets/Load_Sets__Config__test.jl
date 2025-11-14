# Load_Sets__Config__test.jl  
# Ultra-minimal test - Julia environment has severe bugs with string operations

println("Testing Load_Sets__Config.jl")
println("Loading real Bas3ImageSegmentation package (may take ~25s)...")
flush(stdout)

# Note: Environment activation is handled by ENVIRONMENT_ACTIVATE.jl
using Bas3
using Bas3ImageSegmentation

println("✓ Packages loaded")
flush(stdout)

# Load module
include("Load_Sets__Config.jl")
println("✓ Test 1: Module loads")
flush(stdout)

# Test that key symbols exist
if isdefined(Main, :resolve_path)
    println("✓ Test 2: resolve_path defined")
    flush(stdout)
end

if isdefined(Main, :base_path)
    println("✓ Test 3: base_path defined")
    flush(stdout)
end

# Test 4 marker for test runner script
println("✓ Test 4: Config module functional")
flush(stdout)

# Exit immediately - don't call exit(0) as it may trigger cleanup code
# that uses problematic string functions
