package main

import (
	"bufio"
	"fmt"
	"math/rand"
	"os"
	"strconv"
	"strings"
	"time"
	"unicode"
)

// Constants for special locations and flags
const (
	// Item locations
	CARRIED   = 255 // Item is carried by player
	DESTROYED = 0   // Item is in room 0 (not in game)

	// Special item IDs
	LIGHT_SOURCE = 9 // Item ID for the light source

	// Special bit flags
	DARKBIT     = 15 // Bit flag for darkness
	LIGHTOUTBIT = 16 // Bit flag for light running out

	// Direction constants
	NORTH = 0
	SOUTH = 1
	EAST  = 2
	WEST  = 3
	UP    = 4
	DOWN  = 5
)

// GameHeader contains configuration values for the game
type GameHeader struct {
	TextStorageBytes int // Number of bytes for text storage
	NumItems         int // Highest numbered object
	NumActions       int // Highest numbered action
	NumWords         int // Number of vocabulary words
	NumRooms         int // Highest numbered room
	MaxCarry         int // Maximum items player can carry
	PlayerRoom       int // Starting room for the player
	Treasures        int // Number of treasures in the game
	WordLength       int // Word length for vocabulary matching
	LightTime        int // Turns of light available
	NumMessages      int // Number of messages
	TreasureRoom     int // Room where treasures should be stored
	AdventureVersion int // Version number of the adventure
	AdventureNumber  int // Unique identifier for the adventure
}

// Room represents a location in the game world
type Room struct {
	Exits       [6]int // North, South, East, West, Up, Down
	Description string
}

// Item represents an object that can be manipulated
type Item struct {
	Description      string
	Location         int
	OriginalLocation int
	AutoGet          string // Text after "/" in description
}

// Action represents a game action with conditions and commands
type Action struct {
	Verb       int
	Noun       int
	Conditions [5]int
	Commands   [2]int
}

// Word represents a vocabulary word that can be used in the game
type Word struct {
	Word      string
	IsSynonym bool   // True if this is a synonym (starts with *)
	Type      string // "verb" or "noun"
}

// GameState represents the complete state of the game
type GameState struct {
	Header        GameHeader
	Rooms         []Room
	Items         []Item
	Actions       []Action
	Words         []Word
	Messages      []string
	ActionTitles  []string
	CurrentRoom   int
	ItemLocations []int
	BitFlags      uint32 // 32 bit flags
	Counter       int
	AltCounters   [9]int // 0-7 are general, 8 is light time
	AltRooms      [6]int // Alternate room registers
	ContinueFlag  bool
	DisplayedRoom bool // Whether room has been displayed this turn
	Debug         bool // Enable debugging output
	CurrentAction int  // Index of the action currently being executed
}

// NewGameState creates a new game state with default values
func NewGameState() *GameState {
	return &GameState{
		BitFlags:      0,
		Counter:       0,
		ContinueFlag:  false,
		DisplayedRoom: false,
		Debug:         false,
	}
}

// LoadGameData loads the game data from the specified file
func LoadGameData(filename string) (*GameState, error) {
	// Read the entire file content
	content, err := os.ReadFile(filename)
	if err != nil {
		return nil, fmt.Errorf("failed to read game file: %w", err)
	}

	// Parse the content
	tokens, err := tokenizeGameData(string(content))
	if err != nil {
		return nil, err
	}

	state := NewGameState()
	tokenIndex := 0

	// Read header values (first 12 values)
	headerValues := make([]int, 12)
	for i := 0; i < 12; i++ {
		if tokenIndex >= len(tokens) {
			return nil, fmt.Errorf("unexpected end of file while reading header")
		}

		val, err := strconv.Atoi(tokens[tokenIndex])
		if err != nil {
			return nil, fmt.Errorf("invalid header value %d: %s", i, tokens[tokenIndex])
		}
		headerValues[i] = val
		tokenIndex++
	}

	// Set header values
	state.Header = GameHeader{
		TextStorageBytes: headerValues[0],
		NumItems:         headerValues[1],
		NumActions:       headerValues[2],
		NumWords:         headerValues[3],
		NumRooms:         headerValues[4],
		MaxCarry:         headerValues[5],
		PlayerRoom:       headerValues[6],
		Treasures:        headerValues[7],
		WordLength:       headerValues[8],
		LightTime:        headerValues[9],
		NumMessages:      headerValues[10],
		TreasureRoom:     headerValues[11],
	}

	// Read actions (each action consists of 8 numbers)
	state.Actions = make([]Action, state.Header.NumActions+1)
	for i := 0; i <= state.Header.NumActions; i++ {
		var action Action

		// Read vocabulary value (verb/noun pair)
		if tokenIndex >= len(tokens) {
			return nil, fmt.Errorf("unexpected end of file while reading action %d vocabulary", i)
		}

		vocab, err := strconv.Atoi(tokens[tokenIndex])
		if err != nil {
			return nil, fmt.Errorf("invalid action %d vocabulary: %s", i, tokens[tokenIndex])
		}
		action.Verb = vocab / 150
		action.Noun = vocab % 150
		tokenIndex++

		// Read 5 conditions
		for j := 0; j < 5; j++ {
			if tokenIndex >= len(tokens) {
				return nil, fmt.Errorf("unexpected end of file while reading action %d condition %d", i, j)
			}

			cond, err := strconv.Atoi(tokens[tokenIndex])
			if err != nil {
				return nil, fmt.Errorf("invalid action %d condition %d: %s", i, j, tokens[tokenIndex])
			}
			action.Conditions[j] = cond
			tokenIndex++
		}

		// Read 2 commands
		for j := 0; j < 2; j++ {
			if tokenIndex >= len(tokens) {
				return nil, fmt.Errorf("unexpected end of file while reading action %d command %d", i, j)
			}

			cmd, err := strconv.Atoi(tokens[tokenIndex])
			if err != nil {
				return nil, fmt.Errorf("invalid action %d command %d: %s", i, j, tokens[tokenIndex])
			}
			action.Commands[j] = cmd
			tokenIndex++
		}

		state.Actions[i] = action
	}

	// Read vocabulary words (quoted strings)
	vocabulary := []string{}
	for tokenIndex < len(tokens) {
		token := tokens[tokenIndex]
		if !strings.HasPrefix(token, "\"") {
			break // End of vocabulary section
		}

		vocabulary = append(vocabulary, token)
		tokenIndex++
	}

	// Process vocabulary words
	verbCount := 0
	nounCount := 0

	state.Words = make([]Word, len(vocabulary))
	for i, wordText := range vocabulary {
		// Remove quotes
		wordText = wordText[1 : len(wordText)-1]

		var word Word
		if strings.HasPrefix(wordText, "*") {
			// Synonym - starts with *
			word.IsSynonym = true
			word.Word = wordText[1:] // Remove *
		} else {
			word.IsSynonym = false
			word.Word = wordText
		}

		// In Scott Adams format, verbs are listed first, then nouns
		// We need to make a best guess which is which
		if verbCount < (state.Header.NumWords+1)/2 && !word.IsSynonym {
			word.Type = "verb"
			verbCount++
		} else {
			word.Type = "noun"
			nounCount++
		}

		state.Words[i] = word
	}

	// Read rooms (6 exit numbers followed by a quoted description)
	state.Rooms = make([]Room, state.Header.NumRooms+1)
	for i := 0; i <= state.Header.NumRooms; i++ {
		var room Room

		// Read 6 exit numbers (N, S, E, W, U, D)
		for j := 0; j < 6; j++ {
			if tokenIndex >= len(tokens) {
				return nil, fmt.Errorf("unexpected end of file while reading room %d exit %d", i, j)
			}

			exit, err := strconv.Atoi(tokens[tokenIndex])
			if err != nil {
				return nil, fmt.Errorf("invalid room %d exit %d: %s", i, j, tokens[tokenIndex])
			}
			room.Exits[j] = exit
			tokenIndex++
		}

		// Read description (quoted string)
		if tokenIndex >= len(tokens) {
			return nil, fmt.Errorf("unexpected end of file while reading room %d description", i)
		}

		desc := tokens[tokenIndex]
		if !strings.HasPrefix(desc, "\"") {
			return nil, fmt.Errorf("invalid room description format for room %d: %s", i, desc)
		}

		room.Description = desc[1 : len(desc)-1]
		tokenIndex++

		state.Rooms[i] = room
	}

	// Read messages (quoted strings)
	state.Messages = make([]string, state.Header.NumMessages+1)
	for i := 0; i <= state.Header.NumMessages; i++ {
		if tokenIndex >= len(tokens) {
			return nil, fmt.Errorf("unexpected end of file while reading message %d", i)
		}

		msg := tokens[tokenIndex]
		if !strings.HasPrefix(msg, "\"") {
			return nil, fmt.Errorf("invalid message format for message %d: %s", i, msg)
		}

		state.Messages[i] = msg[1 : len(msg)-1]
		tokenIndex++
	}

	// Read items (quoted description followed by location number)
	state.Items = make([]Item, state.Header.NumItems+1)
	state.ItemLocations = make([]int, state.Header.NumItems+1)
	for i := 0; i <= state.Header.NumItems; i++ {
		var item Item

		// Read description (quoted string)
		if tokenIndex >= len(tokens) {
			return nil, fmt.Errorf("unexpected end of file while reading item %d description", i)
		}

		desc := tokens[tokenIndex]
		if !strings.HasPrefix(desc, "\"") {
			return nil, fmt.Errorf("invalid item description format for item %d: %s", i, desc)
		}

		item.Description = desc[1 : len(desc)-1]
		tokenIndex++

		// Check for AutoGet word
		parts := strings.Split(item.Description, "/")
		if len(parts) > 1 {
			item.Description = parts[0]
			if len(parts) > 2 {
				item.AutoGet = parts[1]
			}
		}

		// Read location
		if tokenIndex >= len(tokens) {
			return nil, fmt.Errorf("unexpected end of file while reading item %d location", i)
		}

		loc, err := strconv.Atoi(tokens[tokenIndex])
		if err != nil {
			return nil, fmt.Errorf("invalid item %d location: %s", i, tokens[tokenIndex])
		}
		item.Location = loc
		item.OriginalLocation = loc
		state.ItemLocations[i] = loc
		tokenIndex++

		state.Items[i] = item
	}

	// Read action titles (quoted strings)
	state.ActionTitles = make([]string, state.Header.NumActions+1)
	actionTitleCount := 0
	for tokenIndex < len(tokens) && actionTitleCount <= state.Header.NumActions {
		token := tokens[tokenIndex]
		if !strings.HasPrefix(token, "\"") {
			break // Not a quoted string, might be trailer information
		}

		state.ActionTitles[actionTitleCount] = token[1 : len(token)-1]
		actionTitleCount++
		tokenIndex++
	}

	// Read trailer information
	// - Version
	if tokenIndex >= len(tokens) {
		return nil, fmt.Errorf("unexpected end of file while reading adventure version")
	}

	version, err := strconv.Atoi(tokens[tokenIndex])
	if err != nil {
		return nil, fmt.Errorf("invalid adventure version: %s", tokens[tokenIndex])
	}
	state.Header.AdventureVersion = version
	tokenIndex++

	// - Adventure number
	if tokenIndex >= len(tokens) {
		return nil, fmt.Errorf("unexpected end of file while reading adventure number")
	}

	advNum, err := strconv.Atoi(tokens[tokenIndex])
	if err != nil {
		return nil, fmt.Errorf("invalid adventure number: %s", tokens[tokenIndex])
	}
	state.Header.AdventureNumber = advNum
	tokenIndex++

	// - Checksum
	if tokenIndex >= len(tokens) {
		return nil, fmt.Errorf("unexpected end of file while reading adventure checksum")
	}

	checksum, err := strconv.Atoi(tokens[tokenIndex])
	if err != nil {
		return nil, fmt.Errorf("invalid adventure checksum: %s", tokens[tokenIndex])
	}

	// Verify checksum
	expectedChecksum := (2 * state.Header.NumActions) + state.Header.NumItems + state.Header.AdventureVersion
	if checksum != expectedChecksum {
		return nil, fmt.Errorf("checksum verification failed. Expected %d, got %d", expectedChecksum, checksum)
	}

	// Initialize game state
	state.CurrentRoom = state.Header.PlayerRoom
	state.AltCounters[8] = state.Header.LightTime // Initialize light time counter

	return state, nil
}

// tokenizeGameData parses the game data content and returns a list of tokens
// This handles multi-line quoted strings correctly
func tokenizeGameData(content string) ([]string, error) {
	var tokens []string
	var currentToken strings.Builder
	inQuotes := false
	i := 0

	for i < len(content) {
		char := content[i]

		switch {
		case char == '"':
			// Start or end of a quoted string
			if inQuotes {
				// End of quoted string
				currentToken.WriteByte(char)
				tokens = append(tokens, currentToken.String())
				currentToken.Reset()
				inQuotes = false
			} else {
				// Start of quoted string
				if currentToken.Len() > 0 {
					// If we have a partial token, add it first
					tokens = append(tokens, currentToken.String())
					currentToken.Reset()
				}
				currentToken.WriteByte(char)
				inQuotes = true
			}

		case inQuotes:
			// Inside a quoted string - just add the character
			currentToken.WriteByte(char)

		case char == '\n' || char == '\r':
			// End of line (outside quotes)
			if currentToken.Len() > 0 {
				tokens = append(tokens, currentToken.String())
				currentToken.Reset()
			}

		case char == '/':
			// Possible comment
			if i+1 < len(content) && content[i+1] == '/' {
				// Skip to the end of the line
				for i+1 < len(content) && content[i+1] != '\n' && content[i+1] != '\r' {
					i++
				}
			} else {
				currentToken.WriteByte(char)
			}

		case !unicode.IsSpace(rune(char)):
			// Non-whitespace character
			currentToken.WriteByte(char)

		case unicode.IsSpace(rune(char)):
			// Whitespace character outside quotes
			if currentToken.Len() > 0 {
				tokens = append(tokens, currentToken.String())
				currentToken.Reset()
			}
		}

		i++
	}

	// Add the last token if there is one
	if currentToken.Len() > 0 {
		tokens = append(tokens, currentToken.String())
	}

	// Check if quotes are balanced
	if inQuotes {
		return nil, fmt.Errorf("unbalanced quotes in game data")
	}

	return tokens, nil
}

// Main function - entry point for the interpreter
func main() {
	// Seed random number generator
	rand.Seed(time.Now().UnixNano())

	// Parse command line arguments
	if len(os.Args) < 2 {
		fmt.Println("Usage: adventure <game_file>")
		os.Exit(1)
	}

	// Load game data
	state, err := LoadGameData(os.Args[1])
	if err != nil {
		fmt.Printf("Error loading game data: %v\n", err)
		os.Exit(1)
	}

	// Start the game
	fmt.Printf("Scott Adams Adventure Interpreter\n")
	fmt.Printf("Adventure %d: Version %d.%02d\n\n",
		state.Header.AdventureNumber,
		state.Header.AdventureVersion/100,
		state.Header.AdventureVersion%100)

	// Display introduction message (typically message #1)
	if len(state.Messages) > 1 {
		fmt.Println(state.Messages[1])
	}

	// Enable debug mode with -debug flag
	for _, arg := range os.Args {
		if arg == "-debug" {
			state.Debug = true
			fmt.Println("Debug mode enabled")
			DumpVocabulary(state)
		}
	}

	// Main game loop
	RunGame(state)
}

// DumpVocabulary prints all vocabulary words (helpful for debugging)
func DumpVocabulary(state *GameState) {
	fmt.Println("\n--- Vocabulary Dump ---")
	fmt.Println("Index | Type | Word")
	fmt.Println("------|------|------")

	for i, word := range state.Words {
		// Skip if index is out of bounds
		if i > state.Header.NumWords {
			continue
		}

		synonymMark := " "
		if word.IsSynonym {
			synonymMark = "*"
		}

		fmt.Printf("%5d | %4s | %s%s\n", i, word.Type, synonymMark, word.Word)
	}

	fmt.Println("----------------------\n")
}

// RunGame implements the main game loop
func RunGame(state *GameState) {
	reader := bufio.NewReader(os.Stdin)

	for {
		// Process automatic actions
		ProcessAutomaticActions(state)

		// Display current location if not already displayed this turn
		if !state.DisplayedRoom {
			DisplayCurrentLocation(state)
			state.DisplayedRoom = true
		}

		// Get player input
		fmt.Print("> ")
		input, _ := reader.ReadString('\n')
		input = strings.TrimSpace(input)

		// Reset room display flag for next turn
		state.DisplayedRoom = false

		// Handle quit command
		if strings.ToUpper(input) == "QUIT" {
			fmt.Println("Thanks for playing!")
			break
		}

		// Process player command
		ProcessCommand(state, input)

		// Update light source status
		UpdateLightSource(state)
	}
}

// ParseCommand converts player input into verb/noun numbers
func ParseCommand(state *GameState, words []string) (int, int) {
	verb := 0
	noun := 0

	if len(words) > 0 {
		verb = GetWordNumber(state, words[0], "verb")
	}

	if len(words) > 1 {
		noun = GetWordNumber(state, words[1], "noun")
	}

	// Special case for GO + direction
	// In Scott Adams format, directions in vocabulary are:
	// NORTH=1, SOUTH=2, EAST=3, WEST=4, UP=5, DOWN=6
	if verb == 1 && len(words) > 1 { // GO
		directionMap := map[string]int{
			"NORTH": 1,
			"SOUTH": 2,
			"EAST":  3,
			"WEST":  4,
			"UP":    5,
			"DOWN":  6,
			"N":     1,
			"S":     2,
			"E":     3,
			"W":     4,
			"U":     5,
			"D":     6,
		}

		if dirIndex, ok := directionMap[words[1]]; ok {
			noun = dirIndex
			if state.Debug {
				fmt.Printf("[DEBUG] GO direction mapped: %s -> %d\n", words[1], noun)
			}
		}
	}

	return verb, noun
}

// GetWordNumber returns the index of a word in the vocabulary
func GetWordNumber(state *GameState, word string, wordType string) int {
	// Truncate word to match game's word length
	if len(word) > state.Header.WordLength {
		word = word[:state.Header.WordLength]
	}

	// Special case for direction words (make sure they map correctly)
	if wordType == "noun" {
		directionMap := map[string]int{
			"NORTH": 1,
			"SOUTH": 2,
			"EAST":  3,
			"WEST":  4,
			"UP":    5,
			"DOWN":  6,
			"N":     1,
			"S":     2,
			"E":     3,
			"W":     4,
			"U":     5,
			"D":     6,
		}

		if index, ok := directionMap[word]; ok {
			return index
		}
	}

	// Check for exact match
	for i, w := range state.Words {
		if !w.IsSynonym && w.Type == wordType && strings.EqualFold(w.Word, word) {
			if state.Debug {
				fmt.Printf("[DEBUG] Exact word match: '%s' -> %d ('%s')\n", word, i, w.Word)
			}
			return i
		}
	}

	// Check for prefix match (Scott Adams only matches on first few letters)
	for i, w := range state.Words {
		if !w.IsSynonym && w.Type == wordType && strings.HasPrefix(strings.ToUpper(w.Word), word) {
			if state.Debug {
				fmt.Printf("[DEBUG] Prefix word match: '%s' -> %d ('%s')\n", word, i, w.Word)
			}
			return i
		}
	}

	// Look for synonym exact match
	for i, w := range state.Words {
		if w.IsSynonym && w.Type == wordType && strings.EqualFold(w.Word, word) {
			// Find the previous non-synonym word
			for j := i - 1; j >= 0; j-- {
				if !state.Words[j].IsSynonym && state.Words[j].Type == wordType {
					if state.Debug {
						fmt.Printf("[DEBUG] Synonym exact match: '%s' -> %d\n", word, j)
					}
					return j
				}
			}
		}
	}

	// Look for synonym prefix match
	for i, w := range state.Words {
		if w.IsSynonym && w.Type == wordType && strings.HasPrefix(strings.ToUpper(w.Word), word) {
			// Find the previous non-synonym word
			for j := i - 1; j >= 0; j-- {
				if !state.Words[j].IsSynonym && state.Words[j].Type == wordType {
					if state.Debug {
						fmt.Printf("[DEBUG] Synonym prefix match: '%s' -> %d\n", word, j)
					}
					return j
				}
			}
		}
	}

	if state.Debug {
		fmt.Printf("[DEBUG] No match for word: '%s' (type: %s)\n", word, wordType)
	}
	return 0 // Not found
}

// ProcessAutomaticActions processes actions with verb=0
func ProcessAutomaticActions(state *GameState) {
	state.ContinueFlag = true

	for state.ContinueFlag {
		state.ContinueFlag = false

		for i, action := range state.Actions {
			// Process actions with verb=0 (automatic actions)
			if action.Verb != 0 {
				continue
			}

			// If noun > 0, it's a percentage chance of action happening
			if action.Noun > 0 {
				chance := rand.Intn(100) + 1
				if chance > action.Noun {
					continue
				}
			}

			// Check conditions
			if CheckConditions(state, i) {
				ExecuteCommands(state, i)
				if state.ContinueFlag {
					break // Start checking from beginning again
				}
			}
		}
	}
}

// ProcessActionsWithVerb checks actions matching player's verb/noun
func ProcessActionsWithVerb(state *GameState, verb int, noun int) {
	// First try exact verb+noun match
	if ProcessExactAction(state, verb, noun) {
		return
	}

	// Try verb with ANY noun (noun=0)
	if noun != 0 && ProcessExactAction(state, verb, 0) {
		return
	}

	// Handle built-in commands if no matching action
	if verb == 10 { // CARRY/GET
		GetItem(state, noun)
		return
	}

	if verb == 18 { // DROP
		DropItem(state, noun)
		return
	}

	// No matching action found
	fmt.Println("I don't understand how to do that.")
}

// ProcessExactAction checks and executes actions with exact verb/noun match
func ProcessExactAction(state *GameState, verb int, noun int) bool {
	found := false

	for i, action := range state.Actions {
		if action.Verb == verb && action.Noun == noun {
			if CheckConditions(state, i) {
				ExecuteCommands(state, i)
				found = true
				if !state.ContinueFlag {
					break
				}
			}
		}
	}

	return found
}

// CheckConditions verifies if all conditions for an action are met
func CheckConditions(state *GameState, actionIndex int) bool {
	action := state.Actions[actionIndex]

	// Each condition must be true for action to proceed
	for _, encodedCondition := range action.Conditions {
		if encodedCondition == 0 {
			continue // Condition code 0 (PAR) always returns true
		}

		conditionCode := encodedCondition % 20
		parameter := encodedCondition / 20

		if !EvaluateCondition(state, conditionCode, parameter) {
			return false
		}
	}

	return true
}

// EvaluateCondition checks a single condition
func EvaluateCondition(state *GameState, code int, parameter int) bool {
	switch code {
	case 0: // PAR - Always true (parameter is passed to action)
		return true
	case 1: // HAS - Player is carrying item [parameter]
		return state.ItemLocations[parameter] == CARRIED
	case 2: // IN/W - Item [parameter] is in current room
		return state.ItemLocations[parameter] == state.CurrentRoom
	case 3: // AVL - Item [parameter] is carried or in current room
		return state.ItemLocations[parameter] == CARRIED || state.ItemLocations[parameter] == state.CurrentRoom
	case 4: // IN - Player is in room [parameter]
		return state.CurrentRoom == parameter
	case 5: // -IN/W - Item [parameter] is not in current room
		return state.ItemLocations[parameter] != state.CurrentRoom
	case 6: // -HAVE - Player is not carrying item [parameter]
		return state.ItemLocations[parameter] != CARRIED
	case 7: // -IN - Player is not in room [parameter]
		return state.CurrentRoom != parameter
	case 8: // BIT - Bit flag [parameter] is set
		return state.BitFlags&(1<<uint(parameter)) != 0
	case 9: // -BIT - Bit flag [parameter] is not set
		return state.BitFlags&(1<<uint(parameter)) == 0
	case 10: // ANY - Player is carrying at least one item
		for i, loc := range state.ItemLocations {
			if i <= state.Header.NumItems && loc == CARRIED {
				return true
			}
		}
		return false
	case 11: // -ANY - Player is not carrying any items
		for i, loc := range state.ItemLocations {
			if i <= state.Header.NumItems && loc == CARRIED {
				return false
			}
		}
		return true
	case 12: // -AVL - Item [parameter] is not carried or in current room
		return state.ItemLocations[parameter] != CARRIED && state.ItemLocations[parameter] != state.CurrentRoom
	case 13: // -RM0 - Item [parameter] is not in room 0 (not destroyed)
		return state.ItemLocations[parameter] != DESTROYED
	case 14: // RM0 - Item [parameter] is in room 0 (destroyed)
		return state.ItemLocations[parameter] == DESTROYED
	case 15: // CT<= - Counter <= [parameter]
		return state.Counter <= parameter
	case 16: // CT> - Counter > [parameter]
		return state.Counter > parameter
	case 17: // ORIG - Item [parameter] is in its original location
		return state.ItemLocations[parameter] == state.Items[parameter].OriginalLocation
	case 18: // -ORIG - Item [parameter] is not in its original location
		return state.ItemLocations[parameter] != state.Items[parameter].OriginalLocation
	case 19: // CT= - Counter = [parameter]
		return state.Counter == parameter
	default:
		fmt.Printf("Unknown condition code: %d\n", code)
		return false
	}
}

// ExecuteCommands processes the commands for an action
func ExecuteCommands(state *GameState, actionIndex int) {
	// Store current action index for condition parameter access
	state.CurrentAction = actionIndex
	action := state.Actions[actionIndex]

	// Actions have two command "pairs"
	for i := 0; i < 2; i++ {
		cmd := action.Commands[i]
		if cmd == 0 {
			continue // No command
		}

		// Process first command in pair
		cmd1 := cmd / 150
		ExecuteCommand(state, cmd1, 0)

		// Process second command in pair
		cmd2 := cmd % 150
		ExecuteCommand(state, cmd2, i+1)
	}

	// Debug output
	if state.Debug {
		title := "Unknown"
		if actionIndex < len(state.ActionTitles) {
			title = state.ActionTitles[actionIndex]
		}
		fmt.Printf("[DEBUG] Executed action %d: %s\n", actionIndex, title)
	}
}

// ExecuteCommand processes a single command
func ExecuteCommand(state *GameState, cmd int, cmdPosition int) {
	// Get parameter from conditions if applicable
	parameter := 0
	if cmdPosition < 5 {
		condition := state.Actions[state.CurrentAction].Conditions[cmdPosition]
		parameter = condition / 20
	}

	// Command is a message to display (1-51)
	if cmd >= 1 && cmd <= 51 {
		fmt.Println(state.Messages[cmd])
		return
	}

	// Command is a message to display (52-99, encoded as 102-149)
	if cmd >= 102 && cmd <= 149 {
		fmt.Println(state.Messages[cmd-50])
		return
	}

	// Action commands (52-101)
	switch cmd {
	case 52: // GETx - Pick up item x (fail if carrying too many items)
		GetItem(state, parameter)
	case 53: // DROPx - Drop item x in current room
		DropItem(state, parameter)
	case 54: // GOTOy - Move player to room y
		state.CurrentRoom = parameter
		state.DisplayedRoom = false
	case 55, 59: // x->RM0 - Move item x to room 0 (destroy it)
		state.ItemLocations[parameter] = DESTROYED
	case 56: // NIGHT - Set darkness bit (15)
		state.BitFlags |= (1 << DARKBIT)
	case 57: // DAY - Clear darkness bit (15)
		state.BitFlags &= ^uint32(1 << DARKBIT)
	case 58: // SETz - Set bit flag z
		state.BitFlags |= (1 << uint(parameter))
	case 60: // CLRz - Clear bit flag z
		state.BitFlags &= ^(1 << uint(parameter))
	case 61: // DEAD - Kill player (move to last room, show death message)
		state.CurrentRoom = state.Header.NumRooms
		state.DisplayedRoom = false
	case 62: // x->y - Move item x to room y
		if cmdPosition < 5 {
			// Get the second parameter from the next condition
			nextCond := state.Actions[state.CurrentAction].Conditions[cmdPosition+1]
			nextParam := nextCond / 20
			state.ItemLocations[parameter] = nextParam
		}
	case 63: // FINI - End game
		fmt.Println("Game over! You've completed the adventure!")
		os.Exit(0)
	case 64, 76: // DspRM - Show room description
		state.DisplayedRoom = false
	case 65: // SCORE - Show score
		DisplayScore(state)
	case 66: // INV - Show inventory
		DisplayInventory(state)
	case 67: // SET0 - Set bit flag 0
		state.BitFlags |= (1 << 0)
	case 68: // CLR0 - Clear bit flag 0
		state.BitFlags &= ^uint32(1 << 0)
	case 69: // FILL - Refill light source
		state.AltCounters[8] = state.Header.LightTime
		state.BitFlags &= ^uint32(1 << LIGHTOUTBIT)
		// Move light source to inventory if not already there
		if state.ItemLocations[LIGHT_SOURCE] != CARRIED {
			state.ItemLocations[LIGHT_SOURCE] = CARRIED
		}
	case 70: // CLS - Clear screen
		fmt.Print("\033[H\033[2J") // ANSI escape sequence to clear screen
	case 71: // SAVE - Save game
		SaveGame(state)
	case 72: // EXx,x - Swap locations of two items
		if cmdPosition < 4 {
			item1 := parameter
			nextCond := state.Actions[state.CurrentAction].Conditions[cmdPosition+1]
			item2 := nextCond / 20

			// Swap locations
			state.ItemLocations[item1], state.ItemLocations[item2] = state.ItemLocations[item2], state.ItemLocations[item1]
		}
	case 73: // CONT - Continue executing actions
		state.ContinueFlag = true
	case 74: // AGETx - Pick up item x (no carrying capacity check)
		state.ItemLocations[parameter] = CARRIED
	case 75: // BYx<-x - Item x gets location of item y
		if cmdPosition < 4 {
			item1 := parameter
			nextCond := state.Actions[state.CurrentAction].Conditions[cmdPosition+1]
			item2 := nextCond / 20

			state.ItemLocations[item1] = state.ItemLocations[item2]
		}
	case 77: // CT-1 - Decrement counter
		state.Counter--
	case 78: // DspCT - Display counter value
		fmt.Printf("Counter = %d\n", state.Counter)
	case 79: // CT<-n - Set counter to n
		state.Counter = parameter
	case 80: // EXRM0 - Swap current room with alternate room 0
		state.CurrentRoom, state.AltRooms[0] = state.AltRooms[0], state.CurrentRoom
		state.DisplayedRoom = false
	case 81: // EXm,CT - Swap counter with alternate counter m
		state.Counter, state.AltCounters[parameter] = state.AltCounters[parameter], state.Counter
	case 82: // CT+n - Add n to counter
		state.Counter += parameter
	case 83: // CT-n - Subtract n from counter (minimum -1)
		state.Counter -= parameter
		if state.Counter < -1 {
			state.Counter = -1
		}
	case 84: // SAYw - Display noun entered by player
		// This would normally display the noun entered by the player
		// Since we don't track that separately, we'll just skip this
	case 85: // SAYwCR - Display noun entered by player with newline
		// Same as above but with newline
	case 86: // SAYCR - Display newline
		fmt.Println()
	case 87: // EXc,CR - Swap current room with alternate room c
		state.CurrentRoom, state.AltRooms[parameter] = state.AltRooms[parameter], state.CurrentRoom
		state.DisplayedRoom = false
	case 88: // DELAY - Pause for a moment
		time.Sleep(500 * time.Millisecond)
	}
}

// GetItem attempts to pick up an item
func GetItem(state *GameState, itemNumber int) {
	// Check if item exists
	if itemNumber <= 0 || itemNumber > state.Header.NumItems {
		fmt.Println("I don't see that here.")
		return
	}

	// Check if item is in current room
	if state.ItemLocations[itemNumber] != state.CurrentRoom {
		fmt.Println("I don't see that here.")
		if state.Debug {
			fmt.Printf("[DEBUG] Item %d is in room %d, not current room %d\n",
				itemNumber, state.ItemLocations[itemNumber], state.CurrentRoom)
		}
		return
	}

	// Count carried items
	carried := 0
	for i, loc := range state.ItemLocations {
		if i <= state.Header.NumItems && loc == CARRIED {
			carried++
		}
	}

	// Check if carrying too many items
	if carried >= state.Header.MaxCarry {
		fmt.Println("I'm carrying too much already.")
		return
	}

	// Pick up the item
	state.ItemLocations[itemNumber] = CARRIED
	fmt.Printf("I'm now carrying the %s\n", getItemDescription(state, itemNumber))

	if state.Debug {
		fmt.Printf("[DEBUG] Picked up item %d, now in inventory\n", itemNumber)
	}
}

// DropItem attempts to drop an item
func DropItem(state *GameState, itemNumber int) {
	// Check if item exists
	if itemNumber <= 0 || itemNumber > state.Header.NumItems {
		fmt.Println("I don't have that.")
		return
	}

	// Check if item is carried
	if state.ItemLocations[itemNumber] != CARRIED {
		fmt.Println("I don't have that.")
		if state.Debug {
			fmt.Printf("[DEBUG] Item %d is not carried, it's in room %d\n",
				itemNumber, state.ItemLocations[itemNumber])
		}
		return
	}

	// Drop the item
	state.ItemLocations[itemNumber] = state.CurrentRoom
	fmt.Printf("I've dropped the %s\n", getItemDescription(state, itemNumber))

	if state.Debug {
		fmt.Printf("[DEBUG] Dropped item %d, now in room %d\n", itemNumber, state.CurrentRoom)
	}
}

// getItemDescription returns a clean description of an item
func getItemDescription(state *GameState, itemNumber int) string {
	if itemNumber < 0 || itemNumber > state.Header.NumItems {
		return "unknown item"
	}

	desc := state.Items[itemNumber].Description

	// Remove any asterisks (used to mark treasures)
	desc = strings.ReplaceAll(desc, "*", "")

	// Remove any AutoGet part if present
	if idx := strings.Index(desc, "/"); idx != -1 {
		desc = desc[:idx]
	}

	return strings.TrimSpace(desc)
}

// MovePlayer attempts to move the player in a given direction
func MovePlayer(state *GameState, direction int) {
	// Check if room is dark with no light source
	if IsDark(state) {
		// Movement in the dark is dangerous
		if rand.Intn(100) < 25 { // 25% chance of death when moving in darkness
			fmt.Println("I fell into a pit and broke every bone in my body!")
			state.CurrentRoom = state.Header.NumRooms // Last room is typically "death" room
			state.DisplayedRoom = false
			return
		}
	}

	// Check if direction is valid
	nextRoom := state.Rooms[state.CurrentRoom].Exits[direction]
	if nextRoom == 0 {
		fmt.Println("I can't go that way.")
		return
	}

	// Move player to new room
	state.CurrentRoom = nextRoom
	state.DisplayedRoom = false
}

// DisplayInventory shows the items the player is carrying
func DisplayInventory(state *GameState) {
	fmt.Println("I'm carrying:")

	count := 0
	for i, loc := range state.ItemLocations {
		if i <= state.Header.NumItems && loc == CARRIED {
			count++
			fmt.Printf("- %s\n", getItemDescription(state, i))
		}
	}

	if count == 0 {
		fmt.Println("Nothing.")
	}
}

// DisplayScore calculates and shows the player's score
func DisplayScore(state *GameState) {
	treasureCount := 0
	totalTreasures := state.Header.Treasures

	for i, loc := range state.ItemLocations {
		if i <= state.Header.NumItems && loc == state.Header.TreasureRoom {
			// Check if item is a treasure (description starts with *)
			if strings.Contains(state.Items[i].Description, "*") {
				treasureCount++
			}
		}
	}

	fmt.Printf("I've stored %d treasures.\n", treasureCount)
	fmt.Printf("On a scale of 0 to 100, that rates a %d.\n", (treasureCount*100)/totalTreasures)

	if treasureCount == totalTreasures {
		fmt.Println("Well done! You've found all the treasures!")
	}
}

// DisplayHelp shows help information
func DisplayHelp(state *GameState) {
	fmt.Println("Commands you can use:")
	fmt.Println("- Direction commands: NORTH (N), SOUTH (S), EAST (E), WEST (W), UP (U), DOWN (D)")
	fmt.Println("- GET/TAKE [item]: Pick up an item")
	fmt.Println("- DROP [item]: Drop an item you're carrying")
	fmt.Println("- INVENTORY/I: See what you're carrying")
	fmt.Println("- LOOK: Look around again")
	fmt.Println("- SCORE: See your current score")
	fmt.Println("- SAVE/LOAD: Save or load your game")
	fmt.Println("- QUIT: End the game")
}

// UpdateLightSource handles light source time limit
func UpdateLightSource(state *GameState) {
	// Only update if light source is carried and lit
	if state.ItemLocations[LIGHT_SOURCE] == CARRIED && !IsDark(state) {
		// Decrement light time
		state.AltCounters[8]--

		// Check if light has run out
		if state.AltCounters[8] <= 0 {
			state.BitFlags |= (1 << LIGHTOUTBIT)
			fmt.Println("Light has run out!")

			// Move light source to room 0 (destroyed)
			state.ItemLocations[LIGHT_SOURCE] = DESTROYED
		} else if state.AltCounters[8] <= 10 {
			// Warning when light is running low
			fmt.Println("Light is getting dim.")
		}
	}
}

// SaveGame saves the current game state
func SaveGame(state *GameState) {
	fmt.Print("Enter filename to save: ")
	scanner := bufio.NewScanner(os.Stdin)
	scanner.Scan()
	filename := scanner.Text()

	if filename == "" {
		filename = "adventure.sav"
	}

	file, err := os.Create(filename)
	if err != nil {
		fmt.Printf("Error creating save file: %v\n", err)
		return
	}
	defer file.Close()

	// Write game state
	fmt.Fprintf(file, "%d\n", state.Header.AdventureNumber)
	fmt.Fprintf(file, "%d\n", state.CurrentRoom)
	fmt.Fprintf(file, "%d\n", state.Counter)
	fmt.Fprintf(file, "%d\n", state.BitFlags)
	fmt.Fprintf(file, "%d\n", state.AltCounters[8]) // Light time

	// Write alternate rooms
	for i := 0; i < 6; i++ {
		fmt.Fprintf(file, "%d\n", state.AltRooms[i])
	}

	// Write alternate counters
	for i := 0; i < 8; i++ {
		fmt.Fprintf(file, "%d\n", state.AltCounters[i])
	}

	// Write item locations
	for i := 0; i <= state.Header.NumItems; i++ {
		fmt.Fprintf(file, "%d\n", state.ItemLocations[i])
	}

	fmt.Println("Game saved.")
}

// LoadGame loads a saved game state
func LoadGame(state *GameState) {
	fmt.Print("Enter filename to load: ")
	scanner := bufio.NewScanner(os.Stdin)
	scanner.Scan()
	filename := scanner.Text()

	if filename == "" {
		filename = "adventure.sav"
	}

	file, err := os.Open(filename)
	if err != nil {
		fmt.Printf("Error opening save file: %v\n", err)
		return
	}
	defer file.Close()

	scanner = bufio.NewScanner(file)

	// Read adventure number and verify
	if !scanner.Scan() {
		fmt.Println("Error reading save file.")
		return
	}
	advNum, _ := strconv.Atoi(scanner.Text())
	if advNum != state.Header.AdventureNumber {
		fmt.Println("This save file is for a different adventure.")
		return
	}

	// Read game state
	if !scanner.Scan() {
		fmt.Println("Error reading save file.")
		return
	}
	state.CurrentRoom, _ = strconv.Atoi(scanner.Text())

	if !scanner.Scan() {
		fmt.Println("Error reading save file.")
		return
	}
	state.Counter, _ = strconv.Atoi(scanner.Text())

	if !scanner.Scan() {
		fmt.Println("Error reading save file.")
		return
	}
	flags, _ := strconv.ParseUint(scanner.Text(), 10, 32)
	state.BitFlags = uint32(flags)

	if !scanner.Scan() {
		fmt.Println("Error reading save file.")
		return
	}
	state.AltCounters[8], _ = strconv.Atoi(scanner.Text())

	// Read alternate rooms
	for i := 0; i < 6; i++ {
		if !scanner.Scan() {
			fmt.Println("Error reading save file.")
			return
		}
		state.AltRooms[i], _ = strconv.Atoi(scanner.Text())
	}

	// Read alternate counters
	for i := 0; i < 8; i++ {
		if !scanner.Scan() {
			fmt.Println("Error reading save file.")
			return
		}
		state.AltCounters[i], _ = strconv.Atoi(scanner.Text())
	}

	// Read item locations
	for i := 0; i <= state.Header.NumItems; i++ {
		if !scanner.Scan() {
			fmt.Println("Error reading save file.")
			return
		}
		state.ItemLocations[i], _ = strconv.Atoi(scanner.Text())
	}

	fmt.Println("Game loaded.")
	state.DisplayedRoom = false
}

// DisplayCurrentLocation shows the current room and its contents
func DisplayCurrentLocation(state *GameState) {
	// Check if room is dark
	if IsDark(state) {
		fmt.Println("It is too dark to see")
		return
	}

	room := state.Rooms[state.CurrentRoom]

	// Display room description
	if strings.HasPrefix(room.Description, "*") {
		// Direct description (without "I'm in a" prefix)
		fmt.Println(strings.TrimPrefix(room.Description, "*"))
	} else {
		// Prefixed description
		fmt.Printf("I'm in a %s\n", room.Description)
	}

	// Display visible items
	for i, loc := range state.ItemLocations {
		if i <= state.Header.NumItems && loc == state.CurrentRoom {
			desc := state.Items[i].Description
			// Remove AutoGet part if present
			if idx := strings.Index(desc, "/"); idx != -1 {
				desc = desc[:idx]
			}

			fmt.Printf("I can see %s here\n", desc)
		}
	}

	// Display available exits
	exits := []string{}
	if room.Exits[NORTH] != 0 {
		exits = append(exits, "NORTH")
	}
	if room.Exits[SOUTH] != 0 {
		exits = append(exits, "SOUTH")
	}
	if room.Exits[EAST] != 0 {
		exits = append(exits, "EAST")
	}
	if room.Exits[WEST] != 0 {
		exits = append(exits, "WEST")
	}
	if room.Exits[UP] != 0 {
		exits = append(exits, "UP")
	}
	if room.Exits[DOWN] != 0 {
		exits = append(exits, "DOWN")
	}

	if len(exits) > 0 {
		fmt.Printf("Obvious exits: %s\n", strings.Join(exits, ", "))
	} else {
		fmt.Println("Obvious exits: NONE")
	}
}

// IsDark checks if the current room is dark without a light source
func IsDark(state *GameState) bool {
	return (state.BitFlags&(1<<DARKBIT) != 0) &&
		state.ItemLocations[LIGHT_SOURCE] != CARRIED &&
		state.ItemLocations[LIGHT_SOURCE] != state.CurrentRoom
}

// ProcessCommand handles player input
func ProcessCommand(state *GameState, command string) {
	// Convert to uppercase and split into words
	command = strings.ToUpper(command)
	words := strings.Fields(command)

	if len(words) == 0 {
		return
	}

	// Handle single-letter direction shortcuts
	if len(words[0]) == 1 {
		switch words[0] {
		case "N":
			words[0] = "NORTH"
		case "S":
			words[0] = "SOUTH"
		case "E":
			words[0] = "EAST"
		case "W":
			words[0] = "WEST"
		case "U":
			words[0] = "UP"
		case "D":
			words[0] = "DOWN"
		}
	}

	// Handle special commands
	if words[0] == "I" || words[0] == "INV" || words[0] == "INVENTORY" {
		DisplayInventory(state)
		return
	}

	if words[0] == "LOOK" {
		state.DisplayedRoom = false
		return
	}

	if words[0] == "SAVE" {
		SaveGame(state)
		return
	}

	if words[0] == "LOAD" || (len(words) > 1 && words[0] == "RESTORE" && words[1] == "GAME") {
		LoadGame(state)
		return
	}

	if words[0] == "SCORE" {
		DisplayScore(state)
		return
	}

	if words[0] == "DEBUG" {
		state.Debug = !state.Debug
		fmt.Printf("Debug mode: %v\n", state.Debug)
		return
	}

	if words[0] == "HELP" {
		DisplayHelp(state)
		return
	}

	// Handle single direction commands (e.g. "NORTH" instead of "GO NORTH")
	directionWords := map[string]int{
		"NORTH": 0,
		"SOUTH": 1,
		"EAST":  2,
		"WEST":  3,
		"UP":    4,
		"DOWN":  5,
	}

	if dir, ok := directionWords[words[0]]; ok {
		MovePlayer(state, dir)
		return
	}

	// Special case for "GO" + direction
	if strings.EqualFold(words[0], "GO") && len(words) > 1 {
		directionWords := map[string]int{
			"NORTH": 0,
			"SOUTH": 1,
			"EAST":  2,
			"WEST":  3,
			"UP":    4,
			"DOWN":  5,
			"N":     0,
			"S":     1,
			"E":     2,
			"W":     3,
			"U":     4,
			"D":     5,
		}

		if dir, ok := directionWords[words[1]]; ok {
			if state.Debug {
				fmt.Printf("[DEBUG] Direct GO command: %s -> direction %d\n", words[1], dir)
			}
			MovePlayer(state, dir)
			return
		}
	}

	// Special case for GET/TAKE + item
	if (strings.EqualFold(words[0], "GET") || strings.EqualFold(words[0], "TAKE")) && len(words) > 1 {
		// Find the item in the current room
		itemIndex := FindItemByName(state, words[1])
		if itemIndex > 0 {
			if state.Debug {
				fmt.Printf("[DEBUG] Direct GET command for item %d (%s)\n", itemIndex, words[1])
			}
			GetItem(state, itemIndex)
			return
		}
	}

	// Special case for DROP + item
	if strings.EqualFold(words[0], "DROP") && len(words) > 1 {
		// Find the item in inventory
		itemIndex := FindItemByName(state, words[1])
		if itemIndex > 0 {
			if state.Debug {
				fmt.Printf("[DEBUG] Direct DROP command for item %d (%s)\n", itemIndex, words[1])
			}
			DropItem(state, itemIndex)
			return
		}
	}

	// Parse input to get verb and noun
	verb, noun := ParseCommand(state, words)

	if state.Debug {
		fmt.Printf("[DEBUG] Verb: %d, Noun: %d\n", verb, noun)
	}

	// Handle GO [direction] special case via action system
	if verb == 1 { // GO
		if noun >= 1 && noun <= 6 { // Direction nouns NORTH=1, SOUTH=2, etc.
			if state.Debug {
				fmt.Printf("[DEBUG] GO direction via action system: direction %d\n", noun-1)
			}
			MovePlayer(state, noun-1)
			return
		}
	}

	// Handle GET/TAKE special case via action system
	if verb == 10 { // GET/TAKE
		if noun > 0 {
			if state.Debug {
				fmt.Printf("[DEBUG] GET item via action system: item %d\n", noun)
			}
			GetItem(state, noun)
			return
		}
	}

	// Handle DROP special case via action system
	if verb == 18 { // DROP
		if noun > 0 {
			if state.Debug {
				fmt.Printf("[DEBUG] DROP item via action system: item %d\n", noun)
			}
			DropItem(state, noun)
			return
		}
	}

	// Process actions with matching verb/noun
	ProcessActionsWithVerb(state, verb, noun)
}

// FindItemByName looks for an item by its name
func FindItemByName(state *GameState, name string) int {
	// Convert name to uppercase and truncate if needed
	name = strings.ToUpper(name)
	if len(name) > state.Header.WordLength {
		name = name[:state.Header.WordLength]
	}

	// Check each item
	for i, item := range state.Items {
		if i == 0 {
			continue // Skip item 0
		}

		// Extract the noun part from item description
		itemName := item.Description

		// If it has an AutoGet part, use that
		if item.AutoGet != "" {
			itemName = item.AutoGet
		} else {
			// Otherwise use the last word of the description
			parts := strings.Fields(itemName)
			if len(parts) > 0 {
				itemName = parts[len(parts)-1]
			}
		}

		itemName = strings.ToUpper(itemName)

		// Check if this noun matches
		if strings.HasPrefix(itemName, name) || strings.Contains(itemName, name) {
			if state.Debug {
				fmt.Printf("[DEBUG] Found item match: '%s' -> item %d (%s)\n", name, i, itemName)
			}
			return i
		}

		// Special case for mud
		if name == "MUD" && strings.Contains(strings.ToUpper(item.Description), "MUD") {
			if state.Debug {
				fmt.Printf("[DEBUG] Found mud special case: item %d\n", i)
			}
			return i
		}
	}

	if state.Debug {
		fmt.Printf("[DEBUG] No item match for: '%s'\n", name)
	}
	return 0 // Not found
}
