# BOSA Framework Test Suite

## Overview

This directory contains comprehensive tests for the BOSA framework, organized by test type and functionality.

## Test Structure

```
tests/
├── runalltests.sh              # Main test runner
├── validatesyntax.sh             # Syntax validation
├── testframework.sh              # Test framework utilities
├── unit/                          # Unit tests
│   ├── test_logger_unit.sh
│   └── ...
├── integration/                   # Integration tests
│   ├── test_basic_functionality.sh
│   ├── test_shebang_mode.sh
│   ├── test_core_modules.sh
│   ├── test_installation.sh
│   ├── test_error_handling.sh
│   └── ...
└── demos/                         # Demo and example tests
    ├── test_telegram_integration_demo.sh
    ├── test_bash_it_integration_demo.sh
    ├── test_display_settings_demo.sh
    └── ...
```

## Running Tests

### Run All Tests
```bash
./runalltests.sh
```

### Validate Syntax
```bash
./validatesyntax.sh
```

### Run Specific Test Categories
```bash
# Unit tests
./unit/test_logger_unit.sh

# Integration tests
./integration/test_basic_functionality.sh

# Demo tests
./demos/test_presentation.sh
```

### Run Framework Comprehensive Test
```bash
./run_comprehensive_test.sh
```

## Test Categories

### Unit Tests
- **Purpose:** Test individual functions and modules in isolation
- **Characteristics:** Fast, focused, no external dependencies
- **Examples:** Logger module tests, utility function tests

### Integration Tests
- **Purpose:** Test interaction between modules and framework components
- **Characteristics:** Test module loading, framework initialization, error handling
- **Examples:** Basic functionality, shebang mode, installation process

### Demo Tests
- **Purpose:** Demonstrate module functionality and usage
- **Characteristics:** Show real-world examples, interactive demonstrations
- **Examples:** Telegram integration, UI components, data processing

## Writing Tests

### Using the Test Framework

```bash
#!/usr/bin/env bash
source "../testframework.sh"

# Initialize test framework
testframework::init

# Test section
testframework::section "Testing Logger"

# Run tests
testframework::assert_true "true" "True condition"
testframework::assert_equal "expected" "$result" "String comparison"
testframework::assert_file_exists "boot.sh" "File exists"
testframework::assert_command "ls boot.sh" "Command succeeds"

# Summary
testframework::summary
```

### Test Best Practices

1. **Clear Test Names:** Describe what is being tested
2. **Isolated Tests:** Each test should be independent
3. **Proper Setup/Teardown:** Clean up after tests
4. **Meaningful Assertions:** Test behavior, not implementation
5. **Bilingual Comments:** Use Russian and English

## Test Coverage

### Core Modules
- ✅ Logger (all levels, formats)
- ✅ Error Handling (codes, cleanup)
- ✅ Module Loading (loading, duplicates)
- ✅ Constants (error codes, descriptions)

### System Modules
- ✅ System Utilities (info, operations)
- ✅ Distribution Logic (detection, packages)
- ✅ Network (interfaces, connectivity)
- ✅ Services (start, stop, status)
- ✅ Users (creation, permissions)

### Integration Modules
- ✅ Telegram Integration (messages, bots)
- ✅ UI Components (presentation, themes)
- ✅ Data Processing (algorithms, formatting)
- ✅ External Tools (docker, git)

## Test Requirements

### Dependencies
- BOSA framework initialized
- Test framework loaded
- Appropriate permissions
- External tools (when testing integrations)

### Environment Setup
```bash
# Make test scripts executable
chmod +x tests/*.sh
chmod +x tests/*/*.sh

# Run from project root
cd bosa_project
./tests/runalltests.sh
```

## Adding New Tests

1. **Choose appropriate directory** (unit, integration, or demos)
2. **Follow naming convention** (test_*.sh)
3. **Use test framework functions**
4. **Add bilingual documentation**
5. **Test both success and failure cases**

## CI/CD Integration

### GitHub Actions Example
```yaml
name: Test BOSA Framework
on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
    - uses: actions/checkout@v2
    - name: Run tests
      run: |
        cd tests
        ./runalltests.sh
    - name: Validate syntax
      run: |
        cd tests
        ./validatesyntax.sh
```

## Debugging Tests

### Enable Debug Output
```bash
export BOSA_LOG_LEVEL=DEBUG
./runalltests.sh
```

### Run with Bash Debug
```bash
bash -x ./tests/unit/test_logger_unit.sh
```

### Check Individual Test Output
```bash
./tests/integration/test_basic_functionality.sh 2>&1 | less
```

## Test Results

Tests output results in the following format:
- ✓ PASSED — Green checkmark
- ✗ FAILED — Red X
- ⚠ WARNING — Yellow warning
- ▶ RUNNING — Blue arrow

## Performance

- Unit tests: ~0.1s per test
- Integration tests: ~0.5s per test
- Demo tests: ~1-2s per test
- Full suite: ~10-30s total

## Contributing

When adding new tests:
1. Follow existing patterns
2. Add bilingual comments
3. Test both positive and negative cases
4. Update this README if needed
5. Ensure tests are idempotent

## License

Tests are part of the BOSA framework and follow the same licensing terms.
