-- DDS.lua — Drag Drive Simulator helper (autorun, CoreGui, watchdog)
-- By misuminitt — final build

-- ==========================
-- Helpers: services, UI parent, protection, logging
-- ==========================
local S = setmetatable({}, { __index = function(_, k) return game:GetService(k) end })
local LP = S.Players.LocalPlayer
local function getUiParent()
    return (gethui and gethui())
        or S.CoreGui
        or LP:FindFirstChildOfClass("PlayerGui")
        or LP:WaitForChild("PlayerGui", 3)
end
local function protect(gui)
    pcall(function() if syn and syn.protect_gui then syn.protect_gui(gui) end end)
end
local function log(t)
    print("[DDS] " .. tostring(t))
    pcall(function()
        S.StarterGui:SetCore("SendNotification", { Title = "DDS", Text = tostring(t), Duration = 3 })
    end)
end
local function now() return os.date("[%H:%M:%S] ") end

-- small utils
local function clamp(num, a, b)
    num = tonumber(num) or 0
    if a and num < a then num = a end
    if b and num > b then num = b end
    return num
end
local function hrp()
    local ch = LP.Character or LP.CharacterAdded:Wait()
    return ch:WaitForChild("HumanoidRootPart")
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
    if not cf then return false end
    local ok = pcall(function()
        local root = hrp()
        local tw = S.TweenService:Create(root, TweenInfo.new(0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { CFrame = cf + Vector3.new(0, 3, 0) })
        tw:Play()
        tw.Completed:Wait()
    end)
    return ok
end

-- prompt helpers
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
local function tripleInteractPrompt(p, minI, maxI)
    minI, maxI = minI or 0.15, maxI or 0.25
    for _ = 1, 3 do
        firePromptOnce(p)
        task.wait(minI + math.random() * (maxI - minI))
    end
end
local function nearestPrompt(maxRadius)
    local root = hrp()
    local best, bestDist
    for _, d in ipairs(workspace:GetDescendants()) do
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

-- ==========================
-- Core object/state
-- ==========================
local DDS = {
    NAME       = "DDS",
    GUI_NAME   = "DDSGUI",
    -- default delays (as you asked previously): startjob 10, after start 30, fail next 30, success wait 30
    DELAY      = _G.__DDS_delays or { start = 10, afterStart = 30, failNext = 30, successNext = 30 },

    -- scan order & location labels (sesuaikan dengan map kamu)
    SCAN_ORDER = { 1,2,3,4,5,6,7,8 },
    ID_TO_LABEL = {
        [1]="Faroka",[2]="Karangasem",[3]="Kleco",[4]="Manahan",
        [5]="Pajang",[6]="Klodran",[7]="Colomadu",[8]="Klaten",
    },

    -- tempat mulai job (ubah sesuai game)
    TP1_PATH   = "Workspace.Livrason.Take1.Take",

    -- keyword nama Tool paket
    BOX_KEYWORDS = { "box","package","parcel","paket","paketbox","delivery" },

    -- UI theme
    THEME = {
        bg   = Color3.fromRGB(25,25,30),
        bg2  = Color3.fromRGB(35,35,45),
        btn  = Color3.fromRGB(52,152,219),
        good = Color3.fromRGB(46,204,113),
        bad  = Color3.fromRGB(231,76,60),
        text = Color3.fromRGB(240,240,255),
        sub  = Color3.fromRGB(200,220,255),
    },

    -- runtime state & UI refs
    STATE = { running = false, firstRound = true },
    UI    = {},
}
_G._DDS_PRIVATE = DDS
_G.__DDS_delays = DDS.DELAY

-- ==========================
-- Game-specific finders
-- ==========================
local function findByPath(path)
    local node = game
    for seg in string.gmatch(path, "([^%.]+)") do
        if seg == "game" then node = game
        elseif seg == "Workspace" then node = workspace
        else node = node and node:FindFirstChild(seg) end
        if not node then return nil end
    end
    return node
end

local function hasPackage()
    local function toolIsBox(t)
        local n = string.lower(t.Name)
        for _, kw in ipairs(DDS.BOX_KEYWORDS) do
            if n:find(kw, 1, true) then return true end
        end
        return false
    end
    local bp = LP:FindFirstChildOfClass("Backpack")
    if bp then
        for _, t in ipairs(bp:GetChildren()) do
            if t:IsA("Tool") and toolIsBox(t) then return true end
        end
    end
    local ch = LP.Character
    if ch then
        for _, t in ipairs(ch:GetChildren()) do
            if t:IsA("Tool") and toolIsBox(t) then return true end
        end
    end
    return false
end

local function equipPackage(timeout)
    timeout = timeout or 5
    local t0 = time()
    local function pick()
        local bp = LP:FindFirstChildOfClass("Backpack")
        if not bp then return nil end
        for _, tool in ipairs(bp:GetChildren()) do
            if tool:IsA("Tool") then
                local n = string.lower(tool.Name)
                for _, kw in ipairs(DDS.BOX_KEYWORDS) do
                    if n:find(kw, 1, true) then return tool end
                end
            end
        end
        -- fallback ambil tool pertama non-flashlight
        local list = {}
        for _, tool in ipairs(bp:GetChildren()) do
            if tool:IsA("Tool") and not string.lower(tool.Name):find("flash") then
                table.insert(list, tool)
            end
        end
        table.sort(list, function(a,b) return a.Name < b.Name end)
        return list[1]
    end
    local chosen = pick()
    while not chosen and (time() - t0) < timeout do
        task.wait(0.2)
        chosen = pick()
    end
    if not chosen then return false end
    chosen.Parent = LP.Character
    return true
end

local function findStartJobPrompt(timeout)
    local t0 = time()
    repeat
        for _, d in ipairs(workspace:GetDescendants()) do
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
    until (time() - t0) > (timeout or 3)
    return nil
end

local function clickNearbyOrFallback()
    local p = nearestPrompt(20)
    if p then
        tripleInteractPrompt(p, 0.2, 0.35)
        return true
    end
    -- fallback: coba tombol di GUI
    local pg = LP:FindFirstChildOfClass("PlayerGui")
    if not pg then return false end
    for _, gui in ipairs(pg:GetDescendants()) do
        if gui:IsA("TextButton") then
            local t = string.lower(gui.Text or "")
            if t:find("package") or t:find("deliver") or t:find("drop") or t:find("put") then
                for _ = 1, 3 do
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

local function tpToStart()
    local tp1 = findByPath(DDS.TP1_PATH)
    local cf = tp1 and anyCFrame(tp1)
    if not cf then log("TP1 tidak ditemukan.") return false end
    log("Teleport ke Start Job…")
    return tweenTo(cf)
end

local function tpToBlockId(id)
    local liv = workspace:FindFirstChild("Livrason"); if not liv then log("Folder Livrason tidak ada."); return false end
    local loc = liv:FindFirstChild("Location"); if not loc then log("Folder Location tidak ada."); return false end
    local node = loc:FindFirstChild(tostring(id)); if not node then log(("Location.%s tidak ada."):format(id)); return false end

    local blk = node:FindFirstChild("Block") or node:FindFirstChild("BLOCK")
    local cf = blk and blk:IsA("BasePart") and blk.CFrame or anyCFrame(node)
    if not cf then
        log(("Block untuk %s tidak ditemukan."):format(DDS.ID_TO_LABEL[id] or ("ID "..id)))
        return false
    end
    log(("Teleport ke %s (BLOCK)…"):format(DDS.ID_TO_LABEL[id] or ("ID "..id)))
    return tweenTo(cf)
end

-- ==========================
-- Main job phases
-- ==========================
function DDS:doStartJobPhase()
    if not tpToStart() then return false end
    task.wait(self.DELAY.start)

    log("Mencari prompt 'Start Job / Take Packages'…")
    local prompt = findStartJobPrompt(3)
    if not prompt then log("Prompt Start Job tidak ketemu."); return false end

    log("Menekan Start Job x3…")
    tripleInteractPrompt(prompt, 0.25, 0.5)
    task.wait(self.DELAY.afterStart)
    return true
end

function DDS:tryDropAtBlock(id)
    if not tpToBlockId(id) then return false end

    if not hasPackage() then
        log("Paket tidak ada saat tiba—anggap sudah sukses sebelumnya.")
        return true
    end

    equipPackage(5)
    clickNearbyOrFallback()

    if hasPackage() then
        log(("Belum ada tombol di %s / paket masih ada → lanjut."):format(self.ID_TO_LABEL[id] or id))
        return false
    else
        log(("Paket ter-drop di %s ✅"):format(self.ID_TO_LABEL[id] or id))
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
    if self.STATE.running then return log("Sudah berjalan…") end
    self.STATE.running = true
    self.STATE.firstRound = true
    task.spawn(function()
        while self.STATE.running do
            local ok, dropped = self:runOneScanRound()
            if not self.STATE.running then break end
            if not ok then
                task.wait(1.5)
                self.STATE.firstRound = true
            else
                self.STATE.firstRound = not dropped
                if not dropped then
                    log("Belum menemukan lokasi drop pada putaran ini. Ulangi dari awal…")
                    task.wait(1.0)
                end
            end
        end
    end)
end

function DDS:stop()
    self.STATE.running = false
    log("Proses dihentikan ❌")
end

-- ==========================
-- UI
-- ==========================
local function mkCorner(parent, r)
    local c = Instance.new("UICorner", parent); c.CornerRadius = UDim.new(0, r or 8); return c
end
local function mkLabel(parent, props)
    local l = Instance.new("TextLabel")
    l.BackgroundTransparency = 1
    l.TextXAlignment = props.align or Enum.TextXAlignment.Left
    l.Font = props.font or Enum.Font.Gotham
    l.TextSize = props.size or 13
    l.TextColor3 = props.color or DDS.THEME.text
    l.Text = props.text or ""
    l.Size = props.sizeUDim2 or UDim2.new(1, -8, 0, 20)
    l.Position = props.pos or UDim2.new(0, 4, 0, 0)
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
    -- cleanup jika sudah ada
    pcall(function()
        local parent = getUiParent()
        if parent then
            local old = parent:FindFirstChild(DDS.GUI_NAME)
            if old then old:Destroy() end
        end
        local pg = LP:FindFirstChildOfClass("PlayerGui")
        if pg then
            local old2 = pg:FindFirstChild(DDS.GUI_NAME)
            if old2 then old2:Destroy() end
        end
    end)

    -- screen gui
    local gui = Instance.new("ScreenGui")
    gui.Name = DDS.GUI_NAME
    gui.ResetOnSpawn = false
    gui.DisplayOrder = 999
    gui.IgnoreGuiInset = true
    local parent = getUiParent()
    if parent then
        protect(gui); gui.Parent = parent
        log("GUI dipasang ke: " .. (parent.Name or "?"))
    else
        log("UI parent tidak ditemukan.")
    end

    -- root panel
    local panel = Instance.new("Frame", gui)
    panel.Size = UDim2.new(0, 520, 0, 420)
    panel.Position = UDim2.new(0, 24, 0, 90)
    panel.BackgroundColor3 = DDS.THEME.bg
    panel.BorderSizePixel = 0
    mkCorner(panel, 12)

    local header = Instance.new("Frame", panel)
    header.Size = UDim2.new(1, 0, 0, 36)
    header.BackgroundColor3 = DDS.THEME.bg2
    header.BorderSizePixel = 0

    local title = mkLabel(header, { text = "Star Job — DDS", size = 16, font = Enum.Font.GothamBold, color = DDS.THEME.text, sizeUDim2 = UDim2.new(1, -120, 1, 0), pos = UDim2.new(0, 12, 0, 0) })

    -- drag
    do
        local dragging, startPos, startInputPos
        header.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 then
                dragging = true; startPos = panel.Position; startInputPos = input.Position
                input.Changed:Connect(function()
                    if input.UserInputState == Enum.UserInputState.End then dragging = false end
                end)
            end
        end)
        S.UserInputService.InputChanged:Connect(function(input)
            if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
                local d = input.Position - startInputPos
                panel.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
            end
        end)
    end

    -- tabs
    local tabs = Instance.new("Frame", panel); tabs.BackgroundTransparency = 1; tabs.Size = UDim2.new(1, -12, 0, 30); tabs.Position = UDim2.new(0, 6, 0, 40)
    local pages = Instance.new("Frame", panel); pages.Size = UDim2.new(1, -12, 1, -80); pages.Position = UDim2.new(0, 6, 0, 72); pages.BackgroundTransparency = 1
    local function mkPage() local f = Instance.new("Frame", pages); f.Size = UDim2.new(1, 0, 1, 0); f.BackgroundTransparency = 1; return f end
    local pageJob, pageTP, pageSet = mkPage(), mkPage(), mkPage()
    local function show(which)
        pageJob.Visible = (which == "Job")
        pageTP.Visible  = (which == "Teleport")
        pageSet.Visible = (which == "Settings")
    end
    local function mkTab(text, x, target)
        return mkButton(tabs, text, UDim2.new(0, 160, 0, 28), UDim2.new(0, x, 0, 0), DDS.THEME.bg2, DDS.THEME.text, function() show(target) end, true)
    end
    mkTab("Job", 0, "Job"); mkTab("Teleport", 166, "Teleport"); mkTab("Settings", 332, "Settings")

    -- Job page
    local statusLbl = mkLabel(pageJob, { text = "Tidak ada proses berjalan", color = DDS.THEME.sub })
    mkButton(pageJob, "Start", UDim2.new(0, 200, 0, 34), UDim2.new(0, 4, 0, 40), DDS.THEME.good, Color3.new(1,1,1),
        function() if not DDS.STATE.running then DDS:start() else log("Sudah berjalan…") end end, true)
    mkButton(pageJob, "Stop",  UDim2.new(0, 200, 0, 34), UDim2.new(0, 220, 0, 40), DDS.THEME.bad, Color3.new(1,1,1),
        function() DDS:stop() end, true)

    -- delay box
    local box = Instance.new("Frame", pageJob)
    box.Size = UDim2.new(1, -8, 0, 64); box.Position = UDim2.new(0, 4, 0, 90)
    box.BackgroundColor3 = DDS.THEME.bg2; mkCorner(box, 8)
    local function tiny(parent, text, x, y)
        return mkLabel(parent, { text = text, color = DDS.THEME.text, size = 12, pos = UDim2.new(0, x, 0, y), sizeUDim2 = UDim2.new(0, 140, 0, 18) })
    end
    tiny(box, "StartJob", 8, 6);     local inStart = mkTextBox(box, DDS.DELAY.start,       UDim2.new(0, 50, 0, 22), UDim2.new(0, 78, 0, 6))
    tiny(box, "AfterStart", 140, 6);  local inAfter = mkTextBox(box, DDS.DELAY.afterStart,  UDim2.new(0, 50, 0, 22), UDim2.new(0, 215, 0, 6))
    tiny(box, "FailNext",  270, 6);   local inFail  = mkTextBox(box, DDS.DELAY.failNext,    UDim2.new(0, 50, 0, 22), UDim2.new(0, 338, 0, 6))
    tiny(box, "Success",   400, 6);   local inSucc  = mkTextBox(box, DDS.DELAY.successNext, UDim2.new(0, 50, 0, 22), UDim2.new(0, 465, 0, 6))

    mkButton(box, "Apply", UDim2.new(0, 110, 0, 24), UDim2.new(0, 400, 0, 34), DDS.THEME.btn, Color3.new(1,1,1), function()
        DDS.DELAY.start       = clamp(inStart.Text, 0, 60)
        DDS.DELAY.afterStart  = clamp(inAfter.Text, 0, 60)
        DDS.DELAY.failNext    = clamp(inFail.Text,  0, 60)
        DDS.DELAY.successNext = clamp(inSucc.Text,  0, 60)
        log(("Delays updated: start=%.1fs, afterStart=%.1fs, fail=%.1fs, success=%.1fs"):format(
            DDS.DELAY.start, DDS.DELAY.afterStart, DDS.DELAY.failNext, DDS.DELAY.successNext))
    end, true)

    -- log area
    local scroll = Instance.new("ScrollingFrame", pageJob)
    scroll.Size = UDim2.new(1, -8, 1, -170)
    scroll.Position = UDim2.new(0, 4, 0, 160)
    scroll.BackgroundColor3 = DDS.THEME.bg2
    scroll.BorderSizePixel = 0
    scroll.ScrollBarThickness = 6
    mkCorner(scroll, 8)

    local container = Instance.new("Frame", scroll)
    container.BackgroundTransparency = 1
    container.Size = UDim2.new(1, -6, 0, 0)
    container.AutomaticSize = Enum.AutomaticSize.Y

    local list = Instance.new("UIListLayout", container)
    list.SortOrder = Enum.SortOrder.LayoutOrder
    list.Padding = UDim.new(0, 2)

    local function pushLog(t)
        statusLbl.Text = t
        local l = Instance.new("TextLabel")
        l.BackgroundTransparency = 1
        l.Size = UDim2.new(1, -8, 0, 18)
        l.Font = Enum.Font.Gotham
        l.TextSize = 13
        l.TextXAlignment = Enum.TextXAlignment.Left
        l.TextColor3 = DDS.THEME.sub
        l.Text = now() .. t
        l.Parent = container
        task.defer(function()
            scroll.CanvasSize = UDim2.new(0,0,0,container.AbsoluteSize.Y)
            scroll.CanvasPosition = Vector2.new(0, math.max(0, scroll.AbsoluteCanvasSize.Y))
        end)
    end

    -- hook DDS.log to also UI
    DDS._pushLog = pushLog
    local oldLog = log
    log = function(t) oldLog(t); pcall(function() pushLog(tostring(t)) end) end

    -- Teleport page
    local grid = Instance.new("UIGridLayout", pageTP)
    grid.CellPadding = UDim2.new(0, 8, 0, 8)
    grid.CellSize = UDim2.new(0, 150, 0, 36)
    grid.FillDirectionMaxCells = 3
    grid.HorizontalAlignment = Enum.HorizontalAlignment.Left
    grid.VerticalAlignment = Enum.VerticalAlignment.Top

    local function mkTPBtn(label, cb)
        local b = mkButton(pageTP, label, UDim2.new(0, 150, 0, 36), UDim2.new(0, 0, 0, 0), DDS.THEME.btn, Color3.new(1,1,1), cb, true)
        return b
    end
    mkTPBtn("Start Job", function() tpToStart() end)
    for id = 1, 8 do
        local lbl = DDS.ID_TO_LABEL[id] or ("ID " .. id)
        mkTPBtn(lbl, function() tpToBlockId(id) end)
    end

    -- Settings page (toggle keybind show/hide)
    local kbTitle = mkLabel(pageSet, { text = "Toggle GUI (key): RightShift", size = 14, font = Enum.Font.GothamBold, pos = UDim2.new(0, 4, 0, 0) })
    local infoLbl = mkLabel(pageSet, { text = "Tekan RightShift untuk hide/show panel.", size = 12, color = DDS.THEME.sub, pos = UDim2.new(0, 4, 0, 22) })

    -- toggle visibility
    S.UserInputService.InputBegan:Connect(function(input, gp)
        if gp then return end
        if input.KeyCode == Enum.KeyCode.RightShift then
            panel.Visible = not panel.Visible
        end
    end)

    -- defaults
    show("Job"); log("GUI siap. Tabs: Job / Teleport / Settings")

    -- store UI refs
    DDS.UI = {
        gui = gui, panel = panel, header = header,
        statusLbl = statusLbl, scroll = scroll, container = container
    }
end

-- ==========================
-- Autorun
-- ==========================
local ok, err = pcall(function()
    buildGUI()
    log("DDS loaded (autorun). Gunakan tombol Start/Stop. Cek F9 jika tidak tampak.")
end)
if not ok then warn("[DDS] build error: " .. tostring(err)) end

-- watchdog re-parent (jika GUI dihapus)
task.spawn(function()
    while task.wait(1.0) do
        local ok2, err2 = pcall(function()
            local gui = DDS.UI and DDS.UI.gui
            if gui and not gui.Parent then
                local p = getUiParent()
                if p then protect(gui); gui.Parent = p; log("GUI terhapus → re-parent.")
                else log("Re-parent gagal: parent tidak ada.") end
            end
        end)
        if not ok2 then warn("[DDS] watchdog: " .. tostring(err2)) end
    end
end)

-- (Opsional) auto-start pekerjaan saat load:
-- DDS:start()
