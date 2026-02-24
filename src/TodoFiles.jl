module TodoFiles

using Dates

export Todo, parse_todo, parse_todos, write_todo, write_todos, read_todos,
       contexts, projects, metadata

#--------------------------------------------------------------------------------# Todo
"""
    Todo

A single task in the [Todo.txt](https://github.com/todotxt/todo.txt) format.

# Fields
- `completed::Bool`: Whether the task is marked complete (`x`).
- `priority::Union{Char, Nothing}`: Priority letter `'A'`–`'Z'`, or `nothing`.
- `completion_date::Union{Date, Nothing}`: Date the task was completed.
- `creation_date::Union{Date, Nothing}`: Date the task was created.
- `description::String`: The task description text (including contexts, projects, and metadata).

# Accessors
- [`contexts`](@ref): Extract `@context` tags.
- [`projects`](@ref): Extract `+project` tags.
- [`metadata`](@ref): Extract `key:value` pairs.

### Examples
```julia
julia> t = parse_todo("(A) 2024-01-15 Call Mom +Family @phone due:2024-01-20")
Todo: (A) 2024-01-15 Call Mom +Family @phone due:2024-01-20

julia> t.priority
'A': ASCII/Unicode U+0041 (category Lu: Letter, uppercase)

julia> contexts(t)
["phone"]

julia> projects(t)
["Family"]

julia> metadata(t)
Dict{String, String} with 1 entry:
  "due" => "2024-01-20"
```
"""
mutable struct Todo
    completed::Bool
    priority::Union{Char, Nothing}
    completion_date::Union{Date, Nothing}
    creation_date::Union{Date, Nothing}
    description::String
end

function Todo(description::String;
              completed::Bool=false,
              priority::Union{Char, Nothing}=nothing,
              completion_date::Union{Date, Nothing}=nothing,
              creation_date::Union{Date, Nothing}=nothing)
    Todo(completed, priority, completion_date, creation_date, description)
end

function Base.:(==)(a::Todo, b::Todo)
    a.completed == b.completed &&
    a.priority == b.priority &&
    a.completion_date == b.completion_date &&
    a.creation_date == b.creation_date &&
    a.description == b.description
end

function Base.show(io::IO, t::Todo)
    print(io, "Todo: ", write_todo(t))
end

#--------------------------------------------------------------------------------# Accessors
"""
    contexts(t::Todo) -> Vector{String}

Extract all `@context` tags from the task description.

### Examples
```julia
julia> t = parse_todo("Call Mom @phone @home")
Todo: Call Mom @phone @home

julia> contexts(t)
["phone", "home"]
```
"""
function contexts(t::Todo)
    [m.captures[1] for m in eachmatch(r"(?:^|\s)@(\S+)", t.description)]
end

"""
    projects(t::Todo) -> Vector{String}

Extract all `+project` tags from the task description.

### Examples
```julia
julia> t = parse_todo("Call Mom +Family +Health")
Todo: Call Mom +Family +Health

julia> projects(t)
["Family", "Health"]
```
"""
function projects(t::Todo)
    [m.captures[1] for m in eachmatch(r"(?:^|\s)\+(\S+)", t.description)]
end

"""
    metadata(t::Todo) -> Dict{String, String}

Extract all `key:value` metadata pairs from the task description.

### Examples
```julia
julia> t = parse_todo("Call Mom due:2024-01-20 effort:low")
Todo: Call Mom due:2024-01-20 effort:low

julia> metadata(t)
Dict{String, String} with 2 entries:
  "due"    => "2024-01-20"
  "effort" => "low"
```
"""
function metadata(t::Todo)
    Dict(m.captures[1] => m.captures[2]
         for m in eachmatch(r"(?:^|\s)(\S+):(\S+)", t.description)
         if !startswith(m.captures[1], "@") && !startswith(m.captures[1], "+"))
end

#--------------------------------------------------------------------------------# Parsing
const DATE_REGEX = r"^(\d{4}-\d{2}-\d{2})\s"

function tryparse_date(s::AbstractString)
    m = match(DATE_REGEX, s)
    isnothing(m) && return (nothing, s)
    d = tryparse(Date, m.captures[1])
    isnothing(d) && return (nothing, s)
    return (d, s[length(m.match)+1:end])
end

"""
    parse_todo(line::AbstractString) -> Todo

Parse a single line of Todo.txt format into a [`Todo`](@ref).

### Examples
```julia
julia> parse_todo("(A) 2024-01-15 Call Mom +Family @phone")
Todo: (A) 2024-01-15 Call Mom +Family @phone

julia> parse_todo("x 2024-01-16 2024-01-15 Call Mom +Family @phone")
Todo: x 2024-01-16 2024-01-15 Call Mom +Family @phone
```
"""
function parse_todo(line::AbstractString)
    s = strip(String(line))
    completed = false
    priority = nothing
    completion_date = nothing
    creation_date = nothing

    # Check for completion marker: "x "
    if startswith(s, "x ")
        completed = true
        s = s[3:end]

        # Completion date (required for completed tasks per spec, but be lenient)
        (completion_date, s) = tryparse_date(s)
    end

    # Check for priority: "(A) "
    m = match(r"^\(([A-Z])\)\s", s)
    if !isnothing(m)
        priority = m.captures[1][1]
        s = s[length(m.match)+1:end]
    end

    # Creation date (or second date for completed tasks)
    (d, s) = tryparse_date(s)
    if completed && !isnothing(completion_date)
        creation_date = d
    elseif !completed
        creation_date = d
    elseif completed && isnothing(completion_date)
        # "x" with one date: treat as completion date
        completion_date = d
    end

    description = strip(s)

    Todo(completed, priority, completion_date, creation_date, String(description))
end

"""
    parse_todos(text::AbstractString) -> Vector{Todo}

Parse multiple lines of Todo.txt format into a vector of [`Todo`](@ref) items.
Blank lines are skipped.

### Examples
```julia
julia> todos = parse_todos(\"""
       (A) Call Mom @phone
       (B) Buy groceries @store +Errands
       x 2024-01-15 Pay bills
       \""")
3-element Vector{Todo}:
 Todo: (A) Call Mom @phone
 Todo: (B) Buy groceries @store +Errands
 Todo: x 2024-01-15 Pay bills
```
"""
function parse_todos(text::AbstractString)
    lines = split(text, r"\r?\n")
    todos = Todo[]
    for line in lines
        stripped = strip(line)
        isempty(stripped) && continue
        push!(todos, parse_todo(stripped))
    end
    return todos
end

#--------------------------------------------------------------------------------# Writing
"""
    write_todo(t::Todo) -> String

Serialize a [`Todo`](@ref) back to a single Todo.txt formatted line.

### Examples
```julia
julia> t = Todo("Call Mom +Family @phone"; priority='A', creation_date=Date(2024, 1, 15))
Todo: (A) 2024-01-15 Call Mom +Family @phone

julia> write_todo(t)
"(A) 2024-01-15 Call Mom +Family @phone"
```
"""
function write_todo(t::Todo)
    parts = String[]
    if t.completed
        push!(parts, "x")
        !isnothing(t.completion_date) && push!(parts, string(t.completion_date))
    end
    !isnothing(t.priority) && push!(parts, "($(t.priority))")
    !isnothing(t.creation_date) && push!(parts, string(t.creation_date))
    push!(parts, t.description)
    return join(parts, " ")
end

"""
    write_todos(todos::Vector{Todo}) -> String

Serialize a vector of [`Todo`](@ref) items into a Todo.txt formatted string.
"""
function write_todos(todos::Vector{Todo})
    return join(write_todo.(todos), "\n") * "\n"
end

#--------------------------------------------------------------------------------# File I/O
"""
    read_todos(filepath::AbstractString) -> Vector{Todo}

Read a Todo.txt file and return a vector of [`Todo`](@ref) items.

### Examples
```julia
julia> todos = read_todos("todo.txt")
```
"""
function read_todos(filepath::AbstractString)
    parse_todos(read(filepath, String))
end

"""
    write_todos(filepath::AbstractString, todos::Vector{Todo})

Write a vector of [`Todo`](@ref) items to a file in Todo.txt format.

### Examples
```julia
julia> write_todos("todo.txt", todos)
```
"""
function write_todos(filepath::AbstractString, todos::Vector{Todo})
    write(filepath, write_todos(todos))
end

end # module
