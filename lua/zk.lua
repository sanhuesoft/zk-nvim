local lsp = require("zk.lsp")
local config = require("zk.config")
local ui = require("zk.ui")
local api = require("zk.api")
local util = require("zk.util")

local M = {}

local function setup_lsp_auto_attach()
  --- NOTE: modified version of code in nvim-lspconfig
  local trigger
  local filetypes = config.options.lsp.config.filetypes
  if filetypes then
    trigger = "FileType " .. table.concat(filetypes, ",")
  else
    trigger = "BufReadPost *"
  end
  M._lsp_buf_auto_add(0)
  vim.api.nvim_command(string.format("autocmd %s lua require'zk'._lsp_buf_auto_add(0)", trigger))
end

---Automatically called via an |autocmd| if lsp.auto_attach is enabled.
--
---@param bufnr number
function M._lsp_buf_auto_add(bufnr)
  if vim.api.nvim_buf_get_option(bufnr, "buftype") == "nofile" then
    return
  end

  if not util.notebook_root(vim.api.nvim_buf_get_name(bufnr)) then
    return
  end

  lsp.buf_add(bufnr)
end

---The entry point of the plugin
--
---@param options? table user configuration options
function M.setup(options)
  config.options = vim.tbl_deep_extend("force", config.defaults, options or {})

  if config.options.lsp.auto_attach.enabled then
    setup_lsp_auto_attach()
  end

  require("zk.commands.builtin")
end

---Cd into the notebook root
--
---@param options? table
function M.cd(options)
  options = options or {}
  local notebook_path = options.notebook_path or util.resolve_notebook_path(0)
  local root = util.notebook_root(notebook_path)
  if root then
    vim.cmd("cd " .. root)
  end
end

---Creates and edits a new note
--
---@param options? table additional options
---@see https://github.com/zk-org/zk/blob/main/docs/tips/editors-integration.md#zknew
function M.new(options)
  options = options or {}
  api.new(options.notebook_path, options, function(err, res)
    assert(not err, tostring(err))
    if options and options.dryRun ~= true and options.edit ~= false then
      -- neovim does not yet support window/showDocument, therefore we handle options.edit locally
      vim.cmd("edit " .. res.path)
    end
  end)
end

---Indexes the notebook
--
---@param options? table additional options
---@param cb? function for processing stats
---@see https://github.com/zk-org/zk/blob/main/docs/tips/editors-integration.md#zkindex
function M.index(options, cb)
  options = options or {}
  cb = cb or function(stats)
    vim.notify(vim.inspect(stats))
  end
  api.index(options.notebook_path, options, function(err, stats)
    assert(not err, tostring(err))
    cb(stats)
  end)
end

---Opens a notes picker, and calls the callback with the selection
--
---@param options? table additional options
---@param picker_options? table options for the picker
---@param cb function
---@see https://github.com/zk-org/zk/blob/main/docs/tips/editors-integration.md#zklist
---@see zk.ui.pick_notes
function M.pick_notes(options, picker_options, cb)
  options =
    vim.tbl_extend("force", { select = ui.get_pick_notes_list_api_selection(picker_options) }, options or {})
  if options["notebook_path"] then
    picker_options["notebook_path"] = options["notebook_path"]
  end
  api.list(options.notebook_path, options, function(err, notes)
    assert(not err, tostring(err))
    ui.pick_notes(notes, picker_options, cb)
  end)
end

---Opens a tags picker, and calls the callback with the selection
--
---@param options? table additional options
---@param picker_options? table options for the picker
---@param cb function
---@see https://github.com/zk-org/zk/blob/main/docs/tips/editors-integration.md#zktaglist
---@see zk.ui.pick_tags
function M.pick_tags(options, picker_options, cb)
  options = options or {}
  api.tag.list(options.notebook_path, options, function(err, tags)
    assert(not err, tostring(err))
    ui.pick_tags(tags, picker_options, cb)
  end)
end

---Opens a notes picker, and edits the selected notes
--
---@param options? table additional options
---@param picker_options? table options for the picker
---@see https://github.com/zk-org/zk/blob/main/docs/tips/editors-integration.md#zklist
---@see zk.ui.pick_notes
function M.edit(options, picker_options)
  M.pick_notes(options, picker_options, function(notes)
    if picker_options and picker_options.multi_select == false then
      notes = { notes }
    end
    for _, note in ipairs(notes) do
      vim.cmd("e " .. note.absPath)
    end
  end)
end

---Opens a random note, skipping notes inside the given directories.
--
---@param options? table additional options accepted by zk list (e.g. `excludeDirs`, `notebook_path`).
---                       Pass `excludeDirs = { "templates", "daily" }` to ignore those folders.
function M.random(options)
  options = options or {}

  -- Build the list options: request only the path field to keep the payload small.
  local list_options = vim.tbl_extend("force", { select = { "path", "absPath" } }, options)
  -- Remove the custom key so it is not forwarded to the LSP server.
  local exclude_dirs = list_options.excludeDirs
  list_options.excludeDirs = nil

  api.list(list_options.notebook_path, list_options, function(err, notes)
    assert(not err, tostring(err))
    assert(notes and #notes > 0, "ZkRandom: no notes found in this notebook")

    -- Filter out notes whose absPath starts with any of the excluded directories.
    if exclude_dirs and #exclude_dirs > 0 then
      local notebook_path = list_options.notebook_path or util.resolve_notebook_path(0)
      local root = util.notebook_root(notebook_path) or notebook_path

      notes = vim.tbl_filter(function(note)
        local abs = note.absPath or note.path or ""
        for _, dir in ipairs(exclude_dirs) do
          -- Build the absolute prefix, handling both absolute and relative dirs.
          local prefix = vim.fn.fnamemodify(dir, ":p") == dir and dir
            or (root .. "/" .. dir)
          -- Normalise trailing slash.
          if not vim.endswith(prefix, "/") then
            prefix = prefix .. "/"
          end
          if vim.startswith(abs, prefix) then
            return false
          end
        end
        return true
      end, notes)
    end

    assert(#notes > 0, "ZkRandom: all notes were filtered out by excludeDirs")

    math.randomseed(os.time())
    local pick = notes[math.random(#notes)]
    vim.cmd("edit " .. vim.fn.fnameescape(pick.absPath or pick.path))
  end)
end

return M
