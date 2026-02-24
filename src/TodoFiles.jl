module TodoFiles

using Dates
using Tables

export Todo, TodoFile, parse_todo, parse_todos, write_todo, write_todos, read_todos,
       ListView, TableView, KanbanView, html_view

#--------------------------------------------------------------------------------# Helpers
function _extract_tags(description::AbstractString)
    words = split(description)
    plain = String[]
    ctx = String[]
    prj = String[]
    meta = Dict{String, String}()
    for word in words
        if startswith(word, "@") && length(word) > 1
            push!(ctx, String(word[2:end]))
        elseif startswith(word, "+") && length(word) > 1
            push!(prj, String(word[2:end]))
        elseif contains(word, ":") && !startswith(word, "@") && !startswith(word, "+")
            parts = split(word, ":", limit=2)
            if length(parts) == 2 && !isempty(parts[1]) && !isempty(parts[2])
                meta[String(parts[1])] = String(parts[2])
            else
                push!(plain, String(word))
            end
        else
            push!(plain, String(word))
        end
    end
    return (join(plain, " "), ctx, prj, meta)
end

#--------------------------------------------------------------------------------# Todo
"""
    Todo

A single task in the [Todo.txt](https://github.com/todotxt/todo.txt) format.

# Fields
- `completed::Bool`: Whether the task is marked complete (`x`).
- `priority::Union{Char, Nothing}`: Priority letter `'A'`–`'Z'`, or `nothing`.
- `completion_date::Union{Date, Nothing}`: Date the task was completed.
- `creation_date::Union{Date, Nothing}`: Date the task was created.
- `description::String`: The task description text (tags are stored separately).
- `contexts::Vector{String}`: `@context` tags.
- `projects::Vector{String}`: `+project` tags.
- `metadata::Dict{String, String}`: `key:value` pairs.

### Examples
```julia
julia> t = parse_todo("(A) 2024-01-15 Call Mom @phone +Family due:2024-01-20")
Todo: (A) 2024-01-15 Call Mom @phone +Family due:2024-01-20

julia> t.priority
'A': ASCII/Unicode U+0041 (category Lu: Letter, uppercase)

julia> t.contexts
["phone"]

julia> t.projects
["Family"]

julia> t.metadata
Dict{String, String} with 1 entry:
  "due" => "2024-01-20"
```
"""
struct Todo
    completed::Bool
    priority::Union{Char, Nothing}
    completion_date::Union{Date, Nothing}
    creation_date::Union{Date, Nothing}
    description::String
    contexts::Vector{String}
    projects::Vector{String}
    metadata::Dict{String, String}
end

function Todo(description::String;
              completed::Bool=false,
              priority::Union{Char, Nothing}=nothing,
              completion_date::Union{Date, Nothing}=nothing,
              creation_date::Union{Date, Nothing}=nothing,
              contexts::Vector{String}=String[],
              projects::Vector{String}=String[],
              metadata::Dict{String, String}=Dict{String, String}())
    desc, parsed_ctx, parsed_prj, parsed_meta = _extract_tags(description)
    Todo(completed, priority, completion_date, creation_date, desc,
         isempty(contexts) ? parsed_ctx : contexts,
         isempty(projects) ? parsed_prj : projects,
         isempty(metadata) ? parsed_meta : metadata)
end

function Base.:(==)(a::Todo, b::Todo)
    a.completed == b.completed &&
    a.priority == b.priority &&
    a.completion_date == b.completion_date &&
    a.creation_date == b.creation_date &&
    a.description == b.description &&
    a.contexts == b.contexts &&
    a.projects == b.projects &&
    a.metadata == b.metadata
end

function Base.show(io::IO, t::Todo)
    print(io, "Todo: ", write_todo(t))
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
julia> parse_todo("(A) 2024-01-15 Call Mom @phone +Family")
Todo: (A) 2024-01-15 Call Mom @phone +Family

julia> parse_todo("x 2024-01-16 2024-01-15 Call Mom @phone +Family")
Todo: x 2024-01-16 2024-01-15 Call Mom @phone +Family
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

    desc_str = strip(s)
    desc, ctx, prj, meta = _extract_tags(desc_str)

    Todo(completed, priority, completion_date, creation_date, String(desc), ctx, prj, meta)
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
julia> t = Todo("Call Mom @phone +Family"; priority='A', creation_date=Date(2024, 1, 15))
Todo: (A) 2024-01-15 Call Mom @phone +Family

julia> write_todo(t)
"(A) 2024-01-15 Call Mom @phone +Family"
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
    for c in t.contexts
        push!(parts, "@$c")
    end
    for p in t.projects
        push!(parts, "+$p")
    end
    for (k, v) in sort(collect(t.metadata))
        push!(parts, "$k:$v")
    end
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

#--------------------------------------------------------------------------------# TodoFile
"""
    TodoFile

A Todo.txt file represented as a filepath and a vector of [`Todo`](@ref) items.
Implements the [Tables.jl](https://github.com/JuliaData/Tables.jl) interface for
interoperability with DataFrames, CSV, and other tabular data packages.

### Examples
```julia
julia> tf = TodoFile("todo.txt")

julia> length(tf)
3

julia> tf[1]
Todo: (A) Call Mom @phone +Family

julia> write_todos(tf)  # writes back to tf.filepath
```
"""
struct TodoFile
    filepath::String
    todos::Vector{Todo}
end

"""
    TodoFile(filepath::AbstractString)

Read a Todo.txt file and return a [`TodoFile`](@ref).
"""
TodoFile(filepath::AbstractString) = TodoFile(String(filepath), read_todos(filepath))

Base.length(tf::TodoFile) = length(tf.todos)
Base.getindex(tf::TodoFile, i) = tf.todos[i]
Base.iterate(tf::TodoFile, args...) = iterate(tf.todos, args...)
Base.eltype(::Type{TodoFile}) = Todo

function Base.show(io::IO, tf::TodoFile)
    n = length(tf.todos)
    print(io, "TodoFile(\"$(tf.filepath)\") with $n task$(n == 1 ? "" : "s")")
end

"""
    write_todos(tf::TodoFile)

Write a [`TodoFile`](@ref) back to its filepath.
"""
write_todos(tf::TodoFile) = write_todos(tf.filepath, tf.todos)

#--------------------------------------------------------------------------------# Tables.jl
Tables.istable(::Type{TodoFile}) = true
Tables.rowaccess(::Type{TodoFile}) = true
Tables.rows(tf::TodoFile) = tf.todos
Tables.schema(::TodoFile) = Tables.Schema(
    fieldnames(Todo),
    (Bool, Union{Char, Nothing}, Union{Date, Nothing}, Union{Date, Nothing}, String, Vector{String}, Vector{String}, Dict{String, String})
)

Tables.columnnames(::Todo) = fieldnames(Todo)
Tables.getcolumn(t::Todo, nm::Symbol) = getfield(t, nm)
Tables.getcolumn(t::Todo, i::Int) = getfield(t, i)

#--------------------------------------------------------------------------------# HTML Helpers
_html_escape(s::AbstractString) = replace(s, "&" => "&amp;", "<" => "&lt;", ">" => "&gt;", "\"" => "&quot;")

function _todo_css()
    """
    <style>
    .todo-container { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif; font-size: 14px; color: #1a1a1a; }
    .todo-list { list-style: none; padding: 0; margin: 0; }
    .todo-card { background: #fff; border: 1px solid #e0e0e0; border-radius: 8px; padding: 10px 14px; margin-bottom: 8px; display: flex; align-items: center; gap: 10px; }
    .todo-card.todo-done { opacity: 0.6; }
    .todo-checkbox { width: 18px; height: 18px; border: 2px solid #999; border-radius: 4px; flex-shrink: 0; display: flex; align-items: center; justify-content: center; }
    .todo-card.todo-done .todo-checkbox { background: #4caf50; border-color: #4caf50; color: #fff; }
    .todo-desc { flex: 1; }
    .todo-card.todo-done .todo-desc { text-decoration: line-through; color: #888; }
    .todo-priority { display: inline-block; width: 22px; height: 22px; border-radius: 50%; text-align: center; line-height: 22px; font-weight: 700; font-size: 12px; color: #fff; flex-shrink: 0; }
    .todo-priority-a { background: #e53935; }
    .todo-priority-b { background: #fb8c00; }
    .todo-priority-c { background: #fdd835; color: #333; }
    .todo-priority-other { background: #90a4ae; }
    .todo-pill { display: inline-block; padding: 1px 8px; border-radius: 12px; font-size: 12px; margin-left: 4px; }
    .todo-ctx { background: #e3f2fd; color: #1565c0; }
    .todo-prj { background: #e8f5e9; color: #2e7d32; }
    .todo-meta { background: #f3e5f5; color: #6a1b9a; }
    .todo-date { color: #888; font-size: 12px; white-space: nowrap; }
    .todo-table { border-collapse: collapse; width: 100%; }
    .todo-table th { background: #f5f5f5; text-align: left; padding: 8px 12px; border-bottom: 2px solid #ddd; font-weight: 600; }
    .todo-table td { padding: 8px 12px; border-bottom: 1px solid #eee; vertical-align: middle; }
    .todo-kanban { display: flex; gap: 16px; overflow-x: auto; padding-bottom: 8px; }
    .todo-kanban-col { background: #f5f5f5; border-radius: 8px; padding: 12px; min-width: 220px; max-width: 300px; flex-shrink: 0; }
    .todo-kanban-col h3 { margin: 0 0 10px 0; font-size: 15px; padding-bottom: 6px; border-bottom: 2px solid #ddd; }
    .todo-kanban-col .todo-card { font-size: 13px; }
    </style>"""
end

function _priority_html(p::Union{Char, Nothing})
    isnothing(p) && return ""
    cls = if p == 'A'; "todo-priority-a"
    elseif p == 'B'; "todo-priority-b"
    elseif p == 'C'; "todo-priority-c"
    else; "todo-priority-other"
    end
    """<span class="todo-priority $cls">$(_html_escape(string(p)))</span>"""
end

function _tags_html(t::Todo)
    parts = String[]
    for c in t.contexts
        push!(parts, """<span class="todo-pill todo-ctx">@$(_html_escape(c))</span>""")
    end
    for p in t.projects
        push!(parts, """<span class="todo-pill todo-prj">+$(_html_escape(p))</span>""")
    end
    for (k, v) in sort(collect(t.metadata))
        push!(parts, """<span class="todo-pill todo-meta">$(_html_escape(k)):$(_html_escape(v))</span>""")
    end
    join(parts)
end

function _description_html(t::Todo)
    done_cls = t.completed ? " todo-done" : ""
    check = t.completed ? "&#10003;" : ""
    """<div class="todo-card$done_cls"><span class="todo-checkbox">$check</span><span class="todo-desc">$(_html_escape(t.description))</span>$(_priority_html(t.priority))$(_tags_html(t))</div>"""
end

_date_str(d::Union{Date, Nothing}) = isnothing(d) ? "" : string(d)

function _group_keys(t::Todo, group_by::Symbol)
    if group_by == :priority
        return isnothing(t.priority) ? ["(none)"] : [string(t.priority)]
    elseif group_by == :completed
        return t.completed ? ["Done"] : ["Pending"]
    elseif group_by == :projects
        return isempty(t.projects) ? ["(no project)"] : t.projects
    elseif group_by == :contexts
        return isempty(t.contexts) ? ["(no context)"] : t.contexts
    else
        error("Invalid group_by: $group_by. Use :priority, :completed, :projects, or :contexts.")
    end
end

function _kanban_groups(tf::TodoFile, group_by::Symbol)
    groups = Dict{String, Vector{Todo}}()
    for t in tf
        for key in _group_keys(t, group_by)
            push!(get!(Vector{Todo}, groups, key), t)
        end
    end
    # Sort: special "(none)"/"(no ...)" keys go last
    pairs = collect(groups)
    sort!(pairs, by = p -> (startswith(p.first, "(") ? 1 : 0, p.first))
    return pairs
end

#--------------------------------------------------------------------------------# HTML Views
"""
    ListView

A card-style HTML list view of a [`TodoFile`](@ref). Display in Jupyter/Pluto notebooks
via their rich HTML rendering.

### Examples
```julia
julia> tf = TodoFile("todo.txt")

julia> ListView(tf)
ListView(3 tasks)
```
"""
struct ListView
    todofile::TodoFile
end

"""
    TableView

A tabular HTML view of a [`TodoFile`](@ref).

### Examples
```julia
julia> tf = TodoFile("todo.txt")

julia> TableView(tf)
TableView(3 tasks)
```
"""
struct TableView
    todofile::TodoFile
end

"""
    KanbanView

A kanban board HTML view of a [`TodoFile`](@ref), grouped by a specified field.

### Examples
```julia
julia> tf = TodoFile("todo.txt")

julia> KanbanView(tf, :priority)
KanbanView(3 tasks, group_by=:priority)

julia> KanbanView(tf)  # defaults to :priority
KanbanView(3 tasks, group_by=:priority)
```
"""
struct KanbanView
    todofile::TodoFile
    group_by::Symbol
end
KanbanView(tf::TodoFile) = KanbanView(tf, :priority)

# Plain-text show
Base.show(io::IO, v::ListView) = print(io, "ListView($(length(v.todofile)) tasks)")
Base.show(io::IO, v::TableView) = print(io, "TableView($(length(v.todofile)) tasks)")
Base.show(io::IO, v::KanbanView) = print(io, "KanbanView($(length(v.todofile)) tasks, group_by=:$(v.group_by))")

# HTML show — ListView
function Base.show(io::IO, ::MIME"text/html", v::ListView)
    print(io, _todo_css())
    print(io, """<div class="todo-container"><div class="todo-list">""")
    for t in v.todofile
        print(io, _description_html(t))
    end
    print(io, "</div></div>")
end

# HTML show — TableView
function Base.show(io::IO, ::MIME"text/html", v::TableView)
    print(io, _todo_css())
    print(io, """<div class="todo-container"><table class="todo-table">""")
    print(io, "<thead><tr><th>Done</th><th>Priority</th><th>Description</th><th>Tags</th><th>Created</th><th>Completed</th></tr></thead><tbody>")
    for t in v.todofile
        check = t.completed ? "&#10003;" : ""
        pri = isnothing(t.priority) ? "" : _priority_html(t.priority)
        print(io, "<tr>")
        print(io, "<td>$check</td>")
        print(io, "<td>$pri</td>")
        print(io, "<td>$(_html_escape(t.description))</td>")
        print(io, "<td>$(_tags_html(t))</td>")
        print(io, """<td class="todo-date">$(_date_str(t.creation_date))</td>""")
        print(io, """<td class="todo-date">$(_date_str(t.completion_date))</td>""")
        print(io, "</tr>")
    end
    print(io, "</tbody></table></div>")
end

# HTML show — KanbanView
function Base.show(io::IO, ::MIME"text/html", v::KanbanView)
    print(io, _todo_css())
    print(io, """<div class="todo-container"><div class="todo-kanban">""")
    for (label, todos) in _kanban_groups(v.todofile, v.group_by)
        print(io, """<div class="todo-kanban-col"><h3>$(_html_escape(label))</h3>""")
        for t in todos
            print(io, _description_html(t))
        end
        print(io, "</div>")
    end
    print(io, "</div></div>")
end

# Default HTML for TodoFile delegates to ListView
function Base.show(io::IO, mime::MIME"text/html", tf::TodoFile)
    show(io, mime, ListView(tf))
end

"""
    html_view(tf::TodoFile; view::Symbol=:list, group_by::Symbol=:priority)

Create an HTML view of a [`TodoFile`](@ref) for rich display in notebooks.

Returns a [`ListView`](@ref), [`TableView`](@ref), or [`KanbanView`](@ref).

### Examples
```julia
julia> tf = TodoFile("todo.txt")

julia> html_view(tf)
ListView(3 tasks)

julia> html_view(tf; view=:table)
TableView(3 tasks)

julia> html_view(tf; view=:kanban, group_by=:projects)
KanbanView(3 tasks, group_by=:projects)
```
"""
function html_view(tf::TodoFile; view::Symbol=:list, group_by::Symbol=:priority)
    if view == :list
        return ListView(tf)
    elseif view == :table
        return TableView(tf)
    elseif view == :kanban
        return KanbanView(tf, group_by)
    else
        error("Invalid view: $view. Use :list, :table, or :kanban.")
    end
end

end # module
