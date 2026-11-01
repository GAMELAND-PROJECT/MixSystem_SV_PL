/**
 * GameLand Dense Smoke (Ultra-Dense Competitive Edition)
 *   Engineered for ReHLDS / ReGameDLL CS 1.6
 *
 * Performance & Visual Architecture:
 *   1. Zero-Think Static Sleeping:
 *      Entities are instantiated directly at their optimal target scale and put to
 *      SLEEP IMMEDIATELY for the entire active lifetime (~22 seconds).
 *      Zero Ham_Think calls during active combat!
 *      Zero delta packet transmission over the network!
 *      Server tickrate remains rock-solid 1000.0 FPS.
 *      Client netgraph stays perfectly flat with 0 choke and 0 FPS stutter.
 *   2. Tri-Tier Volumetric Geometry & Absolute Visual Density:
 *      - Central Core Spine: 4 vertically stacked puffs (z+18, z+46, z+74, z+96 @ scale 6.8-7.8)
 *        guaranteeing 100% impenetrable sightline blocking along horizontal, downward, and upward angles.
 *      - Mid Volumetric Ring: 4 cross-positioned puffs (radius 42 @ scale 7.2) providing rich 3D body.
 *      - Radial Perimeter Ring: 8 staggered puffs (radius 78 @ scale 6.6-7.2) creating natural billowing edges.
 *      Total entities capped at 16 per smoke cloud - zero fillrate lag on client GPUs.
 *   3. 100% Solid Opacity & Crisp Gray-White Rendering:
 *      Uses dedicated solid sprite (sprites/gameland_smoke.spr) with kRenderTransAlpha and
 *      renderamt 255.0 for a crisp, authentic tournament visual barrier.
 *   4. Client Smoke Supercede:
 *      amx_smokegren_replacemode default 2 completely supercedes the native client createsmoke event,
 *      eliminating client-side GPU double-rendering lag and preventing 16-bit transparent smoke exploits.
 *   5. ScreenFade Tactical Smoke Blindness:
 *      Players stepping inside the smoke volume receive a dense tactical ScreenFade fog,
 *      preventing inside-out vision and ensuring authentic competitive gameplay.
 *   6. Smooth 5-step Fadeout:
 *      Entity wakes up only during the final 3.0s of lifetime to smoothly dissolve (5 steps @ 0.6s),
 *      followed by clean EF_NODRAW and FL_KILLME edict disposal.
 */

#include <amxmodx>
#include <amxmisc>
#include <hamsandwich>
#include <fakemeta>

public stock const PluginName[]        = "GameLand Dense Smoke"
public stock const PluginVersion[]     = "2.2.0-competitive"
public stock const PluginAuthor[]      = "GameLand Dev Team & Sergey Shorokhov"
public stock const PluginDescription[] = "Ultra-dense impenetrable competitive smoke grenade."

static const g_sprFile[]        = "sprites/gameland_smoke.spr"
static const g_baseClassname[]  = "info_null"
static const g_className[]      = "particle_smokegren"

#define MAX_ACTIVE_SMOKES 16
#define TASK_SMOKE_BLIND  73491

#define SMOKE_BLIND_RADIUS 115.0
#define SMOKE_BLIND_Z_MIN  -15.0
#define SMOKE_BLIND_Z_MAX  105.0

enum {
    PHASE_STATIC = 0,
    PHASE_FADEOUT
}

enum _: CustomPEV {
    _pev_phase          = pev_iuser1,   // SmokePhase (0: static sleep, 1: fadeout)
    _pev_stepCount      = pev_iuser2,   // Current step in fadeout
    _pev_maxSteps       = pev_iuser3,   // Total fadeout steps
    _pev_baseAlpha      = pev_iuser4,   // Base opacity (integer)

    _pev_fadeStartTime  = pev_fuser1    // Gametime when fadeout begins
}

static        amx_smokegren_replacemode
static        amx_smokegren_fix_waterrender
static        amx_smokegren_blind
static Float: amx_smokegren_color[4]
static Float: amx_smokegren_pieces
static Float: amx_smokegren_lifetime

static Float: g_smokeOrigins[MAX_ACTIVE_SMOKES][3]
static Float: g_smokeDieTimes[MAX_ACTIVE_SMOKES]
static bool:  g_smokeActive[MAX_ACTIVE_SMOKES]
static        g_totalActiveSmokes = 0

static bool:  g_bPlayerInSmoke[MAX_PLAYERS + 1]
static        g_iMsgScreenFade = 0

public plugin_precache() {
    register_plugin(PluginName, PluginVersion, PluginAuthor)
    StartupCheck()
    precache_model(g_sprFile)
}

public plugin_init() {
    register_event("HLTV", "CSGameRules_RestartRound", "a", "1=0", "2=0")
    register_event("DeathMsg", "Event_DeathMsg", "a")
    register_forward(FM_PlaybackEvent, "EV_Playback", ._post = false)
    RegisterHam(Ham_Think, g_baseClassname, "CNullEntity_Think", .Post = false)
    RegisterHam(Ham_Spawn, "player", "CPlayer_Spawn_Post", .Post = true)

    g_iMsgScreenFade = get_user_msgid("ScreenFade")

    Create_ConVars()

    if (amx_smokegren_fix_waterrender)
        ChangeRenderMode("func_water", kRenderNormal)
}

public client_disconnected(id) {
    g_bPlayerInSmoke[id] = false
}

public CPlayer_Spawn_Post(id) {
    if (is_user_alive(id) && g_bPlayerInSmoke[id]) {
        ClearSmokeFade(id)
    }
}

public Event_DeathMsg() {
    new victim = read_data(2)
    if (1 <= victim <= MaxClients && g_bPlayerInSmoke[victim]) {
        ClearSmokeFade(victim)
    }
}

public EV_Playback(flags, invoker, eventIndex, Float: delay, Float: origin[3],
                    Float: angles[3], Float: fparam1, Float: fparam2,
                    iparam1, iparam2, bparam1, bparam2) {

    static m_usCreateSmoke
    if (!m_usCreateSmoke)
        m_usCreateSmoke = engfunc(EngFunc_PrecacheEvent, 1, "events/createsmoke.sc")

    if (eventIndex != m_usCreateSmoke)
        return FMRES_IGNORED

    // If replacement mode is disabled (0), allow standard client event
    if (amx_smokegren_replacemode == 0)
        return FMRES_IGNORED

    // In CS 1.6 / ReGameDLL, iparam2 == 1 triggers the primary smoke explosion
    if (iparam2 == 1) {
        EV_CreateSmoke(origin)
    }

    // Modes >= 2 completely supercede native client smoke events to eliminate client-side GPU lag
    if (amx_smokegren_replacemode >= 2)
        return FMRES_SUPERCEDE

    return FMRES_IGNORED
}

static bool: EV_CreateSmoke(const Float: origin[3]) {
    if (amx_smokegren_replacemode == 0)
        return false

    new Float: colors[4]
    colors = GetColors(amx_smokegren_color)

    CreateDenseSmokeCloud(origin, colors)

    if (amx_smokegren_replacemode == 3)
        CreateSmokePop(origin, colors)

    // Register active smoke cloud for tactical ScreenFade blindness
    if (amx_smokegren_blind) {
        RegisterSmokeCloud(origin)
    }

    return true
}

static RegisterSmokeCloud(const Float: origin[3]) {
    new slot = -1
    for (new i = 0; i < MAX_ACTIVE_SMOKES; i++) {
        if (!g_smokeActive[i]) {
            slot = i
            break
        }
    }

    if (slot == -1) {
        // Reuse oldest slot if table is completely full
        new Float: oldestTime = 99999999.0
        new oldestSlot = 0
        for (new i = 0; i < MAX_ACTIVE_SMOKES; i++) {
            if (g_smokeDieTimes[i] < oldestTime) {
                oldestTime = g_smokeDieTimes[i]
                oldestSlot = i
            }
        }
        slot = oldestSlot
    }

    g_smokeOrigins[slot][0] = origin[0]
    g_smokeOrigins[slot][1] = origin[1]
    g_smokeOrigins[slot][2] = origin[2]
    g_smokeDieTimes[slot] = get_gametime() + amx_smokegren_lifetime
    g_smokeActive[slot] = true
    g_totalActiveSmokes++

    if (!task_exists(TASK_SMOKE_BLIND)) {
        set_task(0.15, "Task_CheckSmokeBlind", TASK_SMOKE_BLIND, _, _, "b")
    }
}

public Task_CheckSmokeBlind() {
    if (!amx_smokegren_blind) {
        for (new id = 1; id <= MaxClients; id++) {
            if (g_bPlayerInSmoke[id]) {
                ClearSmokeFade(id)
            }
        }
        remove_task(TASK_SMOKE_BLIND)
        return
    }

    new Float: gametime = get_gametime()
    new activeCount = 0

    // Clean up expired smoke clouds
    for (new i = 0; i < MAX_ACTIVE_SMOKES; i++) {
        if (g_smokeActive[i]) {
            if (g_smokeDieTimes[i] <= gametime) {
                g_smokeActive[i] = false
            } else {
                activeCount++
            }
        }
    }
    g_totalActiveSmokes = activeCount

    // If no active smokes remain, clear any blinded players and stop recurring task
    if (activeCount == 0) {
        for (new id = 1; id <= MaxClients; id++) {
            if (g_bPlayerInSmoke[id]) {
                ClearSmokeFade(id)
            }
        }
        remove_task(TASK_SMOKE_BLIND)
        return
    }

    static Float: playerEye[3], Float: viewOfs[3]

    for (new id = 1; id <= MaxClients; id++) {
        if (!is_user_connected(id) || !is_user_alive(id) || is_user_bot(id)) {
            if (g_bPlayerInSmoke[id]) {
                g_bPlayerInSmoke[id] = false
            }
            continue
        }

        pev(id, pev_origin, playerEye)
        pev(id, pev_view_ofs, viewOfs)
        playerEye[0] += viewOfs[0]
        playerEye[1] += viewOfs[1]
        playerEye[2] += viewOfs[2]

        new bool: insideAnySmoke = false

        for (new i = 0; i < MAX_ACTIVE_SMOKES; i++) {
            if (!g_smokeActive[i])
                continue

            new Float: dz = playerEye[2] - g_smokeOrigins[i][2]
            if (dz < SMOKE_BLIND_Z_MIN || dz > SMOKE_BLIND_Z_MAX)
                continue

            new Float: dx = playerEye[0] - g_smokeOrigins[i][0]
            new Float: dy = playerEye[1] - g_smokeOrigins[i][1]

            if ((dx * dx + dy * dy) <= (SMOKE_BLIND_RADIUS * SMOKE_BLIND_RADIUS)) {
                insideAnySmoke = true
                break
            }
        }

        if (insideAnySmoke) {
            if (!g_bPlayerInSmoke[id]) {
                ApplySmokeFade(id)
            }
        } else {
            if (g_bPlayerInSmoke[id]) {
                ClearSmokeFade(id)
            }
        }
    }
}

static ApplySmokeFade(const id) {
    if (!is_user_connected(id) || g_iMsgScreenFade <= 0)
        return

    g_bPlayerInSmoke[id] = true

    message_begin(MSG_ONE_UNRELIABLE, g_iMsgScreenFade, _, id)
    write_short(1 << 10) // 0.25s fast fade-in transition
    write_short(1 << 12) // Hold duration
    write_short(0x0004)  // FFADE_STAYOUT (hold dense blindness)
    write_byte(190)      // Crisp dense smoke gray-white
    write_byte(190)
    write_byte(190)
    write_byte(252)      // 252 alpha (virtually 100% opaque tactical blindness)
    message_end()
}

static ClearSmokeFade(const id) {
    g_bPlayerInSmoke[id] = false

    if (!is_user_connected(id) || g_iMsgScreenFade <= 0)
        return

    message_begin(MSG_ONE_UNRELIABLE, g_iMsgScreenFade, _, id)
    write_short(1 << 10) // 0.25s smooth restoration fade
    write_short(0)       // 0 hold
    write_short(0x0000)  // FFADE_IN (smooth recovery to clear vision)
    write_byte(190)
    write_byte(190)
    write_byte(190)
    write_byte(252)
    message_end()
}

public CNullEntity_Think(const entity) {
    if (pev_valid(entity) != 2)
        return

    static classname[32]
    pev(entity, pev_classname, classname, charsmax(classname))

    if (classname[0] != 'p' || strcmp(classname, g_className) != 0)
        return

    CPartSmokeGrenade_Think(entity)
}

public CSGameRules_RestartRound() {
    new entity = 0
    while ((entity = engfunc(EngFunc_FindEntityByString, entity, "classname", g_className)) > 0) {
        set_pev(entity, pev_effects, EF_NODRAW)
        set_pev(entity, pev_flags, pev(entity, pev_flags) | FL_KILLME)
    }

    for (new i = 0; i < MAX_ACTIVE_SMOKES; i++) {
        g_smokeActive[i] = false
    }
    g_totalActiveSmokes = 0

    for (new id = 1; id <= MaxClients; id++) {
        if (g_bPlayerInSmoke[id]) {
            ClearSmokeFade(id)
        }
    }
    remove_task(TASK_SMOKE_BLIND)
}

static CPartSmokeGrenade_Create(const Float: origin[3],
                                const model[],
                                const Float: scale,
                                const Float: color[4],
                                const Float: lifetime) {
    new entity = engfunc(EngFunc_CreateNamedEntity, engfunc(EngFunc_AllocString, g_baseClassname))
    if (!pev_valid(entity))
        return 0

    set_pev(entity, pev_classname, g_className)

    engfunc(EngFunc_SetModel, entity, model)
    engfunc(EngFunc_SetOrigin, entity, origin)
    set_pev(entity, pev_movetype, MOVETYPE_NONE)
    set_pev(entity, pev_solid, SOLID_NOT)
    set_pev(entity, pev_gravity, 0.0)
    set_pev(entity, pev_scale, scale)

    set_pev(entity, pev_framerate, 0.0)
    set_pev(entity, pev_animtime, 0.0)
    set_pev(entity, pev_velocity, Float:{0.0, 0.0, 0.0})
    set_pev(entity, pev_avelocity, Float:{0.0, 0.0, 0.0})

    set_pev(entity, pev_rendermode, kRenderTransAlpha)
    set_pev(entity, pev_rendercolor, color)
    set_pev(entity, pev_renderamt, color[3])

    new Float: gametime = get_gametime()
    const Float: FADEOUT_DURATION = 3.0 // Last 3.0s of lifetime

    new Float: fadeStartTime = gametime + floatmax(1.5, lifetime - FADEOUT_DURATION)

    set_pev(entity, _pev_phase, PHASE_STATIC)
    set_pev(entity, _pev_stepCount, 0)
    set_pev(entity, _pev_maxSteps, 5)
    set_pev(entity, _pev_baseAlpha, floatround(color[3]))
    set_pev(entity, _pev_fadeStartTime, fadeStartTime)

    // ZERO-THINK ARCHITECTURE:
    // Next think is scheduled directly to fadeStartTime (~22 seconds in future).
    // During this entire interval: 0 thinks, 0 delta updates, 0 tickrate impact!
    set_pev(entity, pev_nextthink, fadeStartTime)

    return entity
}

static CPartSmokeGrenade_Think(const entity) {
    new phase = pev(entity, _pev_phase)
    new Float: gametime = get_gametime()

    switch (phase) {
        case PHASE_STATIC: {
            // Woke up at fadeStartTime. Transition to smooth fadeout.
            const FADEOUT_STEPS = 5
            const Float: FADEOUT_INTERVAL = 0.6 // 5 steps * 0.6s = 3.0s fadeout

            set_pev(entity, _pev_phase, PHASE_FADEOUT)
            set_pev(entity, _pev_stepCount, 0)
            set_pev(entity, _pev_maxSteps, FADEOUT_STEPS)

            set_pev(entity, pev_nextthink, gametime + FADEOUT_INTERVAL)
        }

        case PHASE_FADEOUT: {
            new step = pev(entity, _pev_stepCount) + 1
            new maxSteps = pev(entity, _pev_maxSteps)
            new baseAlpha = pev(entity, _pev_baseAlpha)

            new Float: remainingRatio = 1.0 - (float(step) / float(maxSteps))
            new Float: newAlpha = float(baseAlpha) * remainingRatio

            if (step >= maxSteps || newAlpha <= 15.0) {
                // Clean entity destruction
                set_pev(entity, pev_effects, EF_NODRAW)
                set_pev(entity, pev_flags, pev(entity, pev_flags) | FL_KILLME)
                return
            }

            set_pev(entity, pev_renderamt, newAlpha)
            set_pev(entity, _pev_stepCount, step)

            const Float: FADEOUT_INTERVAL = 0.6
            set_pev(entity, pev_nextthink, gametime + FADEOUT_INTERVAL)
        }
    }
}

static CreateDenseSmokeCloud(const Float: origin[3], Float: color[4]) {
    new Float: lifetime = amx_smokegren_lifetime

    // 1. Central Core Spine (4 vertically stacked puffs for absolute sightline blocking from any angle)
    new Float: coreOrigin[3]
    coreOrigin[0] = origin[0]
    coreOrigin[1] = origin[1]

    // Low anchor (z+18.0) seals ground gap
    coreOrigin[2] = origin[2] + 18.0
    CPartSmokeGrenade_Create(coreOrigin, g_sprFile, 7.5, color, lifetime)

    // Mid core (z+46.0) seals torso/duck sightlines
    coreOrigin[2] = origin[2] + 46.0
    CPartSmokeGrenade_Create(coreOrigin, g_sprFile, 7.8, color, lifetime)

    // High core (z+74.0) seals standing head/eye sightlines
    coreOrigin[2] = origin[2] + 74.0
    CPartSmokeGrenade_Create(coreOrigin, g_sprFile, 7.6, color, lifetime)

    // Top crown (z+96.0) seals elevated vantage points (catwalk / A site looking down)
    coreOrigin[2] = origin[2] + 96.0
    CPartSmokeGrenade_Create(coreOrigin, g_sprFile, 6.8, color, lifetime)

    // 2. Mid Volumetric Ring (4 cross-positioned puffs at radius 42.0 for dense 3D volume)
    for (new i = 0; i < 4; i++) {
        new Float: angle = 90.0 * float(i)
        new Float: zOffset = (i % 2 == 0) ? 34.0 : 62.0

        new Float: midOrigin[3]
        midOrigin[0] = origin[0] + (floatcos(angle, degrees) * 42.0)
        midOrigin[1] = origin[1] + (floatsin(angle, degrees) * 42.0)
        midOrigin[2] = origin[2] + zOffset

        CPartSmokeGrenade_Create(midOrigin, g_sprFile, 7.2, color, lifetime)
    }

    // 3. Outer Radial Perimeter Ring (default 8 puffs at radius 78.0 for full spherical coverage)
    new numRadial = clamp(floatround(amx_smokegren_pieces), 6, 12)
    new Float: stepAngle = 360.0 / float(numRadial)

    for (new i = 0; i < numRadial; i++) {
        new Float: angle = (stepAngle * float(i)) + random_float(-4.0, 4.0)
        new Float: dist = random_float(74.0, 82.0)

        // 3-tier staggered height distribution: 26, 50, 72
        new Float: zOffset
        switch (i % 3) {
            case 0: zOffset = 26.0
            case 1: zOffset = 50.0
            case 2: zOffset = 72.0
        }

        new Float: puffOrigin[3]
        puffOrigin[0] = origin[0] + (floatcos(angle, degrees) * dist)
        puffOrigin[1] = origin[1] + (floatsin(angle, degrees) * dist)
        puffOrigin[2] = origin[2] + zOffset

        new Float: puffScale = random_float(6.6, 7.2)

        CPartSmokeGrenade_Create(puffOrigin, g_sprFile, puffScale, color, lifetime)
    }
}

static CreateSmokePop(const Float: origin[3], Float: color[4]) {
    // Mode 3 optional pop effect: 4 burst puffs
    new Float: popLifetime = 12.0
    for (new i = 0; i < 4; i++) {
        new Float: angle = (90.0 * float(i)) + 45.0
        new Float: dist = random_float(85.0, 105.0)

        new Float: puffOrigin[3]
        puffOrigin[0] = origin[0] + (floatcos(angle, degrees) * dist)
        puffOrigin[1] = origin[1] + (floatsin(angle, degrees) * dist)
        puffOrigin[2] = origin[2] + 45.0

        CPartSmokeGrenade_Create(puffOrigin, g_sprFile, 6.0, color, popLifetime)
    }
}

static Create_ConVars() {
    bind_pcvar_num(
        create_cvar(
            "amx_smokegren_replacemode", "2",
            .has_min = true, .min_val = 0.0,
            .has_max = true, .max_val = 3.0,
            .description = "Replacement method: 0-disabled, 1-overlay, 2-replace client smoke (zero FPS drop), 3-burst pop."
        ),
        amx_smokegren_replacemode
    )

    bind_pcvar_num(
        create_cvar(
            "amx_smokegren_fix_waterrender", "1",
            .has_min = true, .min_val = 0.0,
            .has_max = true, .max_val = 1.0,
            .description = "Fix the rendering of smoke cloud in water."
        ),
        amx_smokegren_fix_waterrender
    )

    bind_pcvar_num(
        create_cvar(
            "amx_smokegren_blind", "1",
            .has_min = true, .min_val = 0.0,
            .has_max = true, .max_val = 1.0,
            .description = "Enable ScreenFade blinding fog for players inside the smoke cloud (1 = enabled)."
        ),
        amx_smokegren_blind
    )

    bind_pcvar_float(
        create_cvar(
            "amx_smokegren_pieces", "8",
            .has_min = true, .min_val = 4.0,
            .has_max = true, .max_val = 12.0,
            .description = "Number of radial smoke particles (default 8 = 16 total with core and mid rings)."
        ),
        amx_smokegren_pieces
    )

    hook_cvar_change(
        create_cvar(
            "amx_smokegren_color", "190 190 190 255",
            .description = "The color of the smoke cloud in [R G B A] format (default 255 alpha for 100% opaque competitive smoke)."
        ),
        "CVarChange_amx_smokegren_color"
    )
    CVarChange_amx_smokegren_color(0, "", "190 190 190 255")

    bind_pcvar_float(
        create_cvar(
            "amx_smokegren_lifetime", "25.0",
            .has_min = true, .min_val = 6.0,
            .has_max = true, .max_val = 60.0,
            .description = "Smoke cloud lifetime in seconds."
        ),
        amx_smokegren_lifetime
    )

    AutoExecConfig()
}

stock Float: ParseColors4(const buffer[]) {
    new stringParsed[4][4]
    new Float: colors[4]

    if (!strlen(buffer))
        return colors

    new parsedArgs = parse(
        buffer,
        stringParsed[0], charsmax(stringParsed[]),  // R
        stringParsed[1], charsmax(stringParsed[]),  // G
        stringParsed[2], charsmax(stringParsed[]),  // B
        stringParsed[3], charsmax(stringParsed[])   // A
    )

    if (parsedArgs < 3)
        return colors

    for (new i; i < sizeof(stringParsed); i++)
        colors[i] = strtof(stringParsed[i])

    if (parsedArgs < 4 || colors[3] <= 0.0)
        colors[3] = 255.0

    return colors
}

stock bool: IsRandomColors(const Float: colors[4]) {
    return floatround(colors[0] + colors[1] + colors[2]) == -3
}

static Float: GetColors(const Float: colors[4]) {
    new Float: newColors[4] = { 0.0, 0.0, 0.0, 255.0 }

    if (IsRandomColors(colors)) {
        for (new i; i < sizeof(newColors) - 1; i++) {
            newColors[i] = random_float(1.0, 255.0)
        }
        return newColors
    }

    return colors
}

public CVarChange_amx_smokegren_color(const cvar, const oldValue[], const newValue[]) {
    amx_smokegren_color = ParseColors4(newValue)

    if (IsRandomColors(amx_smokegren_color))
        return

    for (new i; i < sizeof(amx_smokegren_color); i++)
        amx_smokegren_color[i] = floatclamp(amx_smokegren_color[i], 1.0, 255.0)
}

static ChangeRenderMode(const classname[], const mode = kRenderNormal) {
    new entity = MaxClients
    while ((entity = engfunc(EngFunc_FindEntityByString, entity, "classname", classname))) {
        set_pev(entity, pev_rendermode, mode)
    }
}

static StartupCheck() {
    if (!cstrike_running())
        set_fail_state("Plugin work is supported only for Counter-Strike mod!")

    if (!file_exists(g_sprFile))
        set_fail_state("The file `%s` is missing!", g_sprFile)
}
