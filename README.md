[![CI](https://github.com/RallypointOne/TodoFiles.jl/actions/workflows/CI.yml/badge.svg)](https://github.com/RallypointOne/TodoFiles.jl/actions/workflows/CI.yml)
[![Docs Build](https://github.com/RallypointOne/TodoFiles.jl/actions/workflows/Docs.yml/badge.svg)](https://github.com/RallypointOne/TodoFiles.jl/actions/workflows/Docs.yml)
[![Stable Docs](https://img.shields.io/badge/docs-stable-blue)](https://RallypointOne.github.io/TodoFiles.jl/stable/)
[![Dev Docs](https://img.shields.io/badge/docs-dev-blue)](https://RallypointOne.github.io/TodoFiles.jl/dev/)

# TodoFiles.jl

A Julia package for reading and writing the [Todo.txt](https://github.com/todotxt/todo.txt) format. Parses todo.txt lines into structured objects with direct access to priorities, dates, contexts, projects, and metadata.

## Installation

```julia
using Pkg
Pkg.add("TodoFiles")
```

## Usage

```julia
using TodoFiles, Dates

# Parse a task
t = parse_todo("(A) 2024-01-15 Call Mom @phone +Family due:2024-01-20")
t.priority    # 'A'
t.contexts    # ["phone"]
t.projects    # ["Family"]
t.metadata    # Dict("due" => "2024-01-20")

# Construct a task (tags are auto-extracted from the description)
t = Todo("Buy groceries @store +Errands"; priority='B', creation_date=Date(2024, 1, 15))

# Write back to Todo.txt format
write_todo(t)  # "(B) 2024-01-15 Buy groceries @store +Errands"

# File I/O
write_todos("todo.txt", [t])
todos = read_todos("todo.txt")
```
