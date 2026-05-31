IO.puts("Hello, World!")

fun = &String.length/1
IO.puts(fun.("Hello, World!"))

add = &+/2
IO.puts(add.(1, 2))
