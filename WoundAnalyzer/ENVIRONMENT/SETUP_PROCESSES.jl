import Pkg; Pkg.activate(@__DIR__)
using Revise
#import Distributed; Distributed.rmprocs()
using Bas3_EnvironmentTools
@setup_processes(
    "Master",
    
    "Worker"=>(
        #threads=1,
        #environment_path="C:/Users/OsW-x/Julia_Worker/.julia", #TODO: make this optional somehow homedir() ?
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
    =#
    
    
    
    "Worker"=>(
        address="Julia_Worker@143.93.52.28",
        shell=:wincmd,
        exe_path="C:/Users/Julia_Worker/AppData/Local/Programs/Julia-1.11.5/bin/julia.exe",
        environment_path="C:/Users/Julia_Worker/.julia",
    )
    
)
#TODO: second resolve after develop?

#store all specific directorys in .julia/managed

#start machines and terminate them after setup_processes
#setup local and remote machines
#precompile everything together (supress on intermediate *develop* and *add* calls; dont precompile at all should be happen at the first *using*/*import* statement)
#the environment for the local machine gets localy modified through *develop* and *free* commands
#the environments for the remote machines are set up on the remote machines in a separate directory (specific for the package/workspace)
#set up of the remote machines:
#1. copy the package to the remote machine (in the separate directory)
#2. activate the package/workspace on the remote machine
#3. resolve the workspace
#4. copy packages that are dependencies of the package/workspace to the remote machine when found under *path* on local machine (in the separate directory) and *develop* them to the environment
#