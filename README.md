# `libcntutils.sh`

This is a bash(1) library of small helper functions intended to be used with e.g. [podman-run(1)](https://docs.podman.io/en/stable/markdown/podman-run.1.html) to spin up containers or pods from bash(1) scripts.

I typically include this library as [git submodule](https://git-scm.com/book/en/v2/Git-Tools-Submodules), e.g. something like

```bash
git init newcontainerproject && cd newcontainerproject
git submodule add https://github.com/7h145/libcntutils lib
source lib/libcntutils-1.sh
```


This is probably not that useful for public consumption, at least in its current state.  But feel free to have a look if you like fancy bash(1)ing.

