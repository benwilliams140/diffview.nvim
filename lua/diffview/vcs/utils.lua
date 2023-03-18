local Scanner = require("diffview.scanner")
--[[
Standard change:

diff --git a/lua/diffview/health.lua b/lua/diffview/health.lua
index c05dcda..07bdd33 100644
--- a/lua/diffview/health.lua
+++ b/lua/diffview/health.lua
@@ -48,7 +48,7 @@ function M.check()

Rename with change:

diff --git a/test/index_watcher_spec.lua b/test/gitdir_watcher_spec.lua
similarity index 94%
rename from test/index_watcher_spec.lua
rename to test/gitdir_watcher_spec.lua
index 008beab..66116dc 100644
--- a/test/index_watcher_spec.lua
+++ b/test/gitdir_watcher_spec.lua
@@ -17,7 +17,7 @@ local get_buf_name    = helpers.curbufmeths.get_name
--]]

local DIFF_HEADER = [[^diff %-%-git ]]
local DIFF_SIMILARITY = [[^similarity index (%d+)%%]]
local DIFF_INDEX = { [[^index (%x-)%.%.(%x-) (%d+)]], [[^index (%x-)%.%.(%x-)]] }
local DIFF_PATH_OLD = { [[^%-%-%- a/(.*)]], [[^%-%-%- (/dev/null)]] }
local DIFF_PATH_NEW = { [[^%+%+%+ b/(.*)]], [[^%+%+%+ (/dev/null)]] }
local DIFF_HUNK_HEADER = [[^@@+ %-(%d+),(%d+) %+(%d+),(%d+) @@+]]

---@class diff.Hunk
---@field old_row integer
---@field old_size integer
---@field new_row integer
---@field new_size integer
---@field common_content string[]
---@field old_content { [1]: integer, [2]: string[] }[]
---@field new_content { [1]: integer, [2]: string[] }[]

---@param scanner Scanner
---@param old_row integer
---@param old_size integer
---@param new_row integer
---@param new_size integer
---@return diff.Hunk
local function parse_diff_hunk(scanner, old_row, old_size, new_row, new_size)
  local ret = {
    old_row = old_row,
    old_size = old_size,
    new_row = new_row,
    new_size = new_size,
    common_content = {},
    old_content = {},
    new_content = {},
  }

  local common_idx, old_offset, new_offset = 1, 0, 0
  local line = scanner:peek_line()
  local cur_start = (line or ""):match("^([%+%- ])")

  while cur_start do
    line = scanner:next_line() --[[@as string ]]

    if cur_start == " " then
      ret.common_content[#ret.common_content + 1] = line:sub(2) or ""
      common_idx = common_idx + 1

    elseif cur_start == "-" then
      local content = { line:sub(2) or "" }

      while (scanner:peek_line() or ""):sub(1, 1) == "-" do
        content[#content + 1] = scanner:next_line():sub(2) or ""
      end

      ret.old_content[#ret.old_content + 1] = { common_idx + old_offset, content }
      old_offset = old_offset + #content

    elseif cur_start == "+" then
      local content = { line:sub(2) or "" }

      while (scanner:peek_line() or ""):sub(1, 1) == "+" do
        content[#content + 1] = scanner:next_line():sub(2) or ""
      end

      ret.new_content[#ret.new_content + 1] = { common_idx + new_offset, content }
      new_offset = new_offset + #content
    end

    cur_start = (scanner:peek_line() or ""):match("^([%+%- ])")
  end

  return ret
end

---@class diff.FileEntry
---@field renamed boolean
---@field similarity? integer
---@field dissimilarity? integer
---@field index_old? integer
---@field index_new? integer
---@field mode? integer
---@field old_mode? integer
---@field new_mode? integer
---@field deleted_file_mode? integer
---@field new_file_mode? integer
---@field path_old? string
---@field path_new? string
---@field hunks diff.Hunk[]

---@param scanner Scanner
---@return diff.FileEntry
local function parse_file_diff(scanner)
  ---@type diff.FileEntry
  local ret = { renamed = false, hunks = {} }

  -- The current line will here be the diff header

  -- Extended git diff headers
  while scanner:peek_line() and
    not utils.str_match(scanner:peek_line() or "", { DIFF_HEADER, DIFF_HUNK_HEADER })
  do
    -- Extended header lines:
    -- old mode <mode>
    -- new mode <mode>
    -- deleted file mode <mode>
    -- new file mode <mode>
    -- copy from <path>
    -- copy to <path>
    -- rename from <path>
    -- rename to <path>
    -- similarity index <number>
    -- dissimilarity index <number>
    -- index <hash>..<hash> <mode>
    --
    -- Note: Combined diffs have even more variations

    local last_line_idx = scanner:cur_line_idx()

    -- Similarity
    local similarity = (scanner:peek_line() or ""):match(DIFF_SIMILARITY)
    if similarity then
      ret.similarity = tonumber(similarity) or -1
      scanner:next_line()
    end

    -- Dissimilarity
    local dissimilarity = (scanner:peek_line() or ""):match([[^dissimilarity index (%d+)%%]])
    if dissimilarity then
      ret.dissimilarity = tonumber(dissimilarity) or -1
      scanner:next_line()
    end

    -- Renames
    local rename_from = (scanner:peek_line() or ""):match([[^rename from (.*)]])
    if rename_from then
      ret.renamed = true
      ret.path_old = rename_from
      scanner:skip_line()
      ret.path_new = (scanner:next_line() or ""):match([[^rename to (.*)]])
    end

    -- Copies
    local copy_from = (scanner:peek_line() or ""):match([[^copy from (.*)]])
    if copy_from then
      ret.path_old = copy_from
      scanner:skip_line()
      ret.path_new = (scanner:next_line() or ""):match([[^copy to (.*)]])
    end

    -- Old mode
    local old_mode = (scanner:peek_line() or ""):match([[^old mode (%d+)]])
    if old_mode then
      ret.old_mode = old_mode
      scanner:next_line()
    end

    -- New mode
    local new_mode = (scanner:peek_line() or ""):match([[^new mode (%d+)]])
    if new_mode then
      ret.new_mode = new_mode
      scanner:next_line()
    end

    -- Deleted file
    local deleted_file_mode = (scanner:peek_line() or ""):match([[^deleted file mode (%d+)]])
    if deleted_file_mode then
      ret.old_file_mode = deleted_file_mode
      scanner:next_line()
    end

    -- New file
    local new_file_mode = (scanner:peek_line() or ""):match([[^new file mode (%d+)]])
    if new_file_mode then
      ret.new_file_mode = new_file_mode
      scanner:next_line()
    end

    -- Index
    local index_old, index_new, mode = utils.str_match(scanner:peek_line() or "", DIFF_INDEX)
    if index_old then
      ret.index_old = index_old
      ret.index_new = index_new
      ret.mode = mode
      scanner:next_line()
    end

    -- Paths
    local path_old = utils.str_match(scanner:peek_line() or "", DIFF_PATH_OLD)
    if path_old then
      if not ret.path_old then
        ret.path_old = path_old ~= "/dev/null" and path_old or nil
        scanner:skip_line()
        local path_new = utils.str_match(scanner:next_line() or "", DIFF_PATH_NEW)
        ret.path_new = path_new ~= "/dev/null" and path_new or nil
      else
        scanner:skip_line(2)
      end
    end

    if last_line_idx == scanner:cur_line_idx() then
      -- Non-git patches don't have the extended header lines
      break
    end
  end

  -- Hunks
  local line = scanner:peek_line()
  while line and not line:match(DIFF_HEADER) do
    local old_row, old_size, new_row, new_size = line:match(DIFF_HUNK_HEADER)
    scanner:next_line() -- Current line is now the hunk header

    if old_row then
      table.insert(ret.hunks, parse_diff_hunk(
        scanner,
        tonumber(old_row) or -1,
        tonumber(old_size) or -1,
        tonumber(new_row) or -1,
        tonumber(new_size) or -1
      ))
    end

    line = scanner:peek_line()
  end

  return ret
end

---Parse a diff patch.
---@param lines string[]
---@return diff.FileEntry[]
function M.parse_diff(lines)
  local ret = {}
  local scanner = Scanner(lines)

  while scanner:peek_line() do
    local line = scanner:next_line() --[[@as string ]]
    -- TODO: Diff headers and patch format can take a few different forms. I.e. combined diffs
    if line:match(DIFF_HEADER) then
      table.insert(ret, parse_file_diff(scanner))
    end
  end

  return ret
end

---Build either the old or the new version of a diff hunk.
---@param hunk diff.Hunk
---@param version "old"|"new"
---@return string[]
function M.diff_build_hunk(hunk, version)
  local vcontent = version == "old" and hunk.old_content or hunk.new_content
  local size = version == "old" and hunk.old_size or hunk.new_size
  local common_idx = 1
  local chunk_idx = 1

  local ret = {}
  local i = 1

  while i <= size do
    local chunk = vcontent[chunk_idx]

    if chunk and chunk[1] == i then
      for _, line in ipairs(chunk[2]) do
        ret[#ret + 1] = line
      end

      i = i + (#chunk[2] - 1)
      chunk_idx = chunk_idx + 1
    else
      ret[#ret + 1] = hunk.common_content[common_idx]
      common_idx = common_idx + 1
    end

    i = i + 1
  end

  return ret
end
