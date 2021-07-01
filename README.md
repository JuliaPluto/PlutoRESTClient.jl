# PlutoRESTClient.jl
Interact with your Pluto notebooks from other Julia programs!
## How to use
First, make sure you run Pluto with the following configuration option to expose the "What you see is what you REST" API.
```julia
import Pluto
Pluto.run(; enable_rest=true)
```
### Examples
```julia
using PlutoRESTClient

nb = PlutoNotebook("MyExampleNotebook.jl")
# Alternatively, if Pluto is running somewhere on the internet...
nb = PlutoNotebook("MyExampleNotebook.jl", "http://example.com:1234")

# Gets the value of a variable named `a` from MyExampleNotebook.jl
nb.a
# Gets the value of a variable named `some_other_variable`
nb.some_other_variable

# Calls a function called `my_add` defined in MyExampleNotebook.jl
nb.my_add(1, 2)
# Calls a function called `my_subtract` defined in MyExampleNotebook.jl
nb.my_subtract(1, 2)

# Updates the values of `a` and `b`
# Returns the new value of `c` after the changes
nb(; a=3, b=4).c
