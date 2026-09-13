script_name("Private Assistant - Cloud Core")
script_author("Diagnostic")
script_version("3000.0.CLOUD_ONLY_UPDATE")

local sampev = require 'samp.events'
local inicfg = require 'inicfg'
local http = require 'socket.http'
local ltn12 = require 'ltn12'

local iniFile = "AutoElectrician.ini"
local defaultConfig = {
    wires = { RED_ID = -1, RED_IS_PLAYER = false, GREEN_ID = -1, GREEN_IS_PLAYER = false, BLUE_ID = -1, BLUE_IS_PLAYER = false, YELLOW_ID = -1, YELLOW_IS_PLAYER = false },
    settings = { autoClick = true, jobMode = "repair", clickDelay = 180 },
    stats = { savedPoles = 0, savedMoney = 0 },
    daily = { date = os.date("%Y-%m-%d"), poles = 0, money = 0 }
}
local config = nil
local status, res = pcall(inicfg.load, defaultConfig, iniFile)
if not status or not res then
    iniFile = "PrivateSettings.ini"
    status, res = pcall(inicfg.load, defaultConfig, iniFile)
end
if status and res then config = res else config = defaultConfig end

if not config.daily then
    config.daily = { date = os.date("%Y-%m-%d"), poles = 0, money = 0 }
end

local autoPilot = false
local currentPoleCoords = nil
local completedJobs = 0
local sessionMoney = config.stats.savedMoney or 0
local totalPoles = config.stats.savedPoles or 0
local hasTeleported = false

local currentColor = nil
local isAutoClicking = false
local isInMinigame = false
local lastWireTime = 0

-- اطلاعات ربات بله
local BALE_BOT_TOKEN = "1192198839:fHVEOH081y3QF1ppDcurfNwC1Fxs3TGztss"
local BALE_CHAT_ID   = "1804721465"
local MY_OWN_NAME    = "Amir"

-- بررسی و ریست خودکار آمار روزانه
local function checkDailyReset()
    local today = os.date("%Y-%m-%d")
    if config.daily.date ~= today then
        config.daily.date = today
        config.daily.poles = 0
        config.daily.money = 0
        pcall(inicfg.save, config, iniFile)
    end
end

-- =================================================================
-- شنود مستقیم رندر آرت از داخل core.lua (توقف فقط با تگ [A])
-- =================================================================
local lastAdminAlert = 0
if renderFontDrawText then
    local orig_render = renderFontDrawText
    renderFontDrawText = function(font, text, x, y, color)
        local str = tostring(text or "")
        -- اگر متن در سمت چپ صفحه باشد (محل اسپکتورهای آرت) و تگ [A] داشته باشد:
        if x and x < 350 and str:find("%[A%]") then
            if autoPilot and (os.clock() - lastAdminAlert > 5.0) then
                lastAdminAlert = os.clock()
                autoPilot = false
                if isCharInAnyCar(PLAYER_PED) then
                    freezeCarPosition(storeCarCharIsInNoSave(PLAYER_PED), false)
                end
                sampAddChatMessage("{FF0000}🚨 [HOSHDAR] Admin [A] dar hale tamashaye shomast! Bot foran khamosh shod.", -1)
                sendStatsToBale(config.settings.jobMode:upper())
            end
        end
        return orig_render(font, text, x, y, color)
    end
end

-- =================================================================
-- تابع اصلی (Main)
-- =================================================================
function main()
    while not isSampAvailable() do wait(100) end
    while not sampIsLocalPlayerSpawned() do wait(200) end

    -- فعال‌سازی خودکار تمام تیک‌های ادمین، هلپر، هاستر و VIP آرت
    pcall(function()
        rawset(_G, "SpecNotification", true)
        rawset(_G, "OnlineNotification", true)
        rawset(_G, "AntiPublic", false)
        if rawget(_G, "tagA") then rawget(_G, "tagA")[0] = true end
        if rawget(_G, "tagH") then rawget(_G, "tagH")[0] = true end
        if rawget(_G, "tagV") then rawget(_G, "tagV")[0] = true end
        if rawget(_G, "tagNormal") then rawget(_G, "tagNormal")[0] = true end
    end)

    -- ثبت دستورات
    sampRegisterChatCommand("bot", function()
        autoPilot = not autoPilot
        sampAddChatMessage(autoPilot and "{00FF00}[Bot] ROSHAN" or "{FF0000}[Bot] KHAMOSH", -1)
        if autoPilot then
            startJobCycle()
        else
            if isCharInAnyCar(PLAYER_PED) then
                freezeCarPosition(storeCarCharIsInNoSave(PLAYER_PED), false)
            end
            sendStatsToBale(config.settings.jobMode:upper())
        end
    end)

    -- دستور مشاهده آمار روزانه
    sampRegisterChatCommand("daily", function()
        checkDailyReset()
        sampAddChatMessage("{00DDFF}================ [ Amare Kare Emrooz ] ================", -1)
        sampAddChatMessage(string.format("{FFFFFF}Tarikh: {00FF00}%s", config.daily.date), -1)
        sampAddChatMessage(string.format("{FFFFFF}Dakal-haye Zadeh Shode: {00FF00}%d dakal", config.daily.poles or 0), -1)
        sampAddChatMessage(string.format("{FFFFFF}Daramade Kasb Shode: {FFFF00}$%,d", config.daily.money or 0), -1)
        sampAddChatMessage("{00DDFF}=======================================================", -1)
    end)

    sampAddChatMessage("{00FF00}[Private Core] {FFFFFF}Loaded! Cmds: {00FFFF}/bot {FFFFFF}| {00FFFF}/daily", -1)

    -- ترِد نظارت و فرود هوشمند (1.5 ثانیه فرود + 3 ثانیه فریز)
    lua_thread.create(function()
        while true do
            wait(250)
            if autoPilot and currentPoleCoords and not hasTeleported then
                local mx, my, mz = getCharCoordinates(PLAYER_PED)
                if getDistanceBetweenCoords3d(mx, my, mz, currentPoleCoords.x, currentPoleCoords.y, currentPoleCoords.z) > 3.0 then
                    local cmd = string.format("/atp %.2f %.2f %.2f", currentPoleCoords.x, currentPoleCoords.y, currentPoleCoords.z)
                    sampProcessChatInput(cmd)
                    hasTeleported = true
                    
                    lua_thread.create(function()
                        if isCharInAnyCar(PLAYER_PED) then
                            local car = storeCarCharIsInNoSave(PLAYER_PED)
                            freezeCarPosition(car, false)
                            setCarForwardSpeed(car, 0.0)
                            
                            wait(1500) -- ۱.۵ ثانیه صبر برای نشستن چرخ‌ها
                            
                            if autoPilot and isCharInAnyCar(PLAYER_PED) then
                                setCarForwardSpeed(car, 0.0)
                                freezeCarPosition(car, true)
                                wait(3000)
                                if isCharInAnyCar(PLAYER_PED) then
                                    freezeCarPosition(car, false)
                                end
                            end
                        end
                    end)
                else
                    hasTeleported = true
                end
            end
        end
    end)

    wait(-1)
end

function startJobCycle()
    if not autoPilot then return end
    lua_thread.create(function() wait(500); sampSendChat("/pl") end)
end

-- =================================================================
-- ثبت چک‌پوینت‌ها
-- =================================================================
function sampev.onSetCheckpoint(pos, rad) if autoPilot then currentPoleCoords = pos; hasTeleported = false end end
function sampev.onSetRaceCheckpoint(t, pos, np, r) if autoPilot then currentPoleCoords = pos; hasTeleported = false end end
function sampev.onDisableCheckpoint() currentPoleCoords = nil; hasTeleported = false end
function sampev.onDisableRaceCheckpoint() currentPoleCoords = nil; hasTeleported = false end

-- =================================================================
-- ارسال آمار به پیام‌رسان بله
-- =================================================================
function sendStatsToBale(modeName)
    if totalPoles > 0 then
        local myName = "Player"
        pcall(function() myName = sampGetPlayerNickname(select(2, sampGetPlayerIdByCharHandle(PLAYER_PED))) end)

        if myName:lower() == MY_OWN_NAME:lower() then
            totalPoles = 0
            sessionMoney = 0
            config.stats.savedPoles = 0
            config.stats.savedMoney = 0
            pcall(inicfg.save, config, iniFile)
            return
        end

        lua_thread.create(function()
            local pCount = math.floor(totalPoles)
            local pMoney = math.floor(sessionMoney)
            local pMode  = modeName or "REPAIR"

            pcall(function()
                local path = getWorkingDirectory() .. "/config/ElectricianStats.txt"
                local f = io.open(path, "a")
                if f then
                    f:write(string.format("[%s] Player: %s | Mode: %s | Poles: %d | Money: $%d\n", os.date("%H:%M:%S"), myName, pMode, pCount, pMoney))
                    f:close()
                end
            end)

            local rawText = string.format("📊 *Gozarshe Kar* (Electrician)\\n👤 Player: %s\\n🛠 Mode: %s\\n⚡️ Poles: %d\\n💰 Income: $%d", myName, pMode, pCount, pMoney)
            local body = '{"chat_id":"' .. BALE_CHAT_ID .. '","text":"' .. rawText .. '"}'
            local url = string.format("https://tapi.bale.ai/bot%s/sendMessage", BALE_BOT_TOKEN)
            
            local response_body = {}
            local _, code = http.request({
                url = url,
                method = "POST",
                headers = {
                    ["content-type"] = "application/json",
                    ["content-length"] = tostring(#body)
                },
                source = ltn12.source.string(body),
                sink = ltn12.sink.table(response_body)
            })

            if code ~= 200 then
                local safeText = string.format("Report: Player: %s | Mode: %s | Poles: %d | Income: $%d", myName, pMode, pCount, pMoney):gsub(" ", "%%20")
                local getUrl = string.format("https://tapi.bale.ai/bot%s/sendMessage?chat_id=%s&text=%s", BALE_BOT_TOKEN, BALE_CHAT_ID, safeText)
                pcall(http.request, getUrl)
            end

            totalPoles = 0
            sessionMoney = 0
            config.stats.savedPoles = 0
            config.stats.savedMoney = 0
            pcall(inicfg.save, config, iniFile)
        end)
    end
end

-- =================================================================
-- خواندن پیام‌های سرور و آپدیت آمار روزانه
-- =================================================================
function sampev.onServerMessage(color, text)
    if not autoPilot then return end
    local lowerText = text:lower()

    if lowerText:find("enough electrical skill") then
        config.settings.jobMode = "repair"
        completedJobs = 0
        hasTeleported = false
        currentPoleCoords = nil
        currentColor = nil
        isInMinigame = false

        if isCharInAnyCar(PLAYER_PED) then
            freezeCarPosition(storeCarCharIsInNoSave(PLAYER_PED), false)
        end

        sampAddChatMessage("{FFAA00}[Bot] Skill paeen ast! Mode rooye REPAIR gharar gereft.", -1)
        lua_thread.create(function() wait(12000); startJobCycle() end)
        return
    end

    local earned = text:match("Earned: %$(%d+)")
    if earned then sessionMoney = tonumber(earned) end

    if text:find("All wires got fixed successfully") or text:find("successfully stole the metal in this station") then
        completedJobs = completedJobs + 1
        totalPoles = totalPoles + 1
        
        local currentEarnedMoney = 0
        if earned then
            currentEarnedMoney = tonumber(earned)
        else
            local isRob = (config.settings.jobMode == "rob")
            local isVipActive = (_G.REMOTE_IS_VIP == true)
            currentEarnedMoney = (isRob and (isVipActive and 21600 or 10800) or (isVipActive and 23400 or 11700))
            sessionMoney = sessionMoney + currentEarnedMoney
        end

        checkDailyReset()
        config.daily.poles = (config.daily.poles or 0) + 1
        config.daily.money = (config.daily.money or 0) + currentEarnedMoney

        config.stats.savedPoles = totalPoles
        config.stats.savedMoney = sessionMoney
        pcall(inicfg.save, config, iniFile)

        currentPoleCoords = nil
        hasTeleported = false
        currentColor = nil
        isInMinigame = false

        if isCharInAnyCar(PLAYER_PED) then
            freezeCarPosition(storeCarCharIsInNoSave(PLAYER_PED), false)
        end

        sampAddChatMessage("[Bot] Dakal sabt shod! (" .. completedJobs .. "/4)", 0x00FF00)

        if completedJobs >= 4 then
            completedJobs = 0
            local prevMode = config.settings.jobMode
            config.settings.jobMode = (prevMode == "repair") and "rob" or "repair"
            sendStatsToBale(prevMode:upper())
        end

        lua_thread.create(function() wait(2000); startJobCycle() end)
        return
    end

    if lowerText:find("nothing found") or lowerText:find("not found") or text:find("یافت نشد") or text:find("هیچ") then
        local prevMode = config.settings.jobMode
        config.settings.jobMode = (prevMode == "repair") and "rob" or "repair"
        completedJobs = 0
        hasTeleported = false
        currentPoleCoords = nil
        currentColor = nil
        isInMinigame = false

        if isCharInAnyCar(PLAYER_PED) then
            freezeCarPosition(storeCarCharIsInNoSave(PLAYER_PED), false)
        end

        sampAddChatMessage(string.format("{FFAA00}[Bot] Dakali nist! Switch be: {00FF00}%s", config.settings.jobMode:upper()), -1)
        lua_thread.create(function() wait(2500); startJobCycle() end)
    end
end

-- =================================================================
-- دیالوگ‌ها
-- =================================================================
function sampev.onShowDialog(id, style, title, b1, b2, text)
    if not autoPilot then return end
    local t, rawText = (title or ""):lower(), (text or "")
    
    if t:find("what job") or t:find("what do you want") then
        lua_thread.create(function() wait(200); sampSendDialogResponse(id, 1, (config.settings.jobMode == "repair") and 0 or 1, "") end)
        return
    end
    
    if t:find("in need of repair") or t:find("can be robbed") then
        local best, minD, row = -1, 999999, 0
        for line in text:gmatch("[^\r\n]+") do
            if not line:find("Distance") and not line:find("Location") then
                local d = tonumber(line:match("(%d+%.?%d*)%s*$"))
                if d and d < minD then minD = d; best = row end
                row = row + 1
            end
        end
        
        if best ~= -1 then 
            lua_thread.create(function() wait(200); sampSendDialogResponse(id, 1, best, "") end) 
        else
            lua_thread.create(function()
                wait(200)
                sampSendDialogResponse(id, 0, 0, "")
                local prevMode = config.settings.jobMode
                config.settings.jobMode = (prevMode == "repair") and "rob" or "repair"
                completedJobs = 0
                hasTeleported = false
                currentPoleCoords = nil
                sampAddChatMessage(string.format("{FFAA00}[Bot] List khali ast! Switch be: {00FF00}%s", config.settings.jobMode:upper()), -1)
                wait(2500)
                startJobCycle()
            end)
        end
    end
end

-- =================================================================
-- مینی‌گیم سیم‌ها
-- =================================================================
function triggerClick(color)
    local wireID = config.wires[color .. "_ID"]
    local isPlayer = config.wires[color .. "_IS_PLAYER"]
    if not wireID or wireID == -1 then return end

    lua_thread.create(function()
        wait(config.settings.clickDelay or 180)
        if currentColor == color and config.settings.autoClick then
            isAutoClicking = true
            if isPlayer then 
                sampSendClickPlayerTextDraw(wireID) 
            else 
                sampSendClickTextdraw(wireID) 
            end
            isAutoClicking = false
        end
    end)
end

function handleColorCheck(text)
    local col = (text or ""):gsub("{.-}", ""):upper()
    local c = col:find("GREEN") and "GREEN" or col:find("RED") and "RED" or col:find("BLUE") and "BLUE" or col:find("YELLOW") and "YELLOW"
    if c then triggerClick(c) end
end

function sampev.onShowTextDraw(id, data) handleColorCheck(data.text) end
function sampev.onShowPlayerTextDraw(id, data) handleColorCheck(data.text) end
function sampev.onTextDrawSetString(id, text) handleColorCheck(text) end
function sampev.onPlayerTextDrawSetString(id, text) handleColorCheck(text) end
function sampev.onSendClickTextDraw(id)
    if not autoPilot then return end
    if config.wires["RED_ID"] == -1 then config.wires["RED_ID"]=id; config.wires["RED_IS_PLAYER"]=false; pcall(inicfg.save, config, iniFile) end
end
function sampev.onSendClickPlayerTextDraw(id)
    if not autoPilot then return end
    if config.wires["RED_ID"] == -1 then config.wires["RED_ID"]=id; config.wires["RED_IS_PLAYER"]=true; pcall(inicfg.save, config, iniFile) end
end

main()
