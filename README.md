# ComposeDeck

ComposeDeck is a GTK4/libadwaita desktop app for managing Docker Compose
projects running on Podman.

It scans a folder for compose projects, shows which services are running, and
lets you start, stop, and restart individual apps or all of them at once.

## Requirements

- Flatpak, with the Flathub remote available for the GNOME runtime.
- Podman, with the Docker-compatible socket enabled:

  ```sh
  systemctl --user enable --now podman.socket
  ```

- Compose projects in `~/Apps`, or another folder configured in Settings.

## Install

```sh
flatpak install --from https://a2way-com.github.io/ComposeDeck/com.a2way.ComposeDeck.flatpakref
```

Update:

```sh
flatpak update com.a2way.ComposeDeck
```

Uninstall:

```sh
flatpak uninstall com.a2way.ComposeDeck
```

The current Pages repository contains x86_64 builds. The Flatpak has access
to the home directory because it needs to read compose projects and
`.ComposeDeck/settings.jsonc`. It does not modify your projects.

## Build

The Flatpak build uses the GNOME 51 SDK:

```sh
make flatpak-build
make flatpak-run
make bundle
```

For a standard `flatpak-builder` build:

```sh
flatpak-builder --user --force-clean --default-branch=stable --repo=repo build-dir com.a2way.ComposeDeck.json
```

## Publishing

The `Pages` workflow builds and signs the Flatpak repository, then deploys it
to GitHub Pages. It runs on `v*` tags and on manual dispatch.

### GitHub Pages

In the repository settings, open **Pages** and set **Build and deployment >
Source** to **GitHub Actions**.

### Signing key

Create a dedicated GPG key for signing the repository:

```sh
gpg --full-generate-key
gpg --list-secret-keys --keyid-format=long
gpg --list-secret-keys --with-keygrip
gpg --armor --export-secret-keys KEY_ID > private.asc
```

Add these repository secrets under **Settings > Secrets and variables >
Actions**:

| Secret | Value |
| --- | --- |
| `GPG_PRIVATE_KEY` | Contents of `private.asc` |
| `GPG_PASSPHRASE` | The key passphrase |
| `GPG_KEY_ID` | Long key ID, e.g. `0123456789ABCDEF` |
| `GPG_KEY_GRIP` | Keygrip of the signing key from `--with-keygrip` |

Do not commit `private.asc`. Once the workflow has run, delete it from your
machine.

### Release

1. Update `VERSION` in `src/Logic/ComposeDeck.vala`.
2. Update the release entry in `data/com.a2way.ComposeDeck.metainfo.xml`.
3. Tag and push:

   ```sh
   git tag v0.1.0
   git push gh v0.1.0
   ```

The workflow checks that the tag matches `VERSION` before publishing.

## License

MIT. See [LICENSE](LICENSE).
