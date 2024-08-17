local obj = {}
obj.__index = obj

-- Metadata
obj.name = "DotfileManager"
obj.version = "2.5"
obj.author = "Hammerspoon"
obj.homepage = "https://github.com/Hammerspoon/Spoons"
obj.license = "MIT - https://opensource.org/licenses/MIT"

-- Configuration keys for persistent settings storage
obj.settingsKeys = {
    gitRepo = "DotfileManager.gitRepo",
    remoteOrigin = "DotfileManager.remoteOrigin",
    dotfilePaths = "DotfileManager.dotfilePaths",
    dotfiles = "DotfileManager.dotfiles",
    ignorePatterns = "DotfileManager.ignorePatterns",
    rsyncDelete = "DotfileManager.rsyncDelete"
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
    os.getenv("HOME") .. "/.ssh/*",
    os.getenv("HOME") .. "/.gnupg/*",
    os.getenv("HOME") .. "/.config/gcloud/*",
}

obj.defaultInterval = 3600 -- default interval in seconds (1 hour)

obj.logger = hs.logger.new('DotfileManager', 'debug')
obj.timer = nil

-- Initialize persistent storage from hs.settings or use defaults
function obj:init()
    self.gitRepo = hs.settings.get(obj.settingsKeys.gitRepo) or nil
    self.remoteOrigin = hs.settings.get(obj.settingsKeys.remoteOrigin) or nil
    
    -- Merge default and user-defined dotfile paths, dotfiles, and ignore patterns
    self.dotfilePaths = self:mergeConfigs(hs.settings.get(obj.settingsKeys.dotfilePaths) or {}, defaultDotfilePaths)
    self.dotfiles = self:mergeConfigs(hs.settings.get(obj.settingsKeys.dotfiles) or {}, defaultDotfiles)
    self.ignorePatterns = self:mergeConfigs(hs.settings.get(obj.settingsKeys.ignorePatterns) or {}, defaultIgnorePatterns)
    
    self.rsyncDelete = hs.settings.get(obj.settingsKeys.rsyncDelete) or false

    -- Initialize timer
    self.timer = hs.timer.new(self.defaultInterval, function() self:updateDotfiles() end)
end

-- Set the Git repository path and store it in hs.settings
function obj:setGitRepo(repo)
    self.gitRepo = repo
    hs.settings.set(obj.settingsKeys.gitRepo, repo)
    self.logger.i("Git repository set to: " .. repo)
end

-- Set the remote origin URL and store it in hs.settings
function obj:setRemoteOrigin(url)
    self.remoteOrigin = url
    hs.settings.set(obj.settingsKeys.remoteOrigin, url)
    self.logger.i("Remote origin set to: " .. url)
end

-- Add a dotfile path to be tracked and store it in hs.settings
function obj:addDotfilePath(path)
    if not hs.fnutils.contains(self.dotfilePaths, path) then
        table.insert(self.dotfilePaths, path)
        hs.settings.set(obj.settingsKeys.dotfilePaths, self.dotfilePaths)
        self.logger.i("Added dotfile path: " .. path)
    else
        self.logger.i("Dotfile path already tracked: " .. path)
    end
end

-- Add a dotfile to be tracked and store it in hs.settings
function obj:addDotfile(file)
    if not hs.fnutils.contains(self.dotfiles, file) then
        table.insert(self.dotfiles, file)
        hs.settings.set(obj.settingsKeys.dotfiles, self.dotfiles)
        self.logger.i("Added dotfile: " .. file)
    else
        self.logger.i("Dotfile already tracked: " .. file)
    end
end

-- Add an ignore pattern and update .gitignore
function obj:addIgnorePattern(pattern)
    if not hs.fnutils.contains(self.ignorePatterns, pattern) then
        table.insert(self.ignorePatterns, pattern)
        hs.settings.set(obj.settingsKeys.ignorePatterns, self.ignorePatterns)
        self:updateGitignore()
        self.logger.i("Added ignore pattern: " .. pattern)
    else
        self.logger.i("Ignore pattern already exists: " .. pattern)
    end
end

-- Remove an ignore pattern and update .gitignore
function obj:removeIgnorePattern(pattern)
    for i, p in ipairs(self.ignorePatterns) do
        if p == pattern then
            table.remove(self.ignorePatterns, i)
            hs.settings.set(obj.settingsKeys.ignorePatterns, self.ignorePatterns)
            self:updateGitignore()
            self.logger.i("Removed ignore pattern: " .. pattern)
            return
        end
    end
    self.logger.i("Ignore pattern not found: " .. pattern)
end

-- Update the .gitignore file based on ignorePatterns
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
        self.logger.i(".gitignore file does not exist. It will be created.")
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
        self.logger.i(".gitignore updated")
    else
        self.logger.e("Failed to open .gitignore for writing")
    end
end

-- Ensure a directory exists, create it if it doesn't
function obj:ensureDirectoryExists(directory)
    local attr = hs.fs.attributes(directory)
    if not attr then
        local success, msg = hs.fs.mkdir(directory)
        if success then
            self.logger.i("Created directory: " .. directory)
        else
            self.logger.e("Failed to create directory: " .. directory .. ". Error: " .. msg)
            return false
        end
    elseif attr.mode ~= "directory" then
        self.logger.e(directory .. " exists but is not a directory")
        return false
    end
    return true
end

-- Check if the directory is a valid Git repository
function obj:isGitRepo(directory)
    local status, _, rc = self:runCommand("git -C '" .. directory .. "' rev-parse --is-inside-work-tree")
    return status, rc
end

-- Initialize Git repository if it doesn't exist
function obj:initGitRepo()
    if not self:isGitRepo(self.gitRepo) then
        self.logger.i("Initializing Git repository...")
        local success = self:runCommand("git -C '" .. self.gitRepo .. "' init")
        if success then
            self.logger.i("Git repository initialized")
            return true
        else
            self.logger.e("Failed to initialize Git repository")
            return false
        end
    end
    return true
end

-- Check if the remote origin is set up in the Git repository
function obj:hasRemoteOrigin()
    local status, output = self:runCommand("git -C '" .. self.gitRepo .. "' remote get-url origin")
    return status, output
end

-- Set up the remote origin for the Git repository
function obj:setUpRemoteOrigin()
    if not self.remoteOrigin then
        self.logger.e("Remote origin URL not set. Use setRemoteOrigin() to set it.")
        return false
    end

    local status, output = self:hasRemoteOrigin()
    if not status then
        self.logger.i("Setting up remote origin...")
        local cmd = string.format("git -C '%s' remote add origin %s", self.gitRepo, self.remoteOrigin)
        local success = self:runCommand(cmd)
        if success then
            self.logger.i("Remote origin set successfully.")
            return true
        else
            self.logger.e("Failed to set remote origin")
            return false
        end
    end
    self.logger.i("Remote origin already exists.")
    return true
end

-- Set up tracking branch and handle push conflicts
function obj:setUpTrackingBranch()
    -- Check if there are any commits in the repository
    local hasCommits, _ = self:runCommand(string.format("git -C '%s' rev-parse HEAD", self.gitRepo))
    if not hasCommits then
        -- No commits yet, create an initial README.md with the hostname and username
        self.logger.i("No commits found. Creating initial README.md and committing...")
        
        -- Retrieve the hostname and username
        local hostname = hs.host.localizedName()
        local username = os.getenv("USER")
        
        -- Create the README.md content
        local readmeContent = string.format("# %s %s Dotfiles", hostname, username)
        local readmePath = self.gitRepo .. "/README.md"
        
        -- Write the README.md file
        local file = io.open(readmePath, "w")
        if file then
            file:write(readmeContent .. "\n")
            file:close()
            self.logger.i("Created README.md with content: " .. readmeContent)
        else
            self.logger.e("Failed to create README.md file")
            return false
        end
        
        -- Stage and commit the README.md file
        self:runCommand(string.format("git -C '%s' add README.md", self.gitRepo))
        local cmd = string.format("git -C '%s' commit -m 'Initial commit with README.md'", self.gitRepo)
        local success, output = self:runCommand(cmd)
        if not success then
            self.logger.e("Failed to create initial commit: " .. output)
            return false
        end
        self.logger.i("Initial commit with README.md created.")
    end

    -- Check if the remote repository exists
    local remoteExists, output = self:runCommand(string.format("git ls-remote %s", self.remoteOrigin))
    if not remoteExists then
        self.logger.e(string.format("The remote repository '%s' does not exist or is unreachable. Git output: %s", self.remoteOrigin, output or ""))
        return false
    end

    -- Now that we have at least one commit, ensure we're on the correct branch
    local success, output = self:runCommand(string.format("git -C '%s' rev-parse --abbrev-ref HEAD", self.gitRepo))
    if success and output:gsub("%s+", "") ~= "main" then
        success, output = self:runCommand(string.format("git -C '%s' checkout -b main", self.gitRepo))
        if success then
            self.logger.i("Checked out and created 'main' branch.")
        else
            self.logger.e("Failed to checkout and create 'main' branch: " .. (output or "Unknown error"))
            return false
        end
    end

    -- Ensure that the tracking branch is set up
    success, output = self:runCommand(string.format("git -C '%s' push --set-upstream origin main", self.gitRepo))
    if not success then
        if output:find("fetch first") then
            self.logger.e("Push failed because the remote repository contains commits that are not present locally. Run 'git pull --rebase origin main' in your dotfiles repository to synchronize your local repository with the remote, then try pushing again.")
        else
            self.logger.e("Failed to set up tracking branch. Git error: " .. (output or "Unknown error"))
        end
        return false
    end
    self.logger.i("Tracking branch set up successfully.")
    return true
end

-- Run a command and log the output
function obj:runCommand(cmd)
    self.logger.d("Executing command: " .. cmd)
    -- Capture both stdout and stderr by redirecting stderr to stdout
    local output, status = hs.execute(cmd .. " 2>&1")
    if not status then
        self.logger.e("Command failed: " .. cmd .. "\nOutput: " .. (output or ""))
    else
        self.logger.d("Command succeeded: " .. cmd)
    end
    return status, output
end

-- Check if a file or directory should be ignored based on ignorePatterns
function obj:shouldIgnore(path)
    local isDir = hs.fs.attributes(path, "mode") == "directory"

    for _, pattern in ipairs(self.ignorePatterns) do
        -- Adjust the pattern if it includes HOME, replace with a relative version
        local cleanPattern = pattern:gsub(os.getenv("HOME") .. "/", "")
        -- Handle directories
        if isDir then
            local patternForDir = cleanPattern:gsub("/%*$", "") -- Remove trailing /* for directories
            if string.match(path, patternForDir) then
                return true
            end
        else
            -- Handle regular files
            if string.match(path, cleanPattern) then
                return true
            end
        end
    end
    return false
end

-- Rsync logic for syncing files and directories
function obj:rsyncFiles(src, dest)
    local excludeFile = os.tmpname()
    local f = io.open(excludeFile, "w")
    for _, pattern in ipairs(self.ignorePatterns) do
        f:write(pattern .. "\n")
    end
    f:close()

    local deleteOption = self.rsyncDelete and "--delete" or ""
    local isDir = hs.fs.attributes(src, "mode") == "directory"
    
    local cmd
    if isDir then
        cmd = string.format("rsync -av %s '%s/' '%s/' --exclude-from='%s'", deleteOption, src, dest, excludeFile)
    else
        -- Copy as a file
        cmd = string.format("rsync -av %s '%s' '%s/' --exclude-from='%s'", deleteOption, src, dest, excludeFile)
    end
    
    local status, output = self:runCommand(cmd)
    os.remove(excludeFile)
    
    if not status then
        self.logger.e("Rsync failed for " .. src .. ": " .. output)
    end

    return status, output
end

function obj:commitAndPush()
    -- Check git status for changes
    local status, output = self:runCommand(string.format("git -C '%s' status --porcelain", self.gitRepo))
    local filesChanged = {}

    if status then
        -- Log the output of git status for debugging purposes
        self.logger.d("Git status output:\n" .. output)

        -- Populate filesChanged with names of modified or untracked files
        for line in output:gmatch("[^\r\n]+") do
            local changeType, file = line:match("^(..) (.+)$")
            if changeType and file and changeType:match("[MA%?%?]") then  -- Track modified, added, or untracked files
                table.insert(filesChanged, file)
            end
        end

        -- Ensure that filesChanged is not empty or nil before proceeding
        if #filesChanged > 0 then
            local commitMessage = "Update dotfiles:\n\n" .. table.concat(filesChanged, "\n")

            -- Add changes to git (including untracked files)
            self:runCommand(string.format("git -C '%s' add .", self.gitRepo))

            -- Commit changes
            status, output = self:runCommand(string.format("git -C '%s' commit -m \"%s\"", self.gitRepo, commitMessage:gsub('"', '\\"')))
            if not status then
                self.logger.e("Failed to commit changes: " .. output)
                return
            end

            -- Push changes with automatic pull/rebase on failure
            if self:pushChanges() then
                self.logger.i("Dotfiles updated and pushed to repo")
                hs.notify.new({title="Dotfile Manager", informativeText="Dotfiles updated and pushed to repo"}):send()
            else
                hs.notify.new({title="Dotfile Manager", informativeText="Failed to push changes. Check the log for details."}):send()
            end
        else
            self.logger.i("No content changes detected.")
        end
    else
        self.logger.e("Failed to check git status: " .. output)
    end
end

-- Handle git push and rebase if necessary
function obj:pushChanges(commitSHA, filesChanged, skippedDirs)
    local status, output = self:runCommand("git -C '" .. self.gitRepo .. "' push")
    if not status and output:find("fetch first") then
        self.logger.i("Conflicts detected, pulling and rebasing...")
        status = self:runCommand("git -C '" .. self.gitRepo .. "' pull --rebase")
        if status then
            self.logger.i("Rebase successful, pushing again...")
            status = self:runCommand("git -C '" .. self.gitRepo .. "' push")
        end
    end
    
    if status then
        self.logger.i("Changes pushed successfully.")
    else
        self.logger.e("Failed to push changes: " .. output)
    end
end

function obj:updateDotfiles()
    if not self.gitRepo then
        self.logger.e("Git repository not set. Use setGitRepo() to set it.")
        return
    end

    -- Ensure that the repository path exists and is initialized as a Git repository
    if not self:ensureDirectoryExists(self.gitRepo) then
        self.logger.e("Failed to create or verify the repository directory: " .. self.gitRepo)
        return
    end

    -- Initialize Git repository if it's not already initialized
    if not self:isGitRepo(self.gitRepo) then
        self.logger.i("Git repository not found, initializing...")
        if not self:initGitRepo() then
            self.logger.e("Failed to initialize Git repository at: " .. self.gitRepo)
            return
        end
    end

    -- Ensure the remote origin is set up
    if not self:setUpRemoteOrigin() then
        self.logger.e("Failed to set up remote origin.")
        return
    end

    -- Ensure the tracking branch is set up
    if not self:setUpTrackingBranch() then
        self.logger.e("Failed to set up tracking branch.")
        return
    end

    -- Ensure the .gitignore file is updated
    self:updateGitignore()

    -- Check for changes in dotfile paths (directories)
    for _, path in ipairs(self.dotfilePaths) do
        -- Skip the directory if it's a git repository
        if self:isGitRepo(path) then
            self.logger.i("Skipping git repository: " .. path)
        else
            -- Ensure the directory exists in the destination repo
            local repoPath = self.gitRepo .. "/" .. path:match("([^/]+)$")
            if self:ensureDirectoryExists(repoPath) then
                self:rsyncFiles(path, repoPath)
            else
                self.logger.e("Failed to ensure directory exists: " .. repoPath)
            end
        end
    end

    -- Check for changes in individual dotfiles (files)
    for _, file in ipairs(self.dotfiles) do
        local fileName = file:match("([^/]+)$")
        if not self:shouldIgnore(fileName) then
            -- Rsync the file
            self:rsyncFiles(file, self.gitRepo)
        end
    end

    -- Commit and push changes
    self:commitAndPush()
end

-- Start the timer
function obj:start()
    if not self.timer then
        self:init()
    end
    self.timer:start()
    self.logger.i("DotfileManager started")
end

-- Stop the timer
function obj:stop()
    if self.timer then
        self.timer:stop()
        self.logger.i("DotfileManager stopped")
    end
end

-- Manually trigger the dotfile update process
function obj:manualUpdate()
    self.logger.i("Manual update triggered.")
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

-- Return all function names
function obj:listAllFunctions()
    local functionNames = {}
    for key, value in pairs(obj) do
        if type(value) == "function" then
            table.insert(functionNames, key)
        end
    end
    return functionNames
end

return obj
