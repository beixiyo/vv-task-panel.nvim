-- Public composition facade for vv-task-panel domain services

local Config = require('vv-task-panel.config')
local Discovery = require('vv-task-panel.discovery')
local PackageManager = require('vv-task-panel.package_manager')
local Registry = require('vv-task-panel.registry')
local State = require('vv-task-panel.state')

local M = {}

M.setup = Config.setup
M.get_config = Config.get
M.register_provider = Registry.register
M.discover = Discovery.discover
M.detect_pm = PackageManager.detect
M.groups = State.groups
M.tasks = State.tasks
M.allocate_task_id = State.allocate_task_id
M.add_task = State.add_task
M.remove_task = State.remove_task
---@type fun(group_id: string, task_name: string): VVTaskPanel.TaskRecord?
M.find_recent_task = State.find_recent_task
M.prune_finished = State.finished_before_latest

return M
