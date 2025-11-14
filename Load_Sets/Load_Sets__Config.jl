# Load_Sets__Config.jl
# Configuration constants and path resolution utilities

"""
    Load_Sets__Config

Configuration module for Load_Sets pipeline.
Contains type definitions, path resolution, and base paths.
"""

# ============================================================================
# Type Definitions
# ============================================================================

const input_type = @__(Bas3ImageSegmentation.c__Image_Data{Float32,(:red, :green, :blue)})
const raw_output_type = @__(Bas3ImageSegmentation.c__Image_Data{Float32,(:scar, :redness, :hematoma, :necrosis, :background)})
const output_type = @__(Bas3ImageSegmentation.c__Image_Data{Float32,(:foreground, :background)})

# ============================================================================
# Path Resolution (Windows/WSL Cross-Platform Support)
# ============================================================================

"""
    resolve_path(relative_path::String) -> String

Convert paths between Windows and WSL formats.

# Platform Behavior
- **Windows**: Converts `/mnt/c/` to `C:\\`
- **Linux/WSL**: Converts `C:/` to `/mnt/c/`

# Examples
```julia
# On Windows
resolve_path("/mnt/c/Users/data") → "C:\\Users\\data"

# On WSL
resolve_path("C:/Users/data") → "/mnt/c/Users/data"
```
"""
function resolve_path(relative_path::String)
    if Sys.iswindows()
        # Running on native Windows
        # Convert /mnt/c/ to C:/ if needed
        # Check if path starts with "/mnt/" (manual check - startswith() hangs in WSL Julia)
        if length(relative_path) >= 5 && 
           relative_path[1] == '/' && 
           relative_path[2] == 'm' && 
           relative_path[3] == 'n' && 
           relative_path[4] == 't' && 
           relative_path[5] == '/'
            drive_letter = uppercase(relative_path[6])
            rest_of_path = replace(relative_path[8:end], "/" => "\\")
            return "$(drive_letter):\\$(rest_of_path)"
        else
            return relative_path
        end
    else
        # Running on Linux/WSL
        # Convert C:/ to /mnt/c/ if needed
        # Check for Windows path format: X:/ or X:\
        if length(relative_path) >= 3
            c = relative_path[1]
            is_windows_path = (c >= 'A' && c <= 'Z' || c >= 'a' && c <= 'z') && 
                             relative_path[2] == ':' && 
                             (relative_path[3] == '/' || relative_path[3] == '\\')
            if is_windows_path
                drive_letter = lowercase(relative_path[1])
                rest_of_path = replace(relative_path[4:end], "\\" => "/")
                return "/mnt/$(drive_letter)/$(rest_of_path)"
            end
        end
        return relative_path
    end
end

# ============================================================================
# Base Paths
# ============================================================================

const base_path = resolve_path("C:/Syncthing/Datasets")
