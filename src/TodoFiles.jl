module TodoFiles

using Dates
using Tables

export Todo, TodoFile, TodoSection, MarkdownTodoFile,
       parse_todo, parse_todos, parse_markdown_todos,
       write_todo, write_todos, write_markdown_todos,
       read_todos, read_markdown_todos,
       ListView, TableView, KanbanView, GanttView, DueView, html_view

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
- `subtasks::Vector{Todo}`: Nested sub-tasks (used by `MarkdownTodoFile`; empty for flat Todo.txt).

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
    subtasks::Vector{Todo}
end

function Todo(description::String;
              completed::Bool=false,
              priority::Union{Char, Nothing}=nothing,
              completion_date::Union{Date, Nothing}=nothing,
              creation_date::Union{Date, Nothing}=nothing,
              contexts::Vector{String}=String[],
              projects::Vector{String}=String[],
              metadata::Dict{String, String}=Dict{String, String}(),
              subtasks::Vector{Todo}=Todo[])
    desc, parsed_ctx, parsed_prj, parsed_meta = _extract_tags(description)
    Todo(completed, priority, completion_date, creation_date, desc,
         isempty(contexts) ? parsed_ctx : contexts,
         isempty(projects) ? parsed_prj : projects,
         isempty(metadata) ? parsed_meta : metadata,
         subtasks)
end

function Base.:(==)(a::Todo, b::Todo)
    a.completed == b.completed &&
    a.priority == b.priority &&
    a.completion_date == b.completion_date &&
    a.creation_date == b.creation_date &&
    a.description == b.description &&
    a.contexts == b.contexts &&
    a.projects == b.projects &&
    a.metadata == b.metadata &&
    a.subtasks == b.subtasks
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

    Todo(completed, priority, completion_date, creation_date, String(desc), ctx, prj, meta, Todo[])
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

#--------------------------------------------------------------------------------# MarkdownTodoFile
"""
    TodoSection

A group of [`Todo`](@ref) items under a markdown heading.

# Fields
- `heading::String`: The heading text (empty string for todos before any heading).
- `level::Int`: The heading level (1 for `#`, 2 for `##`, etc.; 0 for no heading).
- `todos::Vector{Todo}`: The tasks in this section.
"""
struct TodoSection
    heading::String
    level::Int
    todos::Vector{Todo}
end

function Base.show(io::IO, s::TodoSection)
    n = length(s.todos)
    h = isempty(s.heading) ? "(no heading)" : s.heading
    print(io, "TodoSection(\"$h\", $n task$(n == 1 ? "" : "s"))")
end

"""
    MarkdownTodoFile

A markdown file with [`TodoSection`](@ref)s, where `#`-headings define sections and
`- ` list items are todo entries in [Todo.txt](https://github.com/todotxt/todo.txt) format.
Existing HTML views work via automatic flattening of all todos.

### Examples
```julia
julia> mf = MarkdownTodoFile("todos.md")

julia> length(mf)
5

julia> mf[1]
Todo: (A) Call Mom @phone +Family
```
"""
struct MarkdownTodoFile
    filepath::String
    sections::Vector{TodoSection}
end

function Base.show(io::IO, mf::MarkdownTodoFile)
    n = length(mf)
    ns = length(mf.sections)
    print(io, "MarkdownTodoFile(\"$(mf.filepath)\") with $ns section$(ns == 1 ? "" : "s"), $n task$(n == 1 ? "" : "s")")
end

Base.length(mf::MarkdownTodoFile) = sum(length(s.todos) + sum(length(t.subtasks) for t in s.todos; init=0) for s in mf.sections; init=0)
Base.eltype(::Type{MarkdownTodoFile}) = Todo

function Base.iterate(mf::MarkdownTodoFile)
    for si in 1:length(mf.sections)
        if !isempty(mf.sections[si].todos)
            return (mf.sections[si].todos[1], (si, 1, 0))
        end
    end
    return nothing
end

function Base.iterate(mf::MarkdownTodoFile, state)
    si, ti, sti = state
    # Try next subtask
    sti += 1
    todo = mf.sections[si].todos[ti]
    if sti <= length(todo.subtasks)
        return (todo.subtasks[sti], (si, ti, sti))
    end
    # Move to next todo
    ti += 1
    while si <= length(mf.sections)
        if ti <= length(mf.sections[si].todos)
            return (mf.sections[si].todos[ti], (si, ti, 0))
        end
        si += 1
        ti = 1
    end
    return nothing
end

function Base.getindex(mf::MarkdownTodoFile, i::Int)
    idx = i
    for s in mf.sections
        for t in s.todos
            idx == 1 && return t
            idx -= 1
            for st in t.subtasks
                idx == 1 && return st
                idx -= 1
            end
        end
    end
    throw(BoundsError(mf, i))
end

"""
    parse_markdown_todos(text::AbstractString) -> Vector{TodoSection}

Parse markdown text with `#`-headings as sections and `- ` list items as
[`Todo`](@ref) entries. Blank lines and non-todo content are skipped.

### Examples
```julia
julia> sections = parse_markdown_todos(\"\"\"
       # Work
       - (A) Finish report @office
       - Email client @office +ClientProject
       ## Personal
       - Buy groceries @store +Errands
       \"\"\")
2-element Vector{TodoSection}:
 TodoSection("Work", 2 tasks)
 TodoSection("Personal", 1 task)
```
"""
function parse_markdown_todos(text::AbstractString)
    sections = TodoSection[]
    current_heading = ""
    current_level = 0
    current_todos = Todo[]

    for line in split(text, r"\r?\n")
        stripped = strip(line)
        isempty(stripped) && continue
        m = match(r"^(#{1,6})\s+(.+)$", stripped)
        if !isnothing(m)
            if !isempty(current_todos) || current_level > 0
                push!(sections, TodoSection(current_heading, current_level, current_todos))
            end
            current_level = length(m.captures[1])
            current_heading = strip(String(m.captures[2]))
            current_todos = Todo[]
        elseif startswith(stripped, "- ")
            indent = length(line) - length(lstrip(line))
            todo_text = strip(stripped[3:end])
            isempty(todo_text) && continue
            if indent > 0 && !isempty(current_todos)
                push!(current_todos[end].subtasks, parse_todo(todo_text))
            else
                push!(current_todos, parse_todo(todo_text))
            end
        end
    end

    if !isempty(current_todos) || current_level > 0
        push!(sections, TodoSection(current_heading, current_level, current_todos))
    end

    return sections
end

"""
    read_markdown_todos(filepath::AbstractString) -> Vector{TodoSection}

Read a markdown file and parse it into [`TodoSection`](@ref)s.

### Examples
```julia
julia> sections = read_markdown_todos("todos.md")
```
"""
function read_markdown_todos(filepath::AbstractString)
    parse_markdown_todos(read(filepath, String))
end

"""
    write_markdown_todos(sections::Vector{TodoSection}) -> String

Serialize [`TodoSection`](@ref)s to a markdown string with `#`-headings and `- ` list items.
"""
function write_markdown_todos(sections::Vector{TodoSection})
    parts = String[]
    for s in sections
        section_lines = String[]
        if s.level > 0 && !isempty(s.heading)
            push!(section_lines, "#"^s.level * " " * s.heading)
        end
        for t in s.todos
            push!(section_lines, "- " * write_todo(t))
            for st in t.subtasks
                push!(section_lines, "    - " * write_todo(st))
            end
        end
        !isempty(section_lines) && push!(parts, join(section_lines, "\n"))
    end
    return join(parts, "\n\n") * "\n"
end

"""
    write_markdown_todos(filepath::AbstractString, sections::Vector{TodoSection})

Write [`TodoSection`](@ref)s to a markdown file.
"""
function write_markdown_todos(filepath::AbstractString, sections::Vector{TodoSection})
    write(filepath, write_markdown_todos(sections))
end

"""
    MarkdownTodoFile(filepath::AbstractString)

Read a markdown file and return a [`MarkdownTodoFile`](@ref).
"""
MarkdownTodoFile(filepath::AbstractString) = MarkdownTodoFile(String(filepath), read_markdown_todos(filepath))

"""
    write_todos(mf::MarkdownTodoFile)

Write a [`MarkdownTodoFile`](@ref) back to its filepath.
"""
write_todos(mf::MarkdownTodoFile) = write_markdown_todos(mf.filepath, mf.sections)

#--------------------------------------------------------------------------------# Tables.jl
Tables.istable(::Type{TodoFile}) = true
Tables.rowaccess(::Type{TodoFile}) = true
Tables.rows(tf::TodoFile) = tf.todos
Tables.schema(::TodoFile) = Tables.Schema(
    fieldnames(Todo),
    (Bool, Union{Char, Nothing}, Union{Date, Nothing}, Union{Date, Nothing}, String, Vector{String}, Vector{String}, Dict{String, String}, Vector{Todo})
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
    .todo-table th { background: #f5f5f5; text-align: left; padding: 8px 12px; border-bottom: 2px solid #ddd; font-weight: 600; white-space: nowrap; }
    .todo-sort-arrow { font-size: 10px; color: #666; }
    .todo-table td { padding: 8px 12px; border-bottom: 1px solid #eee; vertical-align: middle; }
    .todo-kanban { display: flex; gap: 16px; overflow-x: auto; padding-bottom: 8px; }
    .todo-kanban-col { background: #f5f5f5; border-radius: 8px; padding: 12px; min-width: 220px; max-width: 300px; flex-shrink: 0; }
    .todo-kanban-col h3 { margin: 0 0 10px 0; font-size: 15px; padding-bottom: 6px; border-bottom: 2px solid #ddd; }
    .todo-kanban-col .todo-card { font-size: 13px; }
    .todo-gantt { width: 100%; border-collapse: collapse; }
    .todo-gantt th, .todo-gantt td { padding: 6px 8px; border-bottom: 1px solid #eee; vertical-align: middle; }
    .todo-gantt th { background: #f5f5f5; font-weight: 600; font-size: 13px; }
    .todo-gantt-label { white-space: nowrap; max-width: 200px; overflow: hidden; text-overflow: ellipsis; font-size: 13px; width: 200px; }
    .todo-gantt-track { position: relative; height: 24px; background: #f9f9f9; border-radius: 4px; min-width: 300px; }
    .todo-gantt-bar { position: absolute; top: 2px; height: 20px; border-radius: 4px; opacity: 0.9; }
    .todo-gantt-bar-a { background: #e53935; }
    .todo-gantt-bar-b { background: #fb8c00; }
    .todo-gantt-bar-c { background: #fdd835; }
    .todo-gantt-bar-other { background: #90a4ae; }
    .todo-gantt-bar-done { opacity: 0.4; }
    .todo-gantt-dates { display: flex; justify-content: space-between; font-size: 11px; color: #888; padding: 0 8px; }
    .todo-due-track { position: relative; height: 24px; background: #f9f9f9; border-radius: 4px; min-width: 300px; }
    .todo-due-bar { position: absolute; top: 2px; height: 20px; border-radius: 4px; }
    .todo-due-overdue { background: #e53935; }
    .todo-due-urgent { background: #fb8c00; }
    .todo-due-soon { background: #fdd835; }
    .todo-due-ok { background: #66bb6a; }
    .todo-due-plenty { background: #42a5f5; }
    .todo-due-label { font-size: 12px; font-weight: 600; white-space: nowrap; }
    .todo-due-today { position: absolute; top: 0; bottom: 0; width: 2px; background: #333; z-index: 1; }
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
        startswith(k, "_") && continue
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
    elseif group_by == :section
        sec = get(t.metadata, "_section", "(no section)")
        return [sec]
    else
        error("Invalid group_by: $group_by. Use :priority, :completed, :projects, :contexts, or :section.")
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
function _sort_value(t::Todo, col::Symbol)
    if col == :completed
        t.completed ? "1" : "0"
    elseif col == :priority
        isnothing(t.priority) ? "ZZ" : string(t.priority)
    elseif col == :description
        t.description
    elseif col == :tags
        join(t.contexts, ",") * ";" * join(t.projects, ",")
    elseif col == :creation_date
        _date_str(t.creation_date)
    elseif col == :completion_date
        _date_str(t.completion_date)
    else
        ""
    end
end

function Base.show(io::IO, ::MIME"text/html", v::TableView)
    tid = "todo-table-" * string(hash(v), base=16)
    print(io, _todo_css())
    print(io, """<div class="todo-container"><table class="todo-table" id="$tid">""")
    print(io, "<thead><tr>")
    for (i, (label, col)) in enumerate([
        ("Done", :completed), ("Priority", :priority), ("Description", :description),
        ("Tags", :tags), ("Created", :creation_date), ("Completed", :completion_date)
    ])
        print(io, """<th style="cursor:pointer;user-select:none;" onclick="todoSort_$tid($i)">$label <span class="todo-sort-arrow" id="$(tid)_arrow_$i"></span></th>""")
    end
    print(io, "</tr></thead><tbody>")
    cols = [:completed, :priority, :description, :tags, :creation_date, :completion_date]
    for t in v.todofile
        check = t.completed ? "&#10003;" : ""
        pri = isnothing(t.priority) ? "" : _priority_html(t.priority)
        print(io, "<tr>")
        print(io, """<td data-sort-value="$(_html_escape(_sort_value(t, :completed)))">$check</td>""")
        print(io, """<td data-sort-value="$(_html_escape(_sort_value(t, :priority)))">$pri</td>""")
        print(io, """<td data-sort-value="$(_html_escape(_sort_value(t, :description)))">$(_html_escape(t.description))</td>""")
        print(io, """<td data-sort-value="$(_html_escape(_sort_value(t, :tags)))">$(_tags_html(t))</td>""")
        print(io, """<td class="todo-date" data-sort-value="$(_html_escape(_sort_value(t, :creation_date)))">$(_date_str(t.creation_date))</td>""")
        print(io, """<td class="todo-date" data-sort-value="$(_html_escape(_sort_value(t, :completion_date)))">$(_date_str(t.completion_date))</td>""")
        print(io, "</tr>")
    end
    print(io, "</tbody></table></div>")
    print(io, """
    <script>
    (function(){
      var sortCol=null, sortAsc=true;
      window.todoSort_$tid=function(col){
        var table=document.getElementById("$tid");
        var tbody=table.querySelector("tbody");
        var rows=Array.from(tbody.querySelectorAll("tr"));
        if(sortCol===col){sortAsc=!sortAsc}else{sortCol=col;sortAsc=true}
        rows.sort(function(a,b){
          var av=a.cells[col-1].getAttribute("data-sort-value")||"";
          var bv=b.cells[col-1].getAttribute("data-sort-value")||"";
          return sortAsc?av.localeCompare(bv):bv.localeCompare(av);
        });
        rows.forEach(function(r){tbody.appendChild(r)});
        table.querySelectorAll(".todo-sort-arrow").forEach(function(el){el.textContent=""});
        var arrow=document.getElementById("$(tid)_arrow_"+col);
        if(arrow)arrow.textContent=sortAsc?"\\u25B2":"\\u25BC";
      };
    })();
    </script>""")
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

"""
    GanttView

A Gantt chart HTML view of a [`TodoFile`](@ref). Tasks are displayed as horizontal bars
on a timeline. A task needs a `creation_date` (start) and either a `due` metadata key or
`completion_date` (end) to appear on the chart.

### Examples
```julia
julia> tf = TodoFile("todo.txt")

julia> GanttView(tf)
GanttView(3 tasks)
```
"""
struct GanttView
    todofile::TodoFile
end

Base.show(io::IO, v::GanttView) = print(io, "GanttView($(length(v.todofile)) tasks)")

function _gantt_dates(t::Todo)
    start = t.creation_date
    isnothing(start) && return nothing
    due_str = get(t.metadata, "due", "")
    finish = if !isempty(due_str)
        tryparse(Date, due_str)
    elseif t.completed && !isnothing(t.completion_date)
        t.completion_date
    else
        nothing
    end
    isnothing(finish) && return nothing
    finish < start && return nothing
    return (start, finish)
end

function _gantt_bar_class(t::Todo)
    cls = if isnothing(t.priority); "todo-gantt-bar-other"
    elseif t.priority == 'A'; "todo-gantt-bar-a"
    elseif t.priority == 'B'; "todo-gantt-bar-b"
    elseif t.priority == 'C'; "todo-gantt-bar-c"
    else; "todo-gantt-bar-other"
    end
    t.completed ? "$cls todo-gantt-bar-done" : cls
end

function Base.show(io::IO, ::MIME"text/html", v::GanttView)
    # Collect plottable tasks
    items = Tuple{Todo, Date, Date}[]
    for t in v.todofile
        dates = _gantt_dates(t)
        !isnothing(dates) && push!(items, (t, dates[1], dates[2]))
    end
    print(io, _todo_css())
    print(io, """<div class="todo-container">""")
    if isempty(items)
        print(io, """<p style="color:#888;font-style:italic;">No tasks with both a creation date and a due/completion date to display.</p>""")
    else
        min_date = minimum(x[2] for x in items)
        max_date = maximum(x[3] for x in items)
        span = max(Dates.value(max_date - min_date), 1)
        print(io, """<table class="todo-gantt">""")
        print(io, """<thead><tr><th class="todo-gantt-label">Task</th><th>Timeline</th></tr></thead><tbody>""")
        for (t, s, f) in items
            left_pct = round(100.0 * Dates.value(s - min_date) / span, digits=2)
            width_pct = round(100.0 * max(Dates.value(f - s), 1) / span, digits=2)
            width_pct = min(width_pct, 100.0 - left_pct)
            label = _html_escape(t.description)
            bar_cls = _gantt_bar_class(t)
            pri = _priority_html(t.priority)
            print(io, "<tr>")
            print(io, """<td class="todo-gantt-label">$pri $label</td>""")
            print(io, """<td><div class="todo-gantt-track"><div class="todo-gantt-bar $bar_cls" style="left:$(left_pct)%;width:$(width_pct)%" title="$(s) → $(f)"></div></div></td>""")
            print(io, "</tr>")
        end
        print(io, "</tbody></table>")
        print(io, """<div class="todo-gantt-dates"><span>$min_date</span><span>$max_date</span></div>""")
    end
    print(io, "</div>")
end

"""
    DueView

A timeline HTML view of a [`TodoFile`](@ref) showing time remaining until each task is due.
Tasks need a `due` metadata key (e.g. `due:2024-02-01`) to appear. Bars are colored by
urgency: overdue (red), ≤3 days (orange), ≤7 days (yellow), ≤14 days (green), >14 days (blue).

The `today` field defaults to `Dates.today()` but can be overridden for testing.

### Examples
```julia
julia> tf = TodoFile("todo.txt")

julia> DueView(tf)
DueView(3 tasks)
```
"""
struct DueView
    todofile::TodoFile
    today::Date
end
DueView(tf::TodoFile) = DueView(tf, Dates.today())

Base.show(io::IO, v::DueView) = print(io, "DueView($(length(v.todofile)) tasks)")

function _due_date(t::Todo)
    due_str = get(t.metadata, "due", "")
    isempty(due_str) && return nothing
    return tryparse(Date, due_str)
end

function _due_urgency_class(days_remaining::Int)
    if days_remaining < 0
        "todo-due-overdue"
    elseif days_remaining <= 3
        "todo-due-urgent"
    elseif days_remaining <= 7
        "todo-due-soon"
    elseif days_remaining <= 14
        "todo-due-ok"
    else
        "todo-due-plenty"
    end
end

function _due_label(days_remaining::Int)
    if days_remaining < 0
        "$(abs(days_remaining))d overdue"
    elseif days_remaining == 0
        "due today"
    elseif days_remaining == 1
        "1 day left"
    else
        "$days_remaining days left"
    end
end

function Base.show(io::IO, ::MIME"text/html", v::DueView)
    today = v.today
    items = Tuple{Todo, Date, Int}[]
    for t in v.todofile
        t.completed && continue
        due = _due_date(t)
        isnothing(due) && continue
        days = Dates.value(due - today)
        push!(items, (t, due, days))
    end
    sort!(items, by = x -> x[3])
    print(io, _todo_css())
    print(io, """<div class="todo-container">""")
    if isempty(items)
        print(io, """<p style="color:#888;font-style:italic;">No pending tasks with a due date to display.</p>""")
    else
        min_days = minimum(x[3] for x in items)
        max_days = maximum(x[3] for x in items)
        range_start = min(min_days, 0)
        range_end = max(max_days, 1)
        span = range_end - range_start
        span = max(span, 1)
        today_pct = round(100.0 * (0 - range_start) / span, digits=2)
        print(io, """<table class="todo-gantt">""")
        print(io, """<thead><tr><th class="todo-gantt-label">Task</th><th>Time to Due Date</th><th class="todo-due-label" style="text-align:right;">Status</th></tr></thead><tbody>""")
        for (t, due, days) in items
            cls = _due_urgency_class(days)
            label = _html_escape(t.description)
            pri = _priority_html(t.priority)
            status = _due_label(days)
            if days < 0
                bar_end = 0 - range_start
                bar_start = days - range_start
                left_pct = round(100.0 * bar_start / span, digits=2)
                width_pct = round(100.0 * (bar_end - bar_start) / span, digits=2)
            else
                bar_start = 0 - range_start
                bar_end = days - range_start
                left_pct = round(100.0 * bar_start / span, digits=2)
                width_pct = round(100.0 * max(bar_end - bar_start, 0.5) / span, digits=2)
            end
            width_pct = min(width_pct, 100.0 - left_pct)
            print(io, "<tr>")
            print(io, """<td class="todo-gantt-label">$pri $label</td>""")
            print(io, """<td><div class="todo-due-track">""")
            print(io, """<div class="todo-due-today" style="left:$(today_pct)%" title="today"></div>""")
            print(io, """<div class="todo-due-bar $cls" style="left:$(left_pct)%;width:$(width_pct)%" title="due: $due ($status)"></div>""")
            print(io, """</div></td>""")
            print(io, """<td class="todo-due-label" style="text-align:right;color:$(days < 0 ? "#e53935" : days <= 3 ? "#e65100" : "#333")">$status</td>""")
            print(io, "</tr>")
        end
        print(io, "</tbody></table>")
        print(io, """<div class="todo-gantt-dates"><span>$(today + Day(range_start))</span><span style="font-weight:600;">today ($today)</span><span>$(today + Day(range_end))</span></div>""")
    end
    print(io, "</div>")
end

# Default HTML for TodoFile delegates to ListView
function Base.show(io::IO, mime::MIME"text/html", tf::TodoFile)
    show(io, mime, ListView(tf))
end

"""
    html_view(tf::TodoFile; view::Symbol=:list, group_by::Symbol=:priority)

Create an HTML view of a [`TodoFile`](@ref) for rich display in notebooks.

Returns a [`ListView`](@ref), [`TableView`](@ref), [`KanbanView`](@ref), [`GanttView`](@ref), or [`DueView`](@ref).

### Examples
```julia
julia> tf = TodoFile("todo.txt")

julia> html_view(tf)
ListView(3 tasks)

julia> html_view(tf; view=:table)
TableView(3 tasks)

julia> html_view(tf; view=:kanban, group_by=:projects)
KanbanView(3 tasks, group_by=:projects)

julia> html_view(tf; view=:gantt)
GanttView(3 tasks)

julia> html_view(tf; view=:due)
DueView(3 tasks)
```
"""
function html_view(tf::TodoFile; view::Symbol=:list, group_by::Symbol=:priority)
    if view == :list
        return ListView(tf)
    elseif view == :table
        return TableView(tf)
    elseif view == :kanban
        return KanbanView(tf, group_by)
    elseif view == :gantt
        return GanttView(tf)
    elseif view == :due
        return DueView(tf)
    else
        error("Invalid view: $view. Use :list, :table, :kanban, :gantt, or :due.")
    end
end

#--------------------------------------------------------------------------------# MarkdownTodoFile Views
_to_todofile(mf::MarkdownTodoFile) = TodoFile(mf.filepath, collect(mf))

function _with_section_metadata(mf::MarkdownTodoFile)
    todos = Todo[]
    for s in mf.sections
        section_name = isempty(s.heading) ? "(no section)" : s.heading
        for t in s.todos
            meta = copy(t.metadata)
            meta["_section"] = section_name
            push!(todos, Todo(t.completed, t.priority, t.completion_date, t.creation_date, t.description, copy(t.contexts), copy(t.projects), meta, Todo[]))
            for st in t.subtasks
                smeta = copy(st.metadata)
                smeta["_section"] = section_name
                push!(todos, Todo(st.completed, st.priority, st.completion_date, st.creation_date, st.description, copy(st.contexts), copy(st.projects), smeta, Todo[]))
            end
        end
    end
    TodoFile(mf.filepath, todos)
end

ListView(mf::MarkdownTodoFile) = ListView(_to_todofile(mf))
TableView(mf::MarkdownTodoFile) = TableView(_to_todofile(mf))
GanttView(mf::MarkdownTodoFile) = GanttView(_to_todofile(mf))
DueView(mf::MarkdownTodoFile) = DueView(_to_todofile(mf))
DueView(mf::MarkdownTodoFile, today::Date) = DueView(_to_todofile(mf), today)

function KanbanView(mf::MarkdownTodoFile, group_by::Symbol=:priority)
    if group_by == :section
        KanbanView(_with_section_metadata(mf), group_by)
    else
        KanbanView(_to_todofile(mf), group_by)
    end
end

"""
    html_view(mf::MarkdownTodoFile; view::Symbol=:list, group_by::Symbol=:priority)

Create an HTML view of a [`MarkdownTodoFile`](@ref). See [`html_view(::TodoFile)`](@ref) for options.
"""
function html_view(mf::MarkdownTodoFile; view::Symbol=:list, group_by::Symbol=:priority)
    if view == :list
        return ListView(mf)
    elseif view == :table
        return TableView(mf)
    elseif view == :kanban
        return KanbanView(mf, group_by)
    elseif view == :gantt
        return GanttView(mf)
    elseif view == :due
        return DueView(mf)
    else
        error("Invalid view: $view. Use :list, :table, :kanban, :gantt, or :due.")
    end
end

function Base.show(io::IO, mime::MIME"text/html", mf::MarkdownTodoFile)
    show(io, mime, ListView(mf))
end

end # module
