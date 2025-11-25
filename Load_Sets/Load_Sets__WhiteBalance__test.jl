# test_bradford_validation.jl
# Validate Julia Bradford implementation against Python colour-science reference

println("="^60)
println("Bradford White Balance Validation: Julia vs Python")
println("="^60)

using PyCall
using LinearAlgebra

# Import Python colour-science
colour = pyimport("colour")
np = pyimport("numpy")

println("\n[1] colour-science version: ", colour.__version__)

# =============================================================================
# TEST 1: Bradford Matrix Constant
# =============================================================================
println("\n" * "="^60)
println("[TEST 1] Bradford Matrix Constant")
println("="^60)

# Julia Bradford matrix (from Load_Sets__WhiteBalance.jl)
const BRADFORD_JULIA = [0.8951  0.2664 -0.1614;
                       -0.7502  1.7135  0.0367;
                        0.0389 -0.0685  1.0296]

# Python Bradford matrix
CAT_BRADFORD_PY = collect(colour.adaptation.CAT_BRADFORD)

println("\nJulia BRADFORD matrix:")
display(BRADFORD_JULIA)

println("\n\nPython CAT_BRADFORD matrix:")
display(CAT_BRADFORD_PY)

# Compare
matrix_diff = maximum(abs.(BRADFORD_JULIA .- CAT_BRADFORD_PY))
println("\n\nMax absolute difference: ", matrix_diff)
println("Test 1 PASS: ", matrix_diff < 1e-10 ? "YES" : "NO")

# =============================================================================
# TEST 2: Chromatic Adaptation Matrix Computation
# =============================================================================
println("\n" * "="^60)
println("[TEST 2] Chromatic Adaptation Matrix (D65 -> D50)")
println("="^60)

# Standard white points (XYZ, Y=1 normalized)
# D65 and D50 from CIE standard
XYZ_D65 = [0.95047, 1.0, 1.08883]
XYZ_D50 = [0.96422, 1.0, 0.82521]

# Python: Get adaptation matrix
M_py = collect(colour.adaptation.matrix_chromatic_adaptation_VonKries(
    np.array(XYZ_D65), 
    np.array(XYZ_D50), 
    transform="Bradford"
))

# Julia: Compute adaptation matrix (matching our implementation)
const BRADFORD_INV_JULIA = inv(BRADFORD_JULIA)

function compute_bradford_matrix_test(src_xyz, ref_xyz)
    # Transform white points to Bradford cone space
    src_bradford = BRADFORD_JULIA * src_xyz
    ref_bradford = BRADFORD_JULIA * ref_xyz
    
    # Compute diagonal scaling matrix
    scale = zeros(3, 3)
    for i in 1:3
        if abs(src_bradford[i]) > 1e-10
            scale[i, i] = ref_bradford[i] / src_bradford[i]
        else
            scale[i, i] = 1.0
        end
    end
    
    # Combined matrix: Bradford^-1 * Scale * Bradford
    return BRADFORD_INV_JULIA * scale * BRADFORD_JULIA
end

M_julia = compute_bradford_matrix_test(XYZ_D65, XYZ_D50)

println("\nPython adaptation matrix (D65 -> D50):")
display(M_py)

println("\n\nJulia adaptation matrix (D65 -> D50):")
display(M_julia)

adapt_matrix_diff = maximum(abs.(M_julia .- M_py))
println("\n\nMax absolute difference: ", adapt_matrix_diff)
println("Test 2 PASS: ", adapt_matrix_diff < 1e-10 ? "YES" : "NO")

# =============================================================================
# TEST 3: Single Color Adaptation
# =============================================================================
println("\n" * "="^60)
println("[TEST 3] Single Color Adaptation")
println("="^60)

# Test color in XYZ space (example from colour-science docs)
XYZ_test = [0.20654008, 0.12197225, 0.05136952]

# Python: Adapt color
XYZ_adapted_py = collect(colour.adaptation.chromatic_adaptation_VonKries(
    np.array(XYZ_test),
    np.array(XYZ_D65),
    np.array(XYZ_D50),
    transform="Bradford"
))

# Julia: Adapt color using matrix
XYZ_adapted_julia = M_julia * XYZ_test

println("\nInput XYZ: ", XYZ_test)
println("\nPython adapted XYZ: ", XYZ_adapted_py)
println("Julia adapted XYZ:  ", XYZ_adapted_julia)

color_diff = maximum(abs.(XYZ_adapted_julia .- XYZ_adapted_py))
println("\nMax absolute difference: ", color_diff)
println("Test 3 PASS: ", color_diff < 1e-10 ? "YES" : "NO")

# =============================================================================
# TEST 4: Multiple Test Colors
# =============================================================================
println("\n" * "="^60)
println("[TEST 4] Multiple Test Colors (D65 -> D50)")
println("="^60)

# Various test colors spanning color space
test_colors = [
    [0.95047, 1.0, 1.08883],     # D65 white
    [0.5, 0.5, 0.5],             # Mid gray
    [0.4124, 0.2126, 0.0193],    # Red primary
    [0.3576, 0.7152, 0.1192],    # Green primary  
    [0.1805, 0.0722, 0.9505],    # Blue primary
    [0.20654, 0.12197, 0.05137], # Warm skin tone
    [0.01, 0.01, 0.01],          # Near black
    [0.9, 0.95, 0.98],           # Near white
]

println("\nColor               | Python Result        | Julia Result         | Max Diff")
println("-"^80)

max_overall_diff = 0.0
for xyz in test_colors
    py_result = collect(colour.adaptation.chromatic_adaptation_VonKries(
        np.array(xyz),
        np.array(XYZ_D65),
        np.array(XYZ_D50),
        transform="Bradford"
    ))
    
    julia_result = M_julia * xyz
    
    diff = maximum(abs.(julia_result .- py_result))
    global max_overall_diff = max(max_overall_diff, diff)
    
    xyz_str = @sprintf("[%.3f,%.3f,%.3f]", xyz[1], xyz[2], xyz[3])
    py_str = @sprintf("[%.6f,%.6f,%.6f]", py_result[1], py_result[2], py_result[3])
    jl_str = @sprintf("[%.6f,%.6f,%.6f]", julia_result[1], julia_result[2], julia_result[3])
    
    println("$xyz_str | $py_str | $jl_str | $(round(diff, sigdigits=3))")
end

println("\nMax overall difference across all colors: ", max_overall_diff)
println("Test 4 PASS: ", max_overall_diff < 1e-10 ? "YES" : "NO")

# =============================================================================
# TEST 5: Warm Lighting Scenario (A -> D65)
# =============================================================================
println("\n" * "="^60)
println("[TEST 5] Warm Lighting Correction (Illuminant A -> D65)")
println("="^60)

# Illuminant A (incandescent/tungsten, 2856K)
XYZ_A = [1.09850, 1.0, 0.35585]

# Compute adaptation matrix A -> D65
M_A_to_D65_py = collect(colour.adaptation.matrix_chromatic_adaptation_VonKries(
    np.array(XYZ_A), 
    np.array(XYZ_D65), 
    transform="Bradford"
))

M_A_to_D65_julia = compute_bradford_matrix_test(XYZ_A, XYZ_D65)

println("\nPython adaptation matrix (A -> D65):")
display(M_A_to_D65_py)

println("\n\nJulia adaptation matrix (A -> D65):")
display(M_A_to_D65_julia)

warm_matrix_diff = maximum(abs.(M_A_to_D65_julia .- M_A_to_D65_py))
println("\n\nMax absolute difference: ", warm_matrix_diff)
println("Test 5 PASS: ", warm_matrix_diff < 1e-10 ? "YES" : "NO")

# =============================================================================
# SUMMARY
# =============================================================================
println("\n" * "="^60)
println("VALIDATION SUMMARY")
println("="^60)

all_pass = matrix_diff < 1e-10 && 
           adapt_matrix_diff < 1e-10 && 
           color_diff < 1e-10 && 
           max_overall_diff < 1e-10 &&
           warm_matrix_diff < 1e-10

println("\nTest 1 (Bradford Matrix):      ", matrix_diff < 1e-10 ? "PASS" : "FAIL")
println("Test 2 (Adaptation Matrix):    ", adapt_matrix_diff < 1e-10 ? "PASS" : "FAIL")
println("Test 3 (Single Color):         ", color_diff < 1e-10 ? "PASS" : "FAIL")
println("Test 4 (Multiple Colors):      ", max_overall_diff < 1e-10 ? "PASS" : "FAIL")
println("Test 5 (Warm Lighting):        ", warm_matrix_diff < 1e-10 ? "PASS" : "FAIL")

println("\n" * "="^60)
if all_pass
    println("ALL TESTS PASSED - Julia implementation matches Python reference")
else
    println("SOME TESTS FAILED - Review implementation")
end
println("="^60)
