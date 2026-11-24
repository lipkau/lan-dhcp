# Contributing

Issues and pull requests are welcome. For a larger change, open an issue first so we can agree on the approach.

## Layout

| Path              | Contents                                                                                                                                 |
| ----------------- | ---------------------------------------------------------------------------------------------------------------------------------------- |
| `repository.yaml` | Makes this repository a Home Assistant app repository.                                                                                   |
| `lan_dhcp/`       | The app: `config.yaml`, its documentation, changelog, icon and logo, option translations, and the image (`Dockerfile`, `entrypoint.sh`). |
| `tests/`          | `run.sh` and its fixtures.                                                                                                               |
| `.github/`        | CI workflows, the release check, Renovate configuration, templates.                                                                      |

## Develop and test

You need Docker, Node.js (the version in `.nvmrc`) and [ShellCheck](https://www.shellcheck.net/).

```sh
npm ci
npx biome ci                                    # formatting and lint
shellcheck lan_dhcp/entrypoint.sh tests/*.sh .github/scripts/*.sh
.github/scripts/check-release.sh                # app version and changelog
docker build -t lan-dhcp:test lan_dhcp
tests/run.sh lan-dhcp:test
```

`tests/run.sh` runs the entrypoint through its failure cases, then starts the image on a temporary Docker network
and leases addresses to test clients. It removes the network when it finishes. `tests/config/` is a fixture on a
private test subnet. CI also loads the AppArmor profile and runs `tests/ingress.sh` on a Linux Docker host with an
isolated bridge that mimics Supervisor networking.

Pull requests run the same checks, plus the [Home Assistant app linter](https://github.com/frenck/action-addon-linter).
The `CI result` job must pass before a merge.

## Releases

Home Assistant pulls `ghcr.io/lipkau/lan-dhcp:<version>`, where `<version>` is `version` in
`lan_dhcp/config.yaml`. Only a matching release tag publishes that image.

1. In the pull request, bump `version` in `lan_dhcp/config.yaml` and add a `## <version>` entry to
   `lan_dhcp/CHANGELOG.md`.
2. After the merge, tag the merge commit on `main` as `v<version>` and push the tag. CI rejects a tag that doesn't
   match the version.
3. Home Assistant offers the update as soon as `main` has the new version. Wait for the tag's image job to finish
   before you install it.

Bump the version for every change to the image or to `config.yaml`. Documentation changes don't need a release.

## Update dnsmasq

Renovate keeps the Alpine base image and the actions current. dnsmasq is updated by hand:

1. Download the new tarball and its signature from <https://thekelleys.org.uk/dnsmasq/>, and verify the signature
   against Simon Kelley's key (`D6EA CBD6 EE46 B834 248D 1112 15CD DA6A E191 35A2`).
2. Set `DNSMASQ_VERSION` and `DNSMASQ_SHA256` in `lan_dhcp/Dockerfile` together, and release.

## Icon and logo

`lan_dhcp/icon.png` is 128 × 128 pixels and `lan_dhcp/logo.png` 250 × 100, as Home Assistant expects. Keep them as
PNGs with a transparent background, and check the logo on a light and a dark background.
