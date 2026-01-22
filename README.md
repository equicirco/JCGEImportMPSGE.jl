<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/src/assets/jcge_importmpsge_logo_dark.png">
  <source media="(prefers-color-scheme: light)" srcset="docs/src/assets/jcge_importmpsge_logo_light.png">
  <img alt="JCGE ImportMPSGE logo" src="docs/src/assets/jcge_importmpsge_logo_light.png" height="150">
</picture>

# JCGEImportMPSGE

## What is a CGE?
A Computable General Equilibrium (CGE) model is a quantitative economic model that represents an economy as interconnected markets for goods and services, factors of production, institutions, and the rest of the world. It is calibrated with data (typically a Social Accounting Matrix) and solved numerically as a system of nonlinear equations until equilibrium conditions (zero-profit, market-clearing, and income-balance) hold within tolerance.

## What is JCGE?
[JCGE](https://jcge.org) is a block-based CGE modeling and execution framework in Julia. It defines a shared RunSpec structure and reusable blocks so models can be assembled, validated, solved, and compared consistently across packages.

## What is this package?
Placeholder for a converter that lowers MPSGE.jl model objects into [JCGE](https://jcge.org) blocks.

Scope:
- Import MPSGE.jl model objects (not the MPSGE language as a first-class input).
- Act as a converter + conformance test harness for block-based models.

Input:
- An `MPSGEModel` object (constructed via MPSGE.jl macros).
- Optional calibration data for complex models (e.g., trade and tax blocks).

Translation:
- sectors/commodities/consumers → corresponding block entities
- each `@production` tree → production block (nest structure + elasticities + quantities)
- each `@demand` → household/institution block (final demands + endowments + transfers)
- taxes/margins (if present) → tax blocks / wedges routed to agents
- numeraire/fixed variables → RunSpec closures/fixes/normalization fields

Output:
- `RunSpec` (what to solve, closures, shocks/scenarios)
- generated block model instance (the “what” to solve)

## API (v0.1)

```julia
using MPSGE
using JCGEImportMPSGE

m = MPSGEModel()
# ... define sectors/commodities/consumers/production/demand with MPSGE.jl macros ...

spec = import_mpsge(m; name="MyMPSGE")
```

## Current coverage

- Scalar sectors, commodities, and consumers
- Fixed-coefficient (Leontief) production from `@production` netputs
- Cobb-Douglas demand from `@final_demand`
- Endowments from `@endowment`
- Commodity market clearing with MCP complementarity (MCP-only import)
- Optional data-assisted import to populate full block sets for complex models

Unsupported MPSGE features (for now):
- Nested production trees (beyond flat netputs)
- Non-Cobb-Douglas demand
- Taxes, margins, and auxiliary constraints
- Multi-region indexing

## Solving

`import_mpsge` always produces an MCP formulation (no objective). Use
PATH via `PATHSolver.Optimizer` to solve the imported model.

## How to cite

If you use the [JCGE](https://jcge.org) framework, please cite:

Boero, R. *JCGE - Julia Computable General Equilibrium Framework* [software], 2026.
DOI: 10.5281/zenodo.18282436
URL: https://JCGE.org

```bibtex
@software{boero_jcge_2026,
  title  = {JCGE - Julia Computable General Equilibrium Framework},
  author = {Boero, Riccardo},
  year   = {2026},
  doi    = {10.5281/zenodo.18282436},
  url    = {https://JCGE.org}
}
```

If you use this package, please cite:

Boero, R. *JCGEImportMPSGE.jl - Importer from MPSGE.jl model objects into JCGE.* [software], 2026.
DOI: 10.5281/zenodo.18335430
URL: https://ImportMPSGE.JCGE.org/
SourceCode: https://github.com/equicirco/JCGEImportMPSGE.jl

```bibtex
@software{boero_jcgeimportmpsge_2026,
  title  = {JCGEImportMPSGE.jl - Importer from MPSGE.jl model objects into JCGE.},
  author = {Boero, Riccardo},
  year   = {2026},
  doi    = {10.5281/zenodo.18335430},
  url    = {https://ImportMPSGE.JCGE.org/}
}
```

If you use a specific tagged release, please cite the version DOI assigned on Zenodo for that release (preferred for exact reproducibility).
