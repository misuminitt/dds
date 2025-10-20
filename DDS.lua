-- DDS.lua — versi kamu (fitur lengkap), hanya ditambah:
-- - UI dipasang ke gethui/CoreGui (bukan PlayerGui)
-- - watchdog re-parent (kalau GUI dihapus)
-- - tetap autorun 1-chunk → cocok untuk loadstring(HttpGet(...))()

-- ====== SERVICES & HELPERS (TAMBAHAN KECIL) ======
local Players       = game:GetService("Players")
local Workspace     = game:GetService("Workspace")
local TweenService  = game:GetService("TweenService")
local StarterGui    = game:GetService("StarterGui")
local UIS           = game:GetService("UserInputService")
local RunService    = game:GetService("RunService")
local CoreGui       = game:GetService("CoreGui")

local player        = Players.LocalPlayer

-- Parent GUI ke tempat yang lebih aman dari anti-cheat:
local function getUiParent()
    return (gethui and gethui()) or CoreGui or player:FindFirstChildOfClass("PlayerGui") or player:WaitForChild("PlayerGui", 3)
end
local function protect(gui)
    pcall(function() if syn and syn.protect_gui then syn.protect_gui(gui) end end)
end

-- ====== ASLI: STATE & KONFIG ======
local DDS = {
    NAME          = "DDS",
    GUI_NAME      = "DDSGUI",
    TP1_PATH      = "Workspace.Livrason.Take1.Take",
    SCAN_ORDER    = {1,2,3,4,5,6,7,8},
    ID_TO_LABEL   = {
        [1]="Faroka",[2]="Karangasem",[3]="Kleco",[4]="Manahan",
        [5]="Pajang",[6]="Klodran",[7]="Colomadu",[8]="Klaten",
    },
    BOX_KEYWORDS  = { "box","package","parcel","paket","paketbox","delivery" },
    STATE         = { running=false, firstRound=true },
    DELAY         = _G.__DDS_delays or { start=10, afterStart=25, failNext=25, successNext=25 },
    CONFIG        = _G.__DDS_config or { keybind = Enum.KeyCode.RightShift.Name, theme = "Dark" },
    THEMESETS     = {
        Dark  = {bg=Color3.fromRGB(25,25,30),  bg2=Color3.fromRGB(35,35,45),  btn=Color3.fromRGB(52,152,219),
                 good=Color3.fromRGB(46,204,113), bad=Color3.fromRGB(231,76,60),
                 text=Color3.fromRGB(240,240,255), textSub=Color3.fromRGB(200,220,255)},
        Light = {bg=Color3.fromRGB(245,247,250),bg2=Color3.fromRGB(225,230,238),btn=Color3.fromRGB(66,133,244),
                 good=Color3.fromRGB(36,160,90),  bad=Color3.fromRGB(220,68,55),
                 text=Color3.fromRGB(25,25,25),   textSub=Color3.fromRGB(80,90,110)},
        Blue  = {bg=Color3.fromRGB(20,28,38),  bg2=Color3.fromRGB(30,44,60),  btn=Color3.fromRGB(45,140,240),
                 good=Color3.fromRGB(54,185,120), bad=Color3.fromRGB(230,90,80),
                 text=Color3.fromRGB(225,235,255), textSub=Color3.fromRGB(170,190,220)},
    },
    UI            = {},
}

DDS.THEME = DDS.THEMESETS[DDS.CONFIG.theme] or DDS.THEMESETS.Dark
_G.__DDS_config  = DDS.CONFIG
_G.__DDS_delays  = DDS.DELAY
_G.__DDS_theme   = DDS.THEME

local function now() return os.date("[%H:%M:%S] ") end
local function hrp() return (player.Character or player.CharacterAdded:Wait()):WaitForChild("HumanoidRootPart") end

local function clampDelay(n, minV, maxV)
    n = tonumber(n) or 0
    if n < (minV or 0) then n = (minV or 0) end
    if maxV and n > maxV then n = maxV end
    return n
end

local function findByPath(path)
    local node = game
    for seg in string.gmatch(path, "([^%.]+)") do
        node = (seg=="game") and game or (seg=="Workspace" and Workspace or (node and node:FindFirstChild(seg)))
        if not node then return nil end
    end
    return node
end

local function anyCFrame(inst)
    if not inst then return nil end
    if inst:IsA("BasePart") then return inst.CFrame end
    if inst:IsA("Model") then
        local p = inst.PrimaryPart or inst:FindFirstChildWhichIsA("BasePart", true)
        return p and p.CFrame
    end
    local p2 = inst:FindFirstChildWhichIsA("BasePart", true)
    return p2 and p2.CFrame
end

local function tweenTo(cf)
    local part = hrp()
    if not part or not cf then return false end
    local tw = TweenService:Create(part, TweenInfo.new(0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {CFrame = cf + Vector3.new(0,3,0)})
    local ok = pcall(function() tw:Play(); tw.Completed:Wait() end)
    return ok
end

local function logStatus(msg)
    print("[DDS] "..tostring(msg))
    pcall(function()
        StarterGui:SetCore("SendNotification", {Title="Star Job", Text=tostring(msg), Duration=2})
    end)
    if DDS.UI.statusLbl then DDS.UI.statusLbl.Text = tostring(msg) end

    local logContainer = DDS.UI.logContainer
    local scrollLog    = DDS.UI.scrollLog
    if logContainer then
        local lab = Instance.new("TextLabel")
        lab.BackgroundTransparency = 1
        lab.Size = UDim2.new(1, -8, 0, 18)
        lab.TextXAlignment = Enum.TextXAlignment.Left
        lab.Font = Enum.Font.Gotham
        lab.TextSize = 13
        lab.TextColor3 = DDS.THEME.textSub
        lab.Text = now()..tostring(msg)
        lab.Parent = logContainer

        local cnt=0
        for _,c in ipairs(logContainer:GetChildren()) do
            if c:IsA("TextLabel") then cnt += 1 end
        end
        if cnt>60 then
            for _,c in ipairs(logContainer:GetChildren()) do
                if c:IsA("TextLabel") then c:Destroy() break end
            end
        end

        task.defer(function()
            if scrollLog then
                scrollLog.CanvasSize = UDim2.new(0,0,0,logContainer.AbsoluteSize.Y)
                scrollLog.CanvasPosition = Vector2.new(0, scrollLog.AbsoluteCanvasSize.Y)
            end
        end)
    end
end

local function firePromptOnce(p)
    if not p then return false end
    return pcall(function()
        if fireproximityprompt then
            fireproximityprompt(p, 1)
        else
            p:InputHoldBegin(); task.wait(0.6); p:InputHoldEnd()
        end
    end)
end

local function tripleInteractPrompt(p, intervalMin, intervalMax)
    intervalMin, intervalMax = intervalMin or 0.15, intervalMax or 0.25
    math.randomseed(os.clock()*1000)
    for _=1,3 do
        firePromptOnce(p)
        task.wait(intervalMin + math.random()*(intervalMax-intervalMin))
    end
end

local function nearestPrompt(maxRadius)
    local root = hrp()
    local best, bestDist
    for _, d in ipairs(Workspace:GetDescendants()) do
        if d:IsA("ProximityPrompt") then
            local base = d.Parent
            if base and base:IsA("BasePart") then
                local dist = (base.Position - root.Position).Magnitude
                if dist <= (maxRadius or 20) then
                    if not best or dist < bestDist then best, bestDist = d, dist end
                end
            end
        end
    end
    return best
end

local function findStartJobPrompt(timeout)
    local t0 = time()
    repeat
        for _, d in ipairs(Workspace:GetDescendants()) do
            if d:IsA("ProximityPrompt") then
                local base = d.Parent
                if base and base:IsA("BasePart") then
                    local dist = (base.Position - hrp().Position).Magnitude
                    if dist <= 35 then
                        local obj = string.lower(d.ObjectText or "")
                        local act = string.lower(d.ActionText or "")
                        if obj:find("start") or obj:find("job") or obj:find("take") or obj:find("package")
                        or act:find("start") or act:find("job") then
                            return d
                        end
                    end
                end
            end
        end
        task.wait(0.1)
    until (time()-t0) > (timeout or 3)
    return nil
end

local function clickNearbyOrFallback()
    local p = nearestPrompt(20)
    if p then
        tripleInteractPrompt(p, 0.15, 0.25)
        return true
    end

    local pg = player:FindFirstChildOfClass("PlayerGui")
    if not pg then return false end
    for _,gui in ipairs(pg:GetDescendants()) do
        if gui:IsA("TextButton") then
            local t = string.lower(gui.Text or "")
            if t:find("package") or t:find("deliver") or t:find("put") or t:find("drop") then
                for _=1,3 do
                    pcall(function()
                        if firesignal then firesignal(gui.MouseButton1Click) else gui:Activate() end
                    end)
                    task.wait(0.15)
                end
                return true
            end
        end
    end
    return false
end

local function hasPackage()
    local function toolHasBoxName(tool)
        local n = string.lower(tool.Name)
        for _,kw in ipairs(DDS.BOX_KEYWORDS) do
            if n:find(kw, 1, true) then return true end
        end
        return false
    end

    local bp = player:FindFirstChildOfClass("Backpack")
    if bp then
        for _,t in ipairs(bp:GetChildren()) do
            if t:IsA("Tool") and toolHasBoxName(t) then return true end
        end
    end

    local ch = player.Character
    if ch then
        for _,t in ipairs(ch:GetChildren()) do
            if t:IsA("Tool") and toolHasBoxName(t) then return true end
        end
    end
    return false
end

local function equipPackage(timeout)
    timeout = timeout or 5
    local t0 = time()

    local function pick()
        local bp = player:FindFirstChildOfClass("Backpack")
        if not bp then return nil end

        for _,tool in ipairs(bp:GetChildren()) do
            if tool:IsA("Tool") then
                local n = string.lower(tool.Name)
                for _,kw in ipairs(DDS.BOX_KEYWORDS) do
                    if n:find(kw, 1, true) then return tool end
                end
            end
        end

        local list={}
        for _,tool in ipairs(bp:GetChildren()) do
            if tool:IsA("Tool") then
                local n = string.lower(tool.Name)
                if not n:find("flash") and not n:find("senter") then table.insert(list, tool) end
            end
        end
        table.sort(list, function(a,b) return a.Name < b.Name end)
        return list[1]
    end

    local chosen = pick()
    while not chosen and (time()-t0) < timeout do task.wait(0.2); chosen = pick() end
    if not chosen then return false end
    chosen.Parent = player.Character
    return true
end

local function tpToBlockId(id)
    local liv = Workspace:FindFirstChild("Livrason"); if not liv then logStatus("Folder Livrason tidak ada."); return false end
    local loc = liv:FindFirstChild("Location"); if not loc then logStatus("Folder Location tidak ada."); return false end
    local node = loc:FindFirstChild(tostring(id)); if not node then logStatus(("Location.%d tidak ada, lanjut."):format(id)); return false end

    local cf
    local blk = node:FindFirstChild("Block") or node:FindFirstChild("BLOCK")
    if blk and blk:IsA("BasePart") then
        cf = blk.CFrame
    else
        local anyBlock = node:FindFirstChildWhichIsA("BasePart", true)
        if anyBlock and string.find(string.lower(anyBlock.Name), "block") then
            cf = anyBlock.CFrame
        end
    end
    if not cf then
        logStatus(("Block untuk %s tidak ditemukan, lanjut."):format(DDS.ID_TO_LABEL[id] or ("ID "..id)))
        return false
    end

    logStatus(("Teleport ke %s (BLOCK)…"):format(DDS.ID_TO_LABEL[id] or ("ID "..id)))
    return tweenTo(cf)
end

local function tpToStart()
    local tp1 = findByPath(DDS.TP1_PATH)
    local cf  = tp1 and anyCFrame(tp1)
    if not cf then logStatus("TP1 tidak ditemukan."); return false end
    logStatus("Teleport ke Start Job…")
    return tweenTo(cf)
end

function DDS:doStartJobPhase()
    if not tpToStart() then return false end
    task.wait(self.DELAY.start)

    logStatus("Mencari prompt 'Start Job / Take Packages'…")
    local prompt = findStartJobPrompt(3)
    if not prompt then logStatus("Prompt Start Job tidak ketemu."); return false end

    logStatus("Menekan Start Job x3…")
    tripleInteractPrompt(prompt, 0.25, 0.5)
    task.wait(self.DELAY.afterStart)
    return true
end

function DDS:tryDropAtBlock(id)
    if not tpToBlockId(id) then return false end

    if not hasPackage() then
        logStatus("Paket tidak ada saat tiba di blok—anggap sudah sukses sebelumnya.")
        return true
    end

    equipPackage(5)
    clickNearbyOrFallback()

    if hasPackage() then
        logStatus(("Belum ada tombol di %s / paket masih ada → lanjut."):format(self.ID_TO_LABEL[id] or id))
        return false
    else
        logStatus(("Paket ter-drop di %s ✅"):format(self.ID_TO_LABEL[id] or id))
        return true
    end
end

function DDS:runOneScanRound()
    if self.STATE.firstRound then
        if not self:doStartJobPhase() then return false, false end
    end

    local dropped = false
    for _, id in ipairs(self.SCAN_ORDER) do
        if not self.STATE.running then return false, false end
        if self:tryDropAtBlock(id) then
            logStatus(("Menunggu %.1f detik sebelum lanjut putaran berikutnya…"):format(self.DELAY.successNext))
            task.wait(self.DELAY.successNext)
            dropped = true
            break
        else
            task.wait(self.DELAY.failNext)
        end
    end
    return true, dropped
end

function DDS:start()
    if self.STATE.running then return logStatus("Sudah berjalan…") end
    self.STATE.running   = true
    self.STATE.firstRound= true
    task.spawn(function()
        while self.STATE.running do
            local ok, dropped = self:runOneScanRound()
            if not self.STATE.running then break end
            if not ok then
                task.wait(1.5); self.STATE.firstRound = true
            else
                self.STATE.firstRound = not dropped
                if not dropped then
                    logStatus("Belum menemukan lokasi drop pada putaran ini. Ulangi dari awal…")
                    task.wait(1.0)
                end
            end
        end
    end)
end

function DDS:stop()
    self.STATE.running = false
    logStatus("Proses dihentikan ❌")
end

_G.DDS_Start = function() DDS:start() end
_G.DDS_Stop  = function() DDS:stop()  end

local function mkCorner(parent, r) local c=Instance.new("UICorner", parent); c.CornerRadius=UDim.new(0, r or 8); return c end

local function mkLabel(parent, props)
    local l = Instance.new("TextLabel")
    l.BackgroundTransparency = 1
    l.TextXAlignment = props.align or Enum.TextXAlignment.Left
    l.Font = props.font or Enum.Font.Gotham
    l.TextSize = props.size or 13
    l.TextColor3 = props.color or DDS.THEME.text
    l.Text = props.text or ""
    l.Size = props.sizeUDim2 or UDim2.new(1, -8, 0, 20)
    l.Position = props.pos or UDim2.new(0,4,0,0)
    l.Parent = parent
    return l
end

local function mkButton(parent, text, sizeUDim2, posUDim2, bgColor, textColor, onClick, bold)
    local b = Instance.new("TextButton")
    b.Size = sizeUDim2
    b.Position = posUDim2
    b.BackgroundColor3 = bgColor
    b.TextColor3 = textColor or Color3.new(1,1,1)
    b.Font = bold and Enum.Font.GothamBold or Enum.Font.Gotham
    b.TextSize = 14
    b.Text = text
    b.Parent = parent
    mkCorner(b, 8)
    if onClick then b.MouseButton1Click:Connect(onClick) end
    return b
end

local function mkTextBox(parent, text, sizeUDim2, posUDim2)
    local t = Instance.new("TextBox")
    t.Size = sizeUDim2; t.Position = posUDim2
    t.BackgroundColor3 = DDS.THEME.bg
    t.TextColor3 = DDS.THEME.text
    t.Font = Enum.Font.Gotham
    t.TextSize = 12
    t.Text = tostring(text or "")
    t.ClearTextOnFocus = false
    t.TextXAlignment = Enum.TextXAlignment.Center
    t.Parent = parent
    mkCorner(t, 6)
    return t
end

local function buildGUI()
    -- hapus lama (CoreGui & PlayerGui) — TAMBAHAN: bersihin di dua tempat
    pcall(function()
        local parent = getUiParent()
        if parent then
            local old = parent:FindFirstChild(DDS.GUI_NAME); if old then old:Destroy() end
        end
        local pg = player:FindFirstChildOfClass("PlayerGui")
        if pg then local old2 = pg:FindFirstChild(DDS.GUI_NAME); if old2 then old2:Destroy() end end
    end)

    -- ASLI: buat gui, PANEL, dsb. HANYA ganti parent → getUiParent()
    local gui = Instance.new("ScreenGui")
    gui.Name = DDS.GUI_NAME
    gui.ResetOnSpawn = false
    gui.DisplayOrder = 999
    gui.IgnoreGuiInset = true

    local parent = getUiParent()
    if parent then protect(gui); gui.Parent = parent else gui.Parent = player:WaitForChild("PlayerGui") end

    local panel = Instance.new("Frame")
    panel.Size = UDim2.new(0, 520, 0, 420)
    panel.Position = UDim2.new(0, 24, 0, 90)
    panel.BackgroundColor3 = DDS.THEME.bg
    panel.BorderSizePixel = 0
    panel.Parent = gui
    mkCorner(panel, 12)

    local header = Instance.new("Frame")
    header.Size = UDim2.new(1,0,0,36)
    header.BackgroundColor3 = DDS.THEME.bg2
    header.BorderSizePixel = 0
    header.Parent = panel

    local title = mkLabel(header, {
        text="Star Job", size=16, font=Enum.Font.GothamBold,
        color=DDS.THEME.text,
        sizeUDim2=UDim2.new(1,-120,1,0), pos=UDim2.new(0,12,0,0)
    })

    do
        local dragging, startPos, startInputPos
        header.InputBegan:Connect(function(input)
            if input.UserInputType==Enum.UserInputType.MouseButton1 then
                dragging=true; startPos=panel.Position; startInputPos=input.Position
                input.Changed:Connect(function()
                    if input.UserInputState==Enum.UserInputState.End then dragging=false end
                end)
            end
        end)
        UIS.InputChanged:Connect(function(input)
            if dragging and input.UserInputType==Enum.UserInputType.MouseMovement then
                local d = input.Position - startInputPos
                panel.Position = UDim2.new(startPos.X.Scale,startPos.X.Offset+d.X,startPos.Y.Scale,startPos.Y.Offset+d.Y)
            end
        end)
    end

    local tabs = Instance.new("Frame"); tabs.BackgroundTransparency=1; tabs.Size=UDim2.new(1,-12,0,30); tabs.Position=UDim2.new(0,6,0,40); tabs.Parent=panel
    local pages = Instance.new("Frame"); pages.Size=UDim2.new(1,-12,1,-80); pages.Position=UDim2.new(0,6,0,72); pages.BackgroundTransparency=1; pages.Parent=panel
    local function mkPage() local f=Instance.new("Frame"); f.Size=UDim2.new(1,0,1,0); f.BackgroundTransparency=1; f.Parent=pages; return f end
    local pageJob, pageTP, pageSet = mkPage(), mkPage(), mkPage()
    local function show(which) pageJob.Visible=(which=="Job"); pageTP.Visible=(which=="Teleport"); pageSet.Visible=(which=="Settings") end

    local function mkTab(text, x, target)
        return mkButton(tabs, text, UDim2.new(0,160,0,28), UDim2.new(0,x,0,0),
            DDS.THEME.bg2, DDS.THEME.text, function() show(target) end, true)
    end
    mkTab("Job",0,"Job"); mkTab("Teleport",166,"Teleport"); mkTab("Settings",332,"Settings")

    local statusLbl = mkLabel(pageJob, {text="Tidak ada proses berjalan", color=DDS.THEME.textSub})
    local targetLbl = mkLabel(pageJob, {text="Mode: Scan 1→8 (BLOCK)", color=DDS.THEME.textSub, pos=UDim2.new(0,4,0,20)})

    mkButton(pageJob,"Start", UDim2.new(0,200,0,34), UDim2.new(0,4,0,46), DDS.THEME.good, Color3.new(1,1,1),
        function() if not DDS.STATE.running then DDS:start() else logStatus("Sudah berjalan…") end end, true)

    mkButton(pageJob,"Stop",  UDim2.new(0,200,0,34), UDim2.new(0,220,0,46), DDS.THEME.bad, Color3.new(1,1,1),
        function() DDS:stop() end, true)

    local btnClear = mkButton(pageJob,"Clear Log",UDim2.new(0,120,0,28),UDim2.new(0,4,0,86),DDS.THEME.bg2,DDS.THEME.text,
        function()
            local lc = DDS.UI.logContainer
            if lc then for _,c in ipairs(lc:GetChildren()) do if c:IsA("TextLabel") then c:Destroy() end end end
            if DDS.UI.scrollLog then DDS.UI.scrollLog.CanvasPosition = Vector2.new(0,0) end
            logStatus("Log dibersihkan.")
        end, true)

    local scrollLog = Instance.new("ScrollingFrame")
    scrollLog.Size=UDim2.new(1,-8,1,-200); scrollLog.Position=UDim2.new(0,4,0,160)
    scrollLog.BackgroundColor3=DDS.THEME.bg2; scrollLog.BorderSizePixel=0; scrollLog.ScrollBarThickness=6; scrollLog.Parent=pageJob
    mkCorner(scrollLog, 8)

    local logContainer = Instance.new("Frame")
    logContainer.BackgroundTransparency=1; logContainer.Size=UDim2.new(1,-6,0,0); logContainer.AutomaticSize=Enum.AutomaticSize.Y; logContainer.Parent=scrollLog

    local list = Instance.new("UIListLayout"); list.SortOrder=Enum.SortOrder.LayoutOrder; list.Padding=UDim.new(0,2); list.Parent=scrollLog
    local list2 = Instance.new("UIListLayout"); list2.Padding=UDim.new(0,1); list2.Parent=logContainer

    logContainer:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
        scrollLog.CanvasSize = UDim2.new(0,0,0,logContainer.AbsoluteSize.Y)
    end)

    local box = Instance.new("Frame"); box.Size=UDim2.new(1,-8,0,60); box.Position=UDim2.new(0,4,0,120); box.BackgroundColor3=DDS.THEME.bg2; box.Parent=pageJob; mkCorner(box,8)
    local function tiny(parent, text, x, y)
        return mkLabel(parent,{text=text,color=DDS.THEME.text, size=12, pos=UDim2.new(0,x,0,y), sizeUDim2=UDim2.new(0,140,0,18)})
    end
    tiny(box,"StartJob Delay",8,6);  local inStart = mkTextBox(box, DDS.DELAY.start,  UDim2.new(0,50,0,22), UDim2.new(0,110,0,6))
    tiny(box,"After Start",  170,6); local inAfter = mkTextBox(box, DDS.DELAY.afterStart,UDim2.new(0,50,0,22), UDim2.new(0,250,0,6))
    tiny(box,"Fail Next",    310,6); local inFail  = mkTextBox(box, DDS.DELAY.failNext,  UDim2.new(0,50,0,22), UDim2.new(0,380,0,6))

    tiny(box,"Success Wait", 8,32);  local inSucc  = mkTextBox(box, DDS.DELAY.successNext,UDim2.new(0,50,0,22), UDim2.new(0,110,0,32))

    mkButton(box,"Apply", UDim2.new(0,110,0,24), UDim2.new(0,380,0,32), DDS.THEME.btn, Color3.new(1,1,1),
        function()
            DDS.DELAY.start       = clampDelay(inStart.Text, 0, 30)
            DDS.DELAY.afterStart  = clampDelay(inAfter.Text, 0, 30)
            DDS.DELAY.failNext    = clampDelay(inFail.Text,  0, 30)
            DDS.DELAY.successNext = clampDelay(inSucc.Text,  0, 30)
            logStatus(("Delays updated: start=%.1fs, afterStart=%.1fs, failNext=%.1fs, success=%.1fs")
                :format(DDS.DELAY.start, DDS.DELAY.afterStart, DDS.DELAY.failNext, DDS.DELAY.successNext))
        end, true)

    local grid = Instance.new("UIGridLayout")
    grid.CellPadding=UDim2.new(0,8,0,8); grid.CellSize=UDim2.new(0,135,0,36); grid.FillDirectionMaxCells=3
    grid.HorizontalAlignment=Enum.HorizontalAlignment.Left; grid.VerticalAlignment=Enum.VerticalAlignment.Top
    grid.Parent=pageTP

    local function mkTPBtn(label, cb)
        local b = mkButton(pageTP, label, UDim2.new(0,135,0,36), UDim2.new(0,0,0,0), DDS.THEME.btn, Color3.new(1,1,1), cb, true)
        return b
    end

    mkTPBtn("Start Job", function() tpToStart() end)
    for id=1,8 do
        local label = DDS.ID_TO_LABEL[id]
        mkTPBtn(label, function() tpToBlockId(id) end)
    end

    local kbTitle = mkLabel(pageSet, {text="Toggle Keybind:", size=14, font=Enum.Font.GothamBold, pos=UDim2.new(0,4,0,0)})
    local kbBtn = mkButton(pageSet, DDS.CONFIG.keybind.." (click to change)", UDim2.new(0,200,0,30), UDim2.new(0,4,0,26),
        DDS.THEME.bg2, DDS.THEME.text, nil, false)

    local waitingKey=false
    kbBtn.MouseButton1Click:Connect(function()
        if waitingKey then return end
        waitingKey=true; kbBtn.Text="Press any key…"
        local conn; conn=UIS.InputBegan:Connect(function(input,gp)
            if gp then return end
            if input.KeyCode ~= Enum.KeyCode.Unknown then
                DDS.CONFIG.keybind = input.KeyCode.Name
                kbBtn.Text = DDS.CONFIG.keybind.." (click to change)"
                logStatus("Keybind diubah: "..DDS.CONFIG.keybind)
                conn:Disconnect(); waitingKey=false
            end
        end)
    end)

    local thTitle = mkLabel(pageSet, {text="Theme:", size=14, font=Enum.Font.GothamBold, pos=UDim2.new(0,4,0,70)})
    local thBtn = mkButton(pageSet, DDS.CONFIG.theme.." (click to cycle)", UDim2.new(0,200,0,30), UDim2.new(0,4,0,96),
        DDS.THEME.bg2, DDS.THEME.text, nil, false)

    local order={"Dark","Light","Blue"}
    local function nextTheme(cur) for i,n in ipairs(order) do if n==cur then return order[(i%#order)+1] end end return "Dark" end

    local function applyTheme()
        DDS.THEME = DDS.THEMESETS[DDS.CONFIG.theme] or DDS.THEMESETS.Dark
        _G.__DDS_theme = DDS.THEME

        panel.BackgroundColor3 = DDS.THEME.bg
        header.BackgroundColor3= DDS.THEME.bg2
        title.TextColor3       = DDS.THEME.text

        for _,b in ipairs(tabs:GetChildren()) do
            if b:IsA("TextButton") then b.BackgroundColor3=DDS.THEME.bg2; b.TextColor3=DDS.THEME.text end
        end
        statusLbl.TextColor3   = DDS.THEME.textSub
        targetLbl.TextColor3   = DDS.THEME.textSub
        scrollLog.BackgroundColor3 = DDS.THEME.bg2

        box.BackgroundColor3   = DDS.THEME.bg2
        for _,b in ipairs(pageTP:GetChildren()) do
            if b:IsA("TextButton") then b.BackgroundColor3 = DDS.THEME.btn end
        end
    end
    thBtn.MouseButton1Click:Connect(function()
        DDS.CONFIG.theme = nextTheme(DDS.CONFIG.theme)
        thBtn.Text = DDS.CONFIG.theme.." (click to cycle)"
        logStatus("Theme: "..DDS.CONFIG.theme)
        applyTheme()
    end)
    applyTheme()

    UIS.InputBegan:Connect(function(input,gp)
        if gp then return end
        local want = Enum.KeyCode[DDS.CONFIG.keybind or "RightShift"]
        if input.KeyCode == want then panel.Visible = not panel.Visible end
    end)

    local function defaultView()
        show("Job"); logStatus("GUI siap. Tabs: Job / Teleport / Settings")
    end
    defaultView()

    DDS.UI = {
        gui=gui, panel=panel, header=header, title=title, tabs=tabs,
        pageJob=pageJob, pageTP=pageTP, pageSet=pageSet,
        statusLbl=statusLbl, targetLbl=targetLbl,
        scrollLog=scrollLog, logContainer=logContainer,
    }
end

buildGUI()

-- Watchdog (tetap ada + re-parent kalau unparent)
RunService.Heartbeat:Connect(function()
    local gui = DDS.UI and DDS.UI.gui
    if gui and not gui.Parent then
        local p = getUiParent()
        if p then protect(gui); gui.Parent = p; logStatus("GUI terhapus → re-parent.")
        else logStatus("Re-parent gagal: parent tidak ada.") end
    end
end)
