# Deep Review: integrate-community-fixes

**Date:** 2026-03-13
**Branch:** integrate-community-fixes
**Files Reviewed:** 12 (all plugin source + spec files)

---

## Executive Summary

The core architecture (pane tree, hierarchical state, save/restore flow) is sound. However, the codebase has **significant security vulnerabilities** around shell command execution and file path handling that must be addressed before this fork is production-ready. The cherry-picked PRs fix real bugs but the underlying code has systemic issues with inconsistent process execution patterns (`os.execute` vs `io.popen` vs `wezterm.run_child_process`) and insufficient input sanitization. The optimization review found dead code, duplicated save logic, and a crash-causing nil guard.

**Verdict:** Merge the integration PR (the cherry-picks improve things), but Phase 2 MUST address the security and quality findings before release.

---

## Security Findings

### Critical

**S1. Command injection via os.execute in fuzzy_loader.lua (line 123)**
- `os.execute("wscript.exe //nologo " .. launcher_vbs)` with unquoted path concatenation
- Directly contradicts the #125 fix that replaced os.execute in utils.lua
- Fix: Replace with `wezterm.run_child_process({"wscript.exe", "//nologo", launcher_vbs})`

### High

**S2. io.popen shell injection in utils.execute() (lines 51-69)**
- Called from fuzzy_loader.lua with string-interpolated find commands containing `base_path`
- Double quotes don't prevent all shell injection on Unix ($(), backticks)
- Fix: Replace with array-based `wezterm.run_child_process`

**S3. VBScript injection in fuzzy_loader.lua (lines 66-97)**
- `base_path` interpolated into VBS code; only backslash is escaped, not double quotes
- Crafted save_state_dir with `"` breaks out of VBS string literal
- Fix: Escape `"` as `""` in VBS strings, or replace entire VBS approach

**S4. Path traversal in delete_state (state_manager.lua lines 205-214)**
- `pub.save_state_dir .. file_path` with no confinement check
- `../../../important_file` traverses outside state directory
- Fix: Validate resolved path starts with save_state_dir prefix; reject `..` segments

**S7. Shell injection in encrypt() (encryption.lua line 70)**
- `file_path` only has spaces escaped, not other shell metacharacters
- Passed to shell via string.format through `sh -c` or `pwsh.exe -Command`
- Fix: Use array-based `wezterm.run_child_process` like decrypt() already does

**S11. Command execution from untrusted state files (tab_state.lua line 154)**
- `pane:send_text(wezterm.shell_join_args(pane_tree.process.argv) .. "\r\n")`
- Deserialized JSON argv is executed directly in user's shell
- Tampered state file = arbitrary command execution on restore
- Fix: Validate argv[1] against known-safe executables; consider HMAC on state files

### Medium

**S5. Incomplete filename sanitization (state_manager.lua lines 11-21)**
- No null byte check, no Windows reserved name check (CON, PRN, NUL, etc.)
- Fix: Add whitelist validation after sanitization

**S6. Encryption key exposure via process arguments (encryption.lua lines 70, 90)**
- Private key path and public key visible in `ps aux` on shared systems
- Fix: Document risk; use --recipients-file where possible

**S8. Non-atomic file writes (file_io.lua lines 11-22)**
- Direct open-write-close; crash during write corrupts state file
- Fix: Write to `.tmp` file, then atomic rename

**S12. Unquoted path in VBS WshShell.Run (fuzzy_loader.lua lines 101-107)**
- Fix: Quote the path with VBS double-quote escaping

### Low

**S9. Probe file TOCTOU race (utils.lua lines 140-149)** - Negligible in practice
**S10. Unix shell_mkdir goes through sh -c unnecessarily (utils.lua lines 82-84)** - Could use direct mkdir

---

## Optimization Findings

### Dead Code

**O1. pane_tree.map() never called (pane_tree.lua line 257)** - LOW
- Only pub.fold() is used. Remove or document as public API.

**O2. Unused require("resurrect") in window_state.lua line 90** - LOW
- Dead import inside save_window_action(). Remove it.

### Duplication

**O3. is_windows/separator duplicated (init.lua lines 7-8 vs utils.lua lines 5-7)** - LOW
- init.lua should import from utils instead of recomputing.

**O4. Save logic duplicated between periodic_save and event_driven_save** - MEDIUM
- ~40 lines of near-identical save iteration code. Extract shared helper.

**O5. "title not empty" guard repeated 4 times** - LOW
- Extract `has_title(title)` helper.

### Code Quality

**O6. Duck typing for state type (state_manager.lua lines 27-33)** - MEDIUM
- Silent no-op if state object is malformed. Add explicit type field or error logging.

**O7. active_tab:activate() crashes if no tab marked active (window_state.lua line 84)** - HIGH
- Nil crash during restore if no is_active flag in saved state.
- Fix: Guard with `if active_tab then active_tab:activate() end`

**O8. Shadowing Lua built-in `type` keyword** - LOW
- Multiple functions use `type` as parameter name. Rename to `state_type`.

**O9. resurrect_on_gui_startup swallows errors (state_manager.lua lines 181-202)** - MEDIUM
- pcall catches errors but doesn't log them. Add wezterm.log_error.

**O17. Log says "Decryption" in encryption error path (file_io.lua line 83)** - LOW
- Should say "Encryption failed".

### Performance

**O12. Double sanitize_json on write + read (file_io.lua lines 75, 123)** - LOW
- Sanitize only on write; reading already-sanitized files is wasteful.

**O13. Line-by-line read when read_file exists (file_io.lua lines 114-118)** - LOW
- Use pub.read_file() for consistency and performance.

**O14. Heavyweight VBS temp-file dance on Windows (fuzzy_loader.lua lines 56-158)** - MEDIUM
- Replace with wezterm.run_child_process for dir listing.

**O18. sanitize_json emits multi-MB data as event argument (file_io.lua line 61)** - MEDIUM
- Pass string length, not the full payload.

### Architecture

**O10. os.execute in fuzzy_loader contradicts #125 fix (line 123)** - HIGH
- Same as S1. Inconsistent process execution pattern.

**O11. io.popen vs run_child_process inconsistency** - MEDIUM
- Standardize on wezterm.run_child_process throughout.

**O15. Event handlers accumulate on config reload (state_manager.lua lines 141-164)** - MEDIUM
- event_driven_save registers new handlers each call; needs dedup guard.

**O16. periodic_save silently stops on error (state_manager.lua line 89)** - LOW
- Wrap in pcall, always re-schedule. (Already in our Phase 2 plan for #129)

**O19. Fragile pre-flight test in encryption fallback (encryption.lua lines 40-64)** - MEDIUM

**O20. Hardcoded "/" instead of utils.separator (state_manager.lua line 227)** - LOW

---

## Action Items

### Must fix before release (Critical/High security + HIGH quality)

- [ ] **[CRITICAL]** S1: Replace os.execute in fuzzy_loader.lua:123 with wezterm.run_child_process
- [ ] **[HIGH]** S2: Replace utils.execute io.popen with array-based process invocation
- [ ] **[HIGH]** S3: Fix VBScript injection - escape double quotes or replace VBS approach
- [ ] **[HIGH]** S4: Add path confinement to delete_state - reject .. segments
- [ ] **[HIGH]** S7: Fix encrypt() shell injection - use array args like decrypt()
- [ ] **[HIGH]** S11: Validate process.argv before send_text execution on restore
- [ ] **[HIGH]** O7: Guard active_tab:activate() against nil

### Should fix before release (Medium security + MEDIUM optimization)

- [ ] **[MEDIUM]** S5: Add null byte and Windows reserved name validation to filename sanitization
- [ ] **[MEDIUM]** S8: Implement atomic file writes (write to .tmp then rename)
- [ ] **[MEDIUM]** O4: Extract shared save helper to eliminate duplication
- [ ] **[MEDIUM]** O6: Add explicit type field to state objects or log on unknown type
- [ ] **[MEDIUM]** O9: Log errors in resurrect_on_gui_startup instead of swallowing
- [ ] **[MEDIUM]** O14: Replace VBS file listing with wezterm.run_child_process
- [ ] **[MEDIUM]** O15: Add dedup guard for event_driven_save handler registration
- [ ] **[MEDIUM]** O18: Don't emit multi-MB data strings as event arguments

### Can fix later (Low severity)

- [ ] **[LOW]** O1: Remove or document pane_tree.map()
- [ ] **[LOW]** O2: Remove dead require in window_state.lua
- [ ] **[LOW]** O3: Use utils.separator in init.lua instead of recomputing
- [ ] **[LOW]** O5: Extract has_title() helper
- [ ] **[LOW]** O8: Rename `type` parameter to `state_type` throughout
- [ ] **[LOW]** O12: Remove double sanitize_json
- [ ] **[LOW]** O13: Use read_file() in load_json
- [ ] **[LOW]** O17: Fix "Decryption" typo in encryption error log
- [ ] **[LOW]** O20: Use utils.separator in change_state_save_dir
- [ ] **[LOW]** S9, S10, S12: Minor probe race, Unix mkdir, VBS quoting
