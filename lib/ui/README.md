# UI Modules

This directory contains user interface modules for BOSA framework.

## Modules

### presentation.sh
Beautiful presentation and output formatting for terminal applications.

**Features:**
- Colored output with themes
- Header and section formatting
- List and table presentation
- Progress indicators
- Success/error messaging

**Usage:**
```bash
load "lib/ui/presentation"
presentation::header "My Application"
presentation::success "Operation completed"
presentation::error "Something went wrong"
```

### ps1config.sh ⭐ NEW
Advanced PS1 configuration module with oh-my-zsh++ functionality.

**Features:**
- Multiple built-in themes (default, powerline, minimal, time, rainbow)
- Git repository information with branch and status
- SSH connection detection
- Python virtual environment detection
- Dynamic time display
- Custom theme support
- Real-time prompt updates

**Usage:**
```bash
load "lib/ui/ps1config"

# Set theme
ps1config::set_theme "powerline"

# Enable advanced features
ps1config::enable_advanced()

# List available themes
ps1config::list_themes()

# Demo all themes
ps1config::demo()
```

### bosatheme.sh
BS prompt theme (clean, informative bash-it style prompt).

**Usage:**
```bash
load "lib/ui/bosatheme"
bosatheme::apply   # apply the prompt to the current shell
```

## Features

- Rich terminal UI components
- Color support with themes
- Interactive elements
- Cross-platform compatibility
- Accessibility features
- Professional PS1 configuration
- Real-time prompt updates
- Git and virtual environment integration

## PS1 Configuration Features

### Built-in Themes

1. **default** — Classic bash prompt with git info
2. **powerline** — Fancy powerline-style prompt with segments
3. **minimal** — Clean minimal prompt
4. **time** — Prompt with current time
5. **rainbow** — Colorful rainbow prompt

### Dynamic Elements

- **Git information:** Branch name, dirty status, commits ahead/behind
- **SSH indicator:** Shows when connected via SSH
- **Virtual environment:** Python virtualenv and conda detection
- **Time display:** Customizable time format
- **User and host:** Colored user@host display
- **Working directory:** Current directory with color coding

### Customization

```bash
# Set custom time format
ps1config::set_time_format "%Y-%m-%d %H:%M"

# Enable/disable git info
ps1config::set_git_info true

# Reset to default
ps1config::reset()
```

## Examples

### Basic PS1 Configuration
```bash
#!/usr/bin/env bash
source "./boot.sh"
bosa::init

load "lib/ui/ps1config"

# Enable advanced features
ps1config::enable_advanced()

# Your script here
logger::info "PS1 configured with advanced features"
```

### Custom Theme
```bash
# In your .bashrc or profile
source /path/to/bosa/boot.sh
bosa::init
load lib/ui/ps1config

# Set your preferred theme
ps1config::set_theme "powerline"
```

## Best Practices

1. **Always check terminal capabilities** before using colors
2. **Provide fallback** for non-interactive environments
3. **Use themes** for consistent styling
4. **Test on different terminal emulators**
5. **Consider performance** for dynamic elements
6. **Use git info** only in git repositories
7. **Enable SSH detection** for remote sessions

## Performance Considerations

- PS1 updates run before each command
- Keep dynamic operations lightweight
- Use caching for expensive operations
- Consider disabling git info in large repositories
- Use `PROMPT_COMMAND` for complex updates

## Troubleshooting

### PS1 not updating
```bash
# Check if module is loaded
ps1config::get_current_theme

# Re-initialize
ps1config::init
```

### Colors not working
```bash
# Check terminal support
echo $TERM

# Force colors
export FORCE_COLOR=1
```

### Git info too slow
```bash
# Disable git info
ps1config::set_git_info false

# Or use simpler git prompt
export GIT_PS1_SHOWDIRTYSTATE=0
```

## Integration with Other Tools

### With tmux
```bash
# In .tmux.conf
set -g status-right '#(ps1config::get_current_theme)'
```

### With screen
```bash
# In .screenrc
hardstatus string '%{= kG}%-w%{= kW}%n %t%{-}%+w %=%{..G} %Y-%m-%d %{..Y} %H:%M'
```

### With vim
```bash
# In .vimrc
let &statusline = '%{system("ps1config::get_current_theme")}'
```

## Contributing

When adding new PS1 features:
1. Follow existing patterns
2. Add bilingual documentation
3. Consider performance impact
4. Test on multiple terminals
5. Provide fallback options
6. Update this README

## Future Enhancements

Potential additions:
- More built-in themes
- Conditional elements (show/hide based on context)
- Multi-line prompts
- Right-side prompts (RPROMPT)
- Integration with powerline fonts
- Animated elements
- Sound notifications

---

*The ps1config module brings oh-my-zsh level functionality to bash with additional features and better integration with the BOSA framework.*
