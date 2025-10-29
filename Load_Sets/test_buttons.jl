using GLMakie

# Create a simple test with buttons and textbox
fig = Figure(resolution=(800, 400))

# Create buttons and textbox
prev_button = Button(fig[1, 1], label="← Previous")
textbox = Textbox(fig[1, 2], placeholder="Enter number (1-10)", stored_string="1")
next_button = Button(fig[1, 3], label="Next →")

# Label to show current value
label = Label(fig[2, 1:3], "Current: 1", fontsize=20, halign=:center)

# Test observable to track changes
println("Testing button and textbox callbacks...")

# Textbox callback
on(textbox.stored_string) do str
    println("Textbox callback triggered with value: '$str'")
    idx = tryparse(Int, str)
    if idx !== nothing && idx >= 1 && idx <= 10
        label.text = "Current: $idx"
        println("  → Valid input, updated label to: $idx")
    else
        label.text = "Invalid input!"
        println("  → Invalid input")
    end
end

# Previous button callback
on(prev_button.clicks) do n
    println("Previous button clicked (click #$n)")
    current_idx = tryparse(Int, textbox.stored_string[])
    println("  Current textbox value: $(textbox.stored_string[])")
    if current_idx !== nothing && current_idx > 1
        new_idx = current_idx - 1
        println("  Setting textbox to: $new_idx")
        GLMakie.set_close_to!(textbox, string(new_idx))
    else
        println("  Cannot go previous (at minimum or invalid)")
    end
end

# Next button callback
on(next_button.clicks) do n
    println("Next button clicked (click #$n)")
    current_idx = tryparse(Int, textbox.stored_string[])
    println("  Current textbox value: $(textbox.stored_string[])")
    if current_idx !== nothing && current_idx < 10
        new_idx = current_idx + 1
        println("  Setting textbox to: $new_idx")
        GLMakie.set_close_to!(textbox, string(new_idx))
    else
        println("  Cannot go next (at maximum or invalid)")
    end
end

println("\nTest window created. Instructions:")
println("1. Try typing numbers in the textbox (1-10)")
println("2. Click the Previous button")
println("3. Click the Next button")
println("4. Watch the console output to see if callbacks are triggered")
println("\nClose the window when done testing.")

display(fig)
