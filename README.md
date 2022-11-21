# Flutter Version Manager [![fvm version](https://img.shields.io/badge/version-v0.0.1-40d0fd.svg)][2]

Inspired by [nvm](https://github.com/nvm-sh/nvm)

<!-- To update this table of contents, ensure you have run `npm install` then `npm run doctoc` -->
<!-- START doctoc generated TOC please keep comment here to allow auto update -->
<!-- DON'T EDIT THIS SECTION, INSTEAD RE-RUN doctoc TO UPDATE -->
## Table of Contents

- [Intro](#intro)
- [About](#about)
- [Installing and Updating](#installing-and-updating)
  - [Install & Update Script](#install--update-script)
    - [Additional Notes](#additional-notes)
    - [Troubleshooting on Linux](#troubleshooting-on-linux)
    - [Troubleshooting on macOS](#troubleshooting-on-macos)
    - [Ansible](#ansible)
  - [Verify Installation](#verify-installation)
  - [Important Notes](#important-notes)
  - [Git Install](#git-install)
  - [Manual Install](#manual-install)
  - [Manual Upgrade](#manual-upgrade)
- [Usage](#usage)
  - [System Version of Flutter](#system-version-of-flutter)
  - [Listing Versions](#listing-versions)
  - [Restoring PATH](#restoring-path)
  - [Use a mirror of flutter archives](#use-a-mirror-of-flutter-archives)
  - [flutter.version](#flutter.version)
- [Environment variables](#environment-variables)
- [Bash Completion](#bash-completion)
  - [Usage](#usage-1)
- [Compatibility Issues](#compatibility-issues)
- [Uninstalling / Removal](#uninstalling--removal)
  - [Manual Uninstall](#manual-uninstall)
- [Problems](#problems)
- [macOS Troubleshooting](#macos-troubleshooting)
- [Maintainers](#maintainers)
- [License](#license)

<!-- END doctoc generated TOC please keep comment here to allow auto update -->

## Intro

`fvm` allows you to quickly install and use different versions of flutter via the command line.

**Example:**
```sh
$ fvm use 2.10.3
Now using flutter 2.10.3
$ flutter --version
Flutter 2.10.3 • channel stable • https://github.com/flutter/flutter.git
Framework • revision 7e9793dee1 (9 months ago) • 2022-03-02 11:23:12 -0600
Engine • revision bd539267b4
Tools • Dart 2.16.1 • DevTools 2.9.2
$ fvm install 3.3.8
Now using flutter 3.3.8
```

Simple as that!


## About
fvm is a version manager for [flutter](https://flutter.dev/), inspired by [nvm](https://github.com/nvm-sh/nvm) 
.`fvm` works on any POSIX-compliant shell (sh, dash, ksh, zsh, bash), in particular on these platforms: unix, macOS, and [windows WSL](https://github.com/fvm-sh/fvm#important-notes).

<a id="installation-and-update"></a>
<a id="install-script"></a>
## Installing and Updating

### Install & Update Script

To **install** or **update** fvm, you should run the [install script][1]. To do that, you may either download and run the script manually, or use the following cURL or Wget command:
```sh
curl -o- https://raw.githubusercontent.com/fvm-sh/fvm/v0.0.1/install.sh | bash
```
```sh
wget -qO- https://raw.githubusercontent.com/fvm-sh/fvm/v0.0.1/install.sh | bash
```

Running either of the above commands downloads a script and runs it. The script clones the fvm repository to `~/.fvm`, and attempts to add the source lines from the snippet below to the correct profile file (`~/.bash_profile`, `~/.zshrc`, `~/.profile`, or `~/.bashrc`).

<a id="profile_snippet"></a>
```sh
export FVM_DIR="$([ -z "${XDG_CONFIG_HOME-}" ] && printf %s "${HOME}/.fvm" || printf %s "${XDG_CONFIG_HOME}/fvm")"
[ -s "$FVM_DIR/fvm.sh" ] && \. "$FVM_DIR/fvm.sh" # This loads fvm
```

#### Additional Notes

- If the environment variable `$XDG_CONFIG_HOME` is present, it will place the `fvm` files there.</sub>

- You can add `--no-use` to the end of the above script (...`fvm.sh --no-use`) to postpone using `fvm` until you manually [`use`](#usage) it.

- You can customize the install directory, profile, and version using the `FVM_DIR`, `PROFILE`, and `FLUTTER_VERSION` variables.
Eg: `curl ... | FVM_DIR="path/to/fvm"`. Ensure that the `FVM_DIR` does not contain a trailing slash.

- The installer can use `git`, `curl`, or `wget` to download `fvm`, whichever is available.

#### Troubleshooting on Linux

On Linux, after running the install script, if you get `fvm: command not found` or see no feedback from your terminal after you type `command -v fvm`, simply close your current terminal, open a new terminal, and try verifying again.
Alternatively, you can run the following commands for the different shells on the command line:

*bash*: `source ~/.bashrc`

*zsh*: `source ~/.zshrc`

*ksh*: `. ~/.profile`

These should pick up the `fvm` command.

#### Troubleshooting on macOS

Since OS X 10.9, `/usr/bin/git` has been preset by Xcode command line tools, which means we can't properly detect if Git is installed or not. You need to manually install the Xcode command line tools before running the install script, otherwise, it'll fail.

If you get `fvm: command not found` after running the install script, one of the following might be the reason:

  - Since macOS 10.15, the default shell is `zsh` and fvm will look for `.zshrc` to update, none is installed by default. Create one with `touch ~/.zshrc` and run the install script again.

  - If you use bash, the previous default shell, your system may not have `.bash_profile` or `.bashrc` files where the command is set up. Create one of them with `touch ~/.bash_profile` or `touch ~/.bashrc` and run the install script again. Then, run `. ~/.bash_profile` or `. ~/.bashrc` to pick up the `fvm` command.

  - You have previously used `bash`, but you have `zsh` installed. You need to manually add [these lines](#manual-install) to `~/.zshrc` and run `. ~/.zshrc`.

  - You might need to restart your terminal instance or run `. ~/.fvm/fvm.sh`. Restarting your terminal/opening a new tab/window, or running the source command will load the command and the new configuration.

  - If the above didn't help, you might need to restart your terminal instance. Try opening a new tab/window in your terminal and retry.

If the above doesn't fix the problem, you may try the following:

  - If you use bash, it may be that your `.bash_profile` (or `~/.profile`) does not source your `~/.bashrc` properly. You could fix this by adding `source ~/<your_profile_file>` to it or follow the next step below.

  - Try adding [the snippet from the install section](#profile_snippet), that finds the correct fvm directory and loads fvm, to your usual profile (`~/.bash_profile`, `~/.zshrc`, `~/.profile`, or `~/.bashrc`).

**Note** For Macs with the M1 chip, flutter started offering **arm64** arch darwin archive at stable channel since version 3.0.0 and beta channel since 2.12.0-4.1.pre. If you are facing issues installing flutter using `fvm`, you may want to update to one of those versions or later.

#### Ansible

You can use a task:

```yaml
- name: Install fvm
  ansible.builtin.shell: >
    curl -o- https://raw.githubusercontent.com/fvm-sh/fvm/v0.0.1/install.sh | bash
  args:
    creates: "{{ ansible_env.HOME }}/.fvm/fvm.sh"
```

### Verify Installation

To verify that fvm has been installed, do:

```sh
command -v fvm
```

which should output `fvm` if the installation was successful. Please note that `which fvm` will not work, since `fvm` is a sourced shell function, not an executable binary.

**Note:** On Linux, after running the install script, if you get `fvm: command not found` or see no feedback from your terminal after you type `command -v fvm`, simply close your current terminal, open a new terminal, and try verifying again.

### Important Notes

**Note:** `fvm` also support Windows in some cases. It should work through WSL (Windows Subsystem for Linux) depending on the version of WSL. It should also work with [GitBash](https://gitforwindows.org/) (MSYS) or [Cygwin](https://cygwin.com). 

**Note:** On OS X, if you do not have Xcode installed and you do not wish to download the ~4.3GB file, you can install the `Command Line Tools`. You can check out this blog post on how to just that:

  - [How to Install Command Line Tools in OS X Mavericks & Yosemite (Without Xcode)](https://osxdaily.com/2014/02/12/install-command-line-tools-mac-os-x/)

Homebrew installation is not supported. If you have issues with homebrew-installed `fvm`, please `brew uninstall` it, and install it using the instructions below, before filing an issue.

### Git Install

If you have `git` installed (requires git v1.7.10+):

1. clone this repo in the root of your user profile
    - `cd ~/` from anywhere then `git clone https://github.com/fvm-sh/fvm.git .fvm`
1. `cd ~/.fvm` and check out the latest version with `git checkout v0.0.1`
1. activate `fvm` by sourcing it from your shell: `. ./fvm.sh`

Now add these lines to your `~/.bashrc`, `~/.profile`, or `~/.zshrc` file to have it automatically sourced upon login:
(you may have to add to more than one of the above files)

```sh
export FVM_DIR="$HOME/.fvm"
[ -s "$FVM_DIR/fvm.sh" ] && \. "$FVM_DIR/fvm.sh"  # This loads fvm
[ -s "$FVM_DIR/bash_completion" ] && \. "$FVM_DIR/bash_completion"  # This loads fvm bash_completion
```

### Manual Install

For a fully manual install, execute the following lines to first clone the `fvm` repository into `$HOME/.fvm`, and then load `fvm`:

```sh
export FVM_DIR="$HOME/.fvm" && (
  git clone https://github.com/fvm-sh/fvm.git "$FVM_DIR"
  cd "$FVM_DIR"
  git checkout `git describe --abbrev=0 --tags --match "v[0-9]*" $(git rev-list --tags --max-count=1)`
) && \. "$FVM_DIR/fvm.sh"
```

Now add these lines to your `~/.bashrc`, `~/.profile`, or `~/.zshrc` file to have it automatically sourced upon login:
(you may have to add to more than one of the above files)

```sh
export FVM_DIR="$HOME/.fvm"
[ -s "$FVM_DIR/fvm.sh" ] && \. "$FVM_DIR/fvm.sh" # This loads fvm
[ -s "$FVM_DIR/bash_completion" ] && \. "$FVM_DIR/bash_completion"  # This loads fvm bash_completion
```

### Manual Upgrade

For manual upgrade with `git` (requires git v1.7.10+):

1. change to the `$FVM_DIR`
1. pull down the latest changes
1. check out the latest version
1. activate the new version

```sh
(
  cd "$FVM_DIR"
  git fetch --tags origin
  git checkout `git describe --abbrev=0 --tags --match "v[0-9]*" $(git rev-list --tags --max-count=1)`
) && \. "$FVM_DIR/fvm.sh"
```

## Usage

To install a specific version of flutter:

```sh
fvm install 3.3.8 # or 3.0.5, 2.5.3, etc
```

You can list available versions using `ls-remote`:

```sh
fvm ls-remote
```

And then in any new shell just use the installed version:

```sh
fvm use 3.3.8
```

You can also get the path to the executable to where it was installed:

```sh
fvm which 3.3.8
```

### System Version of Flutter

If you want to use the system-installed version of flutter, you can use the special alias "system":

```sh
fvm use system
```

### Listing Versions

If you want to see what versions are installed:

```sh
fvm ls
```

If you want to see what versions are available to install:

```sh
fvm ls-remote
```

### Restoring PATH
To restore your PATH, you can deactivate it:

```sh
fvm deactivate
```

### Use a mirror of flutter archives
To use a mirror of the flutter archives, set `$FLUTTER_STORAGE_BASE_URL`:

```sh
export FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn
fvm install 3.3.8

FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn fvm install 3.3.8
```

`fvm use` will not, by default, create a "current" symlink. Set `$FVM_SYMLINK_CURRENT` to "true" to enable this behavior, which is sometimes useful for IDEs. Note that using `fvm` in multiple shell tabs with this environment variable enabled can cause race conditions.

### flutter.version

You can create a `flutter.version` file containing a flutter version number (or any other string that `fvm` understands; see `fvm --help` for details) in the project root directory (or any parent directory).
Afterwards, `fvm use`, `fvm install`, and `fvm which` will use the version specified in the `flutter.version` file if no version is supplied on the command line.

For example, to make fvm default to the 3.3.8 release for the current directory:

```sh
$ echo "3.3.8" > flutter.version
```

Then when you run fvm:

```sh
$ fvm use
Found '/path/to/project/flutter.version' with version <3.3.8>
Now using flutter 3.3.8
```

`fvm use` et. al. will traverse directory structure upwards from the current directory looking for the `flutter.version` file. In other words, running `fvm use` et. al. in any subdirectory of a directory with an `flutter.version` will result in that `flutter.version` being utilized.

The contents of a `flutter.version` file **must** be the `<version>` (as described by `fvm --help`) followed by a newline. No trailing spaces are allowed, and the trailing newline is required.

## Environment variables

fvm exposes the following environment variables:

- `FVM_DIR` - fvm's installation directory.
- `FVM_BIN` - where flutter, npm, and global packages for the active version of flutter are installed.
- `FVM_CD_FLAGS` - used to maintain compatibility with zsh.
- `FVM_FLUTTER_VERSION` - version from flutter.version file if being used.

Additionally, fvm modifies `PATH`, and, if present, `MANPATH` and `NODE_PATH` when changing versions.


## Bash Completion

To activate, you need to source `bash_completion`:

```sh
[[ -r $FVM_DIR/bash_completion ]] && \. $FVM_DIR/bash_completion
```

Put the above sourcing line just below the sourcing line for fvm in your profile (`.bashrc`, `.bash_profile`).

### Usage

fvm:

> `$ fvm` <kbd>Tab</kbd>
```sh
deactivate          install             list-remote         uninstall           version
cache               ls                  unload              version-remote      current             help                list                ls-remote           use                 which
```

fvm use:
> `$ fvm use` <kbd>Tab</kbd>

```
3.3.8       3.0.5      2.10.3
```

fvm uninstall:
> `$ fvm uninstall` <kbd>Tab</kbd>

```
3.3.8       3.0.5      2.10.3
```

## Compatibility Issues
The following are known to cause issues:

Shell settings:

```sh
set -e
```
## Uninstalling / Removal

### Manual Uninstall

To remove `fvm` manually, execute the following:

```sh
$ rm -rf "$FVM_DIR"
```

Edit `~/.bashrc` (or other shell resource config) and remove the lines below:

```sh
export FVM_DIR="$HOME/.fvm"
[ -s "$FVM_DIR/fvm.sh" ] && \. "$FVM_DIR/fvm.sh" # This loads fvm
[[ -r $FVM_DIR/bash_completion ]] && \. $FVM_DIR/bash_completion
```

## Problems

  - If you try to install a flutter version and the installation fails, be sure to run `fvm cache clear` to delete cached flutter downloads, or you might get an error like the following:

    curl: (33) HTTP server doesn't seem to support byte ranges. Cannot resume.

## macOS Troubleshooting

**fvm flutter version not found in vim shell**

If you set flutter version to a version other than your system flutter version `fvm use 3.3.8` and open vim and run `:!flutter --version` you should see `3.3.8` if you see your system version `2.10.3`. You need to run:

```shell
sudo chmod ugo-x /usr/libexec/path_helper
```

More on this issue in [dotphiles/dotzsh](https://github.com/dotphiles/dotzsh#mac-os-x).

There is one more edge case causing this issue, and that's a **mismatch between the `$HOME` path and the user's home directory's actual name**.

You have to make sure that the user directory name in `$HOME` and the user directory name you'd see from running `ls /Users/` **are capitalized the same way** 

To change the user directory and/or account name follow the instructions [here](https://support.apple.com/en-us/HT201548)

[1]: https://github.com/fvm-sh/fvm/blob/v0.0.1/install.sh
[2]: https://github.com/fvm-sh/fvm/releases/tag/v0.0.1

**Homebrew makes zsh directories unsecure**

```shell
zsh compinit: insecure directories, run compaudit for list.
Ignore insecure directories and continue [y] or abort compinit [n]? y
```

Homebrew causes insecure directories like `/usr/local/share/zsh/site-functions` and `/usr/local/share/zsh`. This is **not** an `fvm` problem - it is a homebrew problem. Refer [here](https://github.com/zsh-users/zsh-completions/issues/680) for some solutions related to the issue.

## Maintainers

Currently, the sole maintainer is [@hyiso](https://github.com/hyiso) - more maintainers are quite welcome, and we hope to add folks to the team over time. [Governance](./GOVERNANCE.md) will be re-evaluated as the project evolves.

## License

See [LICENSE](./LICENSE).
