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

### How it works

Each command is also appended to a per-directory file in `ZSH_PRIORITIZE_CWD_HISTORY_DIR`.
After a directory change, before the next prompt (or at once when a widget changed directory), the plugin rebuilds the in-memory history list: first `$HISTFILE`, then the entries of the current directory, so these come first on UP-arrow and in searches.

The plugin only reads `$HISTFILE`; zsh itself writes every command to it.
For that, the plugin turns on `INC_APPEND_HISTORY_TIME` unless `INC_APPEND_HISTORY`, `INC_APPEND_HISTORY_TIME` or `SHARE_HISTORY` is already set.
It also turns on `EXTENDED_HISTORY`, so that `$HISTFILE` keeps timestamps.

Commands that zsh keeps out of `$HISTFILE` (`HIST_IGNORE_SPACE`, `HISTORY_IGNORE`) are kept out of the per-directory files, too.
The directory holding these files is created readable only by you.

The plugin's hooks never abort the running command line or exit the shell, not even with `ERR_EXIT` set.


## Configuration

Set these variables before or after sourcing the plugin to override defaults.


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


### `can't rename .../history.new to $HISTFILE`

With several shells (say, tmux panes) sharing one `$HISTFILE`, zsh may print this error, abort the command line that was running, and lose history lines.

This plugin never writes `$HISTFILE`, but zsh itself rewrites it through `$HISTFILE.new` and a rename on exit, and when the file has grown past `SAVEHIST`.
With zsh 5.9, these rewrites race when `HIST_FCNTL_LOCK` is set: renaming the new file over `$HISTFILE` drops the lock other shells are waiting on.
Without `HIST_FCNTL_LOCK`, zsh locks with a separate `$HISTFILE.LOCK` file, and no errors or lost lines occurred in tests with many shells exiting at once.
So, in your `.zshrc`:

```shell
unsetopt HIST_FCNTL_LOCK
setopt SHARE_HISTORY  # or INC_APPEND_HISTORY; set only one of the three INC_APPEND/SHARE options
```

Also keep `$HISTFILE` on a local file system: on network or synchronized folders (NFS, Dropbox, Syncthing) locks and renames can fail.


### Reporting an Issue

Before reporting an issue, please try temporarily disabling sections of your configuration and other plugins that may be conflicting with this plugin to isolate the problem.

When reporting an issue, please include:

- The smallest, simplest `.zshrc` configuration that will reproduce the problem.
- The version of zsh you're using (`zsh --version`)
- Which operating system you're running


## Tests

The tests start real interactive zsh shells:

```sh
zsh tests/run.zsh
```


## Uninstallation

1. Remove the code referencing this plugin from `~/.zshrc`.

2. Remove the git repository from your hard drive

    ```sh
    rm -rf ~/.zsh/zsh-prioritize-cwd-history # Or wherever you installed
    ```


## License

This project is licensed under [MIT license](http://opensource.org/licenses/MIT).
For the full text of the license, see the [LICENSE](LICENSE) file.
