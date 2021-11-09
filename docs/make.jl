using Pkg
Pkg.develop(PackageSpec(path=".."))
Pkg.instantiate()

using Documenter
using PlutoRESTClient

makedocs(
    sitename = "PlutoRESTClient",
    format = Documenter.HTML(),
    modules = [PlutoRESTClient]
)

# Documenter can also automatically deploy documentation to gh-pages.
# See "Hosting Documentation" and deploydocs() in the Documenter manual
# for more information.
#=deploydocs(
    repo = "<repository url>"
)=#
