// This file is a part of Julia. License is MIT: https://julialang.org/license

// Declarations for debuginfo.cpp
void jl_jit_add_bytes(size_t bytes) JL_NOTSAFEPOINT;

int jl_DI_for_fptr(uint64_t fptr, uint64_t *symsize, int64_t *slide,
        llvm::object::SectionRef *Section, llvm::DIContext **context) JL_NOTSAFEPOINT;

bool jl_dylib_DI_for_fptr(size_t pointer, llvm::object::SectionRef *Section, int64_t *slide, llvm::DIContext **context,
    bool onlyImage, bool *isImage, uint64_t* fbase, void **saddr, char **name, char **filename) JL_NOTSAFEPOINT;

static object::SectionedAddress makeAddress(
        llvm::object::SectionRef Section, uint64_t address) JL_NOTSAFEPOINT
{
    return object::SectionedAddress{address, Section.getIndex()};
}
