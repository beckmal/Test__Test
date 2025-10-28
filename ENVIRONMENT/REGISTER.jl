import Pkg; Pkg.activate(@__DIR__)
using Bas3_EnvironmentTools
@register(;
    message="commit"
)
#remove all packages tracked by Develop.toml
#operates on .. directory^
#git commit
#modify .gitignore to ignore all Manifest.toml files in sub directories expect explicitly listed ones