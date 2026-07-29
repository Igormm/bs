# BOSA Framework Examples

This directory contains example scripts demonstrating various features and use cases of the BOSA framework.

## Examples Included

### PS1 Configuration Example
**File:** `ps1_configuration_example.sh`

Demonstrates the advanced PS1 configuration module with features surpassing oh-my-zsh:
- Multiple built-in themes (default, powerline, minimal, time, rainbow)
- Git repository information with branch and status
- SSH connection detection
- Python virtual environment detection
- Dynamic time display
- Interactive theme selection
- Professional and minimal configurations

**Usage:**
```bash
# Run interactively
./examples/ps1_configuration_example.sh

# Or source for use in .bashrc
source examples/ps1_configuration_example.sh
# Then run: setup_ps1_professional
```

## How to Use Examples

### Running Examples
```bash
# Make example executable
chmod +x examples/ps1_configuration_example.sh

# Run example
./examples/ps1_configuration_example.sh

# Or source for use in current shell
source examples/ps1_configuration_example.sh
```

### Integrating into .bashrc
```bash
# Add to ~/.bashrc
cd /path/to/bosa_project
source examples/ps1_configuration_example.sh
setup_ps1_professional
```

### Using in Scripts
```bash
#!/usr/bin/env bash
source "/path/to/bosa/boot.sh"
bosa::init

# Load example functions
source "/path/to/bosa/examples/ps1_configuration_example.sh"

# Use example functions
setup_ps1_basic
```

## Creating New Examples

When adding new examples:
1. Use bilingual comments (Russian/English)
2. Include comprehensive usage examples
3. Add clear explanations of features
4. Provide both interactive and non-interactive modes
5. Document requirements and dependencies
6. Test on multiple distributions

## Best Practices

1. **Always check if BOSA is loaded**
2. **Use proper error handling**
3. **Include usage examples**
4. **Document functions with docstrings**
5. **Test on different terminals**
6. **Consider performance impact**

## Integration with Other Modules

Examples can use any BOSA modules:
```bash
# Load multiple modules
load "lib/ui/ps1config"
load "lib/system/utils"
load "lib/integration/telegramintegration"

# Use together
setup_ps1_professional
system::utils::get_hostname | telegramintegration::send_message "$CHAT_ID"
```

## Testing Examples

All examples should be tested:
```bash
# Test example
./examples/ps1_configuration_example.sh

# Or run through test framework
source tests/testframework.sh
testframework::assert_command "./examples/ps1_configuration_example.sh"
```

## Contributing Examples

When contributing new examples:
1. Follow existing patterns
2. Add bilingual documentation
3. Include usage instructions
4. Test thoroughly
5. Update this README
6. Consider different use cases

## License

Examples are part of the BOSA framework and follow the same licensing terms.
