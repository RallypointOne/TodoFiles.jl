using TodoFiles
using Dates
using Test

@testset "TodoFiles.jl" begin
    @testset "parse simple task" begin
        t = parse_todo("Call Mom")
        @test t.completed == false
        @test t.priority === nothing
        @test t.completion_date === nothing
        @test t.creation_date === nothing
        @test t.description == "Call Mom"
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
        @test contexts(t) == ["phone", "home"]
    end

    @testset "projects" begin
        t = parse_todo("Call Mom +Family +Health")
        @test projects(t) == ["Family", "Health"]
    end

    @testset "metadata" begin
        t = parse_todo("Call Mom due:2024-01-20 effort:low")
        m = metadata(t)
        @test m["due"] == "2024-01-20"
        @test m["effort"] == "low"
    end

    @testset "contexts, projects, and metadata together" begin
        t = parse_todo("(A) 2024-01-15 Call Mom +Family @phone due:2024-01-20")
        @test t.priority == 'A'
        @test t.creation_date == Date(2024, 1, 15)
        @test contexts(t) == ["phone"]
        @test projects(t) == ["Family"]
        @test metadata(t)["due"] == "2024-01-20"
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

    @testset "equality" begin
        t1 = parse_todo("(A) Call Mom")
        t2 = parse_todo("(A) Call Mom")
        @test t1 == t2
        t3 = parse_todo("(B) Call Mom")
        @test t1 != t3
    end
end
