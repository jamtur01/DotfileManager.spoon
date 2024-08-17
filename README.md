# DotfileManager Spoon

`DotfileManager` is a Hammerspoon Spoon designed to help manage and synchronize dotfiles across multiple machines using a Git repository. It automates the process of tracking changes to dotfiles, committing them to a local Git repository, and pushing them to a remote origin. It also supports automatic updates of `.gitignore` files and excludes sensitive or unnecessary files from being tracked.

Happy dotfile management! 🚀

## Features

- **Track Dotfiles**: Automatically track dotfiles and specific configuration directories.
- **Git Integration**: Initialize Git repositories, commit changes, and push to remote origins.
- **Customizable Exclusions**: Exclude files and directories using patterns (e.g., `.DS_Store`, `*.log`, etc.).
- **Scheduled Sync**: Automatically synchronize dotfiles at regular intervals (default: 1 hour).
- **Manual Trigger**: Optionally trigger the dotfile update process manually.

### Note

There are a set of default included files to sync and exclude, but you can customize the list of files and directories to track. I recommend you check the default list and adjust it to your needs.

## Installation

1. Ensure you have Hammerspoon installed on your system. Download it from [Hammerspoon.org](https://www.hammerspoon.org/).
2. Install `DotfileManager` Spoon:
   - Copy the `DotfileManager.spoon` directory to your Hammerspoon's `Spoons` directory: `~/.hammerspoon/Spoons/`.
   - In your Hammerspoon config, load the spoon using the following code:

```lua
hs.loadSpoon("DotfileManager")
spoon.DotfileManager:setGitRepo("/path/to/your/git/repo")
spoon.DotfileManager:setRemoteOrigin("git@github.com:your-username/dotfiles.git")
spoon.DotfileManager:start()
```

3. Reload Hammerspoon's config.

## Usage

### Setting Git Repository

To set the Git repository where the dotfiles will be stored:

```lua
spoon.DotfileManager:setGitRepo("/path/to/your/git/repo")
```

### Setting Remote Origin

To set the remote origin for pushing the dotfiles:

```lua
spoon.DotfileManager:setRemoteOrigin("git@github.com:your-username/dotfiles.git")
```

### Start the Manager

To start the manager, which begins syncing the dotfiles at the default interval:

```lua
spoon.DotfileManager:start()
```

### Stop the Manager

To stop the manager:

```lua
spoon.DotfileManager:stop()
```

### Manual Sync

To trigger a manual sync of the dotfiles:

```lua
spoon.DotfileManager:manualUpdate()
```

### Add Dotfile Paths

To add directories to track for dotfiles:

```lua
spoon.DotfileManager:addDotfilePath("/path/to/directory")
```

### Add Dotfiles

To add individual files to track:

```lua
spoon.DotfileManager:addDotfile("/path/to/file")
```

### Add Ignore Patterns

To add patterns to exclude from tracking (e.g., logs, temp files, sensitive data or directories):

```lua
spoon.DotfileManager:addIgnorePattern("*.log")
```

### Custom Interval

To customize the interval between automatic syncs (in seconds):

```lua
spoon.DotfileManager:setInterval(7200) -- Set to 2 hours (7200 seconds)
```

## Logging

`DotfileManager` uses Hammerspoon's logging facilities to provide detailed information and errors. By default, the logging level is set to `info`. You can monitor the logs through Hammerspoon's console or customize the log level if needed.

## License

`DotfileManager` is distributed under the MIT license. See the [LICENSE](https://opensource.org/licenses/MIT) for more details.

## Contributing

Contributions are welcome! Feel free to fork the repository, make your changes, and submit a pull request.

## Author

Developed by [James Turnbull](https://github.com/jamtur01).

## Acknowledgements

Special thanks to the Hammerspoon community for providing an amazing automation tool for macOS.

---
