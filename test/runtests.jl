using TodoFiles
using Dates
using Tables
using Test

@testset "TodoFiles.jl" begin
    @testset "parse simple task" begin
        t = parse_todo("Call Mom")
        @test t.completed == false
        @test t.priority === nothing
        @test t.completion_date === nothing
        @test t.creation_date === nothing
        @test t.description == "Call Mom"
        @test t.contexts == []
        @test t.projects == []
        @test t.metadata == Dict()
    end

    @testset "parse task with priority" begin
        t = parse_todo("(A) Call Mom")
        @test t.priority == 'A'
        @test t.description == "Call Mom"

        t2 = parse_todo("(Z) Low priority task")
        @test t2.priority == 'Z'
    end

    @testset "parse task with creation date" begin
        t = parse_todo("2024-01-15 Call Mom")
        @test t.creation_date == Date(2024, 1, 15)
        @test t.description == "Call Mom"
    end

    @testset "parse task with priority and creation date" begin
        t = parse_todo("(A) 2024-01-15 Call Mom")
        @test t.priority == 'A'
        @test t.creation_date == Date(2024, 1, 15)
        @test t.description == "Call Mom"
    end

    @testset "parse completed task" begin
        t = parse_todo("x 2024-01-16 2024-01-15 Call Mom")
        @test t.completed == true
        @test t.completion_date == Date(2024, 1, 16)
        @test t.creation_date == Date(2024, 1, 15)
        @test t.description == "Call Mom"
    end

    @testset "parse completed task with only completion date" begin
        t = parse_todo("x 2024-01-16 Call Mom")
        @test t.completed == true
        @test t.completion_date == Date(2024, 1, 16)
        @test t.description == "Call Mom"
    end

    @testset "parse completed task without dates" begin
        t = parse_todo("x Call Mom")
        @test t.completed == true
        @test t.completion_date === nothing
        @test t.description == "Call Mom"
    end

    @testset "contexts" begin
        t = parse_todo("Call Mom @phone @home")
        @test t.description == "Call Mom"
        @test t.contexts == ["phone", "home"]
        @test t.contexts == ["phone", "home"]
    end

    @testset "projects" begin
        t = parse_todo("Call Mom +Family +Health")
        @test t.description == "Call Mom"
        @test t.projects == ["Family", "Health"]
        @test t.projects == ["Family", "Health"]
    end

    @testset "metadata" begin
        t = parse_todo("Call Mom due:2024-01-20 effort:low")
        @test t.description == "Call Mom"
        m = t.metadata
        @test m["due"] == "2024-01-20"
        @test m["effort"] == "low"
        @test t.metadata == Dict("due" => "2024-01-20", "effort" => "low")
    end

    @testset "contexts, projects, and metadata together" begin
        t = parse_todo("(A) 2024-01-15 Call Mom +Family @phone due:2024-01-20")
        @test t.priority == 'A'
        @test t.creation_date == Date(2024, 1, 15)
        @test t.description == "Call Mom"
        @test t.contexts == ["phone"]
        @test t.projects == ["Family"]
        @test t.metadata["due"] == "2024-01-20"
    end

    @testset "write_todo roundtrip" begin
        lines = [
            "(A) Call Mom",
            "(B) 2024-01-15 Buy groceries @store +Errands",
            "x 2024-01-16 2024-01-15 Pay bills",
            "x 2024-01-16 Clean house",
            "Simple task",
        ]
        for line in lines
            @test write_todo(parse_todo(line)) == line
        end
    end

    @testset "parse_todos" begin
        text = """
        (A) Call Mom @phone
        (B) Buy groceries @store +Errands

        x 2024-01-15 Pay bills
        """
        todos = parse_todos(text)
        @test length(todos) == 3
        @test todos[1].priority == 'A'
        @test todos[2].priority == 'B'
        @test todos[3].completed == true
    end

    @testset "write_todos" begin
        todos = [
            Todo("Call Mom"; priority='A'),
            Todo("Buy groceries"; priority='B'),
        ]
        result = write_todos(todos)
        @test result == "(A) Call Mom\n(B) Buy groceries\n"
    end

    @testset "file I/O roundtrip" begin
        todos = [
            Todo("Call Mom +Family @phone"; priority='A', creation_date=Date(2024, 1, 15)),
            Todo("Pay bills"; completed=true, completion_date=Date(2024, 1, 16)),
            Todo("Buy groceries @store +Errands"),
        ]
        mktempdir() do dir
            filepath = joinpath(dir, "todo.txt")
            write_todos(filepath, todos)
            loaded = read_todos(filepath)
            @test length(loaded) == 3
            @test loaded == todos
        end
    end

    @testset "Todo constructor with keyword arguments" begin
        t = Todo("Call Mom"; priority='A', creation_date=Date(2024, 1, 15))
        @test t.priority == 'A'
        @test t.creation_date == Date(2024, 1, 15)
        @test t.completed == false
        @test t.description == "Call Mom"
    end

    @testset "Todo constructor extracts tags from description" begin
        t = Todo("Call Mom @phone +Family due:2024-01-20")
        @test t.description == "Call Mom"
        @test t.contexts == ["phone"]
        @test t.projects == ["Family"]
        @test t.metadata == Dict("due" => "2024-01-20")
    end

    @testset "Todo constructor with explicit tags overrides extraction" begin
        t = Todo("Call Mom @phone"; contexts=["work"])
        @test t.description == "Call Mom"
        @test t.contexts == ["work"]
    end

    @testset "equality" begin
        t1 = parse_todo("(A) Call Mom")
        t2 = parse_todo("(A) Call Mom")
        @test t1 == t2
        t3 = parse_todo("(B) Call Mom")
        @test t1 != t3
    end

    @testset "canonical write order" begin
        t = parse_todo("(A) Call Mom +Family @phone due:2024-01-20")
        @test write_todo(t) == "(A) Call Mom @phone +Family due:2024-01-20"
    end

    @testset "TodoFile" begin
        todos = [
            Todo("Call Mom @phone +Family"; priority='A', creation_date=Date(2024, 1, 15)),
            Todo("Pay bills"; completed=true, completion_date=Date(2024, 1, 16)),
            Todo("Buy groceries @store +Errands"),
        ]

        @testset "construction and file I/O" begin
            mktempdir() do dir
                filepath = joinpath(dir, "todo.txt")
                write_todos(filepath, todos)

                tf = TodoFile(filepath)
                @test tf.filepath == filepath
                @test length(tf) == 3
                @test tf[1] == todos[1]
                @test tf[2] == todos[2]
                @test tf[3] == todos[3]
            end
        end

        @testset "iterate" begin
            mktempdir() do dir
                filepath = joinpath(dir, "todo.txt")
                write_todos(filepath, todos)
                tf = TodoFile(filepath)
                @test collect(tf) == todos
                @test eltype(TodoFile) == Todo
            end
        end

        @testset "write_todos roundtrip" begin
            mktempdir() do dir
                filepath = joinpath(dir, "todo.txt")
                write_todos(filepath, todos)
                tf = TodoFile(filepath)

                # Write back to file via TodoFile method
                write_todos(tf)
                tf2 = TodoFile(filepath)
                @test collect(tf2) == collect(tf)
            end
        end

        @testset "show" begin
            mktempdir() do dir
                filepath = joinpath(dir, "todo.txt")
                write_todos(filepath, todos)
                tf = TodoFile(filepath)
                s = sprint(show, tf)
                @test contains(s, "TodoFile")
                @test contains(s, "3 tasks")
            end
        end
    end

    @testset "Tables.jl integration" begin
        todos = [
            Todo("Call Mom @phone +Family"; priority='A', creation_date=Date(2024, 1, 15)),
            Todo("Pay bills"; completed=true, completion_date=Date(2024, 1, 16)),
        ]

        mktempdir() do dir
            filepath = joinpath(dir, "todo.txt")
            write_todos(filepath, todos)
            tf = TodoFile(filepath)

            @testset "istable and rowaccess" begin
                @test Tables.istable(TodoFile)
                @test Tables.rowaccess(TodoFile)
            end

            @testset "schema" begin
                sch = Tables.schema(tf)
                @test sch.names == fieldnames(Todo)
                @test sch.types[1] == Bool
                @test sch.types[5] == String
            end

            @testset "rows" begin
                rows = Tables.rows(tf)
                @test length(rows) == 2
                @test rows[1] == todos[1]
            end

            @testset "columnnames and getcolumn on Todo" begin
                t = tf[1]
                @test Tables.columnnames(t) == fieldnames(Todo)
                @test Tables.getcolumn(t, :priority) == 'A'
                @test Tables.getcolumn(t, :description) == "Call Mom"
                @test Tables.getcolumn(t, :contexts) == ["phone"]
                @test Tables.getcolumn(t, 1) == false  # completed
                @test Tables.getcolumn(t, 5) == "Call Mom"  # description
            end

            @testset "columntable roundtrip" begin
                ct = Tables.columntable(tf)
                @test ct.description == ["Call Mom", "Pay bills"]
                @test ct.completed == [false, true]
                @test ct.priority == ['A', nothing]
            end

            @testset "rowtable roundtrip" begin
                rt = Tables.rowtable(tf)
                @test length(rt) == 2
                @test rt[1].description == "Call Mom"
                @test rt[2].completed == true
            end
        end
    end

    @testset "HTML Views" begin
        todos = [
            Todo("Call Mom @phone +Family"; priority='A', creation_date=Date(2024, 1, 15)),
            Todo("Pay bills"; completed=true, completion_date=Date(2024, 1, 16)),
            Todo("Buy groceries @store +Errands"),
        ]

        mktempdir() do dir
            filepath = joinpath(dir, "todo.txt")
            write_todos(filepath, todos)
            tf = TodoFile(filepath)

            @testset "ListView" begin
                lv = ListView(tf)
                @test sprint(show, lv) == "ListView(3 tasks)"
                html = sprint(show, MIME("text/html"), lv)
                @test contains(html, "todo-container")
                @test contains(html, "todo-card")
                @test contains(html, "Call Mom")
                @test contains(html, "Pay bills")
                @test contains(html, "todo-done")
                @test contains(html, "@phone")
                @test contains(html, "+Family")
                @test contains(html, "todo-priority-a")
            end

            @testset "TableView" begin
                tv = TableView(tf)
                @test sprint(show, tv) == "TableView(3 tasks)"
                html = sprint(show, MIME("text/html"), tv)
                @test contains(html, "todo-table")
                @test contains(html, "Description")
                @test contains(html, "Call Mom")
                @test contains(html, "2024-01-15")
                @test contains(html, "2024-01-16")
                # Sortable columns
                @test contains(html, "data-sort-value")
                @test contains(html, "todoSort_")
                @test contains(html, "todo-sort-arrow")
            end

            @testset "KanbanView" begin
                kv = KanbanView(tf, :priority)
                @test sprint(show, kv) == "KanbanView(3 tasks, group_by=:priority)"
                html = sprint(show, MIME("text/html"), kv)
                @test contains(html, "todo-kanban")
                @test contains(html, "todo-kanban-col")
                @test contains(html, "(none)")

                kv2 = KanbanView(tf)
                @test kv2.group_by == :priority

                kv3 = KanbanView(tf, :completed)
                html3 = sprint(show, MIME("text/html"), kv3)
                @test contains(html3, "Pending")
                @test contains(html3, "Done")

                kv4 = KanbanView(tf, :projects)
                html4 = sprint(show, MIME("text/html"), kv4)
                @test contains(html4, "Family")
                @test contains(html4, "Errands")
                @test contains(html4, "(no project)")

                kv5 = KanbanView(tf, :contexts)
                html5 = sprint(show, MIME("text/html"), kv5)
                @test contains(html5, "phone")
                @test contains(html5, "store")
                @test contains(html5, "(no context)")
            end

            @testset "TodoFile HTML show delegates to ListView" begin
                html_tf = sprint(show, MIME("text/html"), tf)
                html_lv = sprint(show, MIME("text/html"), ListView(tf))
                @test html_tf == html_lv
            end

            @testset "GanttView" begin
                gantt_todos = [
                    Todo("Build feature"; priority='A', creation_date=Date(2024, 1, 1), metadata=Dict("due" => "2024-01-15")),
                    Todo("Write tests"; priority='B', creation_date=Date(2024, 1, 10), metadata=Dict("due" => "2024-01-20")),
                    Todo("Deploy"; completed=true, creation_date=Date(2024, 1, 5), completion_date=Date(2024, 1, 12)),
                    Todo("No dates task"),
                    Todo("Only start"; creation_date=Date(2024, 1, 1)),
                ]
                write_todos(filepath, gantt_todos)
                gtf = TodoFile(filepath)

                gv = GanttView(gtf)
                @test sprint(show, gv) == "GanttView(5 tasks)"

                html = sprint(show, MIME("text/html"), gv)
                @test contains(html, "todo-gantt")
                @test contains(html, "Build feature")
                @test contains(html, "Write tests")
                @test contains(html, "Deploy")
                # Tasks without both dates are excluded from bars
                @test !contains(html, "No dates task")
                @test !contains(html, "Only start")
                # Check date range labels
                @test contains(html, "2024-01-01")
                @test contains(html, "2024-01-20")
                # Check priority colors
                @test contains(html, "todo-gantt-bar-a")
                @test contains(html, "todo-gantt-bar-b")
                # Completed task has done class
                @test contains(html, "todo-gantt-bar-done")

                # Empty gantt (no plottable tasks)
                empty_todos = [Todo("No dates")]
                write_todos(filepath, empty_todos)
                etf = TodoFile(filepath)
                empty_html = sprint(show, MIME("text/html"), GanttView(etf))
                @test contains(empty_html, "No tasks with both")
            end

            @testset "DueView" begin
                today = Date(2024, 1, 15)
                due_todos = [
                    Todo("Overdue task"; priority='A', metadata=Dict("due" => "2024-01-10")),
                    Todo("Due today"; priority='B', metadata=Dict("due" => "2024-01-15")),
                    Todo("Due soon"; metadata=Dict("due" => "2024-01-17")),
                    Todo("Due later"; metadata=Dict("due" => "2024-02-01")),
                    Todo("No due date"),
                    Todo("Completed"; completed=true, metadata=Dict("due" => "2024-01-20")),
                ]
                write_todos(filepath, due_todos)
                dtf = TodoFile(filepath)

                dv = DueView(dtf, today)
                @test sprint(show, dv) == "DueView(6 tasks)"

                html = sprint(show, MIME("text/html"), dv)
                @test contains(html, "todo-due-track")
                @test contains(html, "Overdue task")
                @test contains(html, "Due today")
                @test contains(html, "Due soon")
                @test contains(html, "Due later")
                # No due date excluded
                @test !contains(html, "No due date")
                # Completed tasks excluded
                @test !contains(html, "Completed")
                # Urgency classes
                @test contains(html, "todo-due-overdue")
                @test contains(html, "todo-due-urgent")
                @test contains(html, "todo-due-plenty")
                # Status labels
                @test contains(html, "5d overdue")
                @test contains(html, "due today")
                @test contains(html, "2 days left")
                @test contains(html, "17 days left")
                # Today marker
                @test contains(html, "todo-due-today")

                # Default constructor uses Dates.today()
                dv2 = DueView(dtf)
                @test dv2.today == Dates.today()

                # Empty (no pending tasks with due dates)
                empty_todos = [Todo("No dates")]
                write_todos(filepath, empty_todos)
                etf = TodoFile(filepath)
                empty_html = sprint(show, MIME("text/html"), DueView(etf, today))
                @test contains(empty_html, "No pending tasks with a due date")
            end

            @testset "html_view convenience function" begin
                @test html_view(tf) isa ListView
                @test html_view(tf; view=:list) isa ListView
                @test html_view(tf; view=:table) isa TableView
                @test html_view(tf; view=:kanban) isa KanbanView
                @test html_view(tf; view=:kanban).group_by == :priority
                @test html_view(tf; view=:kanban, group_by=:projects).group_by == :projects
                @test html_view(tf; view=:gantt) isa GanttView
                @test html_view(tf; view=:due) isa DueView
                @test_throws ErrorException html_view(tf; view=:invalid)
            end

            @testset "HTML escaping" begin
                escaped_todos = [Todo("Buy <milk> & \"eggs\"")]
                write_todos(filepath, escaped_todos)
                tf2 = TodoFile(filepath)
                html = sprint(show, MIME("text/html"), ListView(tf2))
                @test contains(html, "&lt;milk&gt;")
                @test contains(html, "&amp;")
                @test contains(html, "&quot;eggs&quot;")
                @test !contains(html, "<milk>")
            end
        end
    end

    @testset "MarkdownTodoFile" begin
        md_text = """
        # Work
        - (A) Finish report @office
        - Email client @office +ClientProject

        ## Personal
        - Buy groceries @store +Errands
        - (B) Call Mom @phone +Family
        """

        @testset "parse_markdown_todos" begin
            sections = parse_markdown_todos(md_text)
            @test length(sections) == 2
            @test sections[1].heading == "Work"
            @test sections[1].level == 1
            @test length(sections[1].todos) == 2
            @test sections[2].heading == "Personal"
            @test sections[2].level == 2
            @test length(sections[2].todos) == 2
        end

        @testset "parse fields" begin
            sections = parse_markdown_todos(md_text)
            t = sections[1].todos[1]
            @test t.priority == 'A'
            @test t.description == "Finish report"
            @test t.contexts == ["office"]
            t2 = sections[2].todos[1]
            @test t2.description == "Buy groceries"
            @test t2.contexts == ["store"]
            @test t2.projects == ["Errands"]
        end

        @testset "todos before any heading" begin
            text = """
            - Orphan task
            # Section
            - Task in section
            """
            sections = parse_markdown_todos(text)
            @test length(sections) == 2
            @test sections[1].heading == ""
            @test sections[1].level == 0
            @test length(sections[1].todos) == 1
            @test sections[1].todos[1].description == "Orphan task"
            @test sections[2].heading == "Section"
            @test sections[2].level == 1
        end

        @testset "empty heading section" begin
            text = """
            # Empty
            # Has tasks
            - A task
            """
            sections = parse_markdown_todos(text)
            @test length(sections) == 2
            @test sections[1].heading == "Empty"
            @test isempty(sections[1].todos)
            @test sections[2].heading == "Has tasks"
            @test length(sections[2].todos) == 1
        end

        @testset "multi-level headers" begin
            text = """
            # Level 1
            - Task 1
            ## Level 2
            - Task 2
            ### Level 3
            - Task 3
            """
            sections = parse_markdown_todos(text)
            @test length(sections) == 3
            @test sections[1].level == 1
            @test sections[2].level == 2
            @test sections[3].level == 3
        end

        @testset "write_markdown_todos roundtrip" begin
            sections = parse_markdown_todos(md_text)
            written = write_markdown_todos(sections)
            reparsed = parse_markdown_todos(written)
            @test length(reparsed) == length(sections)
            for (a, b) in zip(sections, reparsed)
                @test a.heading == b.heading
                @test a.level == b.level
                @test a.todos == b.todos
            end
        end

        @testset "write_markdown_todos format" begin
            sections = [
                TodoSection("Work", 1, [Todo("Task A"; priority='A')]),
                TodoSection("Personal", 2, [Todo("Task B")]),
            ]
            result = write_markdown_todos(sections)
            @test contains(result, "# Work\n- (A) Task A")
            @test contains(result, "## Personal\n- Task B")
            # Blank line between sections
            @test contains(result, "\n\n## Personal")
        end

        @testset "file I/O roundtrip" begin
            sections = parse_markdown_todos(md_text)
            mktempdir() do dir
                filepath = joinpath(dir, "todos.md")
                write_markdown_todos(filepath, sections)
                loaded = read_markdown_todos(filepath)
                @test length(loaded) == length(sections)
                for (a, b) in zip(sections, loaded)
                    @test a.heading == b.heading
                    @test a.level == b.level
                    @test a.todos == b.todos
                end
            end
        end

        @testset "MarkdownTodoFile constructor and methods" begin
            sections = parse_markdown_todos(md_text)
            mktempdir() do dir
                filepath = joinpath(dir, "todos.md")
                write_markdown_todos(filepath, sections)
                mf = MarkdownTodoFile(filepath)

                @test mf.filepath == filepath
                @test length(mf.sections) == 2
                @test length(mf) == 4
                @test eltype(MarkdownTodoFile) == Todo
                @test mf[1].description == "Finish report"
                @test mf[4].description == "Call Mom"
                @test collect(mf) == vcat([s.todos for s in sections]...)

                # show
                s = sprint(show, mf)
                @test contains(s, "MarkdownTodoFile")
                @test contains(s, "2 sections")
                @test contains(s, "4 tasks")

                # TodoSection show
                ss = sprint(show, mf.sections[1])
                @test contains(ss, "TodoSection")
                @test contains(ss, "Work")

                # write_todos roundtrip
                write_todos(mf)
                mf2 = MarkdownTodoFile(filepath)
                @test collect(mf2) == collect(mf)
            end
        end

        @testset "MarkdownTodoFile views" begin
            sections = parse_markdown_todos(md_text)
            mktempdir() do dir
                filepath = joinpath(dir, "todos.md")
                write_markdown_todos(filepath, sections)
                mf = MarkdownTodoFile(filepath)

                @test ListView(mf) isa ListView
                @test TableView(mf) isa TableView
                @test KanbanView(mf) isa KanbanView
                @test GanttView(mf) isa GanttView
                @test DueView(mf) isa DueView

                # ListView HTML renders all todos
                html = sprint(show, MIME("text/html"), ListView(mf))
                @test contains(html, "Finish report")
                @test contains(html, "Buy groceries")

                # MarkdownTodoFile HTML show delegates to ListView
                html_mf = sprint(show, MIME("text/html"), mf)
                html_lv = sprint(show, MIME("text/html"), ListView(mf))
                @test html_mf == html_lv

                # html_view convenience
                @test html_view(mf) isa ListView
                @test html_view(mf; view=:table) isa TableView
                @test html_view(mf; view=:kanban) isa KanbanView
                @test html_view(mf; view=:gantt) isa GanttView
                @test html_view(mf; view=:due) isa DueView
                @test_throws ErrorException html_view(mf; view=:invalid)
            end
        end

        @testset "KanbanView with :section group_by" begin
            sections = parse_markdown_todos(md_text)
            mktempdir() do dir
                filepath = joinpath(dir, "todos.md")
                write_markdown_todos(filepath, sections)
                mf = MarkdownTodoFile(filepath)

                kv = KanbanView(mf, :section)
                html = sprint(show, MIME("text/html"), kv)
                @test contains(html, "Work")
                @test contains(html, "Personal")
                @test contains(html, "Finish report")
                @test contains(html, "Buy groceries")
                # Internal _section metadata should not appear as a pill
                @test !contains(html, "_section")
            end
        end
    end
end
