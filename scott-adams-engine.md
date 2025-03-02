# The Scott Adams Adventure Game Engine: Comprehensive Implementation Guide

## Table of Contents

1. [Introduction and Historical Context](#introduction-and-historical-context)
2. [Game Engine Architecture Overview](#game-engine-architecture-overview)
3. [Game Data Format](#game-data-format)
   - [File Format Specification](#file-format-specification)
   - [Header Structure](#header-structure)
   - [Rooms](#rooms)
   - [Objects](#objects)
   - [Actions](#actions)
   - [Messages](#messages)
   - [Vocabulary](#vocabulary)
   - [Action Titles](#action-titles)
   - [Trailer Information](#trailer-information)
4. [Game Engine Core Concepts](#game-engine-core-concepts)
   - [Game State](#game-state)
   - [Condition System](#condition-system)
   - [Action System](#action-system)
   - [Command Chaining with CONT](#command-chaining-with-cont)
   - [Light Source Handling](#light-source-handling)
   - [Automatic Movement](#automatic-movement)
   - [The Counter System](#the-counter-system)
   - [Room Registers](#room-registers)
5. [Implementing an Interpreter](#implementing-an-interpreter)
   - [Loading Game Data](#loading-game-data)
   - [Game Loop](#game-loop)
   - [Parser Implementation](#parser-implementation)
   - [Command Processing](#command-processing)
   - [Object Handling](#object-handling)
   - [Movement Commands](#movement-commands)
   - [Save/Load System](#saveload-system)
   - [Display Options](#display-options)
   - [Error Handling and Edge Cases](#error-handling-and-edge-cases)
6. [Creating Games](#creating-games)
   - [Game Design Considerations](#game-design-considerations)
   - [Common Action Patterns](#common-action-patterns)
   - [Limitations and Workarounds](#limitations-and-workarounds)
7. [Reference](#reference)
   - [Condition Codes](#condition-codes)
   - [Action Codes](#action-codes)
   - [Special Locations and Constants](#special-locations-and-constants)
   - [Flag Bits](#flag-bits)

## Introduction and Historical Context

Scott Adams created one of the first commercial text adventure game series starting in 1978 with "Adventureland." His games were notable for running in the limited memory of early microcomputers, including the TRS-80, Apple II, and Commodore PET. To achieve this efficiency, Adams designed a compact virtual machine architecture with a specialized database format to describe the game world and logic.

The engine's distinctive terse prose style was a direct result of memory constraints, but it became a defining characteristic of the genre. The Scott Adams format has influenced text adventure design for decades and remains an excellent study in efficient game engine design.

## Game Engine Architecture Overview

The Scott Adams adventure engine uses a data-driven design where the game world, objects, and game logic are stored in a database. The engine conceptually consists of:

1. **Parser**: Interprets user input against known vocabulary
2. **Condition Checker**: Evaluates game state against action conditions
3. **Command Processor**: Executes game actions when conditions are met
4. **State Manager**: Tracks the game's current state (room, inventory, flags, etc.)

This architecture separates the game content from the engine logic, allowing different adventures to be created without modifying the interpreter code. The same database format can be used across different computer platforms, with only the interpreter needing to be implemented for each system.

## Game Data Format

The database format is highly structured and contains several distinct sections that define all aspects of the game.

### File Format Specification

* Stores values as ASCII text with delimiters
* Uses line-based organization with section markers
* Has each data object on a separate line
* Makes the database human-readable and editable

The data is typically organized in the following sequence:

1. **Header values** (12 numeric values)
2. **Action entries** (each action consists of 8 numbers)
3. **Vocabulary words** (verbs and nouns as quoted strings)
4. **Room descriptions** (6 exit numbers followed by a quoted room description)
5. **Messages** (quoted strings)
6. **Objects** (quoted description strings followed by location numbers)
7. **Action titles** (quoted strings used for debugging)
8. **Trailer information** (version, adventure number, checksum)

Here's an example of how the beginning of a game data file might look (from Adventureland):

```
5953    // Number of bytes for text storage
65      // NumObjects (highest numbered object)
169     // NumActions
69      // NumWords
33      // NumRooms
6       // MaxCarry
11      // PlayerRoom (starting room)
13      // Treasures
3       // WordLength
125     // LightTime
75      // NumMessages
3       // TreasureRoom
```

This is followed by action entries, vocabulary, rooms, etc.

### Header Structure

The header contains numerical values defining the structure and constraints of the game:

```
Header {
    NumObjects          // Number of objects in the game (highest numbered object)
    NumActions        // Number of actions in the game (highest numbered action)
    NumWords          // Number of vocabulary words (verbs/nouns)
    NumRooms          // Number of rooms in the game (highest numbered room)
    MaxCarry          // Maximum objects player can carry
    PlayerRoom        // Starting room for the player
    Treasures         // Number of treasures in the game
    WordLength        // Word length for vocabulary matching
    LightTime         // Turns of light available
    NumMessages       // Number of messages in the game (highest numbered message)
    TreasureRoom      // Room where treasures should be stored
    // Some implementations include:
    AdventureVersion  // Version number of the adventure
    AdventureNumber   // Unique identifier for the adventure
}
```

Note that in the actual data file, some of these values are stored as highest numbered object/action/etc., meaning the actual count would be this number plus one (since numbering starts at 0).

### Rooms

Rooms represent locations in the game world. Each room has:

* Six exit directions (North, South, East, West, Up, Down)
  + Each exit contains the room number of the destination (0 = no exit)
* A description text

```
Room {
    Exits[6]          // Array of room numbers for each direction
    Text              // Description of the room
}
```

In the data file, rooms are stored as 6 exit numbers followed by a description string:

```
 0       // North exit (0 = no exit)
 7       // South exit
 10      // East exit
 1       // West exit
 0       // Up exit
 24      // Down exit
"dismal swamp"  // Room description
```

**Important Implementation Note**: Room descriptions may span multiple lines in the data file. Your parser must handle quoted strings that contain newline characters. Don't simply read the file line by line; use a proper tokenizer that tracks whether you're inside a quoted string.

If a room description begins with an asterisk, the engine displays it directly. Otherwise, it prefixes with "You're in a" or "I'm in a" depending on the interpreter configuration.

Room 0 is a special "storeroom" for objects not currently in play. The player cannot normally access this room. The last room is often reserved as a "limbo" where the player is sent when they die.

### Objects

Objects are objects that can be manipulated in the game. Each object has:

```
Object {
    Text              // Description text (may include "/NOUN/" for auto-get)
    Location          // Current location of the object
    InitialLocation   // Original location of the object (implicit, not stored separately)
    AutoGet           // Text after "/" in object description (optional)
}
```

In the data file, objects are stored as a description string followed by a location number:

```
"Glowing *FIRESTONE*" 0
"Dark hole" 4
"*Pot of RUBIES*/RUB/" 4
```

The object description should begin with an asterisk if the object is to be recognized as a treasure; treasures have asterisks displayed around their description. If the object can be picked up or put down, the word to use for it is enclosed in slashes at the end of the description.

For example: `"*FIRESTONE* (cold now)/FIR/"` indicates a treasure that can be picked up with the word "FIR".

**Implementation Note**: When implementing object interaction, you need to handle both:
1. Explicit vocabulary-based interaction using the defined noun
2. Direct name matching where players might type "GET MUD" even if "MUD" isn't in the vocabulary

Special location values:
* CARRIED (255): Object is carried by the player
* DESTROYED (0): Object is not in the game (in room 0)
* Positive numbers: Room number where the object is located
* Negative numbers: Special locations (implementations may differ)

Object 9 is always the artificial light source in its lighted state.

### Actions

Actions are the core of the game logic. Each action consists of:

```
Action {
    Vocab            // Verb/noun vocabulary reference
    Condition[5]     // Array of conditions to check
    Action[2]        // Array of commands to execute if conditions are met
}
```

The vocabulary value is encoded as `(Verb * 150) + Noun` , where:
* Verb = 0: Automatic action (always checked)
* Noun > 0 when Verb = 0: Percent chance of action happening
* Otherwise: Specific verb/noun combination that triggers this action

Actions are processed in order. The first action with matching verb/noun and all passing conditions will be executed. After player-triggered actions, automatic actions (verb=0) are checked.

### Messages

Messages are simple text strings that can be displayed by actions. Each message is indexed by a number. Message 0 is special and should be an empty string.

**Implementation Note**: Messages may span multiple lines in the data file. Your parser must handle multi-line quoted strings correctly.

### Vocabulary

The game vocabulary consists of verbs and nouns. These are matched against player input.

* Words are stored in uppercase
* Words prefixed with "*" are synonyms for the previous non-synonym word
* Words are typically truncated to the length specified in the header (often 3-5 characters)

Special predefined vocabulary includes:

**Verbs:**
* 0: AUTO - Used for automatic actions (not entered by player)
* 1: GO - Special case for direction nouns 1-6
* 10: CARRY/GET/TAKE - Used to pick up objects
* 18: DROP - Used to drop objects

**Nouns:**
* 0: ANY - Matches any noun in an action entry
* 1-6: NORTH, SOUTH, EAST, WEST, UP, DOWN - Direction nouns

**Implementation Note**: It's crucial to implement multiple ways to handle common commands:
1. Direct handling of verb phrases like "GO NORTH" or "GET MUD"
2. Single-word direction commands like "NORTH" or "E"
3. Vocabulary-based command processing

Your word matching should also support both exact matches and prefix matches (the first N characters as defined in WordLength).

### Action Titles

These are descriptive labels for actions, used only by development tools and ignored by the interpreter. Each title is a string that serves as a reminder of what the action does to simplify adventure creation.

In the data file, these come after the objects section:

```
"FISH ESCAPE"
"DIE BITES"
"BITE INFECT"
"BEES DIE"
```

The original Scott Adams games often had titles that described key events in the game, like "BUILD DAM" or "BLAST DRAGON".

### Trailer Information

The trailer contains:
* Version number (e.g., 416 displays as "4.16")
* Adventure number identifying the specific game
* Security checksum calculated as `(2*NumActions + NumObjects + version)`

For example, in the Adventureland file:

```
 416    // Version number (4.16)
 1      // Adventure number
 819    // Security checksum (2*169 + 65 + 416 = 819)
```

If this checksum is not correct, the adventure program will not allow the use of this database.

## Game Engine Core Concepts

### Game State

The game state consists of:

1. **Player location**: The current room number

2. **Object locations**: Where each object currently is
   - Array of locations
   - Special values: CARRIED (255), DESTROYED (0), positive numbers for room locations

3. **Bit flags**: Boolean values used to track game state
   - Special flags:

     - Bit 15 (DARKBIT): Indicates darkness
     - Bit 16 (LIGHTOUTBIT): Indicates light source has run out

4. **Counters**: Numeric values for more complex state tracking
   - Special counter: COUNTER_TIME_LIMIT tracks light source time

5. **Alternate rooms**: Storage for swapping room values temporarily

6. **Continuation flag**: Tracks whether action processing should continue

### Condition System

Conditions are used to determine if an action should execute. Each action can have up to 5 conditions, all of which must be true for the action to execute.

Conditions are encoded as `(Parameter * 20) + ConditionCode` .

Where:
* Parameter: A value used by the condition (often a room or object number)
* ConditionCode: The type of condition to check (see [Condition Codes](#condition-codes) in the reference section)

When evaluating conditions:
1. Check each condition in sequence (up to 5)
2. If any condition returns false, stop and consider the action not applicable
3. If all conditions return true, execute the action's commands

Condition code 0 (PAR) is special - it always returns true but passes its parameter to the action's commands. This is how parameters are passed through the condition system to the action commands.

### Action System

When conditions are met, the action's commands are executed. Commands can display messages, move objects, change the player's location, modify bit flags, and more.

Commands are encoded in these ways:
1. Numbers 1-51: Display message with that index
2. Numbers 102-151: Display message with index (number-50)
3. Numbers 52-101: Execute a command (e.g., 52 = GET object, 54 = GO TO room)

In the data file, the command pairs are encoded as two numbers:

```
17612   // First command pair (encoded as 150*CMD1 + CMD2)
0       // Second command pair
```

To decode this:
17612 / 150 = 117 remainder 62
So this encodes commands 117 and 62 (move object to room)

The full range of commands is detailed in the [Action Codes](#action-codes) section.

### Command Chaining with CONT

The CONT command (code 73) provides a critical mechanism for chaining multiple actions together. Here's how it works:

1. When a CONT command is executed, it sets a continuation flag.

2. Normally, after finding and executing an action that matches the player's input, the interpreter stops checking further actions. The CONT command overrides this behavior.

3. After executing an action with CONT, the interpreter will continue processing subsequent actions with verb=0 and noun=0 (called "continuation actions").

4. Each continuation action still has its conditions checked before execution.

5. The continuation chain stops when an action with non-zero verb and noun is encountered.

6. If a continuation action's conditions fail, it skips that action but keeps the continuation flag set.

This mechanism is essential for complex game logic where a single player command needs to trigger multiple state changes, object movements, or messages in sequence. For example, when opening a door might involve unlocking it, swinging it open, and revealing what's behind it as separate logical steps.

### Light Source Handling

The engine has special handling for darkness and light sources:

1. Object #9 is always the light source
2. If DARKBIT (15) is set, and the light source is not carried or in the current room:
   - Room description shows only "It is too dark to see"
   - Movement becomes dangerous (may result in death)
   - Most actions are restricted
3. The light source has a limited lifetime (LightTime in the header):
   - This value decrements each turn when the light source is carried
4. When the light time reaches zero:
   - LIGHTOUTBIT (16) is set
   - A message is displayed ("Light has run out")
   - Depending on the interpreter version, the light source may be destroyed (moved to room 0)
5. Warning messages appear when light is running low.
6. The FILL command (action 17/69) refills the light source by:
   - Resetting the light time counter to its original value
   - Moving the light source to the player's inventory if it wasn't there

### Automatic Movement

Direction words (NORTH, SOUTH, EAST, WEST, UP, DOWN) receive special handling:
1. Single letter shortcuts (N, S, E, W, U, D) are converted to full directions
2. GO + direction is handled specially, checking the room's exit table
3. Moving in the dark without a light source is dangerous and may result in death

**Implementation Note**: Your interpreter should support all the common movement command forms:
* Single-letter directions: N, S, E, W, U, D
* Full direction words: NORTH, SOUTH, EAST, WEST, UP, DOWN
* GO + direction: GO NORTH, GO SOUTH, etc.

### The Counter System

The engine maintains a primary counter and several alternate counters:
* The primary counter can be incremented, decremented, displayed, and compared
* There are 8 alternate counters (0-7) that can be swapped with the primary counter
* The time limit can be accessed as alternate counter 8

This counter system allows for tracking various numeric states in the game beyond simple binary flags.

### Room Registers

The system allows saving and restoring room locations:
* The current room can be swapped with up to 6 alternate room registers (0-5)
* This enables complex room transitions and returning to previous locations

## Implementing an Interpreter

### Loading Game Data

To implement a Scott Adams interpreter, you first need to parse the game data file:

1. Read the header information
2. Load actions, vocabulary, rooms, messages, and objects
3. Initialize game state (player location, object locations, etc.)

The format follows this sequence:

```text
Header values
Action data (conditions and commands)
Vocabulary words (verbs and nouns)
Room data (exits and descriptions)
Messages
Object data (descriptions and initial locations)
Action explanations (comments for debugging)
Adventure version
Adventure number
```

**Implementation Note**: A critical aspect of loading game data is correctly handling multi-line quoted strings. Rather than using a simple line-by-line parsing approach, implement a proper tokenizer that:
1. Tracks whether you're inside or outside quoted strings
2. Preserves newlines and other characters inside quoted strings
3. Handles comments and whitespace correctly
4. Returns tokens that maintain the logical structure of the file

This tokenization approach is essential for correctly parsing room descriptions, messages, and other text elements that may span multiple lines.

### Game Loop

The main game loop consists of:

1. Process automatic actions (Verb=0)
2. Display current location if needed
3. Get player input
4. Parse input into verb/noun
5. Process player command
6. Update light source status
7. Process automatic actions again
8. Repeat

### Parser Implementation

The parser transforms player input into verb and noun values that can be matched against the game's vocabulary. The implementation should:

1. Read the player's input string
2. Split the input into words (typically only the first two words matter)
3. Convert all text to uppercase for matching
4. Check for single-letter direction shortcuts (N, S, E, W, U, D)
5. Match each word against the vocabulary list, respecting WordLength truncation
6. Handle synonyms by mapping them to their base word
7. Return the verb and noun numbers for command processing

**Implementation Note**: Your word matching should be robust, supporting:
* Exact matches first, then prefix matches
* Proper handling of synonyms
* Special cases for common verbs like GO, GET, TAKE, and DROP
* Direction words in both full and abbreviated forms

### Command Processing

When processing a command:

1. Convert shorthand directions (N, S, E, W, U, D) to full words
2. Special handling for "I" (INVENTORY) command
3. Match input against vocabulary
4. Check if verb is GO and noun is a direction
   - If so, handle movement directly (don't rely solely on the action system)
5. Check if verb is GET/TAKE or DROP with an object
   - Implement direct object handling for these common commands
6. Check all actions with matching verb/noun
7. Execute first matching action with satisfied conditions
   - If the action includes a CONT command, continue processing subsequent actions
8. Handle built-in commands like GET/DROP if no action matched

**Implementation Note**: Command processing should implement multiple layers:
1. Direct handling of common commands (movement, inventory, etc.)
2. Special case handling for GET/TAKE and DROP with intelligent object matching
3. Vocabulary-based action processing via the action system

This layered approach ensures that common commands work as expected even if the game's vocabulary system doesn't perfectly match player expectations.

#### Automatic Actions

Automatic actions (verb=0) are processed:
1. At the beginning of each turn before player input
2. At the end of each turn after processing player commands
3. During action chaining via the CONT command

For automatic actions where noun>0, the value in noun is used as a percentage chance of the action executing. The interpreter calls a random number generator (1-100) and only executes the action if the random number is less than the noun value. This enables random events in the game.

### Object Handling

Object interaction is a core part of adventure games, and your implementation should be robust:

1. **Object Identification**: Implement multiple ways to identify objects:
   - By vocabulary noun number (e.g., noun 12 = "LAMP")
   - By direct name matching (e.g., "GET LAMP")
   - By AutoGet word if defined in the object description (e.g., "/LAM/")

2. **FindObjectByName Function**: Create a function that can find objects by name:
   - Match against the AutoGet word if present
   - Otherwise, try to match words in the object description
   - Handle special cases for objects like "mud" that might need custom matching

3. **GET/TAKE Implementation**:
   - Check if the object exists and is in the current room
   - Verify the player isn't carrying too many objects
   - Move the object to CARRIED status
   - Provide appropriate feedback

4. **DROP Implementation**:
   - Check if the object exists and is carried
   - Move the object to the current room
   - Provide feedback

5. **Object Description Processing**:
   - Handle asterisks for treasures
   - Extract AutoGet words from descriptions
   - Clean descriptions for display

### Movement Commands

Movement is the most common action in adventure games, so implement it robustly:

1. **Command Forms**: Support all common movement formats:
   - Single letters: N, S, E, W, U, D
   - Full direction words: NORTH, SOUTH, EAST, WEST, UP, DOWN
   - GO + direction: GO NORTH, GO EAST, etc.

2. **Direction Mapping**: Map direction words to indices:
   - NORTH = 0, SOUTH = 1, EAST = 2, WEST = 3, UP = 4, DOWN = 5

3. **Exit Checking**: Verify the current room has an exit in the requested direction

4. **Darkness Handling**: Special handling for movement in dark rooms:
   - Potential for random death
   - Limited visibility

5. **Direct Implementation**: Process movement commands directly rather than relying on the action system for basic movement

### Save/Load System

Most implementations include a save/load system that preserves the game state. This is accessible both through an action command (SAVE - code 19/71) and through direct player commands ("SAVE GAME" and "LOAD GAME").

The save game file typically stores:
1. Counter values and room register contents
2. Flag bits
3. Current room location
4. Current counter value
5. Saved room value
6. Light time remaining
7. Object locations

The save file format is text-based with integers (typically 16-bit) for all values. This ensures consistent loading across different platforms.

### Display Options

Some implementations support several display options:

1. **YOUARE**: Uses "You are" instead of "I am" in descriptions
2. **SCOTTLIGHT**: Uses authentic Scott Adams light messages
3. **DEBUGGING**: Shows information during database loading
4. **TRS80_STYLE**: Displays text in TRS-80 style (64 columns, different formatting)
5. **PREHISTORIC_LAMP**: Destroys the lamp when it runs out (for older games)

These affect how the game presents information to the player and allow for compatibility with different versions of the original interpreters.

### Error Handling and Edge Cases

A robust interpreter should handle various edge cases and errors:

1. **File Format Errors**:
   - Invalid or corrupted game files
   - Missing sections or incomplete data
   - Checksum verification failures
   - Multi-line string parsing issues

2. **Runtime Errors**:
   - Invalid action references
   - Out-of-range room/object references
   - Stack overflow from excessive CONT chaining

3. **Player Input Handling**:
   - Empty input
   - Too many words (ignore beyond the first two)
   - Words not in vocabulary
   - Input that's too long
   - Multiple ways to phrase the same command

4. **Game State Validation**:
   - Ensure room numbers are valid
   - Verify object locations are valid
   - Check that counter values and bit flags are within acceptable bounds

When loading a game, verify the checksum to ensure data integrity.

## Creating Games

### Game Design Considerations

When designing a Scott Adams-style adventure game:

1. **Economy of description**: The engine was designed for systems with limited memory, so room and object descriptions should be concise.

2. **Puzzle complexity**: Despite the simple engine, complex puzzles can be created through clever use of bit flags, counters, and object manipulation.

3. **Map design**: The six-direction exit system allows for 3D spatial relationships, but many games primarily use a 2D layout with occasional vertical connections.

4. **Object limits**: Players can only carry a limited number of objects (defined in MaxCarry), so puzzle design should account for this.

5. **Light source management**: Consider whether your game will use the darkness mechanics, and design appropriate puzzles around the limited light duration.

### Common Action Patterns

Here are some common patterns used in Scott Adams games:

1. **Auto-start messages**: Actions with Verb=0 and no conditions to show opening text.

2. **Event triggers**: Set bit flags when certain conditions are met, then check those flags in other actions.

3. **Multi-step puzzles**: Use bit flags to track progress through a puzzle sequence.

4. **Darkness mechanics**: Use the built-in light source mechanics to create areas that require a light source.

5. **Object transformations**: Move one object to room 0 (destroyed) and bring another into play.

6. **Randomized events**: Use automatic actions with percentage chances to create occasional events.

7. **Room state changes**: Use the room exchange feature to implement rooms that change state (e.g., before/after explosion).

### Limitations and Workarounds

1. **Two-word parser**: The engine only recognizes commands with a verb and optional noun, so complex commands must be simplified.

2. **Limited vocabulary**: Words are typically matched only on the first few letters, which can cause ambiguity.

3. **Object carrying limit**: Use containers or storage locations to help the player manage inventory.

4. **Linear action processing**: Actions are checked in order, which can lead to unexpected behavior if not carefully designed.

5. **Action entry limits**: Each action is limited to 5 conditions and 4 commands, but the CONT mechanism can chain multiple actions together.

## Reference

Implementation note: When evaluating conditions and executing actions, you'll need to decode the encoded values. The general approach is:

```
// For condition values encoded as (Parameter * 20) + ConditionCode
function DecodeCondition(encodedValue):
    conditionCode = encodedValue % 20
    parameter = encodedValue / 20  // Integer division
    return {code: conditionCode, parameter: parameter}

// For command values encoded as (150*CMD1 + CMD2)
function DecodeCommandPair(encodedValue):
    command2 = encodedValue % 150
    command1 = encodedValue / 150  // Integer division
    return {cmd1: command1, cmd2: command2}

// For vocabulary values encoded as (Verb * 150) + Noun
function DecodeVocab(encodedValue):
    noun = encodedValue % 150
    verb = encodedValue / 150  // Integer division
    return {verb: verb, noun: noun}
```

### Condition Codes

The condition codes determine when actions can be executed. Here's how to implement the condition checking system:

| Code | Symbol | Description |
|------|---------|-------------|
| 0    | PAR     | Always true (parameter is passed to action) |
| 1    | HAS     | Player is carrying object [parameter] |
| 2    | IN/W    | Object [parameter] is in current room |
| 3    | AVL     | Object [parameter] is carried or in current room |
| 4    | IN      | Player is in room [parameter] |
| 5    | -IN/W   | Object [parameter] is not in current room |
| 6    | -HAVE   | Player is not carrying object [parameter] |
| 7    | -IN     | Player is not in room [parameter] |
| 8    | BIT     | Bit flag [parameter] is set |
| 9    | -BIT    | Bit flag [parameter] is not set |
| 10   | ANY     | Player is carrying at least one object |
| 11   | -ANY    | Player is not carrying any objects |
| 12   | -AVL    | Object [parameter] is not carried or in current room |
| 13   | -RM0    | Object [parameter] is not in room 0 (not destroyed) |
| 14   | RM0     | Object [parameter] is in room 0 (destroyed) |
| 15   | CT<=    | Counter <= [parameter] |
| 16   | CT>     | Counter > [parameter] |
| 17   | ORIG    | Object [parameter] is in its original location |
| 18   | -ORIG   | Object [parameter] is not in its original location |
| 19   | CT=     | Counter = [parameter] |

### Action Codes

These action codes define what happens when conditions are met. Here's how to implement the command execution system:

| Code | Name    | Description |
|------|---------|-------------|
| 0    | -       | No action (displays message 0) |
| 1-51 | -       | Display message number 1-51 |
| 52   | GETx    | Pick up object x (fail if carrying too many objects) |
| 53   | DROPx   | Drop object x in current room |
| 54   | GOTOy   | Move player to room y |
| 55   | x->RM0  | Move object x to room 0 (destroy it) |
| 56   | NIGHT   | Set darkness bit (15) |
| 57   | DAY     | Clear darkness bit (15) |
| 58   | SETz    | Set bit flag z |
| 59   | x->RM0  | Move object x to room 0 (duplicate of 55) |
| 60   | CLRz    | Clear bit flag z |
| 61   | DEAD    | Kill player (move to last room, show death message) |
| 62   | x->y    | Move object x to room y |
| 63   | FINI    | End game |
| 64   | DspRM   | Show room description |
| 65   | SCORE   | Show score (based on treasures stored) |
| 66   | INV     | Show inventory |
| 67   | SET0    | Set bit flag 0 |
| 68   | CLR0    | Clear bit flag 0 |
| 69   | FILL    | Refill light source |
| 70   | CLS     | Clear screen |
| 71   | SAVE    | Save game |
| 72   | EXx, x   | Swap locations of two objects |
| 73   | CONT    | Continue executing actions (don't stop after this one) |
| 74   | AGETx   | Pick up object x (no carrying capacity check) |
| 75   | BYx<-x  | Object x gets location of object y |
| 76   | DspRM   | Show room description (duplicate of 64) |
| 77   | CT-1    | Decrement counter |
| 78   | DspCT   | Display counter value |
| 79   | CT<-n   | Set counter to n |
| 80   | EXRM0   | Swap current room with alternate room 0 |
| 81   | EXm, CT  | Swap counter with alternate counter m |
| 82   | CT+n    | Add n to counter |
| 83   | CT-n    | Subtract n from counter (minimum -1) |
| 84   | SAYw    | Display noun entered by player |
| 85   | SAYwCR  | Display noun entered by player with newline |
| 86   | SAYCR   | Display newline |
| 87   | EXc, CR  | Swap current room with alternate room c |
| 88   | DELAY   | Pause for a moment |
| 89-101| -      | Undefined in version 8.2 |
| 102-149| -     | Display messages 52-99 |

### Special Locations and Constants

| Constant | Value | Description |
|----------|-------|-------------|
| LIGHT_SOURCE | 9 | Object ID for the light source |
| CARRIED | 255 | Location value for carried objects |
| DESTROYED | 0 | Location value for destroyed objects |
| DARKBIT | 15 | Bit flag for darkness |
| LIGHTOUTBIT | 16 | Bit flag for light running out |
| ROOM_INVENTORY | -1 | Object is in player's inventory |
| ROOM_STORE | 0 | Object is in storage/destroyed |

### Flag Bits

There are 32 flag bits (0-31) that track game state. Two have special meanings:
* 15: Darkness flag - When set, rooms are dark unless the light source is present
* 16: Light source empty flag - Set when the artificial light has run out
