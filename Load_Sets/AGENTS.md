## context managment
if a fact from the AGENTS.md file begins to fade from your context you have to read AGENTS.md again. it is extremly important to check your context frequently and if a fact decays from your context read AGENTS.md again.
## overview tracking
keep a overview in the OVERVIEW.md file especially if anything significant happens.
revist the OVERVIEW.md file frequently. if you become unsure about what happend revist the OVERVIEW.md file read it and verify if its claims can be observed in the workspace.
do not trust what claims the OVERVIEW.md file verify if the claims can be observed in the workspace.
remove everything from the OVERVIEW.md file that you did not directly verify through observation in the workspace. keep only claims that you verified by reading or executing.
only relevant claims should be in the OVERVIEW.md file. remove historical and unnecessary claims immedeatly when you revist.
## julia invocation
```bash
julia [*environment operation file*] --eval="*code to execute*"|--script=*file to execute* [--interactive/-i]
```
julia accepts *environment operation file* as optional positional argument and --eval/-e or --script/-s as required keyword argument and --interactive/-i as optional keyword argument
pass *environment operation file*  to julia if you need to do activate/develop/free operations. chose the correct file wherby the files always operate within the folder of the correct file
pass --interactive/-i to julia if you want to reuse the last session to execute. ommiting --interactive/-i uses a new session to execute.
## run tests
all tests at once:
```bash
julia --script=./Bas3*package to test*/test/runtests.jl
```
specific test:
```bash
julia --script=./Bas3*package to test*/test/runtests_*specific test*.jl
```
## logging usage
many packages define loggers to show insight about the temporal execution state. to gain insight about the temporal execution state of a specific functionality search for a targeted logger definition within the packages the definitions always end with *logger.
a package defines a logger hierarchy of specialized loggers that pass and block log messages. each logger is itself a hierarchy with his child loggers whose always recieve the log messages from the logger itself.
if a *specific logger* is set with 'global_logger(*specific logger*)' the *specific logger* recieves each message and broadcasts each message to it's child loggers the pass and block of the *specific logger* decides which log messages go to the sink of the *specific logger* wherby the sink outputs to .log files.
consider to 'dump_logger(*specific logger*)' or 'flush_logger(*specific logger*)' at characteristic execution steps wherby 'dump_logger' outputs the logger hierarchy states and 'flush_logger' writes the logger hierarchy to .log files when it makes the output more clear.
never read a .log file before knowing it's size. prefer to examine the small .log files before the big .log files.
if a .log file is big only read specific log messages by search for a specific gid or specific gid range
## gite rules
NEVER DO A GIT COMMIT
## code structure
in packages code is loading is done in stages. within a stage code is loaded by intentional definitions to ensure consistency. those intentional definitions serve functionalities. definitions potentially inform about theier intention and belonging to a stage: '*definition*__*intention*__*stage (>=1) that the definition belongs to*' or alternatively '*prefix*__*definition*'
intentions inform what a definition serves for a functionality and can serve:
DEPENDENCY folder/file serves import/using/stub/export definitions
TYPE folder/file combines HIERARCHY_TYPE ADAPTER_TYPE VALUE_TYPE TRAIT_TYPE UNION_TYPE folder/file intentional definitions
HIERARCHY_TYPE folder/file serves abstract type h__* intentional definitions that serve as abstract types for adapter/value/trait types
ADAPTER_TYPE folder/file serves abstract type a__* intentional definitions that serve as adapter types
VALUE_TYPE folder/file serves concrete type v__* intentional definitions that serve as value types
TRAIT_TYPE folder/file serves abstract type t__* intentional definitions that serve as trait types
UNION_TYPE folder/file serves unions u__* composed of other types
METHOD folder/file combines ADAPTER_METHOD VALUE_METHOD TRAIT_METHOD folder/file intentional definitions
ADAPTER_METHOD folder/file serves method definitions for adapter type definitions
VALUE_METHOD folder/file serves method definitions for value types
TRAIT_METHOD folder/file serves method definitions for trait types
MACRO folder/file serves macro definitions
GLOBAL folder/file serves global definitions
intentional definition prefixe:
v__* - concrete value types
t__* - abstract trait types
a__* - abstract adapter types
h__* - abstract hierarchy types (h__ is Base.Any)
intentional definitions are always loaded in a specific order which forms one stage. each stage is loaded in the same order: DEPENDENCY->TYPE->METHOD->MACRO->GLOBAL