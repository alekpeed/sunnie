# Starting Prompt for Claude Code

Paste the following into Claude Code after placing this package at the repository root:

```text
You are implementing Sunnie Days, a fully native Swift/SwiftUI iPhone and Apple Watch app.

Before writing code, read these files in order:
1. README_FIRST.md
2. CLAUDE.md
3. MASTER_SOURCE_OF_TRUTH.md
4. DOCUMENT_INDEX.md
5. 01_Product/PRODUCT_VISION_AND_GOALS.md
6. 01_Product/RELEASE_SCOPE_AND_NON_GOALS.md
7. 02_Character_and_Design/SUNNIE_CHARACTER_BIBLE.md
8. 05_Technical/TECHNICAL_ARCHITECTURE.md
9. 05_Technical/PROJECT_STRUCTURE_AND_CODING_STANDARDS.md
10. 06_Delivery/IMPLEMENTATION_ROADMAP.md
11. 06_Delivery/FIRST_VERTICAL_SLICE.md

Then inspect the current repository and report:
- what already exists,
- what conflicts with the documents,
- the exact Phase 0 work required,
- any truly blocking decisions.

Do not build the full app at once. Do not create a web app or cross-platform wrapper. Do not add third-party packages. Do not begin future voice, 3D, Android, caretaker, LifeOS, backend, or generative-AI work.

After the audit, implement Phase 0 only unless I explicitly authorize the next phase. Keep the project compiling, add tests with each functional change, and update ARCHITECTURE_DECISIONS.md if a locked technical decision changes.
```
