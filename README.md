# Plater-Nameplates
Source code for World of Warcraft addon Plater Nameplates.

General Frequent Asked Questions:
https://www.curseforge.com/wow/addons/plater-nameplates/pages/faq

General Scripting Guide:
https://www.curseforge.com/wow/addons/plater-nameplates/pages/scripts

### Legion 7.3.5

The default `Plater.toc` now targets the 7.3.5 client (interface **70300**).
Install this folder as `Interface\AddOns\Plater` and restart the client.
No TOC renaming or WeakAuras dependency is needed. The included
`WeakAurasLegionCompat` folder is reference material, not a Plater dependency.
`Plater_Legion.toc` contains the same Legion load sequence for packaging.
The Retail, Wrath, and Vanilla manifests remain separate.

Back up your Plater saved variables before testing an existing profile.
The compatibility code loads before the libraries and keeps native Legion
APIs intact; aura/cast return values and protected callback arguments are
adapted inside Plater and its bundled framework.
Specialization-change listeners start after profile initialization. Database
initialization also tolerates shared AceAddon copies that do not forward
callback arguments under Lua 5.1.
Pixel positioning uses the owning frame's scale for legacy textures, and
script environments only filter namespaced APIs that exist on the client.
Pixel-aware controls select the bundled `DFPixelUtil` fallback locally when
the native `PixelUtil` API is absent, without replacing the global API.
Framework buttons use native Legion backdrops without requiring
`BackdropTemplate`; keep `Plater_LegionCompat.xml` installed for the other
controls that still inherit that template.
Indicator textures without `SetScale` use scaled dimensions, including custom
indicator sizes.
UIParent scaling only changes a frame's scale when necessary and registers
one size-change hook per nameplate, avoiding recursive Legion layout updates.
Legion nameplate unit tokens are initialized from the unit-added event before
unit queries run. Scheduled refreshes skip inactive or expired plates, and
removal tolerates an incomplete add event. Soft-target unit tokens are not
queried on Legion.
Legion skips the unsupported `nameplateNotSelectedAlpha`,
`nameplateRemovalAnimation`, `nameplateShowFriendlyBuffs`, and
`nameplateShowPersonalCooldowns` startup writes. The first two are also excluded
from profile CVar storage/restoration. Quick Hide on Death remains available
for its addon-side behavior without changing the unsupported animation CVar.
`NamePlateClassificationScale` is also excluded from Legion first-run setup
and profile CVar storage/restoration; it has no separate option.
Legion aura icons use rectangular textures without the hidden rounded masks
attached by the Retail renderer.
Widget API forwarding calls the underlying UI object directly, so unnamed
controls and global name collisions do not break options panels. On Legion,
widget prototypes use separate names to avoid inheriting older generated
wrappers from another addon's bundled DetailsFramework.
Scripting code-selection buttons stay accessible when script options hide
the code editor. Only import/export dialogs hide them, so they do not overlap
the Okay and Cancel controls.
Selecting or creating a script explicitly exits import/export mode and
restores the editable code view in both Scripting and Modding.

If you use ElvUI, disable its **Nameplates** module in `/elvui` and reload
before testing Plater. The rest of ElvUI can remain enabled. The two nameplate
modules share frame fields and must not control nameplates simultaneously;
Plater already reports this conflict in chat.

Dragonflight-only features (empowered casts, soft targeting, and unit widget
bars, charged combo points, and Evoker essence) are not available on Legion.
The resource selector omits Evoker essence, and options controls use legacy
textures where their newer atlases are absent. Imported scripts or mods that call newer
WoW APIs directly also need their own backports. Race-filter labels use
client file names when localized race information is not available.
Load-condition race filters also use client file names when a compatibility
API omits localized names. Panel construction and refresh do not invoke the
mod's change callback; user changes invoke the callback for the current mod.

For an in-game smoke test:

1. Enable Lua errors with `/console scriptErrors 1`, then `/reload`.
2. Confirm `/plater` opens without errors.
3. Test enemy health, interruptible casts, channeled casts, buffs/debuffs,
   threat colors, specialization changes, and class resources.
4. Repeat in combat and in a dungeon; Legion restricts addon modifications
   to friendly nameplates in instances.

The standalone regression suite can be run from the addon folder with
`lua tests\legion_compat.lua` using Lua 5.1. Mocked API tests do not replace
testing on the private server's actual client.


The Wago.io logo was graciously provided for use within Plater by the owner and creator of Wago.io (Oratory).
