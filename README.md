# Pickaxe Pals

Working title. A cute mining incremental for Roblox: mine ore, sell it, hatch pets that mine for you, and rebirth for permanent bonuses.

The code lives here as plain files. [Rojo](https://rojo.space/docs/v7/) syncs them into Roblox Studio.

## One-time setup

1. Install Git and VS Code. VS Code will offer the recommended extensions (Luau language server and StyLua).
2. Install [Rokit](https://github.com/rojo-rbx/rokit) by following its install instructions. It installs and pins the other tools.
3. In this folder, run these commands once, then commit the `rokit.toml` they create:

   ```
   rokit init
   rokit add rojo-rbx/rojo
   rokit add JohnnyMorganz/StyLua
   rokit add lune-org/lune
   ```

   On a fresh clone, `rokit install` installs the pinned versions.
4. Install the Rojo plugin in Roblox Studio. `rojo plugin install` does this, or follow the [Rojo installation guide](https://rojo.space/docs/v7/getting-started/installation/).
5. Start syncing. Run `rojo serve` in this folder. In Studio, open a new Baseplate place, then use Plugins > Rojo > Connect.

## Check that setup works

- Press Play in Studio. The Output window should show `Pickaxe Pals server started. A free player finishes in 21.1 days (the model says about 21).` and `Pickaxe Pals client started.`
- Change the text in `src/server/Main.server.luau`, save, and press Play again. The new text should appear.
- Run `lune run tests/run`. It should end with `All tests passed.`
- Run `stylua src tests` once to apply the project's formatting.

## Folders

```
default.project.json   maps the folders below to Roblox services
src/shared/            code used by both sides: Config (balance numbers) and Formulas (game math)
src/server/            server scripts (saving, economy, eggs, purchases come later)
src/client/            client scripts (screens, input, effects come later)
tests/                 tests for pure code, run outside Studio with Lune
stylua.toml            formatting rules
```

## Notes

- `src/shared/Config.luau` mirrors the economy spreadsheet. Change both together until the config is generated from the spreadsheet.
- Files in `src/shared` that the tests load must not call Roblox services, so they can run outside Studio.
