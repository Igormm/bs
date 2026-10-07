# CI Integration Examples

## GitHub Actions

```yaml
name: Changelog Check
on: [pull_request]

jobs:
  changelog:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: bash engineering/changelog-generator/scripts/commit_linter.sh \
          --from-ref origin/main --to-ref HEAD --strict
```

## GitLab CI

```yaml
changelog_lint:
  image: alpine:latest
  stage: test
  before_script:
    - apk add --no-cache bash git
  script:
    - bash engineering/changelog-generator/scripts/commit_linter.sh --to-ref HEAD --strict
```
