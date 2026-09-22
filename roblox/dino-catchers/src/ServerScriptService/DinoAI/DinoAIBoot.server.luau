-- 恐竜AIの起動役（Script）。
-- 本体は同じフォルダの DinoService（ModuleScript）。他のスクリプトは DinoService を require して使う。

local DinoService = require(script.Parent:WaitForChild("DinoService"))

DinoService.start()
