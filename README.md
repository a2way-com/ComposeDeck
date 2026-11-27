# ComposeDeck

ComposeDeck is a GTK4/libadwaita desktop app for managing Docker Compose
projects running on Podman or Docker.

It scans a folder for compose projects, shows which services are running, and
lets you start, stop, and restart individual apps or all of them at once. Each
project's `.env` file can be viewed and edited from the app.

## Why this exists

ComposeDeck exists to run container stacks as apps. A Compose stack is usually
a directory, a compose file, and a command you have to remember; here each
stack in your apps folder (`~/Apps` by default) becomes an app with its own
status, services, logs, and start/stop/restart lifecycle. State is read from
the Podman or Docker API, so each app reflects what is actually running.

## Requirements

- Flatpak, with the Flathub remote available for the GNOME runtime.
- Podman or Docker. ComposeDeck starts the Podman API or the rootless Docker
  user service on demand. Rootful Docker must already be running.
- Compose projects in `~/Apps`, or another folder configured in Settings.

If your environment blocks the on-demand service start, enable the socket
manually:

```sh
# Podman
systemctl --user enable --now podman.socket

# Rootless Docker
systemctl --user enable --now docker.service
```

### Container engines

ComposeDeck detects Podman at `$XDG_RUNTIME_DIR/podman/podman.sock` or
`/run/podman/podman.sock`, and Docker at `$XDG_RUNTIME_DIR/docker.sock`,
`~/.docker/desktop/docker.sock`, or `/run/docker.sock`. When both are running
it prefers Podman; **Settings > Container engine** pins one explicitly.

A `unix://` endpoint in `CONTAINER_HOST` or `DOCKER_HOST` takes precedence.
The Flatpak needs access to a custom path, for example:

```sh
flatpak override --user --filesystem=/path/to/docker.sock com.a2way.ComposeDeck
```

## Environment variables

A project can keep its settings in a `.env` file next to its compose file. The
Environment row on an app's page edits that file: change values, add or remove
variables, and save. Values whose names look like credentials (`KEY`, `TOKEN`,
`SECRET`, `PASSWORD`, and so on) are masked until revealed.

Saving can recreate the project's containers through compose, so the new
values take effect. Variables are listed and saved alphabetically; a comment
directly above a variable in the file is shown above it in the editor.
ComposeDeck keeps the comments and quoting, and writes the file with `0600`
permissions.

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
`.ComposeDeck/settings.jsonc`. It writes only the `.env` files you edit
through the app and its own settings file.

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
