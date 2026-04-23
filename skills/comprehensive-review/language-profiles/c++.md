## C/C++-Specific Review Context

When reviewing C and C++ code, pay particular attention to:

### Common Bugs
- Use-after-free — pointer used after the pointed-to object has been deallocated; check lifetime of raw pointers
- Double-free — `delete`/`free` called more than once on the same pointer; raw owning pointers should be `nullptr`-ed after free
- Iterator invalidation — modifying a container (`insert`, `erase`, `push_back` causing reallocation) while iterating it
- Uninitialized variables — reading a local variable before assignment; always initialize, especially in C
- Signed integer overflow — undefined behavior in C/C++; use unsigned types or `__builtin_add_overflow`
- Off-by-one in `memcpy`/`memset` size arguments — `sizeof(buf)` vs `sizeof(buf) - 1` for null terminator
- Implicit narrowing conversions — `int` to `char`, `size_t` to `int`, etc.

### Security
- Buffer overflows — `strcpy`/`sprintf`/`gets` without bounds checking; always use `strncpy`/`snprintf`/`fgets` with explicit sizes
- Format string vulnerabilities — `printf(user_input)` where the format string is user-controlled; always use `printf("%s", input)`
- Integer overflow in size calculations before `malloc`/`new` — `malloc(n * sizeof(T))` overflows when `n` is large; use `calloc` or check first
- `system()`/`popen()` with user-controlled strings — shell injection; use `execvp` with argument arrays
- Stack-allocated variable-length arrays (VLAs) from user input — stack overflow; use heap allocation with size validation
- Returning pointers or references to local (stack) variables — dangling pointer/reference

### Idiomatic Modern C++ (C++11 and later)
- Prefer `std::unique_ptr` / `std::shared_ptr` over raw owning pointers — RAII prevents leaks and double-frees
- Prefer `std::array` / `std::vector` over C arrays — bounds checking in debug mode, no decay-to-pointer surprises
- Use `std::string` / `std::string_view` over `const char*` — safer and composable
- `const` correctness — member functions that don't mutate state should be `const`; pass large objects by `const&`
- Move semantics — prefer `std::move` when transferring ownership; avoid unnecessary copies of expensive types
- `nullptr` instead of `NULL` or `0` for null pointers — type-safe
- Range-based `for` loops over index-based where the index is not needed
- `auto` for complex iterator types; avoid `auto` where the type is non-obvious

### Do NOT flag
- `reinterpret_cast` in low-level systems or embedded code where it is the correct tool
- Manual memory management in code that explicitly opts out of RAII for performance reasons — flag only if lifetime is unclear
