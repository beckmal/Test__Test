using Bas3GLMakie
using Statistics

# Recreate the figure from the sets variable
fgr = Bas3GLMakie.GLMakie.Figure(size=(1200, 600))
Bas3GLMakie.GLMakie.Label(fgr[0, :], "Original Dataset Statistics ($(length(sets)) images)", fontsize=20)

# Calculate statistics
class_names = [:scar, :redness, :hematoma, :necrosis, :background]
total_pixels = sum(length(set[1]) for set in sets)

class_totals = Dict{Symbol, Float64}()
for class in class_names
    total = sum(sum(set[2][class]) for set in sets)
    class_totals[class] = total
end

# Create axes
axs1 = Bas3GLMakie.GLMakie.Axis(
    fgr[1, 1],
    xlabel="Dataset Index",
    ylabel="Proportion of Total Pixels",
    title="Class Proportions per Image"
)

axs2 = Bas3GLMakie.GLMakie.Axis(
    fgr[1, 2],
    xlabel="Class",
    ylabel="Mean Proportion ± Std",
    title="Average Class Distribution"
)

# Plot data
for (i, class) in enumerate(class_names)
    for (idx, set) in enumerate(sets)
        prop = sum(set[2][class]) / total_pixels
        Bas3GLMakie.scatter!(axs1, idx, prop; markersize=10)
    end
end

# Save figure
Bas3GLMakie.GLMakie.save("dataset_statistics.png", fgr)
println("Figure saved to dataset_statistics.png")
