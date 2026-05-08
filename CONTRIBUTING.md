# Contributing Guidelines

> **The number 1 requirement for this module is backwards compatibility.**
>
> No matter what upgrades we do, and no matter if the user upgrades or not, their usage of this module must never fail if it was previously valid.

## Table of Contents

- [The Golden Rule](#the-golden-rule)
- [What "Backwards Compatible" Means for Terraform](#what-backwards-compatible-means-for-terraform)
- [Change Classification](#change-classification)
  - [Always Breaking](#always-breaking)
  - [Always Safe](#always-safe)
  - [Requires Careful Review](#requires-careful-review)
- [Variable Rules](#variable-rules)
- [Output Rules](#output-rules)
- [Resource Address Rules](#resource-address-rules)
- [Provider and Version Constraint Rules](#provider-and-version-constraint-rules)
- [Lifecycle Rules](#lifecycle-rules)
- [Module Interface Rules](#module-interface-rules)
- [State Migration Rules](#state-migration-rules)
- [Idempotency Rules](#idempotency-rules)
- [Review Checklist](#review-checklist)
- [AI Agent Instructions](#ai-agent-instructions)
- [Examples](#examples)

---

## The Golden Rule

**Any consumer who has a working, valid configuration with version `N` of this module must be able to upgrade to version `N+1` (or any later version) without their `terraform plan` failing, and without any resource being unexpectedly destroyed or recreated.**

This is absolute. There are no exceptions. If a change would break an existing valid usage, it must be rejected or redesigned.

### Why This Matters

This module is consumed by infrastructure pipelines, by other modules, and by teams who may not have time to audit every minor version bump. Breaking their automation is unacceptable. If we need to make a breaking change, it goes in a **new module** or a **major version that is explicitly opt-in** (and even then, we avoid this if at all possible).

---

## What "Backwards Compatible" Means for Terraform

Terraform modules have a public interface: **variables** (inputs), **outputs** (return values), and **resource addresses** (state mapping). A change is backwards compatible if:

1. All previously valid input configurations remain valid.
2. All previously valid output references continue to work.
3. Existing state continues to map to the same logical resources without manual migration.
4. `terraform plan` after upgrade shows no deletions or unexpected replacements for existing resources.

### What Is NOT Required for Backwards Compatibility

- A plan showing zero changes is NOT required. Adding a new tag, or fixing a default, may show an update — this is fine.
- New outputs or new optional inputs are fine.
- New resources that only appear when new optional inputs are provided are fine.

---

## Idempotency Rules

> **Idempotency is the number 2 requirement.** A module that shows perpetual diffs trains users to ignore `terraform plan` output, which is dangerous.

**Idempotency** means: for a fixed version of this module and fixed inputs, `terraform plan` after a successful `terraform apply` must show **zero changes**.

This is different from backwards compatibility (which is about upgrades across versions). A module can be backwards compatible but non-idempotent. We avoid both.

### 1. Never Add Resources That Perpetually Drift

If a resource attribute is computed by the provider and always returns a different value, either:
- Add `lifecycle { ignore_changes = [that_attribute] }`
- Remove the attribute from the resource if it is optional
- Use a data source instead if the value is only needed for reference

Example: AzureRM schedules have a known `start_time` timezone+offset round-trip bug. The fix is `ignore_changes = [start_time]`.

### 2. Never Use `timestamp()` or Other Volatile Defaults

```hcl
# WRONG — creates a new resource on every apply
variable "created_at" {
  type    = string
  default = timestamp()
}
```

If a timestamp is truly needed, require the caller to provide it. Do not compute volatile defaults inside the module.

### 3. `ignore_changes` Is the Tool for Provider Bugs

When a provider reports drift for an attribute that the user does not control (e.g., API-normalized values, computed timestamps, ordering differences), add `ignore_changes`.

Document WHY the `ignore_changes` exists, so future maintainers know when it can be removed:

```hcl
lifecycle {
  # AzureRM provider bug: start_time is returned with a different offset than
  # was sent, causing perpetual diff. Ignored to maintain idempotency.
  # Tracked: https://github.com/hashicorp/terraform-provider-azurerm/issues/XXXX
  ignore_changes = [start_time]
}
```

### 4. `for_each` Keys Must Be Deterministic

Non-deterministic `for_each` keys can cause resources to be planned for replacement on every apply:

```hcl
# WRONG — order is not stable
for_each = toset(random_shuffle.names.result)

# WRONG — timestamp makes keys unique on every run
for_each = { for n in var.names : "${n}-${timestamp()}" => n }

# CORRECT — stable, deterministic keys
for_each = { for n in var.names : n => n }
```

### 5. Script Content Must Be Stable

If a resource's `content` is generated from a template that embeds timestamps, random values, or non-deterministic data, the resource will drift every apply. Either:
- Remove the volatile data from the template
- Add `lifecycle { ignore_changes = [content] }` (only if the content is truly managed outside Terraform)

### 6. Adding `ignore_changes` Is Safe

Adding `ignore_changes` only suppresses diffs. It never creates them. It is always backwards compatible.

### 7. Removing `ignore_changes` Is Dangerous

Even if the provider bug is fixed, removing `ignore_changes` from a resource that was created while the bug existed may cause Terraform to detect the historical drift and force replacement. Keep the `ignore_changes` block and add a comment noting the provider version that fixed the bug.

---

## Change Classification

### Always Breaking

The following changes are **never allowed** in any version bump (major, minor, or patch):

| Change | Why It Breaks |
|--------|---------------|
| Removing a variable | Existing callers passing it will get a validation error. |
| Renaming a variable | Same as removing — existing callers fail. |
| Narrowing a variable's `type` constraint | Existing callers may pass values that no longer satisfy the type. |
| Adding `validation` blocks that reject previously valid values | Existing configurations may now fail `terraform plan`. |
| Changing a variable's `default` to a different value | Silent infrastructure drift for callers relying on the old default. |
| Removing an output | Existing callers referencing `module.foo.bar` will fail. |
| Changing an output's structure so existing references break | e.g., changing a string output to a map. |
| Removing a resource from state without a `moved` block | Terraform will plan to destroy it. |
| Changing a `for_each` key expression so existing keys map differently | Resources may be planned for destruction/recreation. |
| Removing `lifecycle { ignore_changes = [...] }` | May force replacement of existing resources on next apply. |
| Tightening provider version lower bound | Callers on older provider versions will fail provider resolution. |
| Removing `moved` blocks from previous releases | Callers upgrading across multiple versions lose state migration path. |

### Always Safe

The following changes are **always allowed**:

| Change | Why It's Safe |
|--------|---------------|
| Adding a new variable with a `default` | Existing callers don't use it; default keeps behavior identical. |
| Adding a new output | Existing callers don't reference it. |
| Adding a new resource gated by a new optional variable | Only affects callers who opt in. |
| Loosening a variable's `type` constraint (making it more permissive) | All previously valid values remain valid. |
| Widening provider version constraints (higher upper bound, lower lower bound) | More versions are acceptable, not fewer. |
| Adding `moved` blocks for newly renamed resources | Only helps; never hurts. |
| Adding documentation, comments, or examples | No runtime impact. |
| Fixing a bug that causes a resource to fail to create | If it was already broken, fixing it is not a breaking change. |
| Adding `lifecycle { ignore_changes = [...] }` | Prevents unwanted updates; never forces them. |

### Requires Careful Review

| Change | Condition for Safety |
|--------|---------------------|
| Changing `for_each` from `var.something` to `merge(...)` | All existing keys must be preserved exactly. No reordering, no key format changes. |
| Refactoring locals that feed `for_each` | Must produce identical key sets for identical inputs. |
| Changing how resource attributes are computed | Must not change the final value for any existing input. Test with `terraform plan`. |
| Updating embedded scripts (PS1, SQL) | Must not change parameter contracts. New optional parameters are fine; removing or renaming required parameters is breaking. |
| Changing `azurerm_automation_runbook` content when `ignore_changes = [content]` is present | Safe because Terraform ignores the change. If removing `ignore_changes`, this becomes breaking. |

---

## Variable Rules

### 1. Never Remove or Rename

If a variable is no longer needed, mark it as deprecated in the description and leave it in place. If it must have no effect, ignore it in the code. Example:

```hcl
variable "legacy_thing" {
  description = "DEPRECATED: This variable is no longer used. It is kept for backwards compatibility and will be removed only if a new major module version is ever created."
  type        = string
  default     = ""
}
```

### 2. Never Narrow Types

Do NOT change `type = any` to `type = string`. Do NOT change `type = list(string)` to `type = list(object({...}))` unless `any` was the previous type and all existing lists happen to already match (which is risky — don't do it).

### 3. Never Add Validation That Rejects Existing Values

```hcl
# WRONG — breaks callers who pass "old_name"
validation {
  condition     = can(regex("^new-prefix-", var.name))
  error_message = "Name must start with 'new-prefix-'."
}
```

If you need stricter validation, create a NEW variable with the stricter rules and make the old one deprecated.

### 4. Never Change Defaults

Changing a default changes behavior silently. If the old default was wrong, document it. Callers who want the new behavior can opt in explicitly.

```hcl
# WRONG
variable "enable_feature" {
  type    = bool
  default = true  # was false; breaks callers who relied on it being off
}
```

### 5. Adding Variables

New variables MUST have a `default` that preserves the previous behavior. If there is no sensible default, the feature is not backwards compatible.

```hcl
# CORRECT
variable "new_feature_enabled" {
  description = "Enable the new feature. Defaults to false to preserve existing behavior."
  type        = bool
  default     = false
}
```

---

## Output Rules

### 1. Never Remove an Output

If an output is no longer useful, return `null` or an empty structure, but keep the output.

```hcl
# CORRECT — preserves the output for backwards compatibility
output "legacy_output" {
  description = "DEPRECATED: This output always returns null. Use 'new_output' instead."
  value       = null
}
```

### 2. Never Change Output Structure

If an output was a string, it must remain a string (or at least a type that supports string interpolation). If an output was a map of objects with keys `{id, name}`, do not add a new required key to the object if callers may be using `for` or `lookup` in ways that assume the old shape.

Adding NEW keys to an object output is generally safe. Removing or renaming keys is breaking.

### 3. Adding Outputs

Always safe. New outputs can be added at any time.

---

## Resource Address Rules

Terraform state maps real infrastructure to resource addresses like `azurerm_automation_runbook.webhook["default"]`. If the HCL address changes, Terraform plans to destroy the old resource and create a new one — unless a `moved` block tells it otherwise.

### 1. Every Resource Address Change Requires a `moved` Block

If you refactor:
- `for_each` to `count` or vice versa
- `for_each` key from `"foo"` to `"bar"`
- Resource name from `webhook` to `teams_webhook`

You MUST add a `moved` block for every possible instance:

```hcl
moved {
  from = azurerm_automation_runbook.webhook
  to   = azurerm_automation_runbook.webhook["default"]
}
```

### 2. `moved` Blocks Are Permanent

Never remove a `moved` block from a previous release. A user upgrading from v1.0.0 to v1.2.0 needs the v1.1.0 `moved` block to still exist. Terraform processes `moved` blocks cumulatively.

### 3. `for_each` Keys Must Be Stable

If `for_each` is keyed by `var.something`, and that map's keys are caller-controlled, the keys are stable by definition. If you compute keys internally, they must be deterministic and unchanged across releases for the same inputs.

```hcl
# WRONG — toset() order is not guaranteed across Terraform versions
for_each = toset(var.names)

# CORRECT — map keys are stable
for_each = { for n in var.names : n => n }
```

---

## Provider and Version Constraint Rules

### 1. Keep Lower Bound Wide

The current constraint `>= 4.0, < 5.0` is correct. Do not tighten to `>= 4.71` unless a resource attribute literally does not exist in earlier versions and there is no workaround.

If a new feature requires a newer provider, gate it behind an optional variable and use `try()` or `can()` to degrade gracefully for older providers. Only raise the lower bound if the module is fundamentally unusable below it.

### 2. Upper Bounds Are Acceptable

Pinning `< 5.0` is fine because major provider versions are allowed to break. When AzureRM 5.0 is released, evaluate compatibility before relaxing the bound.

### 3. Terraform Core Version

`required_version = ">= 1.5.0"` should not be tightened. Terraform 1.5.0 introduced `moved` blocks and other features this module relies on. Higher minimums require justification.

---

## Lifecycle Rules

### 1. Never Remove `ignore_changes`

If a resource currently has:

```hcl
lifecycle {
  ignore_changes = [start_time]
}
```

Removing it may cause Terraform to detect drift and force replacement of the resource on the next apply. This is breaking.

If a resource no longer needs `ignore_changes` because the provider bug is fixed, you must still keep it for all resources that were created while the bug existed. You may add a comment documenting the history.

### 2. Adding `ignore_changes` Is Safe

It only suppresses diffs; it never creates them.

---

## Module Interface Rules

### Submodule Contracts

If this module calls submodules (e.g., `modules/failure-alert/`), those submodules are internal implementation details. Changes to them are safe IF and ONLY IF the parent module's interface (variables, outputs, resource addresses) remains unchanged.

If a submodule change requires a parent variable or output change, it is subject to all rules above.

### Embedded Scripts

The PowerShell scripts in `scripts/` are part of the module interface because they determine resource behavior. Changes to script parameters are breaking if the caller (Terraform `content` or `parameters` blocks) does not account for them.

- Adding an OPTIONAL parameter with a default in the script: safe.
- Renaming or removing a parameter: breaking.
- Changing the return/output contract if callers depend on it: breaking.

---

## State Migration Rules

### The `moved` Block Policy

Every release that changes a resource address must include `moved` blocks. These blocks:

- Must cover every instance that could exist in state from the previous release.
- Must never be removed in future releases.
- Must be tested with `terraform plan` on a state file from the previous release to confirm zero deletions.

### Manual State Moves Are Forbidden

Do not document manual `terraform state mv` commands as an upgrade path. If a change cannot be handled by `moved` blocks, redesign the change.

---

## Review Checklist

Before merging ANY change, verify every item below. This checklist applies to human reviewers and CI.

- [ ] No variables were removed or renamed.
- [ ] No variable types were narrowed.
- [ ] No new `validation` blocks were added that could reject previously valid inputs.
- [ ] No variable defaults were changed.
- [ ] No outputs were removed.
- [ ] No output structures were changed in a way that breaks existing references.
- [ ] No resource addresses changed without corresponding `moved` blocks.
- [ ] No `moved` blocks from previous releases were removed.
- [ ] No `lifecycle { ignore_changes = [...] }` blocks were removed.
- [ ] Provider version lower bound was not tightened without explicit justification.
- [ ] `terraform plan` against a state from the previous release shows:
  - [ ] Zero resource deletions.
  - [ ] Zero unexpected resource replacements.
  - [ ] Only additions of new resources (gated by new optional inputs) or in-place updates.
- [ ] Idempotency: `terraform apply` followed by `terraform plan` on the same inputs shows:
  - [ ] Zero changes (no perpetual drift).
  - [ ] No new `ignore_changes` blocks were removed.
  - [ ] No `for_each` keys are derived from volatile or non-deterministic values.

---

## AI Agent Instructions

If you are an AI agent (Claude, Copilot, GPT, etc.) contributing to this repository, follow these rules in addition to everything above:

### 1. Do Not Guess About Breaking Changes

If you are unsure whether a change is breaking, **ask the human**. Do not assume "this probably won't break anyone."

### 2. Analyze Before Proposing

Before proposing any code change, analyze:
- **Variable delta**: What variables exist now vs. after your change? Any removed, renamed, or retyped?
- **Output delta**: What outputs exist now vs. after? Any removed or reshaped?
- **Resource address delta**: What resource addresses exist now vs. after? Any `for_each` key changes?
- **Default delta**: Did any defaults change?
- **Validation delta**: Did you add or tighten validation rules?

Present this analysis explicitly in your proposal.

### 3. Propose `moved` Blocks Proactively

If your change touches any resource address, include the `moved` block in your proposal. Do not make the human ask for it.

### 4. Prefer Deprecation Over Removal

If a variable or output is "no longer needed," your proposal must keep it and mark it deprecated. Do not remove it.

### 5. Gate New Behavior Behind Optional Variables

If you want to change default behavior, create a new boolean variable (default `false`) that callers must opt into. Do not change the behavior for existing callers.

### 6. Test Against Existing State

If you have access to a test environment, run `terraform plan` against a state file created with the current release before proposing your change. If you see deletions or replacements, your change is breaking.

### 7. Document the Change Classification

In your PR or proposal, explicitly label every change as:
- **Safe** — follows "Always Safe" rules above.
- **Breaking** — follows "Always Breaking" rules above (must be rejected).
- **Requires Review** — follows "Requires Careful Review" rules above.

If any change is labeled **Breaking**, the proposal must be rejected or redesigned.

---

## Examples

### Example 1: Adding a New Feature (Safe)

**Goal**: Add support for PowerShell 5 runbooks to use a specific module slot.

**Change**: Add `variable "ps5_special_modules"` with `default = {}`. Add `azurerm_automation_module.ps5_special` resource using `for_each = var.ps5_special_modules`.

**Result**: Existing callers see no changes. New callers can use the variable. ✅ Safe.

---

### Example 2: Fixing a Bug in Default Behavior (Breaking — Rejected)

**Goal**: The `enable_index_optimize` default is `false`, but the module should default to `true` because most users want it.

**Change**: `default = false` → `default = true`.

**Result**: Existing callers who did not set the variable now get an IndexOptimize runbook they did not ask for. If they have no SQL targets configured, it is harmless but noisy. If they have `index_optimize_targets` set but expected it to be inactive, it is active now. ❌ Breaking. Rejected.

**Correct approach**: Document that `enable_index_optimize = true` is recommended. Leave default as `false`.

---

### Example 3: Refactoring `for_each` Keys (Requires `moved` Blocks)

**Goal**: Change `azurerm_automation_runbook.webhook` from un-keyed to keyed by `"default"`.

**Change**:
```hcl
resource "azurerm_automation_runbook" "webhook" {
  for_each = local.webhook_keys  # was: no for_each
  # ...
}

moved {
  from = azurerm_automation_runbook.webhook
  to   = azurerm_automation_runbook.webhook["default"]
}
```

**Result**: Terraform state migrates automatically. ✅ Safe, because `moved` block is present.

**Without the `moved` block**: Terraform plans to destroy the old runbook and create a new one. ❌ Breaking.

---

### Example 4: Removing a Deprecated Output (Breaking — Rejected)

**Goal**: Clean up `output "legacy_thing"` which was deprecated two releases ago.

**Change**: Remove the output.

**Result**: Any caller still referencing `module.automation.legacy_thing` gets an error. ❌ Breaking. Rejected.

**Correct approach**: Keep the output. Update its description to say "DEPRECATED — will be removed only in a hypothetical v2.0.0 major release." Return `null` or a static value.

---

### Example 5: Adding Validation (Breaking — Rejected)

**Goal**: Ensure `name` always contains a hyphen.

**Change**: Add validation to `var.name` requiring a hyphen.

**Result**: Callers with names like `"MyAutomationAccount"` (no hyphen) now fail validation. ❌ Breaking. Rejected.

**Correct approach**: Do not add this validation. If it is truly needed, create `var.name_v2` with stricter validation and deprecate `var.name`.

---

### Example 6: Updating Provider Lower Bound (Breaking — Rejected Without Justification)

**Goal**: Use a new AzureRM feature available only in `4.71.0`.

**Change**: `version = ">= 4.71, < 5.0"`.

**Result**: Callers on `4.26.0` cannot resolve providers. ❌ Breaking. Rejected.

**Correct approach**: Gate the new feature behind an optional variable. Use `try()` or dynamic blocks so the module works on both old and new provider versions. Only raise the lower bound if the module is literally non-functional below it.

---

## Questions?

If you are unsure whether a change is backwards compatible, **open an issue before writing code**. It is always cheaper to discuss a design than to revert a merged breaking change.
