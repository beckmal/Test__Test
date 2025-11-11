import Pkg
Pkg.activate(@__DIR__)

using Bas3GLMakie
using Bas3GLMakie.GLMakie
using Bas3GLMakie.GLMakie: Figure, Axis, barplot!, hlines!, band!, text!, axislegend, ylims!, save, Label
using Colors

# Data
classes = ["Background", "Hematoma", "Redness", "Scar", "Necrosis"]
targets = [74.0, 15.0, 5.0, 5.0, 1.0]
before = [98.04, 1.24, 0.63, 0.08, 0.0]
after = [83.67, 13.81, 0.87, 0.68, 0.98]

# Calculate improvements
improvement_factors = [after[i] / max(before[i], 0.01) for i in 1:length(classes)]
improvement_factors[1] = before[1] / after[1]  # For background, reduction is improvement
improvement_factors[5] = Inf  # Necrosis went from 0 to 0.98

# Color scheme
color_target = colorant"#2ecc71"      # Green
color_before = colorant"#e74c3c"      # Red
color_after = colorant"#3498db"       # Blue
color_improvement = colorant"#9b59b6" # Purple

println("Creating visualizations...")

# ============================================================================
# Figure 1: Side-by-side Bar Chart Comparison
# ============================================================================

fig1 = Figure(size=(1400, 800), backgroundcolor=:white)

ax1 = Axis(fig1[1, 1],
    title="Target vs Actual Distribution\n(Before Hybrid Approach)",
    xlabel="Class",
    ylabel="Percentage (%)",
    xticks=(1:5, classes),
    xticklabelrotation=π/4,
    backgroundcolor=:white
)

# Before
positions = collect(1:5)
barplot!(ax1, positions .- 0.2, targets, width=0.35, color=color_target, label="Target")
barplot!(ax1, positions .+ 0.2, before, width=0.35, color=color_before, label="Actual (Before)")

axislegend(ax1, position=:lt)
ylims!(ax1, 0, 105)

ax2 = Axis(fig1[1, 2],
    title="Target vs Actual Distribution\n(After Hybrid Approach)",
    xlabel="Class",
    ylabel="Percentage (%)",
    xticks=(1:5, classes),
    xticklabelrotation=π/4,
    backgroundcolor=:white
)

# After
positions = collect(1:5)
barplot!(ax2, positions .- 0.2, targets, width=0.35, color=color_target, label="Target")
barplot!(ax2, positions .+ 0.2, after, width=0.35, color=color_after, label="Actual (After)")

axislegend(ax2, position=:lt)
ylims!(ax2, 0, 105)

save("/mnt/c/Syncthing/GitLab/Bas3ImageSegmentation/Load_Sets/comparison_sidebyside.png", fig1)
println("✓ Saved: comparison_sidebyside.png")

# ============================================================================
# Figure 2: Grouped Bar Chart - All Three Together
# ============================================================================

fig2 = Figure(size=(1400, 800), backgroundcolor=:white)

ax3 = Axis(fig2[1, 1],
    title="Balanced Augmentation Results Comparison",
    xlabel="Class",
    ylabel="Percentage (%)",
    xticks=(1:5, classes),
    xticklabelrotation=π/4,
    backgroundcolor=:white
)

positions = collect(1:5)
barplot!(ax3, positions .- 0.3, targets, width=0.25, color=color_target, label="Target")
barplot!(ax3, positions, before, width=0.25, color=color_before, label="Before Hybrid")
barplot!(ax3, positions .+ 0.3, after, width=0.25, color=color_after, label="After Hybrid")

axislegend(ax3, position=:lt)
ylims!(ax3, 0, 105)

save("/mnt/c/Syncthing/GitLab/Bas3ImageSegmentation/Load_Sets/comparison_grouped.png", fig2)
println("✓ Saved: comparison_grouped.png")

# ============================================================================
# Figure 3: Improvement Factors
# ============================================================================

fig3 = Figure(size=(1400, 800), backgroundcolor=:white)

ax4 = Axis(fig3[1, 1],
    title="Improvement Factor by Class\n(Higher is Better)",
    xlabel="Class",
    ylabel="Improvement Factor (x)",
    xticks=(1:5, classes),
    xticklabelrotation=π/4,
    backgroundcolor=:white,
    yscale=log10
)

# Cap infinity at 100 for visualization
improvement_display = copy(improvement_factors)
improvement_display[5] = 100.0  # Cap necrosis at 100x

colors_improvement = [
    before[i] > after[i] ? color_improvement : color_improvement 
    for i in 1:5
]

positions = collect(1:5)
barplot!(ax4, positions, improvement_display, color=colors_improvement)

# Add text labels
for i in 1:5
    label_text = if improvement_factors[i] == Inf
        "∞"
    else
        string(round(improvement_factors[i], digits=1), "x")
    end
    
    text!(ax4, i, improvement_display[i] * 1.2, 
          text=label_text, 
          align=(:center, :bottom),
          fontsize=14,
          color=:black)
end

# Add reference line at 1x
hlines!(ax4, [1.0], color=:gray, linestyle=:dash, linewidth=2)

save("/mnt/c/Syncthing/GitLab/Bas3ImageSegmentation/Load_Sets/improvement_factors.png", fig3)
println("✓ Saved: improvement_factors.png")

# ============================================================================
# Figure 4: Deviation from Target
# ============================================================================

fig4 = Figure(size=(1400, 800), backgroundcolor=:white)

ax5 = Axis(fig4[1, 1],
    title="Deviation from Target Distribution\n(Closer to 0 is Better)",
    xlabel="Class",
    ylabel="Deviation from Target (%)",
    xticks=(1:5, classes),
    xticklabelrotation=π/4,
    backgroundcolor=:white
)

deviation_before = before .- targets
deviation_after = after .- targets

positions = collect(1:5)
barplot!(ax5, positions .- 0.2, deviation_before, width=0.35, color=color_before, label="Before")
barplot!(ax5, positions .+ 0.2, deviation_after, width=0.35, color=color_after, label="After")

# Add zero reference line
hlines!(ax5, [0.0], color=:black, linestyle=:dash, linewidth=2)

axislegend(ax5, position=:lt)

save("/mnt/c/Syncthing/GitLab/Bas3ImageSegmentation/Load_Sets/deviation_from_target.png", fig4)
println("✓ Saved: deviation_from_target.png")

# ============================================================================
# Figure 5: Stacked Area Chart (Distribution Over "Time")
# ============================================================================

fig5 = Figure(size=(1400, 800), backgroundcolor=:white)

ax6 = Axis(fig5[1, 1],
    title="Class Distribution Comparison",
    xlabel="Implementation Stage",
    ylabel="Percentage (%)",
    xticks=(1:3, ["Target", "Before\nHybrid", "After\nHybrid"]),
    backgroundcolor=:white
)

# Create stacked data
stages = 1:3
background_stack = [targets[1], before[1], after[1]]
hematoma_stack = [targets[2], before[2], after[2]]
redness_stack = [targets[3], before[3], after[3]]
scar_stack = [targets[4], before[4], after[4]]
necrosis_stack = [targets[5], before[5], after[5]]

# Colors for each class
class_colors = [
    colorant"#ecf0f1",  # Background - light gray
    colorant"#e74c3c",  # Hematoma - red
    colorant"#e67e22",  # Redness - orange
    colorant"#f39c12",  # Scar - yellow
    colorant"#34495e"   # Necrosis - dark gray
]

# Stack from bottom to top
band!(ax6, stages, zeros(3), background_stack, color=class_colors[1], label="Background")
band!(ax6, stages, background_stack, background_stack .+ hematoma_stack, color=class_colors[2], label="Hematoma")
band!(ax6, stages, background_stack .+ hematoma_stack, 
      background_stack .+ hematoma_stack .+ redness_stack, color=class_colors[3], label="Redness")
band!(ax6, stages, background_stack .+ hematoma_stack .+ redness_stack,
      background_stack .+ hematoma_stack .+ redness_stack .+ scar_stack, color=class_colors[4], label="Scar")
band!(ax6, stages, background_stack .+ hematoma_stack .+ redness_stack .+ scar_stack,
      background_stack .+ hematoma_stack .+ redness_stack .+ scar_stack .+ necrosis_stack, 
      color=class_colors[5], label="Necrosis")

axislegend(ax6, position=:rt)
ylims!(ax6, 0, 100)

save("/mnt/c/Syncthing/GitLab/Bas3ImageSegmentation/Load_Sets/distribution_stacked.png", fig5)
println("✓ Saved: distribution_stacked.png")

# ============================================================================
# Figure 6: Combined Summary Figure
# ============================================================================

fig6 = Figure(size=(1800, 1200), backgroundcolor=:white)

# Title
Label(fig6[1, 1:2], "Hybrid Balanced Augmentation - Complete Results",
      fontsize=24, font=:bold, halign=:center)

# Top left: Grouped comparison
ax_summary1 = Axis(fig6[2, 1],
    title="Distribution Comparison",
    xlabel="Class",
    ylabel="Percentage (%)",
    xticks=(1:5, classes),
    xticklabelrotation=π/4
)

positions = collect(1:5)
barplot!(ax_summary1, positions .- 0.3, targets, width=0.25, color=color_target, label="Target")
barplot!(ax_summary1, positions, before, width=0.25, color=color_before, label="Before")
barplot!(ax_summary1, positions .+ 0.3, after, width=0.25, color=color_after, label="After")
axislegend(ax_summary1, position=:lt)
ylims!(ax_summary1, 0, 105)

# Top right: Improvement factors
ax_summary2 = Axis(fig6[2, 2],
    title="Improvement Factor (Log Scale)",
    xlabel="Class",
    ylabel="Improvement (x)",
    xticks=(1:5, classes),
    xticklabelrotation=π/4,
    yscale=log10
)

positions = collect(1:5)
barplot!(ax_summary2, positions, improvement_display, color=color_improvement)
for i in 1:5
    label_text = improvement_factors[i] == Inf ? "∞" : string(round(improvement_factors[i], digits=1), "x")
    text!(ax_summary2, i, improvement_display[i] * 1.2, text=label_text, align=(:center, :bottom), fontsize=12)
end
hlines!(ax_summary2, [1.0], color=:gray, linestyle=:dash)

# Bottom: Deviation from target
ax_summary3 = Axis(fig6[3, 1:2],
    title="Deviation from Target (Closer to 0 is Better)",
    xlabel="Class",
    ylabel="Deviation (%)",
    xticks=(1:5, classes),
    xticklabelrotation=π/4
)

positions = collect(1:5)
barplot!(ax_summary3, positions .- 0.2, deviation_before, width=0.35, color=color_before, label="Before")
barplot!(ax_summary3, positions .+ 0.2, deviation_after, width=0.35, color=color_after, label="After")
hlines!(ax_summary3, [0.0], color=:black, linestyle=:dash, linewidth=2)
axislegend(ax_summary3, position=:lt)

# Add summary statistics
summary_text = """
Key Results:
• Hematoma: 11.1x improvement (1.24% → 13.81%)
• Necrosis: ∞ improvement (0.0% → 0.98%)
• Scar: 8.5x improvement (0.08% → 0.68%)
• Background: Reduced by 14.4% (98.04% → 83.67%)
• Execution time: +35% (11.3s → 15.3s)
• Rejection rate: 0% (adaptive thresholds)
"""

Label(fig6[4, 1:2], summary_text,
      fontsize=14, halign=:left, valign=:top,
      tellwidth=false, tellheight=false)

save("/mnt/c/Syncthing/GitLab/Bas3ImageSegmentation/Load_Sets/complete_summary.png", fig6)
println("✓ Saved: complete_summary.png")

# ============================================================================
# Print Summary
# ============================================================================

println("\n" * "="^70)
println("VISUALIZATION SUMMARY")
println("="^70)
println("\nGenerated 6 visualizations:")
println("  1. comparison_sidebyside.png   - Before/after side-by-side comparison")
println("  2. comparison_grouped.png      - All three distributions grouped")
println("  3. improvement_factors.png     - Improvement multipliers")
println("  4. deviation_from_target.png   - How far from target")
println("  5. distribution_stacked.png    - Stacked area chart")
println("  6. complete_summary.png        - Combined summary figure")
println("\nAll files saved to:")
println("  /mnt/c/Syncthing/GitLab/Bas3ImageSegmentation/Load_Sets/")
println("="^70)
