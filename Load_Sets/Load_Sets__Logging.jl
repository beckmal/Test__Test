# Load_Sets__Logging.jl
# Logging module for interactive UI debugging

using Dates
using Random

"""
    UILogger

A logger that tracks all interactions with the interactive UI.
Creates a timestamped log file that resets when the UI is recreated.
"""
mutable struct UILogger
    logfile::String
    io::Union{IOStream, Nothing}
    enabled::Bool
    session_id::String
end

# Global logger instance
const GLOBAL_LOGGER = Ref{Union{UILogger, Nothing}}(nothing)

"""
    init_logger(; enabled=true)

Initialize the UI logger. Creates a new log file with timestamp.
Resets the log when called again (e.g., when UI is recreated).

# Arguments
- `enabled::Bool=true`: Whether to enable logging

# Returns
- `UILogger`: The logger instance

# Example
```julia
logger = init_logger()
log_event("UI_CREATED", "Interactive figure initialized")
```
"""
function init_logger(; enabled::Bool=true)
    # Close existing logger if any
    if GLOBAL_LOGGER[] !== nothing && GLOBAL_LOGGER[].io !== nothing
        close(GLOBAL_LOGGER[].io)
    end
    
    # Create new log file with timestamp
    timestamp = Dates.format(Dates.now(), "yyyymmdd_HHMMSS")
    session_id = randstring(6)
    logfile = "Load_Sets_UI_$(timestamp)_$(session_id).log"
    
    # Open log file
    io = enabled ? open(logfile, "w") : nothing
    
    # Create logger
    logger = UILogger(logfile, io, enabled, session_id)
    GLOBAL_LOGGER[] = logger
    
    # Write header
    if enabled
        write_header(logger)
    end
    
    return logger
end

"""
    write_header(logger::UILogger)

Write the log file header with session information.
"""
function write_header(logger::UILogger)
    if !logger.enabled || logger.io === nothing
        return
    end
    
    header = """
    ================================================================================
    Load_Sets Interactive UI Log
    ================================================================================
    Session ID: $(logger.session_id)
    Start Time: $(Dates.now())
    Julia Version: $(VERSION)
    Log File: $(logger.logfile)
    ================================================================================
    
    """
    write(logger.io, header)
    flush(logger.io)
end

"""
    log_event(category::String, message::String; data::Dict=Dict())

Log an event with category, message, and optional data.

# Arguments
- `category::String`: Event category (e.g., "NAVIGATION", "PARAMETER_CHANGE", "ERROR")
- `message::String`: Event description
- `data::Dict`: Optional additional data to log

# Example
```julia
log_event("NAVIGATION", "User navigated to image 2", Dict(:from => 1, :to => 2))
log_event("ERROR", "Failed to update image", Dict(:error => e, :stacktrace => stacktrace()))
```
"""
function log_event(category::String, message::String; data::Dict=Dict())
    logger = GLOBAL_LOGGER[]
    if logger === nothing || !logger.enabled || logger.io === nothing
        return
    end
    
    timestamp = Dates.format(Dates.now(), "yyyy-mm-dd HH:MM:SS.sss")
    
    # Format log entry
    entry = "[$(timestamp)] [$(category)] $(message)\n"
    
    # Add data if present
    if !isempty(data)
        for (key, value) in data
            entry *= "  └─ $(key): $(value)\n"
        end
    end
    
    # Write to log
    write(logger.io, entry)
    flush(logger.io)
    
    # Also print to console for immediate feedback
    print(entry)
end

"""
    log_error(message::String, exception::Exception)

Log an error with full stacktrace.

# Example
```julia
try
    # some code
catch e
    log_error("Failed to process image", e)
end
```
"""
function log_error(message::String, exception::Exception)
    stacktrace_str = sprint(showerror, exception, catch_backtrace())
    log_event("ERROR", message, data=Dict(
        :exception => string(exception),
        :stacktrace => stacktrace_str
    ))
end

"""
    log_observable_change(observable_name::String, old_value, new_value)

Log when an observable changes value.
"""
function log_observable_change(observable_name::String, old_value, new_value)
    log_event("OBSERVABLE", "Observable changed: $(observable_name)", data=Dict(
        :old_value => old_value,
        :new_value => new_value
    ))
end

"""
    log_widget_interaction(widget_name::String, action::String, value=nothing)

Log widget interactions (button clicks, textbox changes, etc.)
"""
function log_widget_interaction(widget_name::String, action::String, value=nothing)
    data = Dict(:action => action)
    if value !== nothing
        data[:value] = value
    end
    log_event("WIDGET", "Widget interaction: $(widget_name)", data=data)
end

"""
    log_function_call(function_name::String, args::Dict=Dict())

Log function calls with arguments.
"""
function log_function_call(function_name::String, args::Dict=Dict())
    log_event("FUNCTION", "Function called: $(function_name)", data=args)
end

"""
    log_navigation(from_image::Int, to_image::Int, method::String)

Log navigation between images.
"""
function log_navigation(from_image::Int, to_image::Int, method::String)
    log_event("NAVIGATION", "Navigated from image $(from_image) to $(to_image)", data=Dict(
        :method => method,
        :from => from_image,
        :to => to_image
    ))
end

"""
    log_parameter_change(parameter::String, old_value, new_value)

Log parameter changes.
"""
function log_parameter_change(parameter::String, old_value, new_value)
    log_event("PARAMETER", "Parameter changed: $(parameter)", data=Dict(
        :old => old_value,
        :new => new_value
    ))
end

"""
    close_logger()

Close the current logger and write footer.
"""
function close_logger()
    logger = GLOBAL_LOGGER[]
    if logger === nothing || logger.io === nothing
        return
    end
    
    if logger.enabled
        footer = """
        
        ================================================================================
        Session End: $(Dates.now())
        ================================================================================
        """
        write(logger.io, footer)
        flush(logger.io)
        close(logger.io)
        
        println("\n[INFO] Log saved to: $(logger.logfile)")
    end
    
    GLOBAL_LOGGER[] = nothing
end

"""
    get_logger()

Get the current logger instance.
"""
function get_logger()
    return GLOBAL_LOGGER[]
end

# Export public functions
export UILogger, init_logger, log_event, log_error, log_observable_change,
       log_widget_interaction, log_function_call, log_navigation,
       log_parameter_change, close_logger, get_logger
