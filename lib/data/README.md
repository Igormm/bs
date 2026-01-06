# Data Processing Modules

This directory contains data processing and algorithm modules for BOSA framework.

## Modules

### algorithms.sh
Common algorithms and data processing functions.

**Features:**
- Sorting algorithms
- Search algorithms
- Data transformations
- Statistical functions
- Array operations

**Usage:**
```bash
load "lib/data/algorithms"
algorithms::sort_array "array[@]"
algorithms::binary_search "value" "array[@]"
```

### datapresentation.sh
Data formatting and presentation utilities.

**Features:**
- JSON parsing and formatting
- CSV processing
- Table formatting
- Chart generation (text-based)
- Data validation

**Usage:**
```bash
load "lib/data/datapresentation"
datapresentation::format_json "$json_string"
datapresentation::display_table "data[@]"
```

### monads.sh
Monadic operations for functional programming in Bash.

**Features:**
- Maybe monad for null-safety
- Either monad for error handling
- IO monad for side effects
- List monad for operations
- Composition utilities

**Usage:**
```bash
load "lib/data/monads"
monads::maybe "value" "default"
monads::either "success_cmd" "failure_cmd"
```

## Features

- Functional programming concepts
- Data processing utilities
- Algorithm implementations
- Cross-platform compatibility
- Performance optimized

## Examples

Each module includes detailed examples and use cases.

## Performance

Modules are optimized for performance with minimal external dependencies.

## Contributing

When adding new algorithms or data processing functions:
1. Follow the established patterns
2. Include comprehensive tests
3. Document with examples
4. Consider performance implications
