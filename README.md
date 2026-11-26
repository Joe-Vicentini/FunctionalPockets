# Functional Pockets

Build 42 development prototype: one combined pocket container per eligible garment. No individual-pocket mode.

**Not ready for gameplay.** The experimental native-container path is enabled by default in single-player for testing. The experimental native-container path changes the Java item type and cannot guarantee original clothing protection, insulation, wetness, tailoring, or save compatibility. Never enable it on an existing or important save. Multiplayer is disabled for the experiment.

## Layout

- `42/mod.info`: Build 42.13+ mod metadata (minimum is an API target, not a tested version).
- `42/media/lua/shared/FunctionalPockets/Rules.lua`: centralized classification, profiles, overrides, tags, capacity modifiers and bulky-item policy.
- `42/media/lua/shared/FunctionalPockets/Native.lua`: script adapter and enabled experimental native container conversion.
- `tests/classifier.lua`: standalone classification regression tests; run `lua tests/classifier.lua` from the repository root.

## Compatibility rules

The classifier checks clothing/native storage eligibility, explicit full-ID overrides, tags, exclusions, ordered inclusion rules and non-stacking modifiers, then body location. Names are normalized independently of translations. Mods can require `FunctionalPockets/Rules` and extend `FunctionalPockets.Rules` before the experimental boot scan. For example:

```lua
require "FunctionalPockets/Rules"
FunctionalPockets.Rules.overrides["Example.PocketlessJacket"] = false
FunctionalPockets.Rules.overrides["Example.WorkJacket"] = {3, 40, 1.0}
FunctionalPockets.Rules.tags["utilitypockets"] = true
```

The override fields are total capacity, weight reduction percentage, and maximum item size. Tag keys are normalized local IDs; these are conventions for cooperating mods, not claims that vanilla defines pocket tags. A negative tag wins over a positive tag. The first matching modifier wins, with special profiles for hunting and tactical vests. Generic ambiguous torso-extra locations do not automatically receive pockets. The experimental adapter skips non-clothing item types (including existing native containers); native storage provided by custom mechanisms has not been audited.

## Native storage research and experiment

Build 42 exposes distinct Java Clothing and InventoryContainer classes, each with its own serialization and class-specific methods. Item scripts have a single ItemType; container capacity is integer-valued. The experiment uses the native container item type, garment body location, native capacity/weight reduction and acceptance callback. Native capacity is rounded upward; the callback attempts to enforce the fractional profile limit and reject bulky/nested items. This is an unverified approximation, not geometric size detection. Inventory transfer time is unchanged.

To investigate, enable the mod and launch a disposable **new single-player** world only. The local `experimental` flag in Native.lua is now true by default. The boot-time conversion and admission callbacks must be verified against the target game version before treating this as functional. Do not toggle it within a save; restart the game between experiments. If the boot hook is too early for the active mod scripts, conversion may not occur.

Before treating the experiment as ready for gameplay, test native inventory tabs, independent instances, actual carried weight, transfer restrictions (including batch transfers), equip/unequip, dropping, storage and save/reload, zombie outfits, hood variants, clothing protection/thermal stats, wetness, tailoring, and later server-authoritative behavior. A supported way to retain the actual Clothing class while providing native storage remains unresolved.

## References

- [Build 42 Item script parameters](https://pz-wiki-modding.github.io/PZ-API-Docs/scripts/item.html)
- [Item Java API](https://projectzomboid.com/modding/zombie/scripting/objects/Item.html)
- [Clothing Java API](https://projectzomboid.com/modding/zombie/inventory/types/Clothing.html)
- [InventoryContainer Java API](https://projectzomboid.com/modding/zombie/inventory/types/InventoryContainer.html)
- [ItemContainer Java API](https://projectzomboid.com/modding/zombie/inventory/ItemContainer.html)
- [Vanilla 42.21 body locations](https://wenopal.work/en/reference/body-locations.html)
- [Vanilla 42.21 item tags](https://wenopal.work/en/reference/tags.html)
- [Functional Clothing Pockets Workshop description](https://steamcommunity.com/sharedfiles/filedetails/?id=3731578189) (technical reference only; no code copied).

The vanilla catalog review is preliminary, not an exhaustive inspection of the installed game scripts. Standalone Lua tests are not in-game validation.
