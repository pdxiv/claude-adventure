#!/usr/bin/env lua
-- Scott Adams Adventure Game Interpreter
-- Implementation in Lua 5.3

-- =====================================================================
-- CONSTANTS
-- =====================================================================

local CARRIED = 255     -- Item is being carried by player
local DESTROYED = 0     -- Item is in room 0 (not in game)
local DARKBIT = 15      -- Bit flag for darkness
local LIGHTOUTBIT = 16  -- Bit flag for light source running out
local LIGHT_SOURCE = 9  -- Item ID for light source (typically)
local DEBUG = false     -- Global debug flag

-- =====================================================================
-- UTILITY FUNCTIONS
-- =====================================================================

-- Decode condition value: parameter * 20 + conditionCode
local function decodeCondition(encodedValue)
    local conditionCode = encodedValue % 20
    local parameter = math.floor(encodedValue / 20)
    return { code = conditionCode, parameter = parameter }
end

-- Decode command pair: 150 * cmd1 + cmd2
local function decodeCommandPair(encodedValue)
    local command2 = encodedValue % 150
    local command1 = math.floor(encodedValue / 150)
    return { cmd1 = command1, cmd2 = command2 }
end

-- Decode vocabulary value: verb * 150 + noun
local function decodeVocab(encodedValue)
    local noun = encodedValue % 150
    local verb = math.floor(encodedValue / 150)
    return { verb = verb, noun = noun }
end

-- Debug print function
local function debugPrint(...)
    if DEBUG then
        print("DEBUG:", ...)
    end
end

-- Function to turn debug mode on/off
local function setDebugMode(value)
    DEBUG = value
    if DEBUG then
        print("Debug mode enabled")
    else
        print("Debug mode disabled")
    end
end

-- String trimming utility
local function trim(s)
    return s:gsub("^%s+", ""):gsub("%s+$", "")
end

-- Dump table contents for debugging
local function dumpTable(t, indent)
    indent = indent or 0
    local indentStr = string.rep("  ", indent)
    
    for k, v in pairs(t) do
        if type(v) == "table" then
            print(indentStr .. k .. ":")
            dumpTable(v, indent + 1)
        else
            print(indentStr .. k .. ": " .. tostring(v))
        end
    end
end

-- =====================================================================
-- GAME STATE AND DATA
-- =====================================================================

-- Game data structure
local game = {
    header = {},
    actions = {},
    vocabulary = { verbs = {}, nouns = {}, verbsById = {}, nounsById = {} },
    rooms = {},
    messages = {},
    items = {},
    actionTitles = {},
    trailer = {}
}

-- Game state
local state = {
    currentRoom = 0,
    itemLocations = {},
    bitFlags = {},
    counter = 0,
    altCounters = {},
    altRooms = {},
    lightTime = 0,
    continuationFlag = false,
    needToDescribeRoom = true,
    lastNoun = nil
}

-- Forward declarations for functions that need to be referenced before defined
local saveGame
local loadSavedGame
local displayRoom
local processAutomaticActions

-- =====================================================================
-- CORE GAME FUNCTIONS
-- =====================================================================

-- Check if a condition is met
local function checkCondition(condition)
    local decoded = decodeCondition(condition)
    local code = decoded.code
    local parameter = decoded.parameter
    
    -- Implement all condition codes
    if code == 0 then
        -- PAR - Always true (parameter is passed to action)
        return true, parameter
    elseif code == 1 then
        -- HAS - Player is carrying item [parameter]
        return state.itemLocations[parameter] == CARRIED
    elseif code == 2 then
        -- IN/W - Item [parameter] is in current room
        return state.itemLocations[parameter] == state.currentRoom
    elseif code == 3 then
        -- AVL - Item [parameter] is carried or in current room
        return state.itemLocations[parameter] == CARRIED or state.itemLocations[parameter] == state.currentRoom
    elseif code == 4 then
        -- IN - Player is in room [parameter]
        return state.currentRoom == parameter
    elseif code == 5 then
        -- -IN/W - Item [parameter] is not in current room
        return state.itemLocations[parameter] ~= state.currentRoom
    elseif code == 6 then
        -- -HAVE - Player is not carrying item [parameter]
        return state.itemLocations[parameter] ~= CARRIED
    elseif code == 7 then
        -- -IN - Player is not in room [parameter]
        return state.currentRoom ~= parameter
    elseif code == 8 then
        -- BIT - Bit flag [parameter] is set
        return state.bitFlags[parameter] == true
    elseif code == 9 then
        -- -BIT - Bit flag [parameter] is not set
        return state.bitFlags[parameter] ~= true
    elseif code == 10 then
        -- ANY - Player is carrying at least one item
        for _, location in pairs(state.itemLocations) do
            if location == CARRIED then
                return true
            end
        end
        return false
    elseif code == 11 then
        -- -ANY - Player is not carrying any items
        for _, location in pairs(state.itemLocations) do
            if location == CARRIED then
                return false
            end
        end
        return true
    elseif code == 12 then
        -- -AVL - Item [parameter] is not carried or in current room
        return state.itemLocations[parameter] ~= CARRIED and state.itemLocations[parameter] ~= state.currentRoom
    elseif code == 13 then
        -- -RM0 - Item [parameter] is not in room 0 (not destroyed)
        return state.itemLocations[parameter] ~= DESTROYED
    elseif code == 14 then
        -- RM0 - Item [parameter] is in room 0 (destroyed)
        return state.itemLocations[parameter] == DESTROYED
    elseif code == 15 then
        -- CT<= - Counter <= [parameter]
        return state.counter <= parameter
    elseif code == 16 then
        -- CT> - Counter > [parameter]
        return state.counter > parameter
    elseif code == 17 then
        -- ORIG - Item [parameter] is in its original location
        return state.itemLocations[parameter] == game.items[parameter].location
    elseif code == 18 then
        -- -ORIG - Item [parameter] is not in its original location
        return state.itemLocations[parameter] ~= game.items[parameter].location
    elseif code == 19 then
        -- CT= - Counter = [parameter]
        return state.counter == parameter
    end
    
    return false
end

-- Display current room
displayRoom = function()
    -- Make sure room exists before checking anything
    if not game.rooms[state.currentRoom] then
        print("ERROR: Invalid room number: " .. state.currentRoom)
        return
    end
    
    -- Check if it's dark - with null safety
    if state.bitFlags[DARKBIT] and 
       (state.itemLocations[LIGHT_SOURCE] ~= CARRIED and 
        state.itemLocations[LIGHT_SOURCE] ~= state.currentRoom) then
        print("It is too dark to see.")
        return
    end
    
    local room = game.rooms[state.currentRoom]
    
    -- Display room description - with null safety
    local desc = room.description or ""
    if desc:sub(1, 1) == "*" then
        -- If description starts with *, display it directly
        print(desc:sub(2))
    else
        -- Otherwise, prefix with "I'm in a" or "You're in a"
        print("I'm in a " .. desc)
    end
    
    -- Display visible items
    local visibleItems = {}
    for i, location in pairs(state.itemLocations) do
        if location == state.currentRoom and game.items[i] and game.items[i].description then
            local itemDesc = game.items[i].description
            -- Remove AutoGet part if present (format: "description/WORD/")
            itemDesc = itemDesc:gsub("/[^/]+/", "")
            table.insert(visibleItems, itemDesc)
        end
    end
    
    if #visibleItems > 0 then
        print("I can see:")
        for _, item in ipairs(visibleItems) do
            print("  " .. item)
        end
    end
    
    -- Display obvious exits
    local exits = {}
    local dirNames = {"NORTH", "SOUTH", "EAST", "WEST", "UP", "DOWN"}
    
    for i = 1, 6 do
        if room.exits and room.exits[i] and room.exits[i] > 0 then
            table.insert(exits, dirNames[i])
        end
    end
    
    if #exits > 0 then
        print("Obvious exits: " .. table.concat(exits, ", "))
    else
        print("No obvious exits.")
    end
    
    state.needToDescribeRoom = false
end

-- Execute a command
local function executeCommand(command, parameter, parameter2)
    debugPrint("Executing command", command, "with parameters", parameter, parameter2)
    
    if command == 0 then
        -- No action (displays message 0)
        if game.messages[0] then
            print(game.messages[0])
        end
    elseif command >= 1 and command <= 51 then
        -- Display message number 1-51
        if game.messages[command] then
            print(game.messages[command])
        else
            debugPrint("Message not found:", command)
        end
    elseif command >= 102 and command <= 151 then
        -- Display message number command-50
        local msgIndex = command-50
        if game.messages[msgIndex] then
            print(game.messages[msgIndex])
        else
            debugPrint("Message not found:", msgIndex)
        end
    elseif command == 52 then
        -- GETx - Pick up item x (fail if carrying too many items)
        if not parameter then
            debugPrint("ERROR: Missing parameter for GET command")
            return false
        end
        
        local itemCount = 0
        for _, location in pairs(state.itemLocations) do
            if location == CARRIED then
                itemCount = itemCount + 1
            end
        end
        
        if itemCount >= game.header.maxCarry then
            print("I can't carry any more.")
            return false
        end
        
        if state.itemLocations[parameter] == state.currentRoom then
            state.itemLocations[parameter] = CARRIED
            print("Taken.")
        else
            print("I don't see it here.")
        end
    elseif command == 53 then
        -- DROPx - Drop item x in current room
        if not parameter then
            debugPrint("ERROR: Missing parameter for DROP command")
            return false
        end
        
        if state.itemLocations[parameter] == CARRIED then
            state.itemLocations[parameter] = state.currentRoom
            print("Dropped.")
        else
            print("I'm not carrying it.")
        end
    elseif command == 54 then
        -- GOTOy - Move player to room y
        if not parameter then
            debugPrint("ERROR: Missing parameter for GOTO command")
            return false
        end
        
        state.currentRoom = parameter
        state.needToDescribeRoom = true
    elseif command == 55 or command == 59 then
        -- x->RM0 - Move item x to room 0 (destroy it)
        if not parameter then
            debugPrint("ERROR: Missing parameter for DESTROY command")
            return false
        end
        
        state.itemLocations[parameter] = DESTROYED
    elseif command == 56 then
        -- NIGHT - Set darkness bit (15)
        state.bitFlags[DARKBIT] = true
    elseif command == 57 then
        -- DAY - Clear darkness bit (15)
        state.bitFlags[DARKBIT] = false
    elseif command == 58 then
        -- SETz - Set bit flag z
        if not parameter then
            parameter = 0  -- Default to flag 0
        end
        
        state.bitFlags[parameter] = true        
        debugPrint("Set bit flag", parameter, "to", state.bitFlags[parameter])
    elseif command == 60 then
        -- CLRz - Clear bit flag z
        if not parameter then
            debugPrint("ERROR: Missing parameter for CLR command")
            return false
        end
        
        state.bitFlags[parameter] = false
        debugPrint("Cleared bit flag", parameter, "to", state.bitFlags[parameter])
    elseif command == 61 then
        -- DEAD - Kill player (move to last room, show death message)
        state.currentRoom = game.header.numRooms  -- Last room is typically death room
        state.needToDescribeRoom = true
        print("I'm dead...")
    elseif command == 62 then
        -- x->y - Move item x to room y
        if not parameter or not parameter2 then
            debugPrint("ERROR: Missing parameters for MOVE command")
            return false
        end
        
        state.itemLocations[parameter] = parameter2
    elseif command == 63 then
        -- FINI - End game
        print("Game over!")
        return true  -- Signal game end
    elseif command == 64 or command == 76 then
        -- DspRM - Show room description
        displayRoom()
    elseif command == 65 then
        -- SCORE - Show score (based on treasures stored)
        local score = 0
        local treasureRoom = game.header.treasureRoom
        
        for i, item in pairs(game.items) do
            if item.description:find("*") and state.itemLocations[i] == treasureRoom then
                score = score + 1
            end
        end
        
        print(string.format("I've stored %d of %d treasures.", score, game.header.treasures))
        if score == game.header.treasures then
            print("I've found all the treasures! Well done!")
        end
    elseif command == 66 then
        -- INV - Show inventory
        local carrying = false
        print("I'm carrying:")
        
        for i, location in pairs(state.itemLocations) do
            if location == CARRIED and game.items[i] then
                carrying = true
                local desc = game.items[i].description
                -- Remove AutoGet part if present
                desc = desc:gsub("/[^/]+/", "")
                -- Remove treasure markers
                desc = desc:gsub("%*", "")
                print("  " .. desc)
            end
        end
        
        if not carrying then
            print("  nothing")
        end
    elseif command == 67 then
        -- SET0 - Set bit flag 0
        state.bitFlags[0] = true
        debugPrint("Set bit flag 0 to", state.bitFlags[0])
    elseif command == 68 then
        -- CLR0 - Clear bit flag 0
        state.bitFlags[0] = false
        debugPrint("Cleared bit flag 0 to", state.bitFlags[0])
    elseif command == 69 then
        -- FILL - Refill light source
        state.lightTime = game.header.lightTime
        -- Move light source to inventory if not already there
        if state.itemLocations[LIGHT_SOURCE] ~= CARRIED then
            state.itemLocations[LIGHT_SOURCE] = CARRIED
        end
        print("Light source is now full and lit.")
    elseif command == 70 then
        -- CLS - Clear screen
        io.write("\027[2J\027[1;1H")  -- ANSI clear screen
    elseif command == 71 then
        -- SAVE - Save game
        saveGame()
    elseif command == 72 then
        -- EXx,x - Swap locations of two items
        if not parameter or not parameter2 then
            debugPrint("ERROR: Missing parameters for SWAP command")
            return false
        end
        
        local tmp = state.itemLocations[parameter]
        state.itemLocations[parameter] = state.itemLocations[parameter2]
        state.itemLocations[parameter2] = tmp
    elseif command == 73 then
        -- CONT - Continue executing actions
        state.continuationFlag = true
        debugPrint("Set continuation flag to true")
    elseif command == 74 then
        -- AGETx - Pick up item x (no carrying capacity check)
        if not parameter then
            debugPrint("ERROR: Missing parameter for AGET command")
            return false
        end
        
        if state.itemLocations[parameter] == state.currentRoom then
            state.itemLocations[parameter] = CARRIED
            print("Taken.")
        else
            print("I don't see it here.")
        end
    elseif command == 75 then
        -- BYx<-x - Item x gets location of item y
        if not parameter or not parameter2 then
            debugPrint("ERROR: Missing parameters for BY command")
            return false
        end
        
        state.itemLocations[parameter] = state.itemLocations[parameter2]
    elseif command == 77 then
        -- CT-1 - Decrement counter
        state.counter = state.counter - 1
        if state.counter < 0 then
            state.counter = 0
        end
    elseif command == 78 then
        -- DspCT - Display counter value
        print("Counter =", state.counter)
    elseif command == 79 then
        -- CT<-n - Set counter to n
        if not parameter then
            debugPrint("ERROR: Missing parameter for SET COUNTER command")
            return false
        end
        
        state.counter = parameter
    elseif command == 80 then
        -- EXRM0 - Swap current room with alternate room 0
        local tmp = state.currentRoom
        state.currentRoom = state.altRooms[0] or 0
        state.altRooms[0] = tmp
        state.needToDescribeRoom = true
    elseif command == 81 then
        -- EXm,CT - Swap counter with alternate counter m
        if not parameter then
            debugPrint("ERROR: Missing parameter for SWAP COUNTER command")
            return false
        end
        
        local tmp = state.counter
        state.counter = state.altCounters[parameter] or 0
        state.altCounters[parameter] = tmp
    elseif command == 82 then
        -- CT+n - Add n to counter
        if not parameter then
            debugPrint("ERROR: Missing parameter for ADD TO COUNTER command")
            return false
        end
        
        state.counter = state.counter + parameter
    elseif command == 83 then
        -- CT-n - Subtract n from counter (minimum -1)
        if not parameter then
            debugPrint("ERROR: Missing parameter for SUBTRACT FROM COUNTER command")
            return false
        end
        
        state.counter = state.counter - parameter
        if state.counter < -1 then
            state.counter = -1
        end
    elseif command == 84 then
        -- SAYw - Display noun entered by player
        if state.lastNoun then
            io.write(state.lastNoun)
        end
    elseif command == 85 then
        -- SAYwCR - Display noun entered by player with newline
        if state.lastNoun then
            print(state.lastNoun)
        else
            print()
        end
    elseif command == 86 then
        -- SAYCR - Display newline
        print()
    elseif command == 87 then
        -- EXc,CR - Swap current room with alternate room c
        if not parameter then
            debugPrint("ERROR: Missing parameter for SWAP ROOM command")
            return false
        end
        
        local tmp = state.currentRoom
        state.currentRoom = state.altRooms[parameter] or 0
        state.altRooms[parameter] = tmp
        state.needToDescribeRoom = true
    elseif command == 88 then
        -- DELAY - Pause for a moment
        io.write("Press Enter to continue...")
        io.read()
    else
        -- Unknown command
        debugPrint("Unknown command code:", command)
    end
    
    return false  -- No game end signal
end

-- Process command pairs from an action
local function processCommandPairs(action, parameter)
    debugPrint("Processing command pairs with parameter:", parameter)
    
    -- Execute each command pair
    for j = 1, 2 do
        if action.commands[j] and action.commands[j] ~= 0 then
            local cmdPair = decodeCommandPair(action.commands[j])
            
            if cmdPair.cmd1 ~= 0 then
                debugPrint("Executing command1:", cmdPair.cmd1)
                local endGame = executeCommand(cmdPair.cmd1, parameter, cmdPair.cmd2)
                if endGame then
                    return true  -- End game
                end
            end
            
            if cmdPair.cmd2 ~= 0 and cmdPair.cmd2 ~= parameter then
                debugPrint("Executing command2:", cmdPair.cmd2)
                local endGame = executeCommand(cmdPair.cmd2, parameter)
                if endGame then
                    return true  -- End game
                end
            end
        end
    end
    
    return false
end

-- Get verb number from input word
local function getInputVerb(word)
    if not word then return 0, 0 end
    
    word = word:upper()
    
    -- Check for direction shortcuts
    local dirShortcuts = {N=1, S=2, E=3, W=4, U=5, D=6}
    local dirNum = dirShortcuts[word]
    if dirNum then
        return 1, dirNum  -- GO + direction
    end
    
    -- Check vocabulary
    for vocabWord, verbNum in pairs(game.vocabulary.verbs) do
        -- Try exact match
        if word == vocabWord then
            return verbNum, 0
        end
        
        -- Try word length match
        if word == vocabWord:sub(1, game.header.wordLength) then
            return verbNum, 0
        end
    end
    
    return 0, 0  -- Not found
end

-- Get noun number from input word
local function getInputNoun(word)
    if not word then return 0 end
    
    word = word:upper()
    
    -- Check for direction shortcuts
    local dirShortcuts = {N=1, S=2, E=3, W=4, U=5, D=6}
    local dirNum = dirShortcuts[word]
    if dirNum then
        return dirNum  -- Direction noun
    end
    
    -- Check vocabulary
    for vocabWord, nounNum in pairs(game.vocabulary.nouns) do
        -- Try exact match
        if word == vocabWord then
            return nounNum
        end
        
        -- Try word length match
        if word == vocabWord:sub(1, game.header.wordLength) then
            return nounNum
        end
    end
    
    return 0  -- Not found
end

-- Handle movement in a direction
local function handleMove(direction)
    -- Check for valid direction
    if direction < 1 or direction > 6 then
        print("Invalid direction.")
        return
    end
    
    -- Check if current room exists
    if not game.rooms[state.currentRoom] then
        print("ERROR: Invalid room")
        return
    end
    
    local exitRoom = game.rooms[state.currentRoom].exits[direction]
    
    if exitRoom == 0 then
        print("You can't go that way.")
        return
    end
    
    -- Check if it's dark and dangerous to move
    if state.bitFlags[DARKBIT] and 
       state.itemLocations[LIGHT_SOURCE] ~= CARRIED and 
       state.itemLocations[LIGHT_SOURCE] ~= state.currentRoom then
        -- There's a chance of falling and dying in the dark
        if math.random(1, 3) == 1 then
            print("I fell in the dark and broke my neck!")
            executeCommand(61)  -- DEAD command
            return
        end
    end
    
    -- Move to the new room
    state.currentRoom = exitRoom
    state.needToDescribeRoom = true
end

-- Process continuation actions
local function processContinuationActions()
    debugPrint("Processing continuation actions")
    
    -- Process actions with verb=0, noun=0 (continuation actions)
    for i = 0, game.header.numActions do
        if not game.actions[i] then
            goto continue
        end
        
        local action = game.actions[i]
        local actionVocab = decodeVocab(action.vocab)
        
        if actionVocab.verb == 0 and actionVocab.noun == 0 and state.continuationFlag then
            debugPrint("Found continuation action", i)
            
            -- Check all conditions
            local allConditionsPass = true
            local parameter = nil
            
            for j = 1, 5 do
                if action.conditions[j] == nil or action.conditions[j] == 0 then
                    -- Zero conditions always pass
                    goto nextCondition
                end
                
                local condition = action.conditions[j]
                local passed, param = checkCondition(condition)
                if not passed then
                    allConditionsPass = false
                    break
                end
                if passed and j == 1 then
                    parameter = param
                end
                
                ::nextCondition::
            end
            
            -- If all conditions pass, execute the commands
            if allConditionsPass then
                debugPrint("All conditions pass for continuation action", i)
                
                -- Execute the action's commands
                local endGame = processCommandPairs(action, parameter)
                if endGame then
                    return true  -- End game
                end
                
                -- If no more CONT commands, stop continuation
                if not state.continuationFlag then
                    debugPrint("Continuation flag cleared, stopping continuation actions")
                    break
                end
            end
        end
        
        ::continue::
    end
    
    -- Reset continuation flag if we've processed all continuation actions
    if state.continuationFlag then
        debugPrint("Resetting continuation flag after processing all actions")
        state.continuationFlag = false
    end
    
    return false
end

-- Find an item by name
local function findItemByName(name)
    if not name then return nil end
    
    name = name:upper()
    
    -- Check for direct auto-get word match
    for i, item in pairs(game.items) do
        if item.autoGet and (item.autoGet == name or 
           item.autoGet == name:sub(1, game.header.wordLength)) then
            return i
        end
    end
    
    -- Check for words in the description
    for i, item in pairs(game.items) do
        local desc = item.description:upper()
        
        -- Remove asterisks from description
        desc = desc:gsub("%*", "")
        
        -- Check if name is in the description
        if desc:find(name) then
            return i
        end
    end
    
    return nil
end

-- Process automatic actions
processAutomaticActions = function()
    debugPrint("Processing automatic actions")
    
    -- First, process actions with verb=0 and noun=0 (unconditional automatic actions)
    for i = 0, game.header.numActions do
        if not game.actions[i] then
            goto continueUnconditional
        end
        
        local action = game.actions[i]
        local actionVocab = decodeVocab(action.vocab)
        
        if actionVocab.verb == 0 and actionVocab.noun == 0 and not state.continuationFlag then
            debugPrint("Found unconditional automatic action", i)
            
            -- Check all conditions
            local allConditionsPass = true
            local parameter = nil
            
            for j = 1, 5 do
                if action.conditions[j] == nil or action.conditions[j] == 0 then
                    -- Zero conditions always pass
                    goto nextConditionUnconditional
                end
                
                local condition = action.conditions[j]
                local passed, param = checkCondition(condition)
                if not passed then
                    allConditionsPass = false
                    break
                end
                if passed and j == 1 then
                    parameter = param
                end
                
                ::nextConditionUnconditional::
            end
            
            -- If all conditions pass, execute the commands
            if allConditionsPass then
                debugPrint("All conditions pass for unconditional automatic action", i)
                
                -- Execute the action's commands
                local endGame = processCommandPairs(action, parameter)
                if endGame then
                    return true  -- End game
                end
                
                -- Process continuation actions if the flag is set
                if state.continuationFlag then
                    local endGame = processContinuationActions()
                    if endGame then
                        return true  -- End game
                    end
                end
            end
        end
        
        ::continueUnconditional::
    end
    
    -- Then, process actions with verb=0 and noun>0 (random chance automatic actions)
    for i = 0, game.header.numActions do
        if not game.actions[i] then
            goto continueRandom
        end
        
        local action = game.actions[i]
        local actionVocab = decodeVocab(action.vocab)
        
        if actionVocab.verb == 0 and actionVocab.noun > 0 then
            debugPrint("Found random automatic action", i, "with chance", actionVocab.noun)
            
            -- For random actions, we need a random number check
            local randomCheck = true
            if actionVocab.noun < 100 then
                -- noun value is percentage chance
                local randomNum = math.random(1, 100)
                if randomNum > actionVocab.noun then
                    randomCheck = false
                    debugPrint("Random check failed:", randomNum, ">", actionVocab.noun)
                end
            end
            
            if randomCheck then
                -- Check all conditions
                local allConditionsPass = true
                local parameter = nil
                
                for j = 1, 5 do
                    if action.conditions[j] == nil or action.conditions[j] == 0 then
                        -- Zero conditions always pass
                        goto nextConditionRandom
                    end
                    
                    local condition = action.conditions[j]
                    local passed, param = checkCondition(condition)
                    if not passed then
                        allConditionsPass = false
                        break
                    end
                    if passed and j == 1 then
                        parameter = param
                    end
                    
                    ::nextConditionRandom::
                end
                
                -- If all conditions pass, execute the commands
                if allConditionsPass then
                    debugPrint("All conditions pass for random automatic action", i)
                    
                    -- Execute the action's commands
                    local endGame = processCommandPairs(action, parameter)
                    if endGame then
                        return true  -- End game
                    end
                    
                    -- Process continuation actions if the flag is set
                    if state.continuationFlag then
                        local endGame = processContinuationActions()
                        if endGame then
                            return true  -- End game
                        end
                    end
                end
            end
        end
        
        ::continueRandom::
    end
    
    return false  -- No game end
end

-- Process player input
local function processPlayerInput(input)
    -- Skip empty input
    if not input or input == "" then
        return false
    end
    
    -- Split input into words
    local words = {}
    for word in input:gmatch("%S+") do
        table.insert(words, word)
    end
    
    -- Special case for "I" (INVENTORY)
    if words[1]:upper() == "I" or words[1]:upper() == "INV" or words[1]:upper() == "INVENTORY" then
        executeCommand(66)  -- Show inventory
        return false
    end
    
    -- Special case for "LOOK"
    if words[1]:upper() == "LOOK" or words[1]:upper() == "L" then
        displayRoom()
        return false
    end
    
    -- Special case for "QUIT"
    if words[1]:upper() == "QUIT" or words[1]:upper() == "Q" then
        print("Are you sure you want to quit? (y/n)")
        local answer = io.read():sub(1, 1):lower()
        if answer == "y" then
            return true  -- Signal game end
        else
            return false
        end
    end
    
    -- Special case for "SAVE"
    if words[1]:upper() == "SAVE" then
        saveGame()
        return false
    end
    
    -- Special case for "LOAD" or "RESTORE"
    if words[1]:upper() == "LOAD" or words[1]:upper() == "RESTORE" then
        loadSavedGame()
        return false
    end
    
    -- Special case for "HELP"
    if words[1]:upper() == "HELP" or words[1]:upper() == "H" then
        print("Try commands like: LOOK, INVENTORY, GET [item], DROP [item], GO [direction]")
        print("Direction shortcuts: N, S, E, W, U, D")
        print("Other commands: SAVE, LOAD, QUIT")
        if game.messages[52] then
            print(game.messages[52]) -- Most Scott Adams games have a help message
        end
        return false
    end
    
    -- Special case for "SCORE"
    if words[1]:upper() == "SCORE" then
        executeCommand(65)  -- Show score
        return false
    end
    
    -- Process direction shortcuts if entered alone
    local dirWords = {NORTH=1, SOUTH=2, EAST=3, WEST=4, UP=5, DOWN=6}
    if words[1]:upper() == "N" or words[1]:upper() == "NORTH" then
        handleMove(1)
        return false
    elseif words[1]:upper() == "S" or words[1]:upper() == "SOUTH" then
        handleMove(2)
        return false
    elseif words[1]:upper() == "E" or words[1]:upper() == "EAST" then
        handleMove(3)
        return false
    elseif words[1]:upper() == "W" or words[1]:upper() == "WEST" then
        handleMove(4)
        return false
    elseif words[1]:upper() == "U" or words[1]:upper() == "UP" then
        handleMove(5)
        return false
    elseif words[1]:upper() == "D" or words[1]:upper() == "DOWN" then
        handleMove(6)
        return false
    end
    
    -- Handle "GO [direction]" specially
    if words[1]:upper() == "GO" and words[2] then
        local dirNum = dirWords[words[2]:upper()]
        if not dirNum then
            if words[2]:upper() == "N" then dirNum = 1
            elseif words[2]:upper() == "S" then dirNum = 2
            elseif words[2]:upper() == "E" then dirNum = 3
            elseif words[2]:upper() == "W" then dirNum = 4
            elseif words[2]:upper() == "U" then dirNum = 5
            elseif words[2]:upper() == "D" then dirNum = 6
            end
        end
        
        if dirNum then
            handleMove(dirNum)
            return false
        end
    end
    
    -- Handle GET/TAKE and DROP specially for better player experience
    if (words[1]:upper() == "GET" or words[1]:upper() == "TAKE") and words[2] then
        local itemNum = findItemByName(words[2])
        if itemNum then
            if state.itemLocations[itemNum] == state.currentRoom then
                -- Count carried items
                local itemCount = 0
                for _, loc in pairs(state.itemLocations) do
                    if loc == CARRIED then
                        itemCount = itemCount + 1
                    end
                end
                
                if itemCount >= game.header.maxCarry then
                    print("I can't carry any more.")
                else
                    state.itemLocations[itemNum] = CARRIED
                    print("Taken.")
                end
            else
                print("I don't see that here.")
            end
            return false
        end
    elseif words[1]:upper() == "DROP" and words[2] then
        local itemNum = findItemByName(words[2])
        if itemNum then
            if state.itemLocations[itemNum] == CARRIED then
                state.itemLocations[itemNum] = state.currentRoom
                print("Dropped.")
            else
                print("I'm not carrying that.")
            end
            return false
        end
    end
    
    -- Regular command processing
    local verb, dirNoun = getInputVerb(words[1])
    local noun = getInputNoun(words[2])
    
    -- If we got a direction noun from getInputVerb (for shortcuts like N, S, E, etc.)
    if dirNoun > 0 then
        noun = dirNoun
    end
    
    debugPrint("Processing command with verb=", verb, "noun=", noun)
    
    -- Store the last noun for SAYw commands
    state.lastNoun = words[2]
    
    -- Process all actions with matching verb/noun
    local actionFound = false
    
    for i = 0, game.header.numActions do
        if not game.actions[i] then
            goto continue
        end
        
        local action = game.actions[i]
        local actionVocab = decodeVocab(action.vocab)
        
        -- Check if verb and noun match
        if (actionVocab.verb == verb and (actionVocab.noun == noun or actionVocab.noun == 0)) then
            debugPrint("Found matching action", i, "with vocab", actionVocab.verb, actionVocab.noun)
            
            -- Check all conditions
            local allConditionsPass = true
            local parameter = nil
            
            for j = 1, 5 do
                if action.conditions[j] == nil or action.conditions[j] == 0 then
                    -- Zero conditions always pass
                    goto nextCondition
                end
                
                local condition = action.conditions[j]
                local passed, param = checkCondition(condition)
                debugPrint("Condition", j, "=", condition, "result:", passed)
                
                if not passed then
                    allConditionsPass = false
                    break
                end
                if passed and j == 1 then  -- The first condition's parameter is used for commands
                    parameter = param
                    debugPrint("Got parameter", parameter, "from first condition")
                end
                
                ::nextCondition::
            end
            
            -- If all conditions pass, execute the commands
            if allConditionsPass then
                actionFound = true
                debugPrint("All conditions pass for action", i)
                
                -- Execute the action's commands
                local endGame = processCommandPairs(action, parameter)
                if endGame then
                    return true  -- End game
                end
                
                -- Process continuation actions if the flag is set
                if state.continuationFlag then
                    debugPrint("Processing continuation actions after action", i)
                    local endGame = processContinuationActions()
                    if endGame then
                        return true  -- End game
                    end
                end
                
                -- If we found and processed an action, and there's no continuation flag,
                -- stop processing actions
                if not state.continuationFlag then
                    break
                end
            end
        end
        
        ::continue::
    end
    
    -- If no action was found and processed
    if not actionFound then
        print("I don't understand how to do that.")
    end
    
    return false  -- No game end
end

-- =====================================================================
-- FILE PARSING FUNCTIONS
-- =====================================================================

-- Function to parse a Scott Adams adventure file
local function parseGameData(filename)
    local file, err = io.open(filename, "r")
    if not file then
        error("Could not open game data file: " .. filename .. " (" .. err .. ")")
    end
    
    local content = file:read("*all")
    file:close()
    
    -- First, replace any \r\n with \n to normalize line endings
    content = content:gsub("\r\n", "\n")
    
    if DEBUG then
        print("File size:", #content, "bytes")
    end
    
    -- Tokenize the file properly, handling quoted strings with newlines
    local tokens = {}
    local position = 1
    local inQuote = false
    local currentToken = ""
    local inComment = false
    
    while position <= #content do
        local char = content:sub(position, position)
        
        -- Handle newlines
        if char == "\n" then
            if inQuote then
                -- Inside quotes, preserve newlines
                currentToken = currentToken .. char
            else
                -- Outside quotes, newlines end comments and tokens
                inComment = false
                if #currentToken > 0 and not inComment then
                    -- Only add non-empty, non-comment tokens
                    table.insert(tokens, currentToken)
                    currentToken = ""
                end
            end
        -- Handle quotes
        elseif char == '"' then
            if inComment then
                -- Ignore quotes in comments
            elseif inQuote then
                -- End of quoted string
                inQuote = false
                currentToken = currentToken .. char  -- Keep the closing quote
                table.insert(tokens, currentToken)  -- Add the quoted content as a token
                currentToken = ""
            else
                -- Start of quoted string
                inQuote = true
                if #currentToken > 0 then
                    -- If we have non-quote content, add it as a token
                    table.insert(tokens, currentToken)
                    currentToken = ""
                end
                currentToken = currentToken .. char  -- Keep the opening quote
            end
        -- Handle comments
        elseif not inQuote and char == "/" and position + 1 <= #content and content:sub(position + 1, position + 1) == "/" then
            -- Start of a comment, ignore rest of line
            inComment = true
            if #currentToken > 0 then
                table.insert(tokens, currentToken)
                currentToken = ""
            end
            -- Skip the second '/'
            position = position + 1
        -- Handle whitespace outside quotes
        elseif not inQuote and char:match("%s") then
            if not inComment and #currentToken > 0 then
                table.insert(tokens, currentToken)
                currentToken = ""
            end
        -- Handle regular characters
        else
            if inQuote or (not inComment) then
                currentToken = currentToken .. char
            end
        end
        
        position = position + 1
    end
    
    -- Add any final token
    if #currentToken > 0 and not inComment then
        table.insert(tokens, currentToken)
    end
    
    -- Process tokens: convert numbers, remove quotes from strings
    local processedTokens = {}
    for i, token in ipairs(tokens) do
        token = trim(token)
        
        if token ~= "" then
            -- Check if it's a quoted string
            if token:sub(1, 1) == '"' and token:sub(-1) == '"' then
                -- Add as a string with quotes preserved
                table.insert(processedTokens, token)
            -- Check if it's a number
            elseif tonumber(token) then
                table.insert(processedTokens, tonumber(token))
            -- Otherwise it's a regular token
            else
                table.insert(processedTokens, token)
            end
        end
    end
    
    tokens = processedTokens
    
    if DEBUG then
        print("Tokenized file, found", #tokens, "tokens")
        for i = 1, math.min(20, #tokens) do
            local t = tokens[i]
            if type(t) == "string" and #t > 50 then
                t = t:sub(1, 47) .. "..."
            end
            print(i .. ":", t)
        end
    end
    
    -- Now process the tokens according to the Scott Adams format
    local tokenIndex = 1
    
    -- Parse header (12 values)
    if DEBUG then print("Parsing header...") end
    
    game.header.numBytes = tonumber(tokens[tokenIndex]) or 0; tokenIndex = tokenIndex + 1
    game.header.numItems = tonumber(tokens[tokenIndex]) or 0; tokenIndex = tokenIndex + 1
    game.header.numActions = tonumber(tokens[tokenIndex]) or 0; tokenIndex = tokenIndex + 1
    game.header.numWords = tonumber(tokens[tokenIndex]) or 0; tokenIndex = tokenIndex + 1
    game.header.numRooms = tonumber(tokens[tokenIndex]) or 0; tokenIndex = tokenIndex + 1
    game.header.maxCarry = tonumber(tokens[tokenIndex]) or 0; tokenIndex = tokenIndex + 1
    game.header.playerRoom = tonumber(tokens[tokenIndex]) or 0; tokenIndex = tokenIndex + 1
    game.header.treasures = tonumber(tokens[tokenIndex]) or 0; tokenIndex = tokenIndex + 1
    game.header.wordLength = tonumber(tokens[tokenIndex]) or 0; tokenIndex = tokenIndex + 1
    game.header.lightTime = tonumber(tokens[tokenIndex]) or 0; tokenIndex = tokenIndex + 1
    game.header.numMessages = tonumber(tokens[tokenIndex]) or 0; tokenIndex = tokenIndex + 1
    game.header.treasureRoom = tonumber(tokens[tokenIndex]) or 0; tokenIndex = tokenIndex + 1
    
    if DEBUG then
        print("Header values:")
        print("  NumItems:", game.header.numItems)
        print("  NumActions:", game.header.numActions)
        print("  NumWords:", game.header.numWords)
        print("  NumRooms:", game.header.numRooms)
        print("  NumMessages:", game.header.numMessages)
        print("  PlayerRoom:", game.header.playerRoom)
        print("  MaxCarry:", game.header.maxCarry)
    end
    
    -- Parse actions
    if DEBUG then print("Parsing actions...") end
    
    for i = 0, game.header.numActions do
        -- Check if we have enough tokens left
        if tokenIndex + 7 > #tokens then
            if DEBUG then print("Not enough tokens for action", i) end
            break
        end
        
        game.actions[i] = {
            vocab = tonumber(tokens[tokenIndex]) or 0,
            conditions = {
                tonumber(tokens[tokenIndex + 1]) or 0,
                tonumber(tokens[tokenIndex + 2]) or 0,
                tonumber(tokens[tokenIndex + 3]) or 0,
                tonumber(tokens[tokenIndex + 4]) or 0,
                tonumber(tokens[tokenIndex + 5]) or 0
            },
            commands = {
                tonumber(tokens[tokenIndex + 6]) or 0,
                tonumber(tokens[tokenIndex + 7]) or 0
            }
        }
        
        tokenIndex = tokenIndex + 8
    end
    
    -- Parse vocabulary
    if DEBUG then print("Parsing vocabulary...") end
    
    -- Initialize standard vocabulary
    game.vocabulary = {
        verbs = {}, 
        nouns = {},
        verbsById = {},
        nounsById = {}
    }
    
    -- Pre-populate standard vocabulary
    game.vocabulary.verbs["AUTO"] = 0
    game.vocabulary.verbsById[0] = "AUTO"
    game.vocabulary.verbs["GO"] = 1
    game.vocabulary.verbsById[1] = "GO"
    game.vocabulary.nouns["ANY"] = 0
    game.vocabulary.nounsById[0] = "ANY"
    
    -- Direction nouns (1-6)
    local directions = {"NORTH", "SOUTH", "EAST", "WEST", "UP", "DOWN"}
    for i, dir in ipairs(directions) do
        game.vocabulary.nouns[dir] = i
        game.vocabulary.nounsById[i] = dir
    end
    
    -- Process vocabulary words
    local vocabWords = {}
    
    -- In Scott Adams format, we need to find all the vocabulary words
    -- The numWords value typically represents the number of vocabulary items,
    -- but we'll continue reading until we hit a non-string token
    local i = 0
    while i < 1000 do  -- Set a reasonable limit to prevent infinite loops
        if tokenIndex > #tokens then
            break
        end
        
        local token = tokens[tokenIndex]
        if type(token) == "string" and token:sub(1, 1) == '"' and token:sub(-1) == '"' then
            -- Remove quotes from vocabulary words
            token = token:sub(2, -2)
            table.insert(vocabWords, token)
            tokenIndex = tokenIndex + 1
            
            if DEBUG then
                print("Added vocabulary word:", token)
            end
        else
            -- If we hit a non-quoted string, we've gone too far
            break
        end
        
        i = i + 1
    end
    
    if DEBUG then 
        print("Found", #vocabWords, "vocabulary words")
        if #vocabWords > 0 then
            print("First vocab word:", vocabWords[1])
            print("Last vocab word:", vocabWords[#vocabWords])
        end
    end
    
    -- The vocabulary section is split into verbs and nouns
    -- In some Scott Adams formats, numWords refers to total words
    -- In others, it might refer to the number of each type
    -- We'll use the actual count we found and split it appropriately
    
    local verbNounCutoff
    if #vocabWords == game.header.numWords * 2 then
        -- NumWords means "each type"
        verbNounCutoff = game.header.numWords
    else
        -- NumWords might mean total words, or we found a different number
        -- Split what we found evenly
        verbNounCutoff = math.floor(#vocabWords / 2)
    end
    
    if DEBUG then
        print("Verb/noun cutoff at position:", verbNounCutoff)
    end
    
    -- Process verbs (first half)
    local lastVerbId = 1  -- Start from 1 (GO)
    for i = 1, verbNounCutoff do
        local word = vocabWords[i]
        if not word then break end
        
        local isSynonym = word:sub(1, 1) == "*"
        if isSynonym then
            word = word:sub(2)  -- Remove the * prefix
            game.vocabulary.verbs[word] = lastVerbId
        else
            lastVerbId = lastVerbId + 1
            game.vocabulary.verbs[word] = lastVerbId
            game.vocabulary.verbsById[lastVerbId] = word
        end
    end
    
    -- Process nouns (second half)
    local lastNounId = 6  -- Start from 6 (after directions)
    for i = verbNounCutoff + 1, #vocabWords do
        local word = vocabWords[i]
        if not word then break end
        
        local isSynonym = word:sub(1, 1) == "*"
        if isSynonym then
            word = word:sub(2)  -- Remove the * prefix
            game.vocabulary.nouns[word] = lastNounId
        else
            lastNounId = lastNounId + 1
            game.vocabulary.nouns[word] = lastNounId
            game.vocabulary.nounsById[lastNounId] = word
        end
    end
    
    -- Parse rooms
    if DEBUG then print("Parsing rooms at token", tokenIndex) end
    
    for i = 0, game.header.numRooms do
        -- Check if we have enough tokens left
        if tokenIndex + 6 > #tokens then
            if DEBUG then print("Not enough tokens for room", i) end
            break
        end
        
        -- Parse 6 exits
        local exits = {
            tonumber(tokens[tokenIndex]) or 0,
            tonumber(tokens[tokenIndex + 1]) or 0,
            tonumber(tokens[tokenIndex + 2]) or 0,
            tonumber(tokens[tokenIndex + 3]) or 0,
            tonumber(tokens[tokenIndex + 4]) or 0,
            tonumber(tokens[tokenIndex + 5]) or 0
        }
        
        tokenIndex = tokenIndex + 6
        
        -- Get room description (a quoted string)
        local description = ""
        if tokenIndex <= #tokens then
            local token = tokens[tokenIndex]
            if type(token) == "string" and token:sub(1, 1) == '"' and token:sub(-1) == '"' then
                description = token:sub(2, -2)
                tokenIndex = tokenIndex + 1
            end
        end
        
        game.rooms[i] = {
            exits = exits,
            description = description
        }
        
        if DEBUG then
            -- Check specific rooms of interest
            if i == 11 then   -- Starting room
                print("Room 11 (starting room):", description)
            end
            if i == 18 then   -- The deep chasm
                print("Room 18 (chasm):", description)
            end
        end
    end
    
    -- Parse messages
    if DEBUG then print("Parsing messages at token", tokenIndex) end
    
    for i = 0, game.header.numMessages do
        if tokenIndex <= #tokens then
            local token = tokens[tokenIndex]
            if type(token) == "string" and token:sub(1, 1) == '"' and token:sub(-1) == '"' then
                game.messages[i] = token:sub(2, -2)
                tokenIndex = tokenIndex + 1
                
                if DEBUG then
                    print("Message", i, ":", game.messages[i])
                end
            else
                -- If not a quoted string, it's not a message - move on
                break
            end
        else
            break
        end
    end
    
    -- Parse items
    if DEBUG then print("Parsing items at token", tokenIndex) end
    
    for i = 0, game.header.numItems do
        -- Check if we have enough tokens left
        if tokenIndex + 1 > #tokens then
            if DEBUG then print("Not enough tokens for item", i) end
            break
        end
        
        -- Get item description (a quoted string)
        local description = ""
        local autoGet = nil
        
        if tokenIndex <= #tokens then
            local token = tokens[tokenIndex]
            if type(token) == "string" and token:sub(1, 1) == '"' and token:sub(-1) == '"' then
                description = token:sub(2, -2)
                tokenIndex = tokenIndex + 1
                
                -- Extract autoGet word if present
                local autoGetMatch = description:match("/([^/]+)/")
                if autoGetMatch then
                    autoGet = autoGetMatch
                end
            else
                -- If not a quoted string, it's not an item description - move on
                break
            end
        else
            break
        end
        
        -- Get item location
        local location = DESTROYED
        if tokenIndex <= #tokens then
            local token = tokens[tokenIndex]
            if type(token) == "number" then
                location = token
                tokenIndex = tokenIndex + 1
            else
                -- If not a number, it's not a location - move on
                break
            end
        else
            break
        end
        
        game.items[i] = {
            description = description,
            location = location,
            autoGet = autoGet
        }
        
        -- Initialize item locations in game state
        state.itemLocations[i] = location
        
        if DEBUG then
            print("Item", i, ":", description, "at location", location)
            if autoGet then print("  AutoGet:", autoGet) end
        end
    end
    
    -- Ensure all critical items have locations (especially LIGHT_SOURCE)
    for i = 0, math.max(game.header.numItems, LIGHT_SOURCE) do
        if not state.itemLocations[i] then
            state.itemLocations[i] = DESTROYED
        end
    end
    
    -- Parse action titles (optional debugging information)
    if DEBUG then print("Parsing action titles at token", tokenIndex) end
    
    local i = 0
    while tokenIndex <= #tokens do
        local token = tokens[tokenIndex]
        
        -- Check if we've reached the trailer (version, adventure number, checksum)
        if type(token) == "number" and tokenIndex <= #tokens - 2 then
            -- Check if next two tokens are also numbers
            if type(tokens[tokenIndex + 1]) == "number" and type(tokens[tokenIndex + 2]) == "number" then
                break  -- Found the trailer, stop parsing action titles
            end
        end
        
        -- Process action title
        if type(token) == "string" and token:sub(1, 1) == '"' and token:sub(-1) == '"' then
            game.actionTitles[i] = token:sub(2, -2)
            i = i + 1
            tokenIndex = tokenIndex + 1
        else
            -- If not a quoted string, move on
            tokenIndex = tokenIndex + 1
        end
    end
    
    -- Process trailer information
    if DEBUG then print("Parsing trailer at token", tokenIndex) end
    
    -- The trailer should contain the final 3 numbers in the file
    -- Look for the last three numeric tokens
    local trailerTokens = {}
    local i = tokenIndex
    
    -- First, try looking for three consecutive numbers
    if tokenIndex <= #tokens - 2 and 
       type(tokens[tokenIndex]) == "number" and 
       type(tokens[tokenIndex+1]) == "number" and 
       type(tokens[tokenIndex+2]) == "number" then
        trailerTokens = {tokens[tokenIndex], tokens[tokenIndex+1], tokens[tokenIndex+2]}
        tokenIndex = tokenIndex + 3
    else
        -- Scan to the end of the file to find the last 3 numbers
        local lastNumbers = {}
        for i = tokenIndex, #tokens do
            if type(tokens[i]) == "number" then
                table.insert(lastNumbers, tokens[i])
            end
        end
        
        -- Get the last 3 numbers if available
        if #lastNumbers >= 3 then
            trailerTokens = {
                lastNumbers[#lastNumbers-2],
                lastNumbers[#lastNumbers-1],
                lastNumbers[#lastNumbers]
            }
        end
    end
    
    -- Apply the trailer values
    if #trailerTokens >= 3 then
        game.trailer.version = trailerTokens[1]
        game.trailer.adventureNumber = trailerTokens[2]
        game.trailer.checksum = trailerTokens[3]
    end
    
    if DEBUG then
        print("Trailer:")
        print("  Version:", game.trailer.version)
        print("  Adventure:", game.trailer.adventureNumber)
        print("  Checksum:", game.trailer.checksum)
    end
    
    -- Verify checksum
    local calculatedChecksum = 2 * game.header.numActions + game.header.numItems + game.trailer.version
    if calculatedChecksum ~= game.trailer.checksum then
        print("Warning: Checksum verification failed!")
        print("Expected:", game.trailer.checksum, "Calculated:", calculatedChecksum)
    else
        if DEBUG then print("Checksum verified successfully") end
    end
    
    -- Initialize game state
    state.currentRoom = game.header.playerRoom
    state.lightTime = game.header.lightTime
    
    -- Initialize alt rooms and counters
    for i = 0, 7 do
        state.altCounters[i] = 0
        if i <= 5 then
            state.altRooms[i] = 0
        end
    end
    
    -- Initialize bit flags to false
    for i = 0, 31 do
        state.bitFlags[i] = false
    end
    
    -- Ensure all critical items are initialized
    if not state.itemLocations[LIGHT_SOURCE] then
        state.itemLocations[LIGHT_SOURCE] = DESTROYED
    end
    
    -- Make sure all rooms have exits properly initialized
    for i = 0, game.header.numRooms do
        if game.rooms[i] and not game.rooms[i].exits then
            game.rooms[i].exits = {0, 0, 0, 0, 0, 0}
        end
    end
    
    -- Make sure all rooms have descriptions
    for i = 0, game.header.numRooms do
        if game.rooms[i] and not game.rooms[i].description then
            game.rooms[i].description = "mysterious place"
        end
    end
    
    if DEBUG then
        -- Print some key data to verify parsing
        print("\nVerification of key game data:")
        print("Treasure items:")
        for i, item in pairs(game.items) do
            if item.description:find("*") then
                print("  Item", i, ":", item.description, "at location", item.location)
            end
        end
    end
end

-- Save the current game state
saveGame = function()
    print("Enter filename to save (default: save.sav):")
    local filename = io.read()
    if filename == "" then
        filename = "save.sav"
    end
    
    local file, err = io.open(filename, "w")
    if not file then
        print("Could not open file for writing: " .. (err or "unknown error"))
        return
    end
    
    -- Save counters and room registers
    file:write("-- Scott Adams Adventure Save File\n")
    
    -- Save counters
    file:write("counter:" .. state.counter .. "\n")
    for i = 0, 7 do
        file:write("altCounter" .. i .. ":" .. (state.altCounters[i] or 0) .. "\n")
    end
    
    -- Save room registers
    file:write("currentRoom:" .. state.currentRoom .. "\n")
    for i = 0, 5 do
        file:write("altRoom" .. i .. ":" .. (state.altRooms[i] or 0) .. "\n")
    end
    
    -- Save bit flags
    file:write("-- Bit Flags\n")
    for i = 0, 31 do
        file:write("flag" .. i .. ":" .. (state.bitFlags[i] and "1" or "0") .. "\n")
    end
    
    -- Save light time
    file:write("lightTime:" .. state.lightTime .. "\n")
    
    -- Save item locations
    file:write("-- Item Locations\n")
    for i = 0, game.header.numItems do
        file:write("item" .. i .. ":" .. (state.itemLocations[i] or 0) .. "\n")
    end
    
    file:close()
    print("Game saved to " .. filename)
end

-- Load a saved game
loadSavedGame = function()
    print("Enter filename to load (default: save.sav):")
    local filename = io.read()
    if filename == "" then
        filename = "save.sav"
    end
    
    local file, err = io.open(filename, "r")
    if not file then
        print("Could not open save file: " .. (err or "unknown error"))
        return
    end
    
    -- Load saved data
    for line in file:lines() do
        -- Skip comments and empty lines
        if line:sub(1, 2) ~= "--" and line ~= "" then
            local key, value = line:match("([^:]+):(.+)")
            
            if key and value then
                if key == "counter" then
                    state.counter = tonumber(value)
                elseif key:find("altCounter") then
                    local index = tonumber(key:match("altCounter(%d+)"))
                    state.altCounters[index] = tonumber(value)
                elseif key == "currentRoom" then
                    state.currentRoom = tonumber(value)
                    state.needToDescribeRoom = true
                elseif key:find("altRoom") then
                    local index = tonumber(key:match("altRoom(%d+)"))
                    state.altRooms[index] = tonumber(value)
                elseif key:find("flag") then
                    local index = tonumber(key:match("flag(%d+)"))
                    state.bitFlags[index] = (value == "1")                    
                elseif key == "lightTime" then
                    state.lightTime = tonumber(value)
                elseif key:find("item") then
                    local index = tonumber(key:match("item(%d+)"))
                    state.itemLocations[index] = tonumber(value)
                end
            end
        end
    end
    
    file:close()
    print("Game loaded from " .. filename)
end

-- =====================================================================
-- MAIN PROGRAM
-- =====================================================================

-- Main function to start the game
function main(args)
    -- Parse command line arguments
    local filename = "adv01.dat.txt"  -- Default filename
    if args and args[1] then
        filename = args[1]
    end
    
    -- Check for debug mode
    if args and args[2] == "debug" then
        DEBUG = true
        print("Debug mode enabled")
    end
    
    -- Initialize random seed
    math.randomseed(os.time())
    
    -- Load game data
    print("Loading adventure from " .. filename)
    parseGameData(filename)
    
    -- Display intro
    print("\nScott Adams Adventure Interpreter")
    print("Adventure " .. game.trailer.adventureNumber .. ": Version " .. (game.trailer.version / 100))
    
    -- Clear continuation flag to be safe
    state.continuationFlag = false
    
    -- Process initial automatic actions
    processAutomaticActions()
    
    -- First room description
    displayRoom()
    
    -- Main game loop
    local gameOver = false
    while not gameOver do
        -- Process light source
        if state.itemLocations[LIGHT_SOURCE] == CARRIED and not state.bitFlags[LIGHTOUTBIT] then
            state.lightTime = state.lightTime - 1
            if state.lightTime <= 0 then
                state.bitFlags[LIGHTOUTBIT] = true
                print("Light has run out!")
                -- Some games destroy the light source when it runs out
                state.itemLocations[LIGHT_SOURCE] = DESTROYED
            elseif state.lightTime <= 25 then
                print("Light is getting dim.")
            end
        end
        
        -- Display room if needed
        if state.needToDescribeRoom then
            displayRoom()
        end
        
        -- Get player input
        io.write("\n> ")
        local input = io.read()
        
        if not input then
            print("End of input - exiting game.")
            break
        end
        
        -- Debug controls
        if input == "@@debug on" then
            setDebugMode(true)
            goto continue
        elseif input == "@@debug off" then
            setDebugMode(false)
            goto continue
        elseif input == "@@dump" then
            -- Dump game state for debugging
            print("Current room:", state.currentRoom)
            print("Room description:", game.rooms[state.currentRoom].description)
            print("Room exits:", table.concat(game.rooms[state.currentRoom].exits, ", "))
            print("Light time:", state.lightTime)
            
            -- Print bit flags
            print("Bit flags:")
            for bit, value in pairs(state.bitFlags) do
                if value then
                    print("  " .. bit .. ": set")
                end
            end
            
            print("Counter:", state.counter)
            goto continue
        end
        
        -- Process player command
        gameOver = processPlayerInput(input)
        
        -- Process automatic actions after player command
        if not gameOver then
            gameOver = processAutomaticActions()
        end
        
        ::continue::
    end
    
    print("\nGame over. Thanks for playing!")
end

-- This is the crucial line that kicks off the whole program
-- It calls the main function with the command line arguments
main({...})