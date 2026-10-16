# ADT license scope

## First-party material

Original ADT documentation (`README.md`, `PLAN.md`, `CONTRIBUTING.md`, `CHANGELOG.md`, `docs/`, `SKB_KNOWLEDGE_*.md`, and `PROJECT_CLASSIFICATION.yaml`), website source/content/assets, project schemas and `versions.json`, `.superdesign/` design material, first-party workflow automation, standalone helpers (`install.sh`, `tools/collect-license-bundle.py`, `tools/doc_bridge.py`, `tools/make-geo.py`, and `tools/repo_knowledge/`), and Sobuj-authored tests are offered under the [PolyForm Noncommercial License 1.0.0](LICENSE) with the additional [commercial-use condition](LICENSE-COMMERCIAL-ADDENDUM.md). The `repo_knowledge` helper was also authored by Sobuj Miah for his SKB project and is vendored here as first-party code. Personal, hobby, research, education, and other noncommercial use and modification are allowed for this scoped material. For-profit company or business-capacity use requires a separate written commercial license even if that particular activity does not directly earn money. Any royalty is agreed separately; this repository does not set a rate. The combined terms are project-specific and are not the unmodified PolyForm license.

`.repo/` is machine-generated repository metadata and is outside the first-party code/documentation grant; any embedded source text remains subject to its originating rights.

## Upstream and contributor material

ADT is an adaptation of `lzhiyong/android-sdk-tools`, and it compiles and patches Android Open Source Project (AOSP) source. The build definitions, source patches, and compiled tools that contain or derive from that work retain their applicable Apache-2.0 and other upstream terms. Those files and binaries are not subject to the company-use addendum unless they independently include scoped PolyForm material. The historical Apache license text is preserved in [`LICENSE-APACHE-2.0`](LICENSE-APACHE-2.0). Source and third-party license texts must accompany published tool archives in `upstream-licenses/`.

The following files contain contributions by `katiusu` accepted while ADT was under Apache-2.0 and remain under those existing Apache-2.0 grants: `.github/workflows/ci.yml`, `AI_ASSISTANT.md`, `COMMANDS.md`, `setup.sh`, `tests/test_cli_args.sh`, and `tests/test_release_integrity.sh`. Their contribution history is recorded in Git. Sobuj's changes in those files are also left under Apache-2.0 to avoid imposing new terms on combined files without a contributor agreement.

The build system and derived files in `CMakeLists.txt`, `build-tools/`, `lib/`, `others/`, `platform-tools/`, `patches/`, `build.py`, `get_source.py`, and `repos.json` remain under the Apache-2.0 or other upstream terms applicable to the adapted source. `.github/workflows/ci.yml` and `setup.sh` are the contributor-file exceptions above. `assets/geo/adt-geo.js` is generated geographic data from Natural Earth public-domain data and is excluded from the first-party grant; the generator script remains first-party.

All other third-party material retains its own terms. Fonts are under SIL Open Font License 1.1; see [`assets/fonts/LICENSES.md`](assets/fonts/LICENSES.md). The `ADT` name, logos, and marks remain governed separately by [`TRADEMARKS.md`](TRADEMARKS.md).

## Earlier versions

ADT commits and releases published before the license transition were offered under Apache-2.0. Those grants continue for those versions; changing the current default does not revoke them.

## Required notice

Redistributions of first-party material covered by these combined terms must include both `LICENSE` and `LICENSE-COMMERCIAL-ADDENDUM.md` (or their URLs) and preserve this notice:

> Required Notice: Copyright (c) 2026 Sobuj Miah (https://github.com/soobujmiah/adt)
