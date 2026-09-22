-- Contract fixture only. Do not treat this as runtime proof.
-- Assumes the host explicitly allow-lists host.log and task values.
local task = task or { id = 1, label = "example" }
host.log(task.id, task.label)
return task.id
