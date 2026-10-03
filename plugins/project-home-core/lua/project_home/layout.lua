-- Display-width-aware layout primitives. No terminal colors are hardcoded.
local M = {}
local function width(s) return vim.fn.strdisplaywidth(s or '') end
M.width = width
function M.clip(s, limit)
  s = tostring(s or ''):gsub('[\r\n\t]', ' ')
  if limit <= 0 then return '' end
  if width(s) <= limit then return s end
  local out = ''
  for i = 0, vim.fn.strchars(s) - 1 do
    local c = vim.fn.strcharpart(s, i, 1)
    if width(out .. c) > limit - 1 then break end
    out = out .. c
  end
  return out .. '…'
end
function M.pr_status(pr)
  local checks, failed, pending = pr.statusCheckRollup or {}, false, false
  local unknown, neutral = false, false
  local failures = { FAILURE = true, ERROR = true, TIMED_OUT = true, CANCELLED = true, ACTION_REQUIRED = true, STARTUP_FAILURE = true, STALE = true }
  for _, check in ipairs(checks) do
    local conclusion = check.conclusion or check.state or ''
    if failures[conclusion] then
      failed = true
    elseif conclusion == '' or conclusion == 'PENDING' or check.status == 'IN_PROGRESS' or check.status == 'QUEUED' then
      pending = true
    elseif conclusion == 'NEUTRAL' or conclusion == 'SKIPPED' then
      neutral = true
    elseif conclusion ~= 'SUCCESS' then
      unknown = true
    end
  end
  local checklabel = failed and 'Checks failed'
    or pending and 'Checks pending'
    or (unknown or #checks == 0) and 'Checks unknown'
    or neutral and 'Checks complete'
    or 'Checks passed'
  local review = pr.isDraft and 'Draft'
    or pr.reviewDecision == 'CHANGES_REQUESTED' and 'Changes requested'
    or pr.reviewDecision == 'APPROVED' and 'Approved'
    or 'Review pending'
  local status = pr.status or (checklabel .. ' · ' .. review)
  if type(status) == 'table' then status = status.label or '' end
  return status
end
return M
