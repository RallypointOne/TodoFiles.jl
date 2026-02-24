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
end
