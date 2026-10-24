local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local player = Players.LocalPlayer

local Services = RS.Packages._Index["sleitnick_knit@1.7.0"].knit.Services
local Roll = Services.StyleService.RF.Roll
local RequestJerseyUpdate = Services.JerseyService.RF.RequestJerseyUpdate
local Redeem = Services.CodeService.RF.Redeem
local ClaimLevelRewards = Services.LevelService.RF.ClaimLevelRewards

-- ===== Config (ถ้าไม่ได้ตั้ง ใช้ค่าเริ่มต้น) =====
local DEFAULT = {
	AUTO_ROLL = false,
	LUCKY_SPIN = true,
	WANTED = { "Sanju", "Kisuki", "Mamori" },
	MAX_ROLLS = 500,
	WAIT_AFTER_ROLL = 1,
	CALL_JERSEY_UPDATE = false,
	AUTO_REDEEM = true,
	REDEEM_LEVEL = 15,
	CODES = {},
	REDEEM_DELAY = 2,
	WAIT_REDEEM_BEFORE_DONE = false,
	LOG_INTERVAL = 60,
}

-- เตรียม _G.RollConfig ให้ UI แก้ค่าได้ (ค่าที่ไม่ได้ตั้งจะเติมจาก DEFAULT)
if type(_G.RollConfig) ~= "table" then
	_G.RollConfig = {}
end
for k, v in pairs(DEFAULT) do
	if _G.RollConfig[k] == nil then
		if type(v) == "table" then
			local copy = {}
			for i, x in ipairs(v) do copy[i] = x end
			_G.RollConfig[k] = copy
		else
			_G.RollConfig[k] = v
		end
	end
end

local function getCfg(key)
	local user = type(_G.RollConfig) == "table" and _G.RollConfig or {}
	if user[key] ~= nil then
		return user[key]
	end
	return DEFAULT[key]
end

local function isAutoRoll() return getCfg("AUTO_ROLL") == true end
local function isAutoRedeem() return getCfg("AUTO_REDEEM") == true end
local function isLuckySpin() return getCfg("LUCKY_SPIN") == true end

-- ===== ฟังก์ชันร่วม =====
local function clean(text)
	text = tostring(text):gsub("<[^>]+>", ""):gsub("[|;]", "")
	return text:match("^%s*(.-)%s*$")
end

local function getStyle()
	local char = workspace:FindFirstChild(player.Name)
	local jersey = char and char:FindFirstChild("JerseyBack")
	local label = jersey and jersey:FindFirstChild("StyleName", true)
	if label and label:IsA("TextLabel") then
		local text = clean(label.Text)
		return text:sub(1, 1):upper() .. text:sub(2):lower()
	end
	return ""
end

local function getLevel()
	local char = workspace:FindFirstChild(player.Name)
	local label = char
		and char:FindFirstChild("Nametag")
		and char.Nametag:FindFirstChild("Container")
		and char.Nametag.Container:FindFirstChild("PlayerLvl")
	if label and label:IsA("TextLabel") then
		return tonumber(label.Text:match("%d+")) or 0
	end
	return 0
end

local function getLuckySpins()
	local char = workspace:FindFirstChild(player.Name)
	for _, src in ipairs({ char, player }) do
		if src then
			for name, value in pairs(src:GetAttributes()) do
				local n = name:lower()
				if n:find("luckyspin") or n:find("lucky_spin") then
					local num = tonumber(value)
					if num then return num end
				end
			end
		end
	end

	for _, child in ipairs(player:GetChildren()) do
		if child:IsA("Folder") or child:IsA("Configuration") or child.Name:lower():find("data") or child.Name == "leaderstats" then
			for _, val in ipairs(child:GetChildren()) do
				if val:IsA("ValueBase") and val.Name:lower():find("lucky") then
					local num = tonumber(val.Value)
					if num then return num end
				end
			end
		end
	end

	local playerGui = player:FindFirstChild("PlayerGui")
	if playerGui then
		local luckyList = playerGui:FindFirstChild("Interface", true)
			and playerGui.Interface:FindFirstChild("Lobby", true)
			and playerGui.Interface.Lobby:FindFirstChild("Styles", true)
			and playerGui.Interface.Lobby.Styles:FindFirstChild("BottomPanel", true)
			and playerGui.Interface.Lobby.Styles.BottomPanel:FindFirstChild("LuckyList", true)

		if luckyList then
			for _, gui in ipairs(luckyList:GetDescendants()) do
				if (gui:IsA("TextLabel") or gui:IsA("TextBox")) and gui.Text ~= "" then
					local num = tonumber(gui.Text:match("%d+"))
					if num and not gui.Name:lower():find("price") then
						return num
					end
				end
			end
		end
	end

	return nil -- อ่านไม่เจอ (ไม่ใช่ 0)
end

-- ===== สถานะกลาง =====
local state = {
	status = "เริ่มทำงาน",
	rolls = 0,
	lastLevel = 0,
	lastStyle = "",
	lastLuckySpins = nil,
}
local redeemState = { finished = false, success = 0, failed = 0, ran = false }
local claimState = { success = 0, failed = 0 }

local function redeemSummary()
	if not redeemState.ran then
		return "ไม่ได้ใส่โค้ด"
	end
	return ("โค้ด %d/%d"):format(redeemState.success, redeemState.success + redeemState.failed)
end

local function sendLog(status, rolls)
	if not _G.Horst_SetDescription then
		warn("ไม่พบ _G.Horst_SetDescription")
		return
	end

	local level = getLevel()
	if level > 0 then state.lastLevel = level else level = state.lastLevel end

	local style = getStyle()
	if style ~= "" then state.lastStyle = style else style = state.lastStyle end

	local luckySpins = getLuckySpins()
	if luckySpins ~= nil then
		state.lastLuckySpins = luckySpins
	else
		luckySpins = state.lastLuckySpins
	end

	local luckyText = luckySpins ~= nil and tostring(luckySpins) or "N/A"
	local msg = clean("🌲Level : " .. level .. " , ⚔️Style : " .. style .. " , 🍀Lucky Spins : " .. luckyText .. ", " .. status)

	local json = HttpService:JSONEncode({
		Level = level,
		Style = style,
		LuckySpins = luckySpins,
		Rolls = rolls,
		Status = status,
		RedeemSuccess = redeemState.success,
		RedeemFailed = redeemState.failed,
		ClaimSuccess = claimState.success,
		ClaimFailed = claimState.failed,
	})

	local ok, err = pcall(_G.Horst_SetDescription, msg, json)
	if not ok then
		warn("ส่ง log ไม่สำเร็จ:", err)
	end
end

local function report()
	sendLog(state.status .. " , " .. redeemSummary(), state.rolls)
end

local function finish(status, rolls, markDone)
	state.status = status
	state.rolls = rolls

	if markDone and getCfg("WAIT_REDEEM_BEFORE_DONE") == true then
		while isAutoRedeem() and not redeemState.finished do
			task.wait(1)
		end
	end

	report()

	if markDone and _G.Horst_AccountChangeDone then
		local ok, err = _G.Horst_AccountChangeDone()
		if not ok then
			warn("ส่ง Done ไม่สำเร็จ:", err)
		end
	end
end

-- ==================== ลูปส่ง log ====================
local function runStatusLoop()
	local interval = tonumber(getCfg("LOG_INTERVAL")) or DEFAULT.LOG_INTERVAL
	if interval < 10 then interval = 10 end

	print("[Log] ส่ง log ทุก", interval, "วินาที")

	while true do
		task.wait(interval)
		report()
	end
end

-- ==================== รับของเลเวล ====================
local function claimOnce(level)
	local ok, result = pcall(function()
		return ClaimLevelRewards:InvokeServer()
	end)

	if ok and result ~= false then
		claimState.success += 1
		print("[Claim] ✅ เลเวล", level, "->", tostring(result))
	else
		claimState.failed += 1
		warn("[Claim] ❌ เลเวล", level, "->", tostring(result))
	end
end

local function runClaim()
	local lastLevel = 0
	while lastLevel == 0 do
		lastLevel = getLevel()
		if lastLevel == 0 then task.wait(2) end
	end

	print("[Claim] เริ่มทำงาน | เลเวลปัจจุบัน:", lastLevel)
	claimOnce(lastLevel)

	while true do
		task.wait(3)
		local level = getLevel()

		if level > lastLevel then
			print(("[Claim] เลเวลเพิ่ม %d -> %d"):format(lastLevel, level))
			claimOnce(level)
			lastLevel = level
		end
	end
end

-- ==================== ใส่โค้ด ====================
local function runRedeem()
	local CODES = getCfg("CODES")
	if type(CODES) == "string" then
		CODES = { CODES }
	end
	if type(CODES) ~= "table" or #CODES == 0 then
		warn("[Redeem] CODES ว่าง ข้ามระบบใส่โค้ด")
		return
	end

	local REDEEM_LEVEL = tonumber(getCfg("REDEEM_LEVEL")) or DEFAULT.REDEEM_LEVEL
	local REDEEM_DELAY = tonumber(getCfg("REDEEM_DELAY")) or DEFAULT.REDEEM_DELAY

	print("[Redeem] เปิด | รอเลเวล:", REDEEM_LEVEL, "| จำนวนโค้ด:", #CODES)

	while true do
		if not isAutoRedeem() then
			print("[Redeem] ปิดอยู่ หยุดทำงาน")
			return
		end
		local level = getLevel()
		if level >= REDEEM_LEVEL then
			print("[Redeem] เลเวล", level, "ถึงเกณฑ์แล้ว เริ่มใส่โค้ด")
			break
		end
		task.wait(5)
	end

	redeemState.ran = true

	for _, code in ipairs(CODES) do
		if not isAutoRedeem() then
			print("[Redeem] ถูกปิดระหว่างทำงาน หยุด")
			break
		end

		local ok, result = pcall(function()
			return Redeem:InvokeServer(code)
		end)

		if ok and result ~= false then
			redeemState.success += 1
			print("[Redeem] ✅", code, "->", tostring(result))
		else
			redeemState.failed += 1
			warn("[Redeem] ❌", code, "->", tostring(result))
		end

		task.wait(REDEEM_DELAY)
	end

	print(("[Redeem] เสร็จแล้ว สำเร็จ %d / ไม่สำเร็จ %d"):format(redeemState.success, redeemState.failed))
end

-- ==================== สุ่ม ====================
local function runRoll()
	local WANTED = getCfg("WANTED")
	if type(WANTED) == "string" then
		WANTED = { WANTED }
	end
	if type(WANTED) ~= "table" or #WANTED == 0 then
		warn("[Roll] WANTED ว่างหรือผิดรูปแบบ ข้ามระบบสุ่ม")
		return
	end

	local MAX_ROLLS = tonumber(getCfg("MAX_ROLLS")) or DEFAULT.MAX_ROLLS
	local WAIT_AFTER_ROLL = tonumber(getCfg("WAIT_AFTER_ROLL")) or DEFAULT.WAIT_AFTER_ROLL
	local CALL_JERSEY_UPDATE = getCfg("CALL_JERSEY_UPDATE") == true

	local function isWanted(style)
		for _, name in ipairs(WANTED) do
			if style:lower() == tostring(name):lower() then
				return true
			end
		end
		return false
	end

	print("[Roll] Auto Roll:", isAutoRoll() and "เปิด" or "ปิด",
		"| โหมด:", isLuckySpin() and "Lucky Spin" or "Normal Spin",
		"| เป้าหมาย:", table.concat(WANTED, ", "), "| สูงสุด:", MAX_ROLLS)

	local startStyle = getStyle()
	if startStyle ~= "" and isWanted(startStyle) then
		finish("ได้ตัวที่ต้องการแล้ว", 0, true)
		return
	end

	if not isAutoRoll() then
		finish("ปิด Auto Roll (ไม่สุ่ม)", 0, false)
		return
	end

	state.status = "เริ่มสุ่ม"
	state.rolls = 0
	report()

	local rolls = 0

	for i = 1, MAX_ROLLS do
		if not isAutoRoll() then
			finish("หยุดสุ่ม (ปิด Auto Roll) สุ่มไป " .. rolls .. " ครั้ง", rolls, false)
			return
		end

		local ok, result = pcall(function()
			if isLuckySpin() then
				return Roll:InvokeServer(true)
			end
			return Roll:InvokeServer()
		end)

		if not ok then
			warn("[Roll] สุ่มไม่สำเร็จ:", result)
			finish("สุ่มไม่สำเร็จ หยุดที่ครั้งที่ " .. rolls, rolls, false)
			return
		end
		if result == false then
			finish("สุ่มไม่ได้ (ของหมด/คูลดาวน์) หยุดที่ครั้งที่ " .. rolls, rolls, false)
			return
		end

		rolls = i
		task.wait(WAIT_AFTER_ROLL)

		if CALL_JERSEY_UPDATE then
			pcall(function()
				RequestJerseyUpdate:InvokeServer()
			end)
			task.wait(1)
		end

		local style = getStyle()
		print(("[Roll] สุ่มครั้งที่ %d -> %s"):format(i, style))

		state.status = ("กำลังสุ่ม สุ่มไปแล้ว %d ครั้ง"):format(i)
		state.rolls = i

		if style ~= "" and isWanted(style) then
			finish("ได้ตัวที่ต้องการ สุ่มไป " .. i .. " ครั้ง", i, true)
			return
		end
	end

	finish("สุ่มครบ " .. MAX_ROLLS .. " ครั้ง ยังไม่ได้ตัวที่ต้องการ", rolls, false)
end

-- ==================== ตัวช่วยสำหรับ UI ====================
local cfg = _G.RollConfig

-- รายการ Style ที่ให้เลือกในเมนู (เพิ่ม/ลบตามที่มีในเกม)
local STYLE_OPTIONS = { "Kisuki", "Sanju", "Mamori" }

-- รวมตัวเลือกกับค่าที่ตั้งไว้ใน config กันค่าที่เลือกไว้ไม่อยู่ในลิสต์
local function mergeOptions(options, selected)
	local out, seen = {}, {}
	for _, v in ipairs(options) do
		local key = tostring(v):lower()
		if not seen[key] then
			seen[key] = true
			table.insert(out, tostring(v))
		end
	end
	for _, v in ipairs(selected or {}) do
		local key = tostring(v):lower()
		if not seen[key] then
			seen[key] = true
			table.insert(out, tostring(v))
		end
	end
	return out
end

local function toList(v)
	if type(v) == "table" then return v end
	if v == nil or v == "" then return {} end
	return { v }
end

-- แปลง "a, b, c" เป็น table
local function splitList(text)
	local t = {}
	for item in tostring(text):gmatch("[^,]+") do
		item = item:match("^%s*(.-)%s*$")
		if item ~= "" then
			table.insert(t, item)
		end
	end
	return t
end

-- กันรันซ้อน
local rollRunning = false
local redeemRunning = false

local function startRoll()
	if rollRunning then return end
	rollRunning = true
	task.spawn(function()
		pcall(runRoll)
		rollRunning = false
	end)
end

local function startRedeem()
	if redeemRunning then return end
	redeemRunning = true
	redeemState.finished = false
	task.spawn(function()
		pcall(runRedeem)
		redeemState.finished = true
		redeemRunning = false
	end)
end

-- ==================== เริ่มทำงาน (ใช้ WindUI) ====================
task.spawn(function() pcall(runStatusLoop) end)
task.spawn(function() pcall(runClaim) end)

local WindUI = loadstring(game:HttpGet("https://github.com/Footagesus/WindUI/releases/latest/download/main.lua"))()

local Window = WindUI:CreateWindow({
	Title = "Style Roller",
	Icon = "dices",
	Author = "Auto Roll & Redeem",
	Folder = "StyleRoller",
	Size = UDim2.fromOffset(580, 460),
	Theme = "Dark",
	ToggleKey = Enum.KeyCode.RightShift, -- กดซ่อน/แสดงหน้าต่าง
})

-- ================= แท็บสุ่ม =================
local RollTab = Window:Tab({ Title = "สุ่ม", Icon = "dices" })
local RollSection = RollTab:Section({ Title = "ตั้งค่าการสุ่ม", Opened = true })

RollSection:Toggle({
	Title = "Auto Roll",
	Desc = "เปิดเพื่อเริ่มสุ่ม ปิดเพื่อหยุด",
	Value = cfg.AUTO_ROLL == true,
	Callback = function(v)
		cfg.AUTO_ROLL = v
		if v then startRoll() end
	end,
})

RollSection:Toggle({
	Title = "Lucky Spin",
	Desc = "เปิด = Lucky Spin / ปิด = Normal Spin",
	Value = cfg.LUCKY_SPIN == true,
	Callback = function(v)
		cfg.LUCKY_SPIN = v
	end,
})

RollSection:Dropdown({
	Title = "Style ที่ต้องการ",
	Desc = "เลือกได้หลายตัว สุ่มเจอตัวไหนก็หยุด",
	Values = mergeOptions(STYLE_OPTIONS, cfg.WANTED),
	Value = cfg.WANTED or {},
	Multi = true,
	AllowNone = false,
	Callback = function(selected)
		local list = toList(selected)
		if #list > 0 then
			cfg.WANTED = list
		end
	end,
})

RollSection:Slider({
	Title = "สุ่มสูงสุด (ครั้ง)",
	Step = 10,
	Value = { Min = 10, Max = 2000, Default = cfg.MAX_ROLLS or 500 },
	Callback = function(v)
		cfg.MAX_ROLLS = math.floor(v)
	end,
})

RollSection:Slider({
	Title = "รอหลังสุ่ม (วินาที)",
	Step = 1,
	Value = { Min = 1, Max = 10, Default = cfg.WAIT_AFTER_ROLL or 3 },
	Callback = function(v)
		cfg.WAIT_AFTER_ROLL = v
	end,
})

RollSection:Toggle({
	Title = "เรียก Jersey Update",
	Desc = "เรียกอัปเดตเสื้อหลังสุ่มทุกครั้ง",
	Value = cfg.CALL_JERSEY_UPDATE == true,
	Callback = function(v)
		cfg.CALL_JERSEY_UPDATE = v
	end,
})

-- ================= แท็บใส่โค้ด =================
local RedeemTab = Window:Tab({ Title = "ใส่โค้ด", Icon = "gift" })
local RedeemSection = RedeemTab:Section({ Title = "ตั้งค่าใส่โค้ด", Opened = true })

RedeemSection:Toggle({
	Title = "Auto Redeem",
	Desc = "รอเลเวลถึงเกณฑ์แล้วใส่โค้ดอัตโนมัติ",
	Value = cfg.AUTO_REDEEM == true,
	Callback = function(v)
		cfg.AUTO_REDEEM = v
		if v then startRedeem() end
	end,
})

RedeemSection:Input({
	Title = "โค้ด",
	Desc = "คั่นด้วยจุลภาค เช่น UPDATE_92, PARRY, MAMORI",
	Value = table.concat(cfg.CODES or {}, ", "),
	Placeholder = "CODE1, CODE2",
	Callback = function(text)
		cfg.CODES = splitList(text)
	end,
})

RedeemSection:Slider({
	Title = "เลเวลที่เริ่มใส่โค้ด",
	Step = 1,
	Value = { Min = 1, Max = 100, Default = cfg.REDEEM_LEVEL or 15 },
	Callback = function(v)
		cfg.REDEEM_LEVEL = math.floor(v)
	end,
})

RedeemSection:Slider({
	Title = "หน่วงระหว่างโค้ด (วินาที)",
	Step = 1,
	Value = { Min = 1, Max = 10, Default = cfg.REDEEM_DELAY or 2 },
	Callback = function(v)
		cfg.REDEEM_DELAY = v
	end,
})

RedeemSection:Button({
	Title = "ใส่โค้ดเดี๋ยวนี้",
	Desc = "เริ่มใส่โค้ดทันที (ถ้าเลเวลถึงเกณฑ์)",
	Callback = function()
		cfg.AUTO_REDEEM = true
		startRedeem()
	end,
})

-- ================= แท็บทั่วไป =================
local MiscTab = Window:Tab({ Title = "ทั่วไป", Icon = "settings" })
local MiscSection = MiscTab:Section({ Title = "ทั่วไป", Opened = true })

MiscSection:Toggle({
	Title = "รอใส่โค้ดเสร็จก่อนส่ง Done",
	Value = cfg.WAIT_REDEEM_BEFORE_DONE == true,
	Callback = function(v)
		cfg.WAIT_REDEEM_BEFORE_DONE = v
	end,
})

MiscSection:Slider({
	Title = "ส่ง Log ทุก (วินาที)",
	Desc = "มีผลเมื่อรันสคริปต์ใหม่",
	Step = 5,
	Value = { Min = 10, Max = 300, Default = cfg.LOG_INTERVAL or 60 },
	Callback = function(v)
		cfg.LOG_INTERVAL = math.floor(v)
	end,
})

MiscSection:Button({
	Title = "ส่ง Log ตอนนี้",
	Callback = function()
		report()
	end,
})

RollTab:Select() -- เปิดแท็บสุ่มเป็นแท็บแรก

-- เริ่มตามค่าที่ตั้งไว้ตอนต้น
if isAutoRedeem() then
	startRedeem()
else
	redeemState.finished = true
end

startRoll() -- เช็ก Style ปัจจุบันก่อน ถ้า Auto Roll ปิดจะแค่ส่งสถานะแล้วจบ
