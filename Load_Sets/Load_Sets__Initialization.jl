# Load_Sets__Initialization.jl
# Package initialization and reporter setup

"""
    Load_Sets__Initialization

Initialization module for Load_Sets pipeline.
Handles package loading, reporter initialization, and environment setup.
"""

import Random
import LinearAlgebra: eigen
import Base: abs

# ============================================================================
# Reporter Initialization
# ============================================================================

"""
    initialize_reporters()

Initialize or reuse existing reporters for visualization.

# Returns
- `Dict`: Reporters dictionary (empty or existing)

# Notes
- Stops existing reporters before reinitializing
- Closes all GLMakie windows
- Loads required packages: Bas3Plots, Bas3GLMakie, Bas3ImageSegmentation
- Activates package environment in current directory
"""
const reporters = try
    # Try to reuse existing reporters
    for (key, value) in reporters
        stop(value)
    end
    Bas3GLMakie.GLMakie.closeall()
    reporters
catch
    # Initialize fresh
    println("=== Initializing reporters ===")
    import Pkg
    Pkg.activate(@__DIR__)
    println("Updating packages...")
    Pkg.update()
    println("Resolving dependencies...")
    Pkg.resolve()
    println("Skipping Revise for faster loading...")
    
    println("Loading Bas3Plots...")
    using Bas3Plots
    import Bas3Plots.display
    
    println("Loading Bas3GLMakie...")
    using Bas3GLMakie
    
    println("Loading Bas3_EnvironmentTools (1)...")
    using Bas3_EnvironmentTools
    
    println("Loading Bas3ImageSegmentation...")
    using Bas3ImageSegmentation
    
    println("Loading Bas3ImageSegmentation.Bas3...")
    using Bas3ImageSegmentation.Bas3
    
    println("Loading Bas3ImageSegmentation.Bas3IGABOptimization...")
    using Bas3ImageSegmentation.Bas3IGABOptimization
    
    println("Importing Base functions...")
    import Base.size
    import Base.length
    import Base.minimum
    import Base.maximum
    
    println("Loading Random, Mmap, Statistics, LinearAlgebra...")
    using Random
    using Mmap
    using Statistics
    using LinearAlgebra
    
    println("Loading JLD2...")
    using Bas3ImageSegmentation.JLD2
    
    println("Loading Bas3_EnvironmentTools (2)...")
    using Bas3_EnvironmentTools
    
    println("Importing RemoteChannel...")
    import Bas3_EnvironmentTools.Distributed.RemoteChannel
    
    println("=== Reporters initialized ===")
    Dict()
end

# ============================================================================
# Additional Imports
# ============================================================================

# Import conversion function for image type conversion
import Bas3.convert
