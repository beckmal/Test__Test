
import Pkg; Pkg.activate(@__DIR__)
using Revise
using Bas3_EnvironmentTools
@develop(
    "Revise";
    path="../../../",
    precompile=false
)
#add explicitly listed packages to project (track in Develop.toml)
#develop all packages found in the path that are part of the projects dependencies (track in Develop.toml)
#track in Develop.toml records all packages that were added or developed through @develop that where not already in the project
#subsequent @develop calls only extend Develop.toml with new packages