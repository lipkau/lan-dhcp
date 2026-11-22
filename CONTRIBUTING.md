# Contributing

Issues and pull requests are welcome. For a larger change, open an issue first so we can agree on the approach.

## Layout

| Path              | Contents                                                                                                                                 |
| ----------------- | ---------------------------------------------------------------------------------------------------------------------------------------- |
| `repository.yaml` | Makes this repository a Home Assistant app repository.                                                                                   |
| `lan_dhcp/`       | The app: `config.yaml`, its documentation, changelog, icon and logo, option translations, and the image (`Dockerfile`, `entrypoint.sh`). |
| `tests/`          | `run.sh` and its fixtures.                                                                                                               |
| `.github/`        | CI workflows, the release scripts, Renovate configuration, templates.                                                                    |

## Develop and test

You need Docker, Node.js (the version in `.nvmrc`) and [ShellCheck](https://www.shellcheck.net/).

```sh
npm ci
npx biome ci                                    # formatting and lint
shellcheck lan_dhcp/entrypoint.sh tests/run.sh .github/scripts/*.sh
.github/scripts/check-release.sh                # app version and changelog
docker build -t lan-dhcp:test lan_dhcp
tests/run.sh lan-dhcp:test
```

`tests/run.sh` runs the entrypoint through its failure cases, then starts the image on a temporary Docker network
and leases addresses to test clients. It removes the network when it finishes. `tests/config/` is a fixture on a
private test subnet.

Pull requests run the same checks, plus the [Home Assistant app linter](https://github.com/frenck/action-addon-linter).
The `CI result` job must pass before a merge.

## Releases

Every merge to `main` that changes the app (anything in `lan_dhcp/` apart from its changelog) releases it. Don't
bump the version or write a changelog entry in the pull request. After the merge, CI's **Release** job:

1. bumps `version` in `lan_dhcp/config.yaml` and adds a `## <version>` entry to `lan_dhcp/CHANGELOG.md` that lists
   the subject of each commit since the last release;
2. commits that to `main` as `chore(release): <version>` and tags it `v<version>`;
3. and the tag's CI run publishes `ghcr.io/lipkau/lan-dhcp:<version>`, the image Home Assistant pulls.

The commit subjects decide the version, so write them as [conventional commits](https://www.conventionalcommits.org/):

| Subject                                   | Release                  |
| ----------------------------------------- | ------------------------ |
| `feat!: …` or any other type with `!`     | major: `1.4.2` → `2.0.0` |
| `feat: …`                                 | minor: `1.4.2` → `1.5.0` |
| anything else (`fix:`, `chore(deps):`, …) | patch: `1.4.2` → `1.4.3` |

A squash merge's subject is the pull request title. The changelog shows each subject without its type, so write it
for the person who updates the app. Changes outside `lan_dhcp/`, such as tests, CI or the README, don't release.

The job pushes with the `RELEASE_DEPLOY_KEY` secret: the private half of a deploy key with write access, which the
`main` ruleset lists as a bypass actor. A push with the workflow token would start no CI run for the tag. Home
Assistant offers the update as soon as `main` has the new version; the image follows a few minutes later.

## Update dnsmasq

Renovate keeps the Alpine base image and the actions current. dnsmasq is updated by hand:

1. Download the new tarball and its signature from <https://thekelleys.org.uk/dnsmasq/>, and verify the signature
   against Simon Kelley's key (`D6EA CBD6 EE46 B834 248D 1112 15CD DA6A E191 35A2`).
2. Set `DNSMASQ_VERSION` and `DNSMASQ_SHA256` in `lan_dhcp/Dockerfile` together, and release.

## Icon and logo

`lan_dhcp/icon.png` is 128 × 128 pixels and `lan_dhcp/logo.png` 250 × 100, as Home Assistant expects. Keep them as
PNGs with a transparent background, and check the logo on a light and a dark background.
