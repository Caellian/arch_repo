---
title: "Build failure: {{package}}"
---
Build failed for `{{package}}`.

**Date:** {{date}}
**Run:** [{{run_id}}]({{run_url}})

### Build log

<details>
<summary>Click to expand</summary>

```
{{build_log}}
```

</details>

### Next steps
- [ ] Check build logs for errors
- [ ] Verify PKGBUILD and dependencies are up to date
- [ ] Reproduce locally with `just build {{package}}`
