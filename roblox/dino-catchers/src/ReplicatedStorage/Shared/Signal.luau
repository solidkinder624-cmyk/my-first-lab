--!strict
-- 小さなシグナル（サーバー内・クライアント内のスクリプト同士の通知用）。
-- BindableEvent と違い、渡したテーブルがコピーされず、そのまま届く。
-- ※サーバー⇔クライアント間の通信には使えない（それは ReplicatedStorage.Remotes の役目）。
--
--   local changed = Signal.new()
--   local conn = changed:Connect(function(a, b) ... end)
--   changed:Fire(1, 2)
--   conn:Disconnect()

local Signal = {}
Signal.__index = Signal

export type Connection = {
	Connected: boolean,
	Disconnect: (self: Connection) -> (),
}

function Signal.new()
	return setmetatable({ _handlers = {} :: { any } }, Signal)
end

function Signal:Connect(handler: (...any) -> ()): Connection
	local connection
	connection = {
		Connected = true,
		_handler = handler,
		Disconnect = function(conn)
			if not conn.Connected then
				return
			end
			conn.Connected = false
			local index = table.find(self._handlers, conn)
			if index then
				table.remove(self._handlers, index)
			end
		end,
	}
	table.insert(self._handlers, connection)
	return connection
end

function Signal:Once(handler: (...any) -> ()): Connection
	local connection
	connection = self:Connect(function(...)
		connection:Disconnect()
		handler(...)
	end)
	return connection
end

-- 各ハンドラを別スレッドで呼ぶ（1つがエラーや待ちで止まっても他に影響しない）。
function Signal:Fire(...: any)
	-- 呼び出し中の Disconnect で配列が崩れないよう、複製してから回す
	for _, connection in table.clone(self._handlers) do
		if connection.Connected then
			task.spawn(connection._handler, ...)
		end
	end
end

-- 次に Fire されるまで待ち、その引数を返す。
function Signal:Wait(): ...any
	local thread = coroutine.running()
	self:Once(function(...)
		task.spawn(thread, ...)
	end)
	return coroutine.yield()
end

function Signal:DisconnectAll()
	for _, connection in table.clone(self._handlers) do
		connection:Disconnect()
	end
end

return Signal
