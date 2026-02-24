# UI Changes Needed for DrupalForge/DevPanel

## Summary

With lenient mode now the default (`DP_FORCE_DEPENDENCIES=1`), the UI needs to be simplified to reflect that we always allow incompatible module combinations for QA testing.

## Changes Required

### 1. Remove DP_FORCE_DEPENDENCIES Checkbox

**Current:** Checkbox labeled "Force Dependencies" or similar

**New:** Remove the checkbox entirely

**Rationale:**
- Lenient mode is now the default and always enabled
- QA workflows should always allow incompatible combinations
- Removing the checkbox simplifies the UI and reduces confusion
- The concept of "forcing dependencies" was confusing - lenient mode is more intuitive

**Implementation:**
```javascript
// Remove from form:
// - DP_FORCE_DEPENDENCIES checkbox
// - Associated help text

// Backend: Always set DP_FORCE_DEPENDENCIES=1
// No longer read from user input
```

### 2. Update Drupal Version Field

#### Placeholder Text

**Current:** May show something like "latest" or "2.0.x"

**New:** `"Auto-detect compatible version"`

Or: `"Leave empty to auto-detect"`

#### Help Text

**Current:** Unknown (likely minimal or none)

**New:**
```
Leave empty to automatically detect the highest compatible Drupal CMS/Core version
based on your test module requirements. Or specify an explicit version (e.g., 1.x,
2.0.x, 11.2.8).
```

**Label:** Keep as "Drupal Version" or "CMS/Core Version"

### 3. Update Form Validation

**Current:** May require DP_VERSION or default to "latest"

**New:**
- Allow empty DP_VERSION (auto-detect)
- Do NOT default to "latest"
- If empty, the backend will resolve compatible version via Composer

### 4. Optional: Add Info Message

Consider adding an informational message near the top of the form:

```
ℹ️ Lenient mode is enabled by default
Version constraints are relaxed to allow testing incompatible module combinations.
```

## Environment Variable Mapping

| UI Field | Environment Variable | Default | Notes |
|----------|---------------------|---------|-------|
| Drupal Version | `DP_VERSION` | Empty (auto-detect) | Empty means auto-detect |
| ~~Force Dependencies~~ | ~~`DP_FORCE_DEPENDENCIES`~~ | ~~Removed~~ | Always set to `1` in backend |
| Template | `DP_STARTER_TEMPLATE` | `cms` | Keep as-is |
| AI Module Version | `DP_AI_MODULE_VERSION` | Empty | Keep as-is |
| Test Module | `DP_TEST_MODULE` | Empty | Keep as-is |

## Backend Changes

In the DrupalForge/DevPanel backend that processes the form:

```javascript
// Old:
const env = {
  DP_VERSION: form.drupalVersion || 'latest',  // ❌ Wrong
  DP_FORCE_DEPENDENCIES: form.forceDeps ? '1' : '0',  // ❌ Remove
  // ...
};

// New:
const env = {
  DP_VERSION: form.drupalVersion || '',  // ✅ Empty = auto-detect
  DP_FORCE_DEPENDENCIES: '1',  // ✅ Always enabled
  // ...
};
```

## User-Facing Documentation

Update any user-facing docs to mention:

1. **Lenient mode is always enabled** - incompatible module combinations are allowed for QA
2. **Empty version auto-detects** - leave the Drupal version field empty to automatically select the highest compatible version
3. **Explicit versions override** - you can still specify a version to test specific combinations

## Testing Checklist

- [ ] Remove DP_FORCE_DEPENDENCIES checkbox from form
- [ ] Update DP_VERSION placeholder to "Auto-detect compatible version"
- [ ] Update DP_VERSION help text
- [ ] Remove DP_FORCE_DEPENDENCIES from form submission
- [ ] Backend always sets DP_FORCE_DEPENDENCIES=1
- [ ] Backend allows empty DP_VERSION (no default to "latest")
- [ ] Test: Empty version auto-detects correctly
- [ ] Test: Explicit version (e.g., "1.x") is respected
- [ ] Test: Incompatible combinations work (e.g., AI 2.0.x + ai_context 1.0.x)
- [ ] Update UI documentation/tooltips
