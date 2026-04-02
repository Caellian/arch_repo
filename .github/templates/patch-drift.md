---
title: "Patch drift: {{package}}"
---
Patches failed to apply cleanly for `{{package}}` after submodule fast-forward.

**Date:** {{date}}
**Run:** [{{run_id}}]({{run_url}})
**Commit range:** {{commit_range}}

### Failed patches
{{patch_list}}

### Next steps
- [ ] Review upstream changes in the commit range above
- [ ] Regenerate patches against current submodule HEAD
- [ ] Verify with `just check-patches`
