# Functional Pockets

Build 42 development prototype: one combined pocket container per eligible garment. No individual-pocket mode.

**Not ready for gameplay.** The experimental native-container path is enabled by default in single-player for testing. The experimental native-container path changes the Java item type and cannot guarantee original clothing protection, insulation, wetness, tailoring, or save compatibility. Never enable it on an existing or important save. Multiplayer is disabled for the experiment.

## Layout

- `42/mod.info`: Build 42.13+ mod metadata (minimum is an API target, not a tested version).
- `42/media/lua/shared/FunctionalPockets/Rules.lua`: centralized classification, profiles, overrides, tags, capacity modifiers and bulky-item policy.
- `42/media/lua/shared/FunctionalPockets/Native.lua`: script adapter and enabled experimental native container conversion.
- `42/media/lua/client/FunctionalPockets/Retrieval.lua`: single-player pocket retrieval speed adjustment.
- `tests/classifier.lua`: standalone classification regression tests; run `lua tests/classifier.lua` from the repository root.

## Compatibility rules

The classifier checks clothing/native storage eligibility, explicit full-ID overrides, tags, exclusions, ordered inclusion rules and non-stacking modifiers, then body location. Names are normalized independently of translations. Mods can require `FunctionalPockets/Rules` and extend `FunctionalPockets.Rules` before the experimental boot scan. For example:

```lua
require "FunctionalPockets/Rules"
FunctionalPockets.Rules.overrides["Example.PocketlessJacket"] = false
FunctionalPockets.Rules.overrides["Example.WorkJacket"] = {3, 40, 1.0}
FunctionalPockets.Rules.tags["utilitypockets"] = true
```

The override fields are total capacity, weight reduction percentage, maximum item size, optional presumed pocket count, and optional list of BloodBodyPartType region names (for example, {2, 30, 0.7, 4, {"Torso_Lower", "Groin", "UpperLeg_L", "UpperLeg_R"}}). Tag keys are normalized local IDs; these are conventions for cooperating mods, not claims that vanilla defines pocket tags. A negative tag wins over a positive tag. The first matching modifier wins, with special profiles for hunting and tactical vests. Generic ambiguous torso-extra locations do not automatically receive pockets. The experimental adapter skips non-clothing item types (including existing native containers); native storage provided by custom mechanisms has not been audited.


## Public Lua API (version 1)

In a compatibility mod, declare `require=FunctionalPockets` in mod.info and put registration code in `media/lua/shared`. Run registrations at file load, before Functional Pockets' OnGameBoot conversion; do not register in OnGameStart or after conversion. Restart the game after changing registrations. The current native conversion remains experimental and single-player only.

```lua
require "FunctionalPockets/Rules"
local API = FunctionalPockets.API

API.registerProfile("Example.Utility", {
    capacity = 4,
    reduction = 40,
    maxItemSize = 0.8,
    pocketCount = 6,
    pocketRegions = {"Torso_Lower", "UpperLeg_L", "UpperLeg_R"},
})
API.registerItem("Example.UtilityJacket", "Example.Utility")
API.overrideStats("Example.OtherJacket", 3, 35)
API.excludeItem("Example.DecorativeJacket")
API.registerInclusionKeyword("utilitysmock", "Example.Utility")
API.registerExclusionKeyword("sealedseams")
API.registerBodyLocation("example:utilityslot", "Example.Utility")
API.registerBulkyKeyword("longtool")
```

| Function | Behavior |
| --- | --- |
| registerProfile(name, profile) | Creates or replaces a named profile. Use mod-prefixed names to avoid collisions. |
| registerItem(fullID, profileOrName) | Explicitly registers a garment using a named profile or an inline profile table with the same five fields. Copies the profile at registration. |
| overrideStats(fullID, capacity, reduction) | Replaces either or both final stats for an otherwise eligible item; pass nil to leave one unchanged. Does not bypass exclusions. |
| excludeItem(fullID) | Explicitly excludes a garment. |
| registerInclusionKeyword(keyword, profileName) | Adds a normalized substring rule ahead of existing inclusion rules. Most recently registered matching inclusion wins. |
| registerExclusionKeyword(keyword) | Adds a normalized exclusion substring. |
| registerBodyLocation(location, profileName) | Maps an existing engine body location to a fallback profile. Does not create engine body locations. |
| registerBulkyKeyword(keyword) | Rejects matching stored item names globally. |

Capacity and maximum item size must be positive finite numbers, reduction is 0–100, pocket count is a positive integer, and pocket regions are an array of engine BloodBodyPartType names (empty is allowed if no regions should cause damage). The API validates basic input types and ranges, not the existence of engine item IDs or region names. Capacity is combined per garment; maxItemSize uses the current weight-based approximation. Native capacity rounds up. Pocket count and regions control the optional damage mechanic, not the number of containers.

Explicit item registrations override tags and classification exclusions but cannot bypass the clothing/native-storage guard. The latest explicit registration or exclusion for the same ID wins and clears earlier stat overrides; call overrideStats afterward if needed. Tags retain their original precedence over keyword rules. Keyword and body-location matching uses the classifier's existing normalization, including local (unqualified) body-location names; collisions across namespaces are possible. Named profile rules still participate in the existing garment name modifiers. Registration errors raise Lua errors. No arbitrary new engine pocket properties or multiple containers are introduced. The legacy Rules tables remain available, but the API is preferred.

## Native storage research and experiment

Build 42 exposes distinct Java Clothing and InventoryContainer classes, each with its own serialization and class-specific methods. Item scripts have a single ItemType; container capacity is integer-valued. The experiment uses the native container item type, garment body location, native capacity/weight reduction and acceptance callback. Native capacity is rounded upward; the callback attempts to enforce the fractional profile limit and reject bulky/nested items. This is an unverified approximation, not geometric size detection. Pocket retrieval speed is configurable under Functional Pockets in Sandbox Options (1–1000%, default 100%). Only transfers out of converted pocket containers are affected; other transfers retain their normal speed.

Zombie Pocket Loot is a four-value sandbox option: vanilla (default), fill pockets and keep overflow, fill pockets and drop overflow, or fill pockets and delete overflow. The experimental single-player implementation uses OnFillContainer for newly generated zombie corpse loot, preserving equipped items and existing bag contents. It tries each worn pocket in inventory order using the existing admission rules. A corpse with no eligible pockets has only overflow; a missing ground square leaves overflow in the corpse rather than losing it. Corpse loot timing and garment recognition require in-game verification.

Pocket Capacity Loss from Holes is an optional boolean sandbox setting (disabled by default). With it enabled, each distinct mapped region with a visual hole removes one presumed pocket's share of the original profile capacity, rounded upward. Ordinary trousers have four presumed pockets, cargo trousers six, and explicitly heavy/eight-pocket trousers eight. The engine has no separate front/back or knee pocket locations, so some pockets share one body region; holes in unmapped regions do not count. Repairs restore capacity. Carried pockets are refreshed periodically, and zombie corpse pockets when vanilla fills the corpse; random overflow items are dropped on the available square. Admission uses the current damaged capacity. This does not scan every stored garment in the world. The experimental container conversion may prevent normal clothing damage or repair from occurring; in-game verification is required.

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

## Additional sewn pockets

Enable **Allow Sewing Additional Pockets** in Sandbox Options (off by default). Right-click a single carried pocket garment with scissors, needle, usable thread and a clean ripped sheet, denim strip or leather strip in carried inventory. The menu shows current presumed pocket count / actual covered body-region count. A completed action uses one fabric strip and one thread use; tools are retained. Each addition occupies a random unused covered region without a hole and adds the original average capacity per pocket. The native capacity is rounded up, and hole damage includes the additional regions when enabled. Added regions are stored in the garment's mod data, not on its shared script. Existing profiles with more presumed pockets than covered regions cannot receive additions. Weight reduction and maximum individual item size remain unchanged. **Additional Pocket Sewing Speed** defaults to 100% of vanilla patch sewing time (150 minus six ticks per Tailoring level); 200% halves duration. This is part of the experimental single-player conversion and needs in-game testing.
