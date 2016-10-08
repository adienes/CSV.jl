function Sink(fullpath::AbstractString;
              delim::Char=',',
              quotechar::Char='"',
              escapechar::Char='\\',
              null::AbstractString="",
              dateformat::Union{AbstractString,Dates.DateFormat}=Dates.ISODateFormat,
              header::Bool=true,
              colnames::Vector{String}=String[],
              append::Bool=false)
    delim = delim % UInt8; quotechar = quotechar % UInt8; escapechar = escapechar % UInt8
    dateformat = isa(dateformat, AbstractString) ? Dates.DateFormat(dateformat) : dateformat
    io = IOBuffer()
    options = CSV.Options(delim=delim, quotechar=quotechar, escapechar=escapechar, null=null, dateformat=dateformat)
    !append && header && !isempty(colnames) && writeheaders(io, colnames, options)
    return Sink(options, io, fullpath, position(io), !append && header && !isempty(colnames), colnames, append)
end

function writeheaders(io::IOBuffer, h::Vector{String}, options)
    cols = length(h)
    q = Char(options.quotechar); e = Char(options.escapechar)
    for col = 1:cols
        print(io, q, replace("$(h[col])", q, "$e$q"), q)
        print(io, ifelse(col == cols, Char(NEWLINE), Char(options.delim)))
    end
    return nothing
end

# DataStreams interface
Data.streamtypes{T<:CSV.Sink}(::Type{T}) = [Data.Field]

# Constructors
function Sink{T}(sch::Data.Schema, ::Type{T}, append::Bool, ref::Vector{UInt8}, file::AbstractString; kwargs...)
    sink = Sink(file; append=append, colnames=Data.header(sch), kwargs...)
    return sink
end

function Sink{T}(sink, sch::Data.Schema, ::Type{T}, append::Bool, ref::Vector{UInt8})
    sink.append = append
    !sink.header && !append && writeheaders(sink.io, Data.header(sch), sink.options)
    return sink
end

Data.streamto!(sink::Sink, ::Type{Data.Field}, val, row, col, sch) = (col == size(sch, 2) ? println(sink.io, val) : print(sink.io, val, Char(sink.options.delim)); return nothing)
function Data.streamto!(sink::Sink, ::Type{Data.Field}, val::AbstractString, row, col, sch)
    q = Char(sink.options.quotechar); e = Char(sink.options.escapechar)
    print(sink.io, q, replace(string(val), q, "$e$q"), q)
    print(sink.io, ifelse(col == size(sch, 2), Char(NEWLINE), Char(sink.options.delim)))
    return nothing
end

function Data.streamto!(sink::Sink, ::Type{Data.Field}, val::Dates.TimeType, row, col, sch)
    q = Char(sink.options.quotechar); e = Char(sink.options.escapechar)
    val = sink.options.datecheck ? string(val) : Dates.format(val, sink.options.dateformat)
    print(sink.io, val)
    print(sink.io, ifelse(col == size(sch, 2), Char(NEWLINE), Char(sink.options.delim)))
    return nothing
end

function Data.streamto!{T}(sink::Sink, ::Type{Data.Field}, val::Nullable{T}, row, col, sch)
    Data.streamto!(sink, Data.Field, isnull(val) ? sink.options.null : get(val), row, col, sch)
    return nothing
end

if isdefined(:NAtype)
function Data.streamto!(sink::Sink, ::Type{Data.Field}, val::NAtype, row, col, sch)
    Data.streamto!(sink, Data.Field, sink.options.null, row, col, sch)
    return nothing
end
end

function Data.close!(sink::CSV.Sink)
    io = open(sink.fullpath, sink.append ? "a" : "w")
    Base.write(io, takebuf_array(sink.io))
    close(io)
    return nothing
end

"""
`CSV.write(fullpath::Union{AbstractString,IO}, source::Type{T}, args...; kwargs...)` => `CSV.Sink`
`CSV.write(fullpath::Union{AbstractString,IO}, source::Data.Source; kwargs...)` => `CSV.Sink`

write a `Data.Source` out to a `CSV.Sink`.

Positional Arguments:

* `fullpath`; can be a file name (string) or other `IO` instance
* `source` can be the *type* of `Data.Source`, plus any required `args...`, or an already constructed `Data.Source` can be passsed in directly (2nd method)

Keyword Arguments:

* `delim::Union{Char,UInt8}`; how fields in the file will be delimited; default is `UInt8(',')`
* `quotechar::Union{Char,UInt8}`; the character that indicates a quoted field that may contain the `delim` or newlines; default is `UInt8('"')`
* `escapechar::Union{Char,UInt8}`; the character that escapes a `quotechar` in a quoted field; default is `UInt8('\\')`
* `null::String`; the ascii string that indicates how NULL values will be represented in the dataset; default is the emtpy string `""`
* `dateformat`; how dates/datetimes will be represented in the dataset; default is ISO-8601 `yyyy-mm-ddTHH:MM:SS.s`
* `header::Bool`; whether to write out the column names from `source`
* `append::Bool`; start writing data at the end of `io`; by default, `io` will be reset to the beginning before writing
"""
function write{T}(file::AbstractString, ::Type{T}, args...; append::Bool=false, transforms::Dict=Dict{Int,Function}(), kwargs...)
    sink = Data.stream!(T(args...), CSV.Sink, append, transforms, file; kwargs...)
    Data.close!(sink)
    return sink
end
function write(file::AbstractString, source; append::Bool=false, transforms::Dict=Dict{Int,Function}(), kwargs...)
    sink = Data.stream!(source, CSV.Sink, append, transforms, file; kwargs...)
    Data.close!(sink)
    return sink
end

write{T}(sink::Sink, ::Type{T}, args...; append::Bool=false, transforms::Dict=Dict{Int,Function}()) = (sink = Data.stream!(T(args...), sink, append, transforms); Data.close!(sink); return sink)
write(sink::Sink, source; append::Bool=false, transforms::Dict=Dict{Int,Function}()) = (sink = Data.stream!(source, sink, append, transforms); Data.close!(sink); return sink)
