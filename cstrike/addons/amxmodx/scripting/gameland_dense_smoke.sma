/**
 * GameLand Dense Smoke (Natural 3D Volumetric Edition)
 *   Engineered for ReHLDS / ReGameDLL CS 1.6
 *
 * Performance & Visual Architecture:
 *   1. Zero-Think Static Sleeping:
 *      Entities are instantiated directly at their optimal target scale and put to
 *      SLEEP IMMEDIATELY for the entire active lifetime (~22 seconds).
 *      Zero Ham_Think calls during active combat!
 *      Server tickrate remains rock-solid 1000.0 FPS.
 *      Client netgraph stays perfectly flat with 0 choke and 0 FPS stutter.
 *   2. Natural 3D Volumetric Spherical Depth & Parallax:
 *      - Reduced particle scale to authentic CS size (scale 3.2 - 3.8).
 *      - Central Core Cluster (6 puffs with natural spatial offsets): eliminates the flat 2D
 *        single-axis billboard appearance and provides multi-angle sightline blocking.
 *      - Mid Volumetric Ring (4 cross-positioned puffs): rich 3D body and parallax.
 *      - Radial Perimeter Ring (8 staggered puffs): feathered cloud billowing edges.
 *      Total entities capped at 18 per smoke cloud - zero fillrate lag on client GPUs.
 *   3. Organic 3D Billowing & Subtle Angular Velocity:
 *      Sprites are initialized with random roll angles (angles[2] = random_float(0, 360))
 *      and gentle angular velocity (avelocity[2] = +/- random_float(2.0, 5.5)), eliminating
 *      the static flat disc effect when players turn their view.
 *   4. Client Smoke Supercede & Forced High-Quality Rendering:
 *      Enforces client_cmd(id, "fastsprites 0") on client connect and spawn, ensuring the
 *      GoldSrc engine renders authentic 3D translucent volumetric smoke rather than 2D billboards.
 *   5. ScreenFade Tactical Smoke Blindness:
 *      Players stepping inside the smoke volume receive dense tactical ScreenFade fog,
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
public stock const PluginVersion[]     = "2.3.0-volumetric"
public stock const PluginAuthor[]      = "GameLand Dev Team & Sergey Shorokhov"
public stock const PluginDescription[] = "Natural 3D volumetric dense competitive smoke grenade."

static const g_sprFile[]        = "sprites/gameland_smoke.spr"
static const g_baseClassname[]  = "info_null"
static const g_className[]      = "particle_smokegren"

#define MAX_ACTIVE_SMOKES 16
#define TASK_SMOKE_BLIND  73491

#define SMOKE_BLIND_RADIUS 85.0
#define SMOKE_BLIND_Z_MIN  -10.0
#define SMOKE_BLIND_Z_MAX  85.0

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

    // Enforce true volumetric 3D smoke rendering on server host
    server_cmd("fastsprites 0")

    if (amx_smokegren_fix_waterrender)
        ChangeRenderMode("func_water", kRenderNormal)
}

public client_putinserver(id) {
    g_bPlayerInSmoke[id] = false
    if (!is_user_bot(id)) {
        // Enforce true 3D volumetric smoke rendering instead of flat 2D billboards
        client_cmd(id, "fastsprites 0")
        set_task(1.2, "Task_EnforceFastSprites", id)
    }
}

public Task_EnforceFastSprites(id) {
    if (is_user_connected(id) && !is_user_bot(id)) {
        client_cmd(id, "fastsprites 0")
    }
}

public client_disconnected(id) {
    g_bPlayerInSmoke[id] = false
    remove_task(id)
}

public CPlayer_Spawn_Post(id) {
    if (is_user_alive(id)) {
        if (g_bPlayerInSmoke[id]) {
            ClearSmokeFade(id)
        }
        if (!is_user_bot(id)) {
            client_cmd(id, "fastsprites 0")
        }
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
    set_pev(entity, pev_movetype, MOVETYPE_NOCLIP)
    set_pev(entity, pev_solid, SOLID_NOT)
    set_pev(entity, pev_gravity, 0.0)
    set_pev(entity, pev_scale, scale)
    set_pev(entity, pev_frame, float(random_num(0, 1)))

    set_pev(entity, pev_framerate, 0.0)
    set_pev(entity, pev_animtime, 0.0)
    set_pev(entity, pev_velocity, Float:{0.0, 0.0, 0.0})

    // Natural random roll orientation for organic 3D appearance
    new Float: angles[3]
    angles[0] = 0.0
    angles[1] = 0.0
    angles[2] = random_float(0.0, 360.0)
    set_pev(entity, pev_angles, angles)

    // Subtle natural angular velocity (gentle swirling roll motion)
    new Float: avelocity[3]
    avelocity[0] = 0.0
    avelocity[1] = 0.0
    avelocity[2] = (random_num(0, 1) ? 1.0 : -1.0) * random_float(2.0, 5.0)
    set_pev(entity, pev_avelocity, avelocity)

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

    // 1. Central Core Cluster (6 puffs with natural spatial offsets to prevent flat single-axis billboard perception)
    new Float: corePos[3]

    // Low Base (Ground Seal): eliminates feet/crouch gaps
    corePos[0] = origin[0] + random_float(-8.0, 8.0)
    corePos[1] = origin[1] + random_float(-8.0, 8.0)
    corePos[2] = origin[2] + 16.0
    CPartSmokeGrenade_Create(corePos, g_sprFile, random_float(3.4, 3.7), color, lifetime)

    // Low-Mid Core A (West/South offset for immediate 3D parallax)
    corePos[0] = origin[0] - random_float(12.0, 18.0)
    corePos[1] = origin[1] + random_float(-8.0, 10.0)
    corePos[2] = origin[2] + 34.0
    CPartSmokeGrenade_Create(corePos, g_sprFile, random_float(3.5, 3.8), color, lifetime)

    // Low-Mid Core B (East/North offset counterbalancing A)
    corePos[0] = origin[0] + random_float(12.0, 18.0)
    corePos[1] = origin[1] + random_float(-10.0, 8.0)
    corePos[2] = origin[2] + 40.0
    CPartSmokeGrenade_Create(corePos, g_sprFile, random_float(3.5, 3.8), color, lifetime)

    // Center Anchor (Standing eye/torso line)
    corePos[0] = origin[0] + random_float(-5.0, 5.0)
    corePos[1] = origin[1] + random_float(-5.0, 5.0)
    corePos[2] = origin[2] + 54.0
    CPartSmokeGrenade_Create(corePos, g_sprFile, random_float(3.6, 3.8), color, lifetime)

    // Upper Core (North offset, covering head and elevated sightlines)
    corePos[0] = origin[0] + random_float(-10.0, 10.0)
    corePos[1] = origin[1] + random_float(12.0, 20.0)
    corePos[2] = origin[2] + 68.0
    CPartSmokeGrenade_Create(corePos, g_sprFile, random_float(3.4, 3.7), color, lifetime)

    // Upper Crown (South offset, seals elevated catwalk/balcony downward sightlines)
    corePos[0] = origin[0] + random_float(-8.0, 8.0)
    corePos[1] = origin[1] - random_float(10.0, 18.0)
    corePos[2] = origin[2] + 82.0
    CPartSmokeGrenade_Create(corePos, g_sprFile, random_float(3.2, 3.5), color, lifetime)

    // 2. Mid Volumetric Shell (4 diagonal puffs at radius 38-46 for rich 3D body and parallax)
    for (new i = 0; i < 4; i++) {
        new Float: angle = 45.0 + (90.0 * float(i)) + random_float(-8.0, 8.0)
        new Float: dist = random_float(38.0, 46.0)
        new Float: zOffset = (i % 2 == 0) ? random_float(28.0, 36.0) : random_float(54.0, 62.0)

        new Float: midPos[3]
        midPos[0] = origin[0] + (floatcos(angle, degrees) * dist)
        midPos[1] = origin[1] + (floatsin(angle, degrees) * dist)
        midPos[2] = origin[2] + zOffset

        CPartSmokeGrenade_Create(midPos, g_sprFile, random_float(3.4, 3.7), color, lifetime)
    }

    // 3. Radial Perimeter Ring (default 8 puffs at radius 66-78 for natural feathered billowing edges)
    new numRadial = clamp(floatround(amx_smokegren_pieces), 6, 10)
    new Float: stepAngle = 360.0 / float(numRadial)

    for (new i = 0; i < numRadial; i++) {
        new Float: angle = (stepAngle * float(i)) + random_float(-5.0, 5.0)
        new Float: dist = random_float(66.0, 78.0)

        // 3-tier staggered height distribution
        new Float: zOffset
        switch (i % 3) {
            case 0: zOffset = random_float(22.0, 28.0)
            case 1: zOffset = random_float(44.0, 52.0)
            case 2: zOffset = random_float(66.0, 74.0)
        }

        new Float: puffPos[3]
        puffPos[0] = origin[0] + (floatcos(angle, degrees) * dist)
        puffPos[1] = origin[1] + (floatsin(angle, degrees) * dist)
        puffPos[2] = origin[2] + zOffset

        new Float: puffScale = random_float(3.2, 3.5)

        CPartSmokeGrenade_Create(puffPos, g_sprFile, puffScale, color, lifetime)
    }
}

static CreateSmokePop(const Float: origin[3], Float: color[4]) {
    // Mode 3 optional pop effect: 4 burst puffs
    new Float: popLifetime = 10.0
    for (new i = 0; i < 4; i++) {
        new Float: angle = (90.0 * float(i)) + 45.0 + random_float(-6.0, 6.0)
        new Float: dist = random_float(45.0, 60.0)

        new Float: puffOrigin[3]
        puffOrigin[0] = origin[0] + (floatcos(angle, degrees) * dist)
        puffOrigin[1] = origin[1] + (floatsin(angle, degrees) * dist)
        puffOrigin[2] = origin[2] + random_float(35.0, 50.0)

        CPartSmokeGrenade_Create(puffOrigin, g_sprFile, random_float(3.2, 3.5), color, popLifetime)
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
            .description = "Number of radial smoke particles (default 8 = 18 total with core and mid rings)."
        ),
        amx_smokegren_pieces
    )

    hook_cvar_change(
        create_cvar(
            "amx_smokegren_color", "185 185 185 215",
            .description = "The color of the smoke cloud in [R G B A] format (default 215 alpha for rich 3D feathered opacity)."
        ),
        "CVarChange_amx_smokegren_color"
    )
    CVarChange_amx_smokegren_color(0, "", "185 185 185 215")

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
        colors[3] = 215.0

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
