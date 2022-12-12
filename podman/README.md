# Install with Podman

You can get started with Penpot locally or self-host it with **podman** and **podman-compose**.
After installation of both tools you can do the following:

- `podman machine init`
- `podman machine start`
- clone this project, navigate into the project
- `manage-podman.sh pull-devenv`
- `manage-podman.sh run-devenv`

## Tested environments
- ✅ Working: Ubuntu 22.04
- ❌ Not working: Mac 12.06 (error during `yarn install` too many files)

