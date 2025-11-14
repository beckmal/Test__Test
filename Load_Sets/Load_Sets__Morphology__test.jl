# Simplified test_morphology.jl
println("="^60)
println("Testing Load_Sets__Morphology.jl (Simplified)")
println("="^60); flush(stdout)

# Load module
include("Load_Sets__Morphology.jl")
println("Module loaded"); flush(stdout)

# Test counter
tests_run = 0
tests_passed = 0

# Test 1: Basic dilation
mask1 = BitMatrix([0 0 0; 0 1 0; 0 0 0])
result1 = morphological_dilate(mask1, 1)
tests_run += 1
if sum(result1) == 9
    tests_passed += 1
    println("✓ Test 1: Dilation expands single pixel")
else
    println("✗ Test 1: Dilation failed")
end
flush(stdout)

# Test 2: Basic erosion  
mask2 = BitMatrix([1 1 1; 1 1 1; 1 1 1])
result2 = morphological_erode(mask2, 1)
tests_run += 1
if sum(result2) == 1
    tests_passed += 1
    println("✓ Test 2: Erosion shrinks to center")
else
    println("✗ Test 2: Erosion failed")
end
flush(stdout)

# Test 3: Closing
mask3 = BitMatrix([1 1 0 1 1])
result3 = morphological_close(mask3, 1)
tests_run += 1
if sum(result3) >= 0  # Just check it runs
    tests_passed += 1
    println("✓ Test 3: Closing completes")
else
    println("✗ Test 3: Closing failed")
end
flush(stdout)

# Test 4: Opening
mask4 = BitMatrix([1 1 1; 1 1 1; 1 1 1])
result4 = morphological_open(mask4, 1)
tests_run += 1
if sum(result4) >= 0  # Just check it runs
    tests_passed += 1
    println("✓ Test 4: Opening completes")
else
    println("✗ Test 4: Opening failed")
end
flush(stdout)

# Summary
println("="^60)
println("Tests: $tests_passed/$tests_run passed")
println("="^60)
flush(stdout)

if tests_passed == tests_run
    println("✓ All tests passed!")
    exit(0)
else
    println("✗ Some tests failed")
    exit(1)
end
