local textSize = 1
local textHeight = 8 * textSize
local keyManager = require("libs.key-manager")

local base_path = shell.resolve("")




local modules = peripheral.find("neuralInterface")
if not modules then error("Must have a neural interface", 0) end
if not modules.hasModule("plethora:glasses") then error("The overlay glasses are missing", 0) end
if not modules.hasModule("plethora:keyboard") then error("The keyboard is missing", 0) end


local configs = {}
local context = {
    keyManager = keyManager,
}

local binds = {
    ["Ore Scanner"] = "ctrl+f",
    ["Wall Hack"]   = "ctrl+g",
    ["Kill Aura"]   = "ctrl+k",
    ["Speed"]       = "ctrl+h"
}

local programs = {}
local binded_programs = {}





local canvas = modules.canvas()
canvas.clear()


local function loadPrograms()
    canvas.clear()

    for n, program_name in pairs(fs.list(base_path.."/programs")) do
        term.write("Loading "..program_name.."...")

        local ok, data = pcall(loadfile(base_path.."/programs/"..program_name))
        if ok then print("Success") else error("Failed: "..data) end

        for _, dependency in pairs(data.dependencies) do
            if not modules.hasModule(dependency) then
                ok = false
                print("Missing: "..dependency)
            end
        end

        local text = canvas.addText({1,1+(n-1)*textHeight}, "", 0xffffffff, textSize)
        local meta = {file = program_name, loaded = ok, active = false, 
        last_time_used = os.clock(), data = data, text = text }

        
        if not ok or data == nil then
            text.setColor(0xff0000ff)
            text.setText(data.name)
        elseif binds[data.name] then
            text.setText(data.name..": ["..binds[data.name].."]")
            local err = keyManager:listen(binds[data.name],
                function (state)
                    if not meta.active and state.pressed and not state.pressing then
                        meta.data.start()
                        meta.active = true
                    elseif meta.active and state.pressed and not state.pressing then
                        meta.data.finish()
                        meta.active = false
                    end
                end
            )
            assert(err == nil, err)
        else
            meta.data.start()
            meta.active = true
            text.setColor(0x00ff00ff)
            text.setText(data.name)
        end
        programs[#programs+1] = meta
    end
end



local function render()
    for _, program in pairs(programs) do
        if program.active then
            program.text.setColor(0x00ff00ff)
        elseif program.loaded then
            program.text.setColor(0xffffffff)
        end
    end
end

local function unloadPrograms()
    print("Unloading programs")
    for _, program in pairs(programs) do
        if program.active then
            print("-"..program.data.name)
           local ok, msg = pcall(program.data.finish)

           if not ok then print("["..program.data.name.."] Error: "..msg) end

           program.active = false
        end
    end
    programs ={}
    binded_programs ={}
end

local function reload()
    unloadPrograms()
    modules = peripheral.find("neuralInterface")
    canvas = modules.canvas()
    canvas.clear()
    loadPrograms()
end

local function executePrograms()
    for _, program in pairs(programs) do
        if program.active then
            if os.clock() - program.last_time_used >= program.data.delay then
                
                local ok, msg = pcall(program.data.run, configs, context, event)
                
                if not ok then print("["..program.data.name.."] Error: "..(msg or "")) end
                
                program.last_time_used = os.clock()
                if program.data.delay > 0 then
                    os.startTimer(program.data.delay+0.05)
                end
            end
        end
    end
end

local function run()
    loadPrograms()
    while true do
        
        local event = {os.pullEventRaw()}
        local now = os.clock()

        if event[1] == "terminate" then
            print("Terminating...")
            canvas.clear()
            unloadPrograms()
            print("Done")
            break

        elseif event[1] == "peripheral_detach" or event[1] == "peripheral" and event[2] == "back" then
            reload()

        elseif event[1] == "key" then
            keyManager:setKeyState(event[2], true, event[3])
            render()
        elseif event[1] == "key_up" then
            keyManager:setKeyState(event[2], false, false)
            render()
        end

        executePrograms()

        term.clearLine()
        term.write("Took "..(os.clock()-now).."s")
        term.setCursorPos(1, ({term.getCursorPos()})[2])
    end
end

run()
