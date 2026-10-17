PartyCDLens 0.9.0-alpha — WoW Retail 12.1.5


0.9 PALADIN / PRIEST / WARLOCK PASS
------------------------------------
This build expands the working protected AuraContainer architecture instead of falling back to
ordinary aura reads for the newly fixed spells. Talent ranks are taken from party inspection.

Paladin: separate Ret/Holy/Prot wings rows, Holy Avenging Crusader and Protection Sentinel;
Call of the Righteous, Sanctified Wrath and Righteous Protector modify the displayed cooldown/
active duration. Lay on Hands is corrected to a 600s base and can be detected through Empyreal
Ward; Unbreakable Spirit/Uther's Counsel/Holy Tirion's Devotion are applied. Aura Mastery now
watches its triggered aura layers. BoP/Spellwarding includes Improved BoP and Uther's Counsel.
Blessing of Freedom and current aura variants are available as an optional row. Unbreakable
Spirit is also applied to Divine Protection, Ardent Defender and Shield of Vengeance.

Priest: Fade now uses a 30s base, current Fade-related aura aliases, and Improved Fade rank CDR.
Desperate Prayer handles Angel's Mercy (Light's Inspiration affects strength, not cooldown).
Dispersion keeps ID 47585 under Intangibility and gets the -30s CDR. Ultimate Penitence is added.
Guardian Spirit, Divine Hymn and Apotheosis use exact protected sensors; Seraphic Crescendo and
Eternal Sanctity are applied. Protector of the Frail shows ×2 charge CAPACITY when inspected.
Its Power Word: Shield CDR and Guardian Angel's outcome-dependent 60s cooldown remain conservative.

Warlock: Summon Darkglare and Grimoire: Imp Lord are added. Grand Warlock's Design, Eye Contract
and Stabilized Portals modify the displayed cooldown/active duration.

Static percentage/flat talent modifiers are now handled generically by Core:GetCooldownSeconds,
and active-duration talent modifiers by Core:GetActiveSeconds. Action-dependent CDR that cannot
be reconstructed safely from another party member is intentionally not guessed.


SHAMAN ASCENDANCE IN 0.6
------------------------
Settings now expose three separate Ascendance entries:
  - Ascendance (Elemental)    - spell 114050
  - Ascendance (Enhancement)  - spell 114051
  - Ascendance (Restoration)  - spell 114052

All three are optional/talent-gated in AUTO and can also be explicitly set to ON/OFF.
Elemental and Enhancement use the exact Kira-style protected AuraContainer mappings already
present in v0.5. Restoration now also has an exact 114052 sensor. The <=10 second secondary
sensor is used to avoid treating short proc Ascendance states as a manual cooldown use.

THE BIG CHANGE IN 0.5
---------------------
The supplied KiraUI files exposed the missing architecture. PartyCDLens no longer relies on
anonymous BIG_DEFENSIVE/IMPORTANT inference for abilities that Kira's PartyCD implementation
can identify exactly.

Kira's core creates Blizzard CustomAuraContainerTemplate sensors with an exact
candidateFilters.includeSpellIDs list. Blizzard performs the spell-ID filtering inside its UI
system. The result of the sensor can remain a protected/secret value; Kira does not read or
branch on that value. Instead, C_CurveUtil.EvaluateColorValueFromBoolean feeds the protected
state into status bars/alpha/geometry so the UI can display a cooldown without Lua learning
the secret value.

PartyCDLens 0.5 ports that design for party1-party4. The older anonymous filtered-aura engine
remains only as a fallback for requested abilities that are not covered by the exact Kira map.

HAVOC METAMORPHOSIS
-------------------
The old UNIT_MODEL_CHANGED heuristic is no longer the normal detection path.

Kira's PartyCD data tracks Havoc Meta as:
  cast: 191427
  aura: 162264
  short cutoff: 10 seconds

PartyCDLens now creates two exact sensors:
  A) aura 162264 at any duration
  B) aura 162264 with maxDuration = 10

The effective Meta state is A AND NOT B. Eye Beam/Demonic should therefore be rejected while
full Metamorphosis should trigger immediately. The old ~6 second model-duration detector is
retained only as a fallback if the protected AuraContainer path is unavailable on the client.

BLUR
----
Blur uses Kira's exact aura 212800. It should trigger the secure glow immediately and start the
local 60 second cooldown display.

ACTIVE EFFECT DISPLAY
---------------------
For exact sensors, active Blur and Havoc Meta get a protected glow plus a center duration timer
(10s Blur / 20s Meta). When the active aura ends, the cooldown timer remains. The secure path
uses clipped UI/status-bar geometry because an ordinary Lua Cooldown frame cannot safely be fed
a readable protected start timestamp.

CHARGES
-------
PartyCDLens can inspect talents and determine the maximum number of charges, but v0.5 does NOT
claim to know the live remaining charge count for abilities tracked through protected exact
sensors. Kira's supplied PartyCD implementation also does not decode live party charge counts.
/pcdl charges therefore prints ?/max for those secure entries rather than a fake number.

DARKNESS
--------
Darkness remains removed from PartyCDLens per request. The supplied Kira file actually contains
an exact Darkness aura route, but PartyCDLens intentionally does not expose it.

EDIT MODE / PARTY FRAMES
------------------------
The existing safe Blizzard Edit Mode overlay remains. Open Blizzard Edit Mode and drag the
"PartyCDLens cooldowns" handle to move the icon rows relative to the party frames.

COMMANDS
--------
/pcdl          open options
/pcdl secure   show exact protected-sensor engine status
/pcdl debug    toggle diagnostic output
/pcdl status   show cached class/spec/talent data
/pcdl rescan   inspect party members again when permitted
/pcdl coverage show detection-path coverage
/pcdl charges  show charge capacity/state; secure entries report ? for live remaining charges
/pcdl test     show fallback UI anchor test
/pcdl reset    reset addon settings

FIRST TEST FOR 0.5
------------------
1. Replace the entire old PartyCDLens folder with this one and /reload.
2. Party with a Havoc Demon Hunter.
3. Run /pcdl secure. It should say available: yes.
4. Use Eye Beam only. Meta should NOT start a 120s cooldown.
5. Use real Metamorphosis. Meta should glow immediately and show its active countdown, then the
   120s cooldown display.
6. Use Blur. Blur should glow immediately and then show its cooldown.

If /pcdl secure says unavailable, send the exact line it prints. If it says available but Meta
still fails, send a screenshot plus /pcdl secure output. This alpha has been syntax-checked and
mock-runtime tested here, but it has not been executed inside a real WoW client yet.

IMPORTANT LIMITATIONS
---------------------
- Exact support currently follows the supplied Kira PartyCD spell/aura map. Requested spells
  outside that map still use PartyCDLens's older inference engine or remain UNKNOWN.
- Several summons, instant heals, ground effects, passive procs and abilities without a useful
  observable aura may still be impossible to track reliably.
- Party charge counts remain a separate problem from aura/cooldown detection.
- Talent/dynamic cooldown reduction can make locally simulated cooldown lengths conservative.


v0.7 rogue fixes
----------------
- Cloak of Shadows exact sensor now accepts aura 31224 plus triggered immunity aura 35729 and polls the native sensor so short aura-event payload quirks cannot hide the edge.
- Deathmark keeps KiraUI's Finish the Job self-aura sensor (1249810), and adds a protected HARMFUL AuraContainer on partyNtarget for Deathmark 360194. This also covers the Negotiable Contract choice where Finish the Job is absent.
- Readable UNIT_SPELLCAST_SUCCEEDED spell IDs are used as an exact fallback; secret spell IDs are ignored.


v0.8 mage Ice Block / Ice Cold cooldown fix
-------------------------------------------
- Ice Block / Ice Cold now starts from the 240s base cooldown and applies inspected talent reductions.
- Winter's Protection (382424): -30s per rank, up to 2 ranks.
- Permafrost Bauble (1265517): -30s.
- Inspect metadata now stores active talent ranks so two-rank cooldown talents are handled correctly.

Cooldown accuracy changes
-------------------------
- Unobserved ordinary timers stay UNKNOWN rather than assuming READY.
- Protected icons show ~: a blank countdown can mean unobserved or estimated ready.
- Talent inspection updates protected cooldown durations without losing the encoded use time.
- Party-slot changes and Mythic+ starts clear protected timers from the prior player/run.
- Inspect results are matched to the requested GUID; requests time out after five seconds.
- Existing database talent/rank modifiers remain in use. This is not an exhaustive catalogue
  of all talent, set-bonus, proc, or spell-combination reductions. Hidden triggers cannot be
  reconstructed, and x2 still denotes charge capacity, not remaining charges.

In-game regression checks
-------------------------
1. Load with a party member whose defensive has not been observed: ordinary icon is UNKNOWN;
   protected icon has ~ and does not claim that a blank timer proves readiness.
2. Cast a supported single-charge defensive: active effect displays, then recharge continues.
3. Inspect that member while the countdown runs: if talent-adjusted duration changes, elapsed
   time is retained rather than erasing/restarting the protected timer.
4. Replace a member in the same party slot: no timer from the previous member should remain.
5. Start a Mythic+ run with an old timer present: the protected countdown must clear.
6. Inspect multiple members: an unrelated INSPECT_READY event must not assign another
   player's talents to the pending member. An unanswered request must not stall the queue.
7. Test a multi-charge defensive: x2 must be described as capacity; do not interpret the
   countdown as proof that no charge remains.

Health potions
--------------
The Items section now includes Health Potion (AUTO/ON/OFF). AUTO follows the
Show experimental option. Silvermoon Health Potion (spell 1234768, including
Fleeting versions) Concentrated Silvermoon Health Potion (1295247), and Algari Healing Potion (431416) feed a single 300-second
estimated timer. No active defensive glow is shown for an instant heal.

Only readable UNIT_SPELLCAST_SUCCEEDED events from party1-party4 start this timer.
If Blizzard hides the ID, use cannot be observed and no timer is invented.
Potion inventory, profession modifiers, other healing consumables, Healthstones,
and battle-potion cooldowns are not inferred. An expired timer does not prove that
the player has another potion available. Potion state stays unknown at key start.

Verify in game: use a supported potion on a party member, check that only their
potion timer starts near 300 seconds without an active glow, reload and check
restoration, and set Items > Health Potion to OFF to check that the icon hides.

Potion data references:
https://www.wowhead.com/spell=1234768/silvermoon-health-potion
https://www.wowhead.com/spell=431416/algari-healing-potion
https://www.wowhead.com/spell=1295247/concentrated-silvermoon-health-potion

Expanded class/spec event coverage
---------------------------------
Manually cast entries have a readable party cast-event fallback when no protected
sensor owns the spell. Passive and state-only effects are excluded. Nearby inferred
observations are deduplicated. Added Anti-Magic Zone, three Mage barriers, and Diffuse
Magic as experimental entries using installed-client base cooldowns. Missing base
data leaves timers UNKNOWN. See COVERAGE.md for per-spec entries and detection paths.

Run tests/cooldowns.lua from the addon directory with Lua 5.1+. It covers cast-only
detection, spec gating, passive/secret-ID exclusion, charge deduplication, missing
base data, potions, and personal defensive dispatch across all 40 listed specs.
Mocked tests do not certify protected UI behavior in a live Mythic+ run.

Potion diagnostics
------------------
Install the updated Core.lua and /reload before capturing.
/pcdl diag clear - discard old capture and counters
/pcdl diag on    - record player/party spell-success events without chat spam
/pcdl diag mark  - insert a timestamp immediately before the observed potion use
/pcdl diag off   - stop recording; report remains available
/pcdl diag show  - open a selectable report; Ctrl/Cmd+A then Ctrl/Cmd+C to copy

Compare a short out-of-combat test and a short Mythic+ combat test. Have a party
member use a supported potion, and note which member and which potion they used.
The report includes plain spell IDs, potion matches, exclusion reasons, hidden-ID
counts, combat/Mythic+ context, and the last 200 lines. Hidden values are never
converted to text or compared with spell IDs. Self-use is logged as a control but
does not start a party timer. An event with a hidden ID cannot identify potion use;
a missing event cannot establish that no potion was consumed.
Copy the report BEFORE /reload or logout: the capture is session-only.
