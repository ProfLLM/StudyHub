---
name: create-pr
description: Create a pull request only after the final changes pass the repository build, then its tests, and all other required checks. Use when asked to open or submit a PR.
---

# Create a PR

The required order is **build → tests → confirm success → create PR**. Apply this gate to every PR, including draft PRs and documentation-only changes.

1. Prepare the intended changes and read the repository's `AGENTS.md`, `README.md`, `CONTRIBUTING.md`, and applicable CI configuration to identify its toolchain, build command, test commands, and additional required checks. Use the repository's documented target and configuration; a successful check for a different platform does not establish that the required build passes.
2. Run the build first. Wait for completion and verify a successful exit status. Do not start tests or create a PR while the build is running or if it fails.
3. After the build succeeds, run the required test suite. Wait for completion and verify that the command succeeds and no required tests failed or were unexpectedly skipped. Then complete any remaining repository-required checks, such as formatting or static analysis.
4. Confirm that the build, tests, and remaining required checks all succeeded for the final changes that will be submitted. Record the commands and their results. If the submitted changes are modified after validation, run the build and then the tests again, along with any affected required checks, before creating the PR.
5. Only after confirming success, commit and push the intended changes as needed and create the PR using the available GitHub tools or CLI. Existing user authorization to create the PR is sufficient; this skill does not authorize unrelated publication or merging. Describe the resulting behavior and include the actual build, test, and check results in the PR description. Attach the created PR to the current chat when the app provides an artifact attachment tool, and return its link.

If a required command fails, cannot run, or has an inconclusive result, fix problems within the requested scope and repeat validation in order. If progress requires missing tools, access, or a decision from the user, report the blocker and leave PR creation pending. Missing commands, unavailable native build tools, prior runs on different changes, and promises that CI will run later do not satisfy the gate. Do not disable checks, suppress failures, or claim success without evidence.
