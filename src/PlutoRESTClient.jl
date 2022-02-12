module PlutoRESTClient


import HTTP
import Serialization

export PlutoNotebook, @resolve


"""
    evaluate(output::Symbol, filename::AbstractString, host::AbstractString="http://localhost:1234"; kwargs...)

Function equivalent of syntax described in documentation for `PlutoNotebook`.

!!! note
    Avoid using this function when possible in favor of the alternate syntax with [`PlutoNotebook`](@ref)

# Examples
```
julia> PlutoRESTClient.evaluate(:c, "EuclideanDistance.jl"; a=5., b=12.)
13.0
```
"""
function evaluate(output::Symbol, filename::AbstractString, host::AbstractString="http://localhost:1234"; kwargs...)
    request_uri = HTTP.URI("$(host)/v1/notebook/$(HTTP.escapeuri(filename))/eval")

    body = IOBuffer()
    Serialization.serialize(body, Dict{String, Any}(
        "outputs" => [output],
        "inputs" => Dict(kwargs)
    ))
    serialized_body = take!(body)

    response = HTTP.request("POST", request_uri, [
        "Accept" => "application/x-julia",
        "Content-Type" => "application/x-julia"
    ], serialized_body; status_exception=false)

    if response.status >= 300
        throw(ErrorException(String(response.body)))
    end

    return Serialization.deserialize(IOBuffer(response.body))[output]
end

"""
    call(fn_name::Symbol, args::Tuple, kwargs::Iterators.Pairs, filename::AbstractString, host::AbstractString="http://localhost:1234")

Function equivalent of syntax described in documentation for `PlutoCallable`.
"""
function call(fn_name::Symbol, args::Tuple, kwargs::Iterators.Pairs, filename::AbstractString, host::AbstractString="http://localhost:1234")
    request_uri = HTTP.URI("$(host)/v1/notebook/$(HTTP.escapeuri(filename))/call")

    body = IOBuffer()
    Serialization.serialize(body, Dict{String, Any}(
        "function" => fn_name,
        "args" => [args...],
        "kwargs" => Dict(kwargs...)
    ))
    serialized_body = take!(body)

    response = HTTP.request("POST", request_uri, [
        "Accept" => "application/x-julia",
        "Content-Type" => "application/x-julia"
    ], serialized_body; status_exception=false)

    if response.status >= 300
        throw(ErrorException(String(response.body)))
    end
    
    return Serialization.deserialize(IOBuffer(response.body))
end

"""
    static_function(output::Symbol, inputs::Vector{Symbol}, filename::AbstractString, host::AbstractString="http://localhost:1234")

Returns the code for a function which uses the relevant Pluto notebook code to compute the value of `output` given `inputs` as parameters.
This function is what the [`@resolve`](@ref) macro calls under-the-hood, whcih subsequently passes the result into `eval`.
"""
function static_function(output::Symbol, inputs::Vector{Symbol}, filename::AbstractString, host::AbstractString="http://localhost:1234")
    @warn "Ensure you trust this host, as the function returned could be malicious"

    query = ["outputs" => String(output), "inputs" => join(inputs, ",")]
    request_uri = merge(HTTP.URI("$(host)/v1/notebook/$filename/static"); query=query)
    response = HTTP.get(request_uri)

    Meta.parse(String(response.body))
end

"""
    PlutoNotebook(filename::AbstractString, host::AbstractString="http://localhost:1234")

Reference a Pluto notebook running on a Pluto server somewhere.

# Examples
```julia-repl
julia> nb = PlutoNotebook("EuclideanDistance.jl");

julia> nb.c
5.0

julia> nb(; a=5., b=12.).c
13.0
```
"""
struct PlutoNotebook
    host::AbstractString
    filename::AbstractString

    PlutoNotebook(filename::AbstractString, host::AbstractString="http://localhost:1234") = new(host, filename)
end
function Base.getproperty(notebook::PlutoNotebook, symbol::Symbol)
    Base.getproperty(notebook(), symbol)
end

"""
    PlutoCallable(notebook::PlutoNotebook, name::Symbol)

Reference to a symbol which can be called as a function within a Pluto notebook.

# Examples
Within a Pluto notebook `EuclideanDistance.jl` the following function is defined:

```julia
distance(args...) = sqrt(sum(args .^ 2))
```

From elsewhere the `PlutoCallable` structure can be called as a function in itself. It will return the same value which is returned by the referenced function.

```julia-repl
julia> nb = PlutoNotebook("EuclideanDistance.jl");

julia> nb.distance
Pluto.PlutoCallable(PlutoNotebook("http://localhost:1234", "EuclideanDistance.jl"), :distance)

julia> nb.distance(5., 12.)
13.0
```
"""
struct PlutoCallable
    notebook::PlutoNotebook
    name::Symbol
end
function (callable::PlutoCallable)(args...; kwargs...)
    call(callable.name, args, kwargs, Base.getfield(callable.notebook, :filename), Base.getfield(callable.notebook, :host))
end

"""
    PlutoNotebookWithArgs(notebook::PlutoNotebook, kwargs::Dict{Symbol, Any})

An intermediate structure which is returned when one calls a `PlutoNotebook` as a function. Holds `kwargs` to be passed to a Pluto server after requesting an output with `getproperty(::PlutoNotebookWithArgs, symbol::Symbol)`.

# Examples
```julia-repl
julia> nb = PlutoNotebook("EuclideanDistance.jl");

julia> nb_withargs = nb(; a=5., b=12.)
Pluto.PlutoNotebookWithArgs(PlutoNotebook("http://localhost:1234", "EuclideanDistance.jl"), Dict{Symbol, Any}(:a => 5.0, :b => 12.0))

julia> nb_withargs.c
13.0
```
Note that this is **not** recommended syntax because it separates the "parameters" from the desired output of your notebook. Rather, perform both steps at once like the following example:
```julia
nb(; a=5., b=12.).c  # Notice that parameters are provided and an output is requested in one step rather than two
```
"""
struct PlutoNotebookWithArgs
    notebook::PlutoNotebook
    kwargs::Dict{Symbol, Any}
end

# Looks like notebook_instance(a=3, b=4)
function (nb::PlutoNotebook)(; kwargs...)
    PlutoNotebookWithArgs(nb, Dict{Symbol, Any}(kwargs))
end
# Looks like notebook_instance(a=3, b=4).c ⟹ 5
function Base.getproperty(with_args::PlutoNotebookWithArgs, symbol::Symbol)
    try
        return evaluate(symbol, Base.getfield(Base.getfield(with_args, :notebook), :filename), Base.getfield(Base.getfield(with_args, :notebook), :host); Base.getfield(with_args, :kwargs)...)
    catch e
        if hasfield(typeof(e), :msg) && contains(e.msg, "function") # See if the function error was thrown, and return a PlutoCallable struct
            return PlutoCallable(Base.getfield(with_args, :notebook), symbol)
        end
        throw(e)
    end
end
# Looks like notebook_instance(a=3, b=4)[:c, :m] ⟹ 5
function Base.getindex(with_args::PlutoNotebookWithArgs, symbols::Symbol...)
    outputs = []

    # TODO: Refactor to make 1 request with multiple output symbols
    for symbol ∈ symbols
        push!(outputs, evaluate(symbol, Base.getfield(Base.getfield(with_args, :notebook), :filename), Base.getfield(Base.getfield(with_args, :notebook), :host); Base.getfield(with_args, :kwargs)...))
    end

    # https://docs.julialang.org/en/v1/base/base/#Core.NamedTuple
    return (; zip(symbols, outputs)...)
end


"""
    resolve(notebook, inputs, output)

Returns a function which when called uses the relevant Pluto notebook code to compute `output` given `inputs` as parameters. This
computation occurs on the **local** Julia session and not the Pluto one. As a result this macro will only work for a narrow set of
notebook code, as the macro isn't smart enough (yet) to figure out module dependencies or define structures.

# Examples
```julia-repl
julia> nb = PlutoNotebook("EuclideanDistance.jl");

julia> distance2d = @resolve nb [:a, :b] :c

julia> distance2d(3., 4.)
5.0

julia> distance2d(5., 12.)
13.0
```

!!! warning
    The distance2d function defined by `@resolve` does **not** connect to Pluto through the REST API to compute results. Rather,
    its behavior is akin to copy-pasting the relevant section of the Pluto notebook's code into the current Julia session and making
    it callable with a function.
"""
macro resolve(notebook, inputs, output)
    :(
        eval(static_function($(esc(output)), [$(esc(inputs))...], Base.getfield($(esc(notebook)), :filename), Base.getfield($(esc(notebook)), :host)))
    )
end

end # module
