# JCGEImportMPSGE Changelog
All notable changes to this project will be documented in this file.
Releases use semantic versioning as in 'MAJOR.MINOR.PATCH'.

## Change entries
Added: For new features that have been added.
Changed: For changes in existing functionality.
Deprecated: For once-stable features removed in upcoming releases.
Removed: For features removed in this release.
Fixed: For any bug fixes.
Security: For vulnerabilities.

## [0.1.0] - unreleased
### Added
- `import_mpsge` entrypoint converting `MPSGEModel` objects to JCGE RunSpecs.
- Minimal importer that builds production, household, market, and numeraire blocks from netputs, final demands, and endowments.
- Data-assisted importer that assembles full block suites (trade, prices, production, labor, government, savings, external) and initial values from precomputed tables.
- MCP-style spec generation with closure and scenario wiring plus label normalization for indexed MPSGE symbols.
