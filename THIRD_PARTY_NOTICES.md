# ADT third-party notices

This inventory covers the tracked project, checked-in binary archives, and release build inputs. It records attribution and license boundaries; it does not replace the upstream license text.

The company-use addendum applies only to the first-party material listed in `LICENSE-SCOPE.md`. It does not restrict use of separately licensed AOSP binaries or third-party components.

| Material | Origin | Terms / distribution handling |
| --- | --- | --- |
| Adapted build logic and upstream-derived files | [lzhiyong/android-sdk-tools](https://github.com/lzhiyong/android-sdk-tools) | Apache-2.0; preserve upstream copyright and license. |
| Linux/glibc adaptation lineage | [hamza72x/android-sdk-linux-arm64](https://github.com/hamza72x/android-sdk-linux-arm64) | Preserve that repository's applicable license and attribution where its work is included. |
| Compiled Android SDK tools and source patches | AOSP repositories listed in `repos.json`, currently built from the version's recorded tag in `versions.json` | AOSP components have varying licenses. Release packaging collects each source repository's tracked `LICENSE*`, `COPYING*`, and `NOTICE*` files under `upstream-licenses/`; do not substitute ADT's license for them. |
| Fonts | Space Grotesk, JetBrains Mono, and Noto Sans Bengali | SIL Open Font License 1.1; see `assets/fonts/LICENSES.md`. |
| Geographic data in `assets/geo/adt-geo.js` | Natural Earth 1:110m physical land and Admin-0 country polygons | Public-domain source data, as recorded in `tools/make-geo.py`; the first-party generator is separately scoped by `LICENSE-SCOPE.md`. |
| `katiusu` contributions | Recorded in Git history; see `LICENSE-SCOPE.md` for affected files | Existing Apache-2.0 grant retained. |

## Existing checked-in archives

The three archives under `artifacts/` were built from AOSP source but contain no license or notice files. They are legacy artifacts and must not be republished as compliant release packages. The release workflow adds the ADT scope notices and license/notice files collected from the exact AOSP source checkout before creating replacement archives.
