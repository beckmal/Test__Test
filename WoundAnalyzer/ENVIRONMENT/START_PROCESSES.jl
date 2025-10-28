import Pkg; Pkg.activate(@__DIR__)
using Revise
#import Distributed; Distributed.rmprocs()
using Bas3_EnvironmentTools
#
workers = @start_processes(
    "Master",
            
    "Worker"=>(
        #machine=1,
        environment_path="C:/Users/OsW-x/Julia_Worker/.julia", #TODO: make this optional somehow homedir() ?
        #dir="=@."
    ),
            
    #=
    "Worker"=>(
        address="Julia_Worker@143.93.62.171", 
        shell=:wincmd,
        exe_path="C:/Users/Julia_Worker/AppData/Local/Programs/Julia-1.11.5/bin/julia.exe",
        environment_path="C:/Users/Julia_Worker/.julia",
        #dir="@.",
    ),
            
            
    "Worker"=>(
        address="Julia_Worker@143.93.52.28",
        shell=:wincmd,
        exe_path="C:/Users/Julia_Worker/AppData/Local/Programs/Julia-1.11.5/bin/julia.exe",
        environment_path="C:/Users/Julia_Worker/.julia",
    )
    =#;
    update=false
)