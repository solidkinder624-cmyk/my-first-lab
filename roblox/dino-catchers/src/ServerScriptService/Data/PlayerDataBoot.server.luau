-- プレイヤーデータサービスの起動役（Script）。
-- 本体は同じフォルダの PlayerData（ModuleScript）。他のスクリプトは PlayerData を require して使う。

local PlayerData = require(script.Parent:WaitForChild("PlayerData"))

PlayerData.start()
