# Usage

`JCGEImportMPSGE` converts an `MPSGE.jl` model object into a JCGE RunSpec.

```julia
using MPSGE, JCGEImportMPSGE
m = MPSGEModel()
# define model...
spec = import_mpsge(m)
```

When the source model is complementarity-based, the importer emits MCP blocks
for PATHSolver.

