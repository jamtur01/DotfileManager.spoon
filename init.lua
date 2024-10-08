local obj = {}
obj.__index = obj

-- Metadata
obj.name = "DotfileManager"
obj.version = "2.7"
obj.author = "James Turnbull <james@lovedthanlost.net>"
obj.homepage = "https://github.com/jamtur01/DotfileManager.spoon"
obj.license = "MIT - https://opensource.org/licenses/MIT"

-- Configuration keys for persistent settings storage
obj.settingsKeys = {
    gitRepo = "DotfileManager.gitRepo",
    remoteOrigin = "DotfileManager.remoteOrigin",
    dotfilePaths = "DotfileManager.dotfilePaths",
    dotfiles = "DotfileManager.dotfiles",
    ignorePatterns = "DotfileManager.ignorePatterns",
}

-- Default configurations
local defaultDotfilePaths = {
    os.getenv("HOME") .. "/.config",
    os.getenv("HOME") .. "/.oh-my-zsh",
}
local defaultDotfiles = {
    os.getenv("HOME") .. "/.bashrc",
    os.getenv("HOME") .. "/.zshrc",
    os.getenv("HOME") .. "/.vimrc",
    os.getenv("HOME") .. "/.zshenv",
    os.getenv("HOME") .. "/.gitconfig",
    os.getenv("HOME") .. "/.vimrc.local",
    os.getenv("HOME") .. "/.vimrc.before"
}
local defaultIgnorePatterns = {
    "*.log",
    "*.tmp",
    ".DS_Store",
    ".ssh/*",
    ".gnupg/*",
    ".git/",
}

obj.defaultInterval = 3600 -- default interval in seconds (1 hour)

obj.logger = hs.logger.new('DotfileManager', 'info')
obj.timer = nil

-- Logging helpers
function obj:logDebug(message)
    self.logger.d(message)
end

function obj:logInfo(message)
    self.logger.i(message)
end

function obj:logError(message)
    self.logger.e(message)
end

-- Helper to run commands and log the results with more granular error handling
function obj:runCommand(cmd)
    self:logDebug("Executing command: " .. cmd)
    local output, status, t, rc = hs.execute(cmd .. " 2>&1")
    
    if not status then
        -- Handle specific expected errors gracefully
        if output:find("ambiguous argument 'HEAD'") then
            self:logInfo("No commits yet in the repository. This is expected for a new repository.")
            return false, output
        elseif output:find("No such remote 'origin'") then
            self:logInfo("Remote origin not set. This is expected for a new repository.")
            return false, output
        elseif output:find("nothing to commit, working tree clean") then
            self:logInfo("Nothing to commit, working tree clean.")
            return false, output
        else
            -- For other errors, log them as actual errors
            self:logError("Command failed: " .. cmd .. "\nOutput: " .. (output or ""))
        end
    else
        self:logDebug("Command succeeded: " .. cmd)
    end
    return status, output
end

-- Improved runCommand to handle dynamic Git arguments
function obj:runGitCommand(args)
    local cmd = string.format("git -C '%s' %s", self.gitRepo, args)
    return self:runCommand(cmd)
end

-- Initialize persistent storage from hs.settings or use defaults
function obj:init()
    self.gitRepo = hs.settings.get(obj.settingsKeys.gitRepo) or nil
    self.remoteOrigin = hs.settings.get(obj.settingsKeys.remoteOrigin) or nil
    
    -- Merge default and user-defined dotfile paths, dotfiles, and ignore patterns
    self.dotfilePaths = self:mergeConfigs(hs.settings.get(obj.settingsKeys.dotfilePaths) or {}, defaultDotfilePaths)
    self.dotfiles = self:mergeConfigs(hs.settings.get(obj.settingsKeys.dotfiles) or {}, defaultDotfiles)
    self.ignorePatterns = self:mergeConfigs(hs.settings.get(obj.settingsKeys.ignorePatterns) or {}, defaultIgnorePatterns)

    -- Initialize timer
    self.timer = hs.timer.new(self.defaultInterval, function() self:updateDotfiles() end)
end

-- Set the Git repository path and store it in hs.settings
function obj:setGitRepo(repo)
    self.gitRepo = repo
    hs.settings.set(obj.settingsKeys.gitRepo, repo)
    self:logInfo("Git repository set to: " .. repo)
end

-- Set the remote origin URL and store it in hs.settings
function obj:setRemoteOrigin(url)
    self.remoteOrigin = url
    hs.settings.set(obj.settingsKeys.remoteOrigin, url)
    self:logInfo("Remote origin set to: " .. url)
end

-- Add a method to customize the default interval
function obj:setInterval(seconds)
    if type(seconds) == "number" and seconds > 0 then
        self.defaultInterval = seconds
        if self.timer then
            self.timer:setNextTrigger(seconds)
            self:logInfo("Interval updated to: " .. seconds .. " seconds.")
        end
    else
        self:logError("Invalid interval: must be a positive number.")
    end
end

-- Add a dotfile path to be tracked and store it in hs.settings
function obj:addDotfilePath(path)
    if not hs.fnutils.contains(self.dotfilePaths, path) then
        table.insert(self.dotfilePaths, path)
        hs.settings.set(obj.settingsKeys.dotfilePaths, self.dotfilePaths)
        self:logDebug("Added dotfile path: " .. path)
    else
        self:logDebug("Dotfile path already tracked: " .. path)
    end
end

-- Add a dotfile to be tracked and store it in hs.settings
function obj:addDotfile(file)
    if not hs.fnutils.contains(self.dotfiles, file) then
        table.insert(self.dotfiles, file)
        hs.settings.set(obj.settingsKeys.dotfiles, self.dotfiles)
        self:logDebug("Added dotfile: " .. file)
    else
        self:logDebug("Dotfile already tracked: " .. file)
    end
end

-- Add an ignore pattern and update .gitignore
function obj:addIgnorePattern(pattern)
    if not hs.fnutils.contains(self.ignorePatterns, pattern) then
        table.insert(self.ignorePatterns, pattern)
        hs.settings.set(obj.settingsKeys.ignorePatterns, self.ignorePatterns)
        self:updateGitignore()
        self:logDebug("Added ignore pattern: " .. pattern)
    else
        self:logDebug("Ignore pattern already exists: " .. pattern)
    end
end

-- Remove an ignore pattern and update .gitignore
function obj:removeIgnorePattern(pattern)
    for i, p in ipairs(self.ignorePatterns) do
        if p == pattern then
            table.remove(self.ignorePatterns, i)
            hs.settings.set(obj.settingsKeys.ignorePatterns, self.ignorePatterns)
            self:updateGitignore()
            self:logDebug("Removed ignore pattern: " .. pattern)
            return
        end
    end
    self:logDebug("Ignore pattern not found: " .. pattern)
end

-- Helper: Ensure a directory exists, create it if it doesn't
function obj:checkAndCreateDirectory(path)
    local attr = hs.fs.attributes(path)
    if not attr then
        local success, msg = hs.fs.mkdir(path)
        if success then
            self:logDebug("Created directory: " .. path)
            return true
        else
            self:logError("Failed to create directory: " .. path .. ". Error: " .. msg)
            return false
        end
    elseif attr.mode ~= "directory" then
        self:logError(path .. " exists but is not a directory")
        return false
    end
    return true
end

-- Helper: Send error notification
function obj:notifyError(title, message)
    hs.notify.new({title=title, informativeText=message}):send()
end

-- Update the .gitignore file
function obj:updateGitignore()
    local gitignorePath = self.gitRepo .. "/.gitignore"
    local gitignoreContents = {}

    -- Check if the .gitignore file exists before trying to open it
    local f = io.open(gitignorePath, "r")
    if f then
        for line in f:lines() do
            table.insert(gitignoreContents, line)
        end
        f:close()
    else
        self:logDebug(".gitignore file does not exist. It will be created.")
    end

    -- Create a set for quick lookup of existing patterns
    local existingPatterns = {}
    for _, line in ipairs(gitignoreContents) do
        existingPatterns[line] = true
    end

    -- Add patterns from ignorePatterns that aren't already in .gitignore
    for _, pattern in ipairs(self.ignorePatterns) do
        if not existingPatterns[pattern] then
            table.insert(gitignoreContents, pattern)
            existingPatterns[pattern] = true
        end
    end

    -- Write the updated .gitignore file
    f = io.open(gitignorePath, "w")
    if f then
        for _, line in ipairs(gitignoreContents) do
            f:write(line .. "\n")
        end
        f:close()
        self:logDebug(".gitignore updated")
    else
        self:logError("Failed to open .gitignore for writing")
    end
end

-- Check if the directory is a git repository by looking for a `.git` folder
function obj:isGitRepo(directory)
    local gitDir = directory .. "/.git"
    local attr = hs.fs.attributes(gitDir)
    return attr and attr.mode == "directory"
end

-- Initialize Git repository if it doesn't exist
function obj:initGitRepo()
    if not self:isGitRepo(self.gitRepo) then
        self:logInfo("Initializing Git repository...")
        local success = self:runGitCommand("init")
        if success then
            self:logInfo("Git repository initialized")
            return true
        else
            self:logError("Failed to initialize Git repository")
            return false
        end
    end
    return true
end

-- Check if the remote origin is set up in the Git repository
function obj:hasRemoteOrigin()
    local status, _ = self:runGitCommand("remote get-url origin")
    return status
end

-- Check if there are any commits in the repository
function obj:checkForCommits()
    local status, _ = self:runGitCommand("rev-parse HEAD")
    return status
end

-- Set up the remote origin for the Git repository
function obj:setUpRemoteOrigin()
    if not self.remoteOrigin then
        self:logError("Remote origin URL not set. Use setRemoteOrigin() to set it.")
        return false
    end

    if not self:hasRemoteOrigin() then
        self:logDebug("Setting up remote origin...")
        local cmd = string.format("remote add origin %s", self.remoteOrigin)
        local success = self:runGitCommand(cmd)
        if success then
            self:logDebug("Remote origin set successfully.")
            return true
        else
            self:logError("Failed to set remote origin")
            return false
        end
    end

    self:logDebug("Remote origin already exists.")
    return true
end

function obj:setUpTrackingBranch()
    if not self:checkForCommits() then
        self:logInfo("No commits found. Creating initial README.md and committing...")

        local hostname = hs.host.localizedName()
        local username = os.getenv("USER")
        local readmeContent = string.format("# Dotfiles for %s on %s", username, hostname)
        local readmePath = self.gitRepo .. "/README.md"

        local file = io.open(readmePath, "w")
        if file then
            file:write(readmeContent .. "\n")
            file:close()
            self:logDebug("Created README.md with content: " .. readmeContent)
        else
            self:logError("Failed to create README.md file")
            self:notifyError("Dotfile Manager", "Failed to create README.md. Check the log for details.")
            return false
        end

        self:runGitCommand("add README.md")
        local cmd = string.format("commit -m 'Initial commit with README.md'")
        local success, output = self:runGitCommand(cmd)
        if not success then
            self:logError("Failed to create initial commit: " .. output)
            self:notifyError("Dotfile Manager", "Failed to create initial commit. Check the log for details.")
            return false
        end
        self:logDebug("Initial commit with README.md created.")
    end

    local remoteExists, output = self:runGitCommand(string.format("ls-remote %s", self.remoteOrigin))
    if not remoteExists then
        self:logError(string.format("The remote repository '%s' does not exist or is unreachable. Git output: %s", self.remoteOrigin, output or ""))
        self:notifyError("Dotfile Manager", "Remote repository unreachable. Check the log for details.")
        return false
    end

    local success, output = self:runGitCommand("push --set-upstream origin main")
    if not success then
        if output:find("fetch first") then
            self:logError("Push failed because the remote repository contains commits that are not present locally.")
            self:notifyError("Dotfile Manager", "Push failed due to remote conflicts. Run 'git pull --rebase origin main' manually.")
        else
            self:logError("Failed to set up tracking branch. Git error: " .. (output or "Unknown error"))
            self:notifyError("Dotfile Manager", "Failed to set up tracking branch. Check the log for details.")
        end
        return false
    end
    self:logDebug("Tracking branch set up successfully.")
    return true
end

function obj:shouldIgnore(path)
    local relativePath = path:gsub("^" .. os.getenv("HOME") .. "/", "")
    for _, pattern in ipairs(self.ignorePatterns) do
        if string.match(relativePath, pattern) then
            self:logDebug("Excluded: " .. relativePath)
            return true
        end
    end
    return false
end

function obj:copyFiles(src, dest)
    if not self:checkAndCreateDirectory(dest) then
        return
    end

    -- Build the rsync command
    local excludePatterns = ""
    for _, pattern in ipairs(self.ignorePatterns) do
        excludePatterns = excludePatterns .. string.format(" --exclude='%s'", pattern)
    end

    -- Ensure .git directories are excluded
    excludePatterns = excludePatterns .. " --exclude='.git/'"

    local cmd = string.format("rsync -avh --delete %s '%s/' '%s/'", excludePatterns, src, dest)
    local status, output = self:runCommand(cmd)
    if not status then
        self:logError("Rsync failed for " .. src .. ": " .. output)
        self:notifyError("Dotfile Manager", "Rsync failed. Check the log for details.")
    else
        self:logDebug("Synchronized files from " .. src .. " to " .. dest)
    end
end

function obj:copyDotfile(file, dest)
    local fileName = file:match("([^/]+)$")
    local destFile = dest .. "/" .. fileName

    local fileAttr = hs.fs.attributes(file)
    if fileAttr then
        if not self:shouldIgnore(file) then
            self:copyFileWithLogging(file, destFile)
        else
            self:logDebug("Excluded: " .. file)
        end
    else
        local destAttr = hs.fs.attributes(destFile)
        if destAttr then
            local cmd = string.format("rm -f '%s'", destFile)
            local status, output = self:runCommand(cmd)
            if not status then
                self:logError("Failed to remove deleted dotfile " .. destFile .. ": " .. output)
            else
                self:logDebug("Removed deleted dotfile: " .. destFile)
            end
        end
    end
end

function obj:copyFileWithLogging(src, dest)
    local cmd = string.format("cp '%s' '%s'", src, dest)
    local status, output = self:runCommand(cmd)
    if not status then
        self:logError("Copy failed for " .. src .. ": " .. output)
    else
        self:logDebug("Copied file: " .. src)
    end
    return status
end

function obj:commitAndPush()
    local status, output = self:runGitCommand("status --porcelain")

    if status then
        if output == "" then
            self:logInfo("No changes detected. Repository is up-to-date.")
            return
        end

        self:logDebug("Git status output:\n" .. output)
        local addStatus, addOutput = self:runGitCommand("add .")
        if not addStatus then
            self:logError("Failed to stage changes: " .. addOutput)
            self:notifyError("Dotfile Manager", "Failed to stage changes. Check the log for details.")
            return
        end

        local hostname = hs.host.localizedName()
        local username = os.getenv("USER")
        local dateTime = os.date("%A %x at %X %p %Z")
        local commitMessage = string.format("Configuration changes committed for %s by %s on %s.", hostname, username, dateTime)

        local commitStatus, commitOutput = self:runGitCommand(string.format("commit -m '%s'", commitMessage))
        if not commitStatus then
            self:logError("Failed to commit changes: " .. commitOutput)
            self:notifyError("Dotfile Manager", "Failed to commit changes. Check the log for details.")
            return
        end

        if self:pushChanges() then
            self:logInfo("Dotfiles updated and pushed to repo successfully.")
            hs.notify.new({title="Dotfile Manager", informativeText="Dotfiles updated and pushed to repo successfully."}):send()
        else
            self:logError("Failed to push changes after committing.")
            self:notifyError("Dotfile Manager", "Failed to push changes. Check the log for details.")
        end
    else
        self:logError("Failed to check git status: " .. output)
        self:notifyError("Dotfile Manager", "Failed to check git status. Check the log for details.")
    end
end

function obj:pushChanges()
    local status, output = self:runGitCommand("push")
    if not status then
        if output:find("fetch first") then
            self:logDebug("Conflicts detected, pulling and rebasing...")
            status = self:runGitCommand("pull --rebase")
            if status then
                self:logDebug("Rebase successful, pushing again...")
                status = self:runGitCommand("push")
            end
        end
    end

    if status then
        self:logInfo("Changes pushed successfully.")
        return true
    else
        self:logError("Failed to push changes: " .. output)
        return false
    end
end

function obj:updateDotfiles()
    if not self.gitRepo then
        self:logError("Git repository not set. Use setGitRepo() to set it.")
        return
    end

    if not self:checkAndCreateDirectory(self.gitRepo) then
        self:logError("Failed to create or verify the repository directory: " .. self.gitRepo)
        return
    end

    if not self:initGitRepo() then
        self:logError("Failed to initialize Git repository at: " .. self.gitRepo)
        return
    end

    if not self:setUpRemoteOrigin() then
        self:logError("Failed to set up remote origin.")
        return
    end

    if not self:setUpTrackingBranch() then
        self:logError("Failed to set up tracking branch.")
        return
    end

    self:updateGitignore()

    for _, path in ipairs(self.dotfilePaths) do
        -- Check if path is a git repository
        if self:isGitRepo(path) then
            self:logDebug("Skipping git repository: " .. path)
        else
            local repoPath = self.gitRepo .. "/" .. path:match("([^/]+)$")
            self:copyFiles(path, repoPath)
        end
    end

    for _, file in ipairs(self.dotfiles) do
        self:copyDotfile(file, self.gitRepo)
    end

    self:commitAndPush()
end

-- Start the timer
function obj:start()
    if not self.timer then
        self:init()
    end
    self.timer:start()
    self:logInfo("DotfileManager started")
end

-- Stop the timer
function obj:stop()
    if self.timer then
        self.timer:stop()
        self:logInfo("DotfileManager stopped")
    end
end

-- Manually trigger the dotfile update process
function obj:manualUpdate()
    self:logInfo("Manual update triggered.")
    self:updateDotfiles()
end

-- Merge default and user-defined configurations, ensuring no duplicates
function obj:mergeConfigs(userConfig, defaultConfig)
    local mergedConfig = {}

    -- Add defaults first
    for _, value in ipairs(defaultConfig) do
        table.insert(mergedConfig, value)
    end

    -- Add user config, skipping duplicates
    for _, value in ipairs(userConfig) do
        if not hs.fnutils.contains(mergedConfig, value) then
            table.insert(mergedConfig, value)
        end
    end

    return mergedConfig
end

return obj
