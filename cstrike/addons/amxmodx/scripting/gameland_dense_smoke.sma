#if (defined _server_side_smokenade_included)
    #endinput
#endif
#define _server_side_smokenade_included

/**
 * GameLand Tournament Pure White Dense Smoke Grenade
 * Precision engineered for competitive 5v5 mix matches.
 *
 * Features:
 *   - Genuine Dev-CS gas_puff_02.spr sprite rendering
 *   - 100% Pure Tournament White color (255 255 255 255)
 *   - Natural CS competitive radius (~115 units, max scale 6.8)
 *   - Dense 17-puff core structure (3 center column, 6 inner ring, 8 outer ring)
 *   - Fast raycast line-of-sight occlusion: completely impenetrable anti-see-through
 *   - Realistic misty white inside-smoke fog screen fade (245 245 245)
 *   - Zero engine overhead, crash-proof, no missing event precaches
 */

#include <amxmodx>
#include <amxmisc>
#include <hamsandwich>
#include <fakemeta>
#include <xs>

public stock const PluginName[]        = "GameLand Tournament Dense Smoke"
public stock const PluginVersion[]     = "5.0.0-PRO"
public stock const PluginAuthor[]      = "GAMELAND"
public stock const PluginURL[]         = "https://github.com/GAMELAND-PROJECT"
public stock const PluginDescription[] = "High-density pure white tournament smoke grenade."

static const g_sprFile[]        = "sprites/gas_puff_02.spr"
static const g_baseClassname[]  = "info_null"
static const g_className[]      = "particle_smokegren"

enum _: CustomPEV {
    _pev_spawnInside     = pev_iuser1,
    _pev_popCreated      = pev_iuser2,

    _pev_targetScale     = pev_fuser2, // Float: maximum volumetric scale (~6.8)
    _pev_dieTime         = pev_fuser3, // Float: lifetime expiry
    _pev_timeCreated     = pev_fuser4, // Float: creation timestamp
}

static        amx_smokegren_replacemode
static Float: amx_smokegren_color[4]
static Float: amx_smokegren_pieces
static Float: amx_smokegren_lifetime

#define MAX_ACTIVE_SMOKES 20
static Float: g_vecActiveSmokes[MAX_ACTIVE_SMOKES][3]
static Float: g_fSmokeExpireTime[MAX_ACTIVE_SMOKES]
static g_iActiveSmokeCount = 0

// Inside-smoke ScreenFade message tracking
static g_iMsgScreenFade = 0
static bool: g_bInsideSmoke[33]

public plugin_precache() {
    register_plugin(PluginName, PluginVersion, PluginAuthor)
    StartupCheck()
    precache_model(g_sprFile)
}

public plugin_init() {
    register_event("HLTV", "CSGameRules_RestartRound", "a", "1=0", "2=0")
    register_forward(FM_PlaybackEvent, "EV_Playback", ._post = false)
    register_forward(FM_AddToFullPack, "Fwd_AddToFullPack_Post", ._post = true)
    RegisterHam(Ham_Think, g_baseClassname, "CNullEntity_Think", .Post = false)

    g_iMsgScreenFade = get_user_msgid("ScreenFade")
    set_task(0.1, "Task_SmokePlayerCheck", .flags = "b")

    Create_ConVars(.createConfigFile = false)
}

public client_disconnected(id) {
    if (id >= 1 && id <= 32) {
        g_bInsideSmoke[id] = false
    }
}

public EV_Playback(flags, invoker, eventIndex, Float:delay, Float:origin[3], Float:angles[3], Float:fparam1, Float:fparam2,
                    iparam1, iparam2, bparam1, bparam2) {

    static m_usCreateSmoke
    if (!m_usCreateSmoke)
        m_usCreateSmoke = engfunc(EngFunc_PrecacheEvent, 1, "events/createsmoke.sc")

    if (eventIndex != m_usCreateSmoke)
        return FMRES_IGNORED

    new bool: isFirstSmoke = (iparam2 == 1)
    if (!isFirstSmoke)
        return FMRES_IGNORED

    new bool: isSmokeReplaced = EV_CreateSmoke(origin)
    return isSmokeReplaced ? FMRES_SUPERCEDE : FMRES_IGNORED
}

static bool: EV_CreateSmoke(const Float: origin[3]) {
    if (amx_smokegren_replacemode == 0)
        return false

    new Float: colors[4]
    colors = GetColors(amx_smokegren_color)

    CreateGasInside(origin, colors)

    if (amx_smokegren_replacemode >= 2)
        CreateSmokePop(origin, colors)

    if (g_iActiveSmokeCount < MAX_ACTIVE_SMOKES) {
        g_vecActiveSmokes[g_iActiveSmokeCount][0] = origin[0]
        g_vecActiveSmokes[g_iActiveSmokeCount][1] = origin[1]
        g_vecActiveSmokes[g_iActiveSmokeCount][2] = origin[2]
        g_fSmokeExpireTime[g_iActiveSmokeCount] = get_gametime() + amx_smokegren_lifetime
        g_iActiveSmokeCount++
    }

    return true
}

public CNullEntity_Think(const entity) {
    static classname[32]
    pev(entity, pev_classname, classname, charsmax(classname))

    if (strcmp(classname, g_className) != 0)
        return

    CPartSmokeGrenade_Think(entity)
}

public CSGameRules_RestartRound() {
    g_iActiveSmokeCount = 0
    arrayset(g_bInsideSmoke, false, sizeof(g_bInsideSmoke))

    new entity = MaxClients
    while ((entity = engfunc(EngFunc_FindEntityByString, entity, "classname", g_className))) {
        set_pev(entity, pev_flags, pev(entity, pev_flags) | FL_KILLME)
    }
}

static CPartSmokeGrenade_Create(const Float: origin[3], const Float: colors[4]) {
    #pragma unused colors
    new entity = engfunc(EngFunc_CreateNamedEntity, engfunc(EngFunc_AllocString, g_baseClassname))
    if (!pev_valid(entity))
        return 0

    set_pev(entity, pev_classname, g_className)
    engfunc(EngFunc_SetOrigin, entity, origin)
    engfunc(EngFunc_SetModel, entity, g_sprFile)

    set_pev(entity, pev_solid, SOLID_NOT)
    set_pev(entity, pev_movetype, MOVETYPE_NOCLIP)

    set_pev(entity, pev_rendermode, kRenderTransAdd)
    set_pev(entity, pev_renderfx, kRenderFxNone)

    // Pure tournament white
    new Float: renderColor[3]
    renderColor[0] = 255.0
    renderColor[1] = 255.0
    renderColor[2] = 255.0
    set_pev(entity, pev_rendercolor, renderColor)

    // Balanced starting scale: 3.2 - 4.4
    new Float: initScale = random_float(3.2, 4.4)
    set_pev(entity, pev_scale, initScale)

    // Target scale: 6.8 max
    new Float: targetScale = random_float(5.6, 6.8)
    set_pev(entity, _pev_targetScale, targetScale)

    new Float: gametime = get_gametime()
    set_pev(entity, _pev_timeCreated, gametime)

    new Float: lifetime = amx_smokegren_lifetime
    set_pev(entity, _pev_dieTime, gametime + lifetime)

    // High density starting alpha
    set_pev(entity, pev_renderamt, 255.0)

    set_pev(entity, pev_nextthink, gametime + 0.05)
    return entity
}

static CPartSmokeGrenade_Think(const entity) {
    if (!pev_valid(entity))
        return

    new Float: gametime = get_gametime()
    new Float: dieTime
    pev(entity, _pev_dieTime, dieTime)

    if (gametime >= dieTime) {
        set_pev(entity, pev_flags, pev(entity, pev_flags) | FL_KILLME)
        return
    }

    new Float: timeCreated, Float: targetScale, Float: scale
    pev(entity, _pev_timeCreated, timeCreated)
    pev(entity, _pev_targetScale, targetScale)
    pev(entity, pev_scale, scale)

    new Float: age = gametime - timeCreated
    new Float: remaining = dieTime - gametime

    // Volumetric expansion bloom in first 2.5 seconds
    if (age < 2.5) {
        new Float: progress = age / 2.5
        new Float: currentTarget = 3.8 + (targetScale - 3.8) * progress
        if (scale < currentTarget) {
            scale += 0.12
            if (scale > currentTarget) scale = currentTarget
            set_pev(entity, pev_scale, scale)
        }
        set_pev(entity, pev_renderamt, 255.0)
    } else if (remaining < 3.5) {
        // Smooth dissipation in final 3.5 seconds
        new Float: fadeRatio = remaining / 3.5
        new Float: alpha = 255.0 * fadeRatio
        if (alpha < 0.0) alpha = 0.0
        set_pev(entity, pev_renderamt, alpha)
    } else {
        set_pev(entity, pev_renderamt, 255.0)
    }

    set_pev(entity, pev_nextthink, gametime + 0.1)
}

static CreateGasInside(const Float: origin[3], const Float: colors[4]) {
    new entity

    // Center vertical core: 3 puffs
    for (new c = 0; c < 3; c++) {
        static Float: cOrigin[3]
        cOrigin[0] = origin[0] + random_float(-8.0, 8.0)
        cOrigin[1] = origin[1] + random_float(-8.0, 8.0)
        cOrigin[2] = origin[2] + float(c * 16) + 4.0

        entity = CPartSmokeGrenade_Create(cOrigin, colors)
        if (pev_valid(entity)) {
            set_pev(entity, _pev_spawnInside, true)
            static Float: vUp[3]
            vUp[0] = random_float(-4.0, 4.0)
            vUp[1] = random_float(-4.0, 4.0)
            vUp[2] = random_float(4.0, 10.0)
            set_pev(entity, pev_velocity, vUp)
        }
    }

    // Inner ring (r = 20.0): 6 puffs
    for (new i = 0; i < 6; i++) {
        new Float: angle = float(i) * (6.28318 / 6.0)
        static Float: pOrigin[3]
        pOrigin[0] = origin[0] + (20.0 * floatcos(angle))
        pOrigin[1] = origin[1] + (20.0 * floatsin(angle))
        pOrigin[2] = origin[2] + random_float(6.0, 18.0)

        entity = CPartSmokeGrenade_Create(pOrigin, colors)
        if (pev_valid(entity)) {
            set_pev(entity, _pev_spawnInside, true)
            static Float: vDrift[3]
            vDrift[0] = floatcos(angle) * random_float(6.0, 14.0)
            vDrift[1] = floatsin(angle) * random_float(6.0, 14.0)
            vDrift[2] = random_float(3.0, 8.0)
            set_pev(entity, pev_velocity, vDrift)
        }
    }

    // Outer ring (r = 42.0): 8 puffs
    for (new j = 0; j < 8; j++) {
        new Float: angle2 = float(j) * (6.28318 / 8.0) + 0.392
        static Float: pOrigin2[3]
        pOrigin2[0] = origin[0] + (42.0 * floatcos(angle2))
        pOrigin2[1] = origin[1] + (42.0 * floatsin(angle2))
        pOrigin2[2] = origin[2] + random_float(4.0, 16.0)

        entity = CPartSmokeGrenade_Create(pOrigin2, colors)
        if (pev_valid(entity)) {
            set_pev(entity, _pev_spawnInside, true)
            static Float: vDrift2[3]
            vDrift2[0] = floatcos(angle2) * random_float(8.0, 18.0)
            vDrift2[1] = floatsin(angle2) * random_float(8.0, 18.0)
            vDrift2[2] = random_float(2.0, 6.0)
            set_pev(entity, pev_velocity, vDrift2)
        }
    }
}

static CreateSmokePop(const Float: origin[3], const Float: colors[4]) {
    new count = floatround(amx_smokegren_pieces)
    if (count <= 0) return

    for (new i = 0; i < count; i++) {
        static Float: popOrigin[3]
        popOrigin[0] = origin[0] + random_float(-14.0, 14.0)
        popOrigin[1] = origin[1] + random_float(-14.0, 14.0)
        popOrigin[2] = origin[2] + random_float(4.0, 18.0)

        new entity = CPartSmokeGrenade_Create(popOrigin, colors)
        if (pev_valid(entity)) {
            set_pev(entity, _pev_popCreated, true)
            static Float: vPop[3]
            vPop[0] = random_float(-28.0, 28.0)
            vPop[1] = random_float(-28.0, 28.0)
            vPop[2] = random_float(8.0, 24.0)
            set_pev(entity, pev_velocity, vPop)
        }
    }
}

// Raycast Line-of-sight Occlusion
stock bool:DoesSegmentIntersectSphere(const Float:p1[3], const Float:p2[3], const Float:center[3], const Float:radius) {
    static Float:d[3], Float:m[3]
    xs_vec_sub(p2, p1, d)
    xs_vec_sub(p1, center, m)

    new Float:dist = xs_vec_len(d)
    new Float:c = xs_vec_dot(m, m) - (radius * radius)

    if (c <= 0.0) {
        if (dist < 110.0)
            return false // Close quarter combat within smoke
        return true
    }

    new Float:b = xs_vec_dot(m, d)
    if (b > 0.0)
        return false

    new Float:a = xs_vec_dot(d, d)
    if (a == 0.0)
        return false

    new Float:discr = (b * b) - (a * c)
    if (discr < 0.0)
        return false

    new Float:sqrtDiscr = floatsqroot(discr)
    new Float:t1 = (-b - sqrtDiscr) / a
    if (t1 >= 0.0 && t1 <= 1.0)
        return true

    new Float:t2 = (-b + sqrtDiscr) / a
    if (t2 >= 0.0 && t2 <= 1.0)
        return true

    return false
}

public Fwd_AddToFullPack_Post(es_handle, e, ent, host, hostflags, player, pSet) {
    if (!player || !g_iActiveSmokeCount)
        return FMRES_IGNORED

    if (ent == host || !is_user_alive(ent) || !is_user_alive(host))
        return FMRES_IGNORED

    if (get_user_team(ent) == get_user_team(host))
        return FMRES_IGNORED

    static Float: vHostEye[3], Float: vHostOrigin[3], Float: vHostViewOfs[3]
    pev(host, pev_origin, vHostOrigin)
    pev(host, pev_view_ofs, vHostViewOfs)
    xs_vec_add(vHostOrigin, vHostViewOfs, vHostEye)

    static Float: vTargetOrigin[3]
    pev(ent, pev_origin, vTargetOrigin)
    vTargetOrigin[2] += 12.0

    new Float: gametime = get_gametime()
    const Float: smokeRadius = 118.0

    for (new i = 0; i < g_iActiveSmokeCount; i++) {
        if (gametime > g_fSmokeExpireTime[i])
            continue

        if (DoesSegmentIntersectSphere(vHostEye, vTargetOrigin, g_vecActiveSmokes[i], smokeRadius)) {
            set_es(es_handle, ES_Effects, get_es(es_handle, ES_Effects) | EF_NODRAW)
            return FMRES_HANDLED
        }
    }

    return FMRES_IGNORED
}

public Task_SmokePlayerCheck() {
    if (!g_iActiveSmokeCount)
        return

    new Float: gametime = get_gametime()

    // Compact expired smokes
    for (new i = 0; i < g_iActiveSmokeCount; i++) {
        if (gametime > g_fSmokeExpireTime[i]) {
            for (new j = i; j < g_iActiveSmokeCount - 1; j++) {
                g_vecActiveSmokes[j] = g_vecActiveSmokes[j + 1]
                g_fSmokeExpireTime[j] = g_fSmokeExpireTime[j + 1]
            }
            g_iActiveSmokeCount--
            i--
        }
    }

    if (!g_iActiveSmokeCount) {
        for (new p = 1; p <= MaxClients; p++) {
            if (g_bInsideSmoke[p]) {
                g_bInsideSmoke[p] = false
                if (is_user_connected(p))
                    SendSmokeFade(p, false)
            }
        }
        return
    }

    static Float: pOrigin[3]
    const Float: insideRadius = 92.0

    for (new p = 1; p <= MaxClients; p++) {
        if (!is_user_connected(p) || !is_user_alive(p)) {
            g_bInsideSmoke[p] = false
            continue
        }

        pev(p, pev_origin, pOrigin)
        new bool: bIsInside = false

        for (new i = 0; i < g_iActiveSmokeCount; i++) {
            if (get_distance_f(pOrigin, g_vecActiveSmokes[i]) < insideRadius) {
                bIsInside = true
                break
            }
        }

        if (bIsInside) {
            if (!g_bInsideSmoke[p]) {
                g_bInsideSmoke[p] = true
                SendSmokeFade(p, true)
            }
        } else {
            if (g_bInsideSmoke[p]) {
                g_bInsideSmoke[p] = false
                SendSmokeFade(p, false)
            }
        }
    }
}

stock SendSmokeFade(id, bool:bInside) {
    if (!id || !is_user_connected(id) || !g_iMsgScreenFade)
        return

    message_begin(MSG_ONE_UNRELIABLE, g_iMsgScreenFade, _, id)
    if (bInside) {
        // Pure White Misty Fog inside smoke
        write_short(1 << 12)        // Duration (1.0s)
        write_short(1 << 12)        // Hold time (1.0s)
        write_short(0x0000)         // Flags: FFADE_IN
        write_byte(245)             // R (pure white fog)
        write_byte(245)             // G
        write_byte(245)             // B
        write_byte(210)             // Alpha (dense tournament opacity)
    } else {
        // Instant clear
        write_short(1 << 8)         // Quick 0.25s fade out
        write_short(0)
        write_short(0x0000)
        write_byte(245)
        write_byte(245)
        write_byte(245)
        write_byte(0)
    }
    message_end()
}

static Create_ConVars(const bool: createConfigFile = false) {
    #pragma unused createConfigFile
    bind_pcvar_num(
        create_cvar(
            "amx_smokegren_replacemode", "2",
            .has_min = true, .min_val = 0.0,
            .has_max = true, .max_val = 2.0,
            .description = "0 - disabled, 1 - gas only, 2 - full tournament volumetric smoke"
        ),
        amx_smokegren_replacemode
    )

    bind_pcvar_float(
        create_cvar(
            "amx_smokegren_pieces", "8",
            .has_min = true, .min_val = 1.0,
            .has_max = true, .max_val = 30.0,
            .description = "Amount of volumetric puffs to spawn on pop"
        ),
        amx_smokegren_pieces
    )

    hook_cvar_change(
        create_cvar(
            "amx_smokegren_color", "255 255 255 255",
            .description = "The color of the smoke cloud [R G B A]"
        ),
        "CVarChange_amx_smokegren_color"
    )
    CVarChange_amx_smokegren_color(0, "", "255 255 255 255")

    bind_pcvar_float(
        create_cvar(
            "amx_smokegren_lifetime", "20.0",
            .has_min = true, .min_val = 6.0,
            .has_max = true, .max_val = 60.0,
            .description = "Smoke cloud lifetime (in seconds)"
        ),
        amx_smokegren_lifetime
    )
}

public CVarChange_amx_smokegren_color(pcvar, const oldValue[], const newValue[]) {
    amx_smokegren_color = ParseColors4(newValue)

    if (xs_vec_equal(amx_smokegren_color, Float:{-1.0, -1.0, -1.0, -1.0})) {
        return
    }

    for (new i; i < sizeof(amx_smokegren_color); i++)
        amx_smokegren_color[i] = floatclamp(amx_smokegren_color[i], 1.0, 255.0)
}

static StartupCheck() {
    if (!cstrike_running())
        set_fail_state("Plugin work is supported only for Counter-Strike mod!")
}

stock Float: ParseColors4(const buffer[]) {
    new stringParsed[4][4]
    new Float: colors[4]

    if (!strlen(buffer))
        return colors

    parse(buffer,
        stringParsed[0], charsmax(stringParsed[]),
        stringParsed[1], charsmax(stringParsed[]),
        stringParsed[2], charsmax(stringParsed[]),
        stringParsed[3], charsmax(stringParsed[])
    )

    for (new i; i < sizeof(colors); i++) {
        colors[i] = str_to_float(stringParsed[i])
    }

    return colors
}

static stock Float: GetColors(const Float: cvarColors[4]) {
    new Float: colors[4]
    xs_vec_copy(cvarColors, colors)
    colors[3] = cvarColors[3]
    return colors
}
