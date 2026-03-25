# zsh-prioritize-cwd-history

_Prioritizes history entries executed from the current working directory._

Forked from [ericfreese/zsh-prioritize-cwd-history](https://github.com/ericfreese/zsh-prioritize-cwd-history) by [@ceed0](https://github.com/ceed0).

<a href="https://asciinema.org/a/7o75n5k4dmmr6aywc84e20ll9" target="_blank"><img src="https://asciinema.org/a/7o75n5k4dmmr6aywc84e20ll9.png" width="500" /></a>


## Installation

### Manual

1. Clone this repository somewhere on your machine. This guide will assume `~/.zsh/zsh-prioritize-cwd-history`.

    ```sh
    git clone https://github.com/Konfekt/zsh-prioritize-cwd-history ~/.zsh/zsh-prioritize-cwd-history
    ```

2. Add the following to your `.zshrc`:

    ```sh
    source ~/.zsh/zsh-prioritize-cwd-history/zsh-prioritize-cwd-history.zsh
    ```

3. Start a new terminal session.


### Oh My Zsh

1. Clone this repository into `$ZSH_CUSTOM/plugins` (by default `~/.oh-my-zsh/custom/plugins`)

    ```sh
    git clone https://github.com/Konfekt/zsh-prioritize-cwd-history $ZSH_CUSTOM/plugins/zsh-prioritize-cwd-history
    ```

2. Add the plugin to the list of plugins for Oh My Zsh to load:

    ```sh
    plugins=(zsh-prioritize-cwd-history)
    ```

3. Start a new terminal session.


## Usage

When you change directories, the zsh history list will be updated to show commands entered in the current working directory before commands executed in other directories.

**Note:** This plugin is not retroactive. History entries created before installing this plugin will not be tied to any particular directory, and will not ever be prioritized.


## Configuration

Set these variables **after** sourcing the plugin to override defaults.


### History Directory

Where per-directory history files are stored (default: `~/.zsh_prioritize_cwd_history`):

```shell
ZSH_PRIORITIZE_CWD_HISTORY_DIR=~/my/special/dir
```

### Max Entries per Directory

Maximum physical lines kept per directory (default: `2000`).
Trimming is amortised — it only runs when the file exceeds twice this limit.

```shell
ZSH_PRIORITIZE_CWD_HISTORY_MAX=2000
```


## Troubleshooting

If you have a problem, please search through [the list of issues on GitHub](https://github.com/Konfekt/zsh-prioritize-cwd-history/issues) to see if someone else has already reported it.


### Reporting an Issue

Before reporting an issue, please try temporarily disabling sections of your configuration and other plugins that may be conflicting with this plugin to isolate the problem.

When reporting an issue, please include:

- The smallest, simplest `.zshrc` configuration that will reproduce the problem.
- The version of zsh you're using (`zsh --version`)
- Which operating system you're running


## Uninstallation

1. Remove the code referencing this plugin from `~/.zshrc`.

2. Remove the git repository from your hard drive

    ```sh
    rm -rf ~/.zsh/zsh-prioritize-cwd-history # Or wherever you installed
    ```


## License

This project is licensed under [MIT license](http://opensource.org/licenses/MIT).
For the full text of the license, see the [LICENSE](LICENSE) file.
