# claude-adventure

An attempt to demonstrate writing an adventure game interpreter using Claude 3.7 Sonnet with extended thinking in different programming languages.

## Example prompt for Go code

```
Hi! How are you? Can you please help me create a Go commandline game interpreter for the Scott Adams text adventure game engine. The appended document "scott-adams-engine.md" describes all the information you need to do this. The supplied file "adv01.dat.txt" contains an example game data file that the game interpreter should be able to load correctly and play as a game.

Please implement this using modern golang best practices. Thank you!
```

This was a mostly straightforward iterative process that involved taking the output of building/running the code, pointing out what went wrong, and asking it to correct things, until the end result was satisfactory.

## Example prompt for Lua code

```
Hi! How are you? Can you please help me create a Lua commandline game interpreter for the Scott Adams text adventure game engine. The appended document "scott-adams-engine.md" describes all the information you need to do this. The supplied file "adv01.dat.txt" contains an example game data file that the game interpreter should be able to load correctly and play as a game.

Please implement this using modern Lua 5.3 best practices. Thank you!

Please remember, that in Lua 5.3, code blocks end with "end", rather than "}", and also please remember that comments are prepended with "--" rather than "//".
```

This was more of a challenge. The LLM had trouble creating valid code blocks and comments with valid Lua syntax. This required manual editing of the code to straighten out. The order of function declarations was also a problem. The end result still has problems with actions and action logic, but this may take too much time to get right.
