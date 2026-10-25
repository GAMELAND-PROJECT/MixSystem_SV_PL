/**
 * Server-Side SmokeNade by Sergey Shorokhov
 *   06.10.2023
 *   https://github.com/wopox1337/
 *
 *
 * Description:
 *   Is an AMXModX plugin that enhances the smoke grenade effects in Counter-Strike 1.6 (and Counter-Strike Condition Zero).
 *
 *   This plugin recreates smoke grenade effects (puffs of smoke) on the server side,
 *   provides a more realistic look to smoke grenades in the game
 *   (as it was changed in later iterations of the game such as CS:S, CS:GO, CS2).
 *
 * Why is it needed:
 *   The default smoke sprite (`sprites/gas_puff_01.spr`) is too transparent
 *   and doesn't allow you to take advantage of the smoke grenade in gameplay.
 *
 * How it works:
 *   The plugin blocks the sending of the event to the game client
 *   and recreates smoke clubs using server-side entities,
 *   exactly repeating the shape and animation of the standard smoke.
 *
 * Important note:
 *   If the smoke effect is fully recreated (`amx_smokegren_replacemode` == 3), the load is increased 2x.
 *
 *   Using full smoke grenade recreation (3) is not recommended for servers
 *   that have more than 10 players online (e.g. servers with 32\32 players online).
 *
 *   Also be careful with setting the parameter `amx_smokegren_pieces`,
 *   it directly affects the shape and quality of the smoke grenade,
 *   affecting the server load when using smoke grenades.
 *
 *   In special cases it may be necessary to set a larger number of allocated edicts
 *   using the startup parameter `-num_edicts` (at least 2000).
 *
 * Calculations.
 *   With standard parameters:
 *     - amx_smokegren_replacemode 1
 *     - amx_smokegren_pieces 8
 *   One smoke cloud will create 17 entities.
 *
 *   At maximum parameters:
 *     - amx_smokegren_replacemode 3
 *     - amx_smokegren_pieces 10
 *   One smoke cloud will create 41 entities.
 *
 * Advantages over standard game smoke:
 *   - Improved transparency of the smoke cloud;
 *   - Fixed poor smoke density in 16-bit video game mode;
 *   - Smoke doesn't disappear on HLTV;
 *   - Smoke can't be abused by reconnecting to the server;
 *   - Smoke is always created (even if the client has a congested network channel);
 *   - Ability to change the visual look of the smoke cloud.
 *
 * Advantages to other similar plugins:
 *   - Ability to set any custom sprite to display smoke;
 *   - Client FPS doesn't drop much;
 *   - Server FPS doesn't drop much;
 *   - The server doesn't flood the client's network channel to display the smoke cloud;
 *   - Doesn't break compatibility with the game:
 *       - Bots understand where smoke is located;
 *       - Cannot see nickname through smoke (mp_playerid);
 *       - Hostages can react to smoke grenade;
 *       - Overview map can show smokes.
 *   - Easy to adjust the color, duration and performance of the smoke cloud;
 *   - No render bugs when positioning the smoke cloud on water;
 *   - Smoke cloud has a very close to the original visual appearance (authenticity);
 *   - Smoke cloud doesn't stay in a new round;
 *   - Cannot be abused with the client command `fastsprites`;
 *   - Smoke doesn't disappear before its lifetime expires;
 *   - Smoke doesn't disappear if the player's internet connection is poor;
 *   - Smoke doesn't disappear if you move away from it.
 *   - Smoke doesn't flicker.
 *
 * Acknowledgements:
 *   - ReGameDLL authors;
 *   - To everyone who has previously tried custom smoke and their code examples;
 *   - To the Counter-Strike developers (for their bugs, including);
 *   - Community https://Dev-CS.ru/ (the most friendly and experienced team of developers).
 *
 * TODO:
 *   - Correct the remaining visual inaccuracies.
 *   - Implement API;
 *   - Improve integration with GameDLL;
 *   - Optimize sprite;
 *
 * Known bugs:
 *   - If the smoke duration changes, the grenade entity may not match the smoke duration.
 *
 */

#include <amxmodx>
#include <amxmisc>
#include <hamsandwich>
#include <fakemeta>
#include <xs>


public stock const PluginName[]        = "Server-Side SmokeNade"
public stock const PluginVersion[]     = "1.0.0-beta.2"
public stock const PluginAuthor[]      = "Sergey Shorokhov"
public stock const PluginURL[]         = "https://github.com/wopox1337/ServerSide_SmokeNade"
public stock const PluginDescription[] = "Replacing client smoke with Server-Side SmokeNade."


static const g_sprFile[]        = "sprites/gas_puff_02.spr"
// https://github.com/s1lentq/ReGameDLL_CS/blob/1e49d947927e7f6f2fd70d8398e4a9519a34450a/regamedll/dlls/subs.h#L31
static const g_baseClassname[]  = "info_null"
static const g_className[]      = "particle_smokegren"

enum _: CustomPEV {
    _pev_spawnInside     = pev_iuser1,
    _pev_popCreated      = pev_iuser2,
    _pev_isClearing      = pev_iuser3, // 0 = normal, 1 = blast clearing, 2 = reforming

    _pev_clearedUntil    = pev_fuser1, // Float: timestamp when cleared state ends
    _pev_targetScale     = pev_fuser2, // Float: maximum volumetric scale (~3.95)
    _pev_dieTime         = pev_fuser3, // Float: lifetime expiry
    _pev_timeCreated     = pev_fuser4, // Float: creation timestamp

    _pev_restoreOrigin   = pev_vuser1, // Float: [3] original rest position
}

static        amx_smokegren_replacemode
static        amx_smokegren_fix_waterrender
static Float: amx_smokegren_color[4]
static Float: amx_smokegren_pieces
static Float: amx_smokegren_lifetime

#define MAX_ACTIVE_SMOKES 20
static Float: g_vecActiveSmokes[MAX_ACTIVE_SMOKES][3]
static Float: g_fSmokeExpireTime[MAX_ACTIVE_SMOKES]
static Float: g_fSmokeClearedUntil[MAX_ACTIVE_SMOKES]
static g_iActiveSmokeCount = 0

// CS2-style Bullet Tunnels through smoke
#define MAX_BULLET_TUNNELS 12
static Float: g_vecTunnelSrc[MAX_BULLET_TUNNELS][3]
static Float: g_vecTunnelEnd[MAX_BULLET_TUNNELS][3]
static Float: g_fTunnelExpire[MAX_BULLET_TUNNELS]
static g_iTunnelHead = 0

static g_iMsgScreenFade
static bool: g_bInsideSmoke[33]

public plugin_precache() {
    #if (!defined PluginDescription)
        register_plugin(PluginName, PluginVersion, PluginAuthor)
    #endif

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

    // CS2 Mechanics: HE Grenade smoke clearing & Bullet holes (Pure HamSandwich & FakeMeta)
    RegisterHam(Ham_Think, "grenade", "Fwd_GrenadeThink_Post", .Post = true)
    RegisterHam(Ham_TraceAttack, "worldspawn", "Fwd_TraceAttack_Post", .Post = true)
    RegisterHam(Ham_TraceAttack, "player", "Fwd_TraceAttack_Post", .Post = true)

    Create_ConVars(.createConfigFile = true)

    if (amx_smokegren_fix_waterrender)
        ChangeRenderMode("func_water", kRenderNormal)
}

public client_disconnected(id) {
    if (id >= 1 && id <= 32) {
        g_bInsideSmoke[id] = false
    }
}

public EV_Playback(flags, invoker, eventIndex, Float: delay, Float: origin[3],
                    Float: angles[3], Float: fparam1, Float: fparam2,
                    iparam1, iparam2, bparam1, bparam2) {

    // https://github.com/s1lentq/ReGameDLL_CS/blob/1e49d947927e7f6f2fd70d8398e4a9519a34450a/regamedll/dlls/wpn_shared/wpn_smokegrenade.cpp#L34
    static m_usCreateSmoke
    if (!m_usCreateSmoke)
        m_usCreateSmoke = engfunc(EngFunc_PrecacheEvent, 1, "events/createsmoke.sc")

    static m_usCreateExplosion
    if (!m_usCreateExplosion)
        m_usCreateExplosion = engfunc(EngFunc_PrecacheEvent, 1, "events/createexplosion.sc")

    if (eventIndex == m_usCreateExplosion && g_iActiveSmokeCount > 0) {
        Trigger_Smoke_Clearing(origin)
        return FMRES_IGNORED
    }

    if (invoker >= 1 && invoker <= MaxClients && g_iActiveSmokeCount > 0) {
        static Float: vEye[3], Float: vAim[3], Float: vEnd[3]
        static Float: vViewOfs[3]
        pev(invoker, pev_origin, vEye)
        pev(invoker, pev_view_ofs, vViewOfs)
        xs_vec_add(vEye, vViewOfs, vEye)

        velocity_by_aim(invoker, 4096, vAim)
        xs_vec_add(vEye, vAim, vEnd)

        On_Bullet_Fired(vEye, vEnd)
    }

    if (eventIndex != m_usCreateSmoke)
        return FMRES_IGNORED

    new bool: isFirstSmoke = (iparam2 == 1)
    if (!isFirstSmoke)
        return FMRES_IGNORED

    new bool: isSmokeReplaced = EV_CreateSmoke(origin)
    return isSmokeReplaced ? FMRES_SUPERCEDE : FMRES_IGNORED
}

static bool: EV_CreateSmoke(const Float: origin[3]) {
    // https://github.com/s1lentq/ReGameDLL_CS/blob/1e49d947927e7f6f2fd70d8398e4a9519a34450a/regamedll/dlls/ggrenade.cpp#L603
    if (amx_smokegren_replacemode == 0)
        return false

    new Float: colors[4]
    colors = GetColors(amx_smokegren_color)

    CreateGasInside(origin, colors)

    if (amx_smokegren_replacemode >= 2)
        CreateSmokePop(origin, colors)

    // Track active smoke cloud for real-time raycast line-of-sight occlusion
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
    g_iTunnelHead = 0
    arrayset(g_bInsideSmoke, false, sizeof(g_bInsideSmoke))
    for (new i = 0; i < MAX_ACTIVE_SMOKES; i++) {
        g_fSmokeClearedUntil[i] = 0.0
    }
    for (new i = 0; i < MAX_BULLET_TUNNELS; i++) {
        g_fTunnelExpire[i] = 0.0
    }

    new entity = MaxClients
    while ((entity = engfunc(EngFunc_FindEntityByString, entity, "classname", g_className))) {
        set_pev(entity, pev_flags, pev(entity, pev_flags) | FL_KILLME)

        #if (defined DEBUG)
            entityCount(-1)
        #endif
    }
}


// ============================================================================
// CS2 MECHANICS: HE GRENADE BLAST CLEARING & REFORMING
// ============================================================================

public Fwd_GrenadeThink_Post(const ent) {
    if (!g_iActiveSmokeCount || !pev_valid(ent))
        return HAM_IGNORED

    static Float: flDmg
    pev(ent, pev_dmg, flDmg)
    // HE grenades have pev_dmg > 40.0; flashbang and smoke have pev_dmg == 0
    if (flDmg > 40.0) {
        static Float: flNextThink
        pev(ent, pev_nextthink, flNextThink)
        if (flNextThink <= 0.0 || (pev(ent, pev_flags) & FL_KILLME)) {
            static Float: explosionOrigin[3]
            pev(ent, pev_origin, explosionOrigin)
            Trigger_Smoke_Clearing(explosionOrigin)
        }
    }
    return HAM_IGNORED
}

static Trigger_Smoke_Clearing(const Float: explosionOrigin[3]) {
    new Float: gametime = get_gametime()
    const Float: BLAST_CLEAR_RADIUS = 250.0

    // 1. Temporarily clear line-of-sight occlusion on nearby smoke clouds (2.8 seconds)
    for (new i = 0; i < g_iActiveSmokeCount; i++) {
        if (gametime > g_fSmokeExpireTime[i])
            continue

        if (get_distance_f(explosionOrigin, g_vecActiveSmokes[i]) < (BLAST_CLEAR_RADIUS + 75.0)) {
            g_fSmokeClearedUntil[i] = gametime + 2.8
        }
    }

    // 2. Displace & dissolve smoke puffs in the blast crater zone
    new entity = MaxClients
    while ((entity = engfunc(EngFunc_FindEntityByString, entity, "classname", g_className))) {
        static Float: puffOrigin[3]
        pev(entity, pev_origin, puffOrigin)
        new Float: dist = get_distance_f(puffOrigin, explosionOrigin)
        if (dist < BLAST_CLEAR_RADIUS) {
            // Save original rest position so it can billow back smoothly
            static Float: restPos[3]
            pev(entity, _pev_restoreOrigin, restPos)
            if (xs_vec_equal(restPos, Float:{0.0, 0.0, 0.0})) {
                set_pev(entity, _pev_restoreOrigin, puffOrigin)
            }

            // Radial blast impulse: violently blow puffs away from explosion
            static Float: blastDir[3]
            xs_vec_sub(puffOrigin, explosionOrigin, blastDir)
            if (xs_vec_len(blastDir) < 1.0) {
                blastDir[0] = random_float(-1.0, 1.0)
                blastDir[1] = random_float(-1.0, 1.0)
                blastDir[2] = 0.6
            }
            xs_vec_normalize(blastDir, blastDir)

            new Float: force = (1.0 - (dist / BLAST_CLEAR_RADIUS)) * 160.0 + 50.0
            static Float: blastVel[3]
            blastVel[0] = blastDir[0] * force
            blastVel[1] = blastDir[1] * force
            blastVel[2] = (blastDir[2] * force) + 28.0
            set_pev(entity, pev_velocity, blastVel)

            // Mark cleared state for 2.8s
            set_pev(entity, _pev_clearedUntil, gametime + 2.8)
            set_pev(entity, _pev_isClearing, 1)
        }
    }

    // 3. Clear inside-smoke fog for any player caught in the blast clearing zone
    static Float: pOrigin[3]
    for (new p = 1; p <= MaxClients; p++) {
        if (!is_user_connected(p) || !is_user_alive(p))
            continue

        pev(p, pev_origin, pOrigin)
        if (get_distance_f(pOrigin, explosionOrigin) < BLAST_CLEAR_RADIUS) {
            if (g_bInsideSmoke[p]) {
                g_bInsideSmoke[p] = false
                SendSmokeFade(p, false)
            }
        }
    }
}

// ============================================================================
// CS2 MECHANICS: BULLET HOLES & VISION TUNNELS THROUGH SMOKE
// ============================================================================

public Fwd_TraceAttack_Post(victim, attacker, Float:damage, Float:direction[3], tr, bitsDamageType) {
    if (!g_iActiveSmokeCount || attacker < 1 || attacker > MaxClients || !is_user_connected(attacker))
        return HAM_IGNORED

    static Float: vecSrc[3], Float: vecEnd[3]
    static Float: vViewOfs[3]
    pev(attacker, pev_origin, vecSrc)
    pev(attacker, pev_view_ofs, vViewOfs)
    xs_vec_add(vecSrc, vViewOfs, vecSrc)

    get_tr2(tr, TR_vecEndPos, vecEnd)

    On_Bullet_Fired(vecSrc, vecEnd)
    return HAM_IGNORED
}

static On_Bullet_Fired(const Float: vecSrc[3], const Float: vecEnd[3]) {
    new Float: gametime = get_gametime()
    const Float: smokeRadius = 132.0
    new bool: bHitSmoke = false

    for (new i = 0; i < g_iActiveSmokeCount; i++) {
        if (gametime > g_fSmokeExpireTime[i])
            continue

        if (DoesSegmentIntersectSphere(vecSrc, vecEnd, g_vecActiveSmokes[i], smokeRadius)) {
            bHitSmoke = true
            break
        }
    }

    if (!bHitSmoke)
        return

    // 1. Register temporary vision tunnel through the smoke (0.40s duration)
    g_vecTunnelSrc[g_iTunnelHead] = vecSrc
    g_vecTunnelEnd[g_iTunnelHead] = vecEnd
    g_fTunnelExpire[g_iTunnelHead] = gametime + 0.40
    g_iTunnelHead = (g_iTunnelHead + 1) % MAX_BULLET_TUNNELS

    // 2. Visual reaction: part/compress puffs along the bullet path
    new entity = MaxClients
    while ((entity = engfunc(EngFunc_FindEntityByString, entity, "classname", g_className))) {
        static Float: puffOrigin[3]
        pev(entity, pev_origin, puffOrigin)
        new Float: distToBullet = DistancePointToSegment(puffOrigin, vecSrc, vecEnd)
        if (distToBullet < 38.0) {
            // Shrink scale temporarily to open a physical bullet seam
            static Float: curScale
            pev(entity, pev_scale, curScale)
            if (curScale > 1.6) {
                set_pev(entity, pev_scale, curScale * 0.68)
            }
        }
    }
}

static CPartSmokeGrenade_Create(const Float: origin[3], const Float: velocity[3],
                        const model[], const Float: scale,
                        const Float: color[4] = { 255.0, 255.0, 255.0, 255.0 }) {

    new entity = engfunc(EngFunc_CreateNamedEntity, engfunc(EngFunc_AllocString, g_baseClassname))
    set_pev(entity, pev_classname, g_className)

    engfunc(EngFunc_SetModel, entity, model)
    engfunc(EngFunc_SetOrigin, entity, origin)
    set_pev(entity, pev_velocity, velocity)
    set_pev(entity, pev_movetype, MOVETYPE_NOCLIP)
    set_pev(entity, pev_gravity, 0.0)
    set_pev(entity, pev_scale, scale)

    set_pev(entity, pev_rendermode, kRenderTransAlpha)
    set_pev(entity, pev_rendercolor, color)
    set_pev(entity, pev_renderamt, color[3])
    set_pev(entity, pev_fuser1, color[3])
    set_pev(entity, _pev_timeCreated, get_gametime())

    #if (defined DEBUG)
        client_print(0, print_center, "Smoke puffs entity count: `%i`", entityCount(1))
    #endif

    return entity
}

static CPartSmokeGrenade_Think(const entity) {
    new Float: gametime = get_gametime()
    new Float: timeCreated, Float: dieTime
    pev(entity, _pev_timeCreated, timeCreated)
    pev(entity, _pev_dieTime, dieTime)
    new Float: age = gametime - timeCreated
    new Float: remainingTime = dieTime - gametime

    static Float: scale, Float: targetScale
    pev(entity, pev_scale, scale)
    pev(entity, _pev_targetScale, targetScale)

    new isClearing = pev(entity, _pev_isClearing)
    new Float: clearedUntil
    pev(entity, _pev_clearedUntil, clearedUntil)

    // ========================================================================
    // CS2 Blast Dispersion & Reforming Logic
    // ========================================================================
    if (isClearing == 1) {
        // State 1: Puffs actively blown away and dissolving by HE blast
        if (gametime < clearedUntil) {
            static Float: velocity[3]
            pev(entity, pev_velocity, velocity)
            xs_vec_mul_scalar(velocity, 0.90, velocity)
            set_pev(entity, pev_velocity, velocity)

            if (scale > 1.2) {
                scale *= 0.88
                set_pev(entity, pev_scale, scale)
            }

            new Float: amt
            pev(entity, pev_renderamt, amt)
            amt *= 0.65
            set_pev(entity, pev_renderamt, amt)

            if (amt < 10.0) {
                set_pev(entity, pev_effects, pev(entity, pev_effects) | EF_NODRAW)
            }

            set_pev(entity, pev_nextthink, gametime + 0.05)
            return
        } else {
            // Time to reform! Switch to State 2
            set_pev(entity, _pev_isClearing, 2)
            set_pev(entity, pev_effects, pev(entity, pev_effects) & ~EF_NODRAW)
            isClearing = 2
        }
    }

    if (isClearing == 2) {
        // State 2: CS2-Style Inward Billow (Smoke rushes back into place!)
        static Float: currPos[3], Float: restPos[3], Float: returnVel[3]
        pev(entity, pev_origin, currPos)
        pev(entity, _pev_restoreOrigin, restPos)

        xs_vec_sub(restPos, currPos, returnVel)
        new Float: distToRest = xs_vec_len(returnVel)
        if (distToRest > 4.0) {
            xs_vec_normalize(returnVel, returnVel)
            xs_vec_mul_scalar(returnVel, floatmin(distToRest * 1.5, 95.0), returnVel)
            set_pev(entity, pev_velocity, returnVel)
        } else {
            set_pev(entity, pev_velocity, Float:{0.0, 0.0, 0.0})
        }

        // Expand scale smoothly back towards target
        if (scale < targetScale) {
            scale += (targetScale - scale) * 0.15 + 0.05
            if (scale > targetScale)
                scale = targetScale
            set_pev(entity, pev_scale, scale)
        }

        // Fade renderamt back to 255.0
        new Float: amt
        pev(entity, pev_renderamt, amt)
        if (amt < 255.0) {
            amt += 22.0
            if (amt > 255.0)
                amt = 255.0
            set_pev(entity, pev_renderamt, amt)
        }

        // Fully reformed?
        if (amt >= 255.0 && scale >= (targetScale - 0.1)) {
            set_pev(entity, _pev_isClearing, 0)
            set_pev(entity, pev_velocity, Float:{0.0, 0.0, 0.0})
        }

        set_pev(entity, pev_nextthink, gametime + 0.05)
        return
    }

    // ========================================================================
    // CS2-Style Initial Volumetric Bloom Phase (First 1.25s)
    // ========================================================================
    if (age < 1.25) {
        static Float: velocity[3]
        pev(entity, pev_velocity, velocity)
        if (velocity[0] != 0.0 || velocity[1] != 0.0 || velocity[2] != 0.0) {
            xs_vec_mul_scalar(velocity, 0.87, velocity)
            set_pev(entity, pev_velocity, velocity)
        }

        if (scale < targetScale) {
            scale += (targetScale - scale) * 0.17
            if (scale > targetScale)
                scale = targetScale
            set_pev(entity, pev_scale, scale)
        }
    } else {
        // Normal mature cloud: ease scale back if displaced by bullets
        if (scale < targetScale) {
            scale += (targetScale - scale) * 0.14
            if (scale > targetScale)
                scale = targetScale
            set_pev(entity, pev_scale, scale)
        }
    }

    // Dense 100% Solid Opacity Curve (Dissipates in final 3.5s)
    if (remainingTime > 3.5) {
        set_pev(entity, pev_renderamt, 255.0)
    } else if (remainingTime > 0.0) {
        new Float: fadeRatio = remainingTime / 3.5
        set_pev(entity, pev_renderamt, 255.0 * fadeRatio)
    } else {
        set_pev(entity, pev_renderamt, 0.0)
        set_pev(entity, pev_effects, EF_NODRAW)
        set_pev(entity, pev_flags, pev(entity, pev_flags) | FL_KILLME)
        #if (defined DEBUG)
            entityCount(-1)
        #endif
        return
    }

    const Float: thinkFreq = 0.05
    set_pev(entity, pev_nextthink, gametime + thinkFreq)
}

static CreateGasSmoke(const Float: origin[3], const Float: velocity[3],
                    const Float: color[4], bool: insideCloud) {

    // Initial scale starts compact (~1.7 to 2.1) to allow the CS2 mushroom bloom animation
    new Float: flInitialScale = random_float(1.7, 2.1)
    new Float: flTargetScale = random_float(3.85, 4.05) // Exact +15% size from 3.4

    new entity = CPartSmokeGrenade_Create(
        .origin = origin,
        .velocity = velocity,
        .model = g_sprFile,
        .scale = flInitialScale,
        .color = color
    )

    static Float: avelocity[3]
    new Float: gametime = get_gametime()
    new Float: dieTime = gametime + amx_smokegren_lifetime

    const Float: scaleFactor = 1.35
    const Float: maxRotateVelocity = 7.0

    if (insideCloud) {
        avelocity[2] = random_float(-(maxRotateVelocity / scaleFactor), (maxRotateVelocity / scaleFactor))
        set_pev(entity, _pev_targetScale, flTargetScale)
        set_pev(entity, _pev_dieTime, dieTime)
    } else {
        avelocity[2] = random_float(-maxRotateVelocity, maxRotateVelocity)
        set_pev(entity, _pev_targetScale, flTargetScale)
        set_pev(entity, _pev_dieTime, dieTime)
    }

    set_pev(entity, _pev_spawnInside, insideCloud)
    set_pev(entity, pev_avelocity, avelocity)
    set_pev(entity, pev_nextthink, gametime + 0.05)

    return entity
}

static CreateSmokePop(const Float: origin[3], Float: color[4]) {
    new Float: step = 360.0 / amx_smokegren_pieces

    static Float: angles[3]
    static Float: vForward[3], Float: vRight[3], Float: vUp[3]

    for (new Float: angleStep = 0.0; angleStep < 360.0; angleStep += step) {
        angles[XS_YAW] += angleStep

        engfunc(EngFunc_AngleVectors, angles, vForward, vRight, vUp)
        xs_vec_normalize(vForward, vForward)

        static Float: velocity[3]
        for (new i; i < sizeof(velocity); i++) {
            velocity[i] = (vForward[i] * 52.0) + (vUp[i] * 22.0)
        }

        CreateGasSmoke(origin, velocity, color, .insideCloud = false)
    }
}

static CreateGasInside(const Float: origin[3], Float: color[4]) {
    // 1. Center Core Puffs (3 vertical heights: 10, 28, 48) with slight upward balloon drift
    new Float: centerPos[3]
    static const Float: flVerticalHeights[3] = { 10.0, 28.0, 48.0 }
    for(new h = 0; h < 3; h++) {
        centerPos = origin
        centerPos[2] += flVerticalHeights[h]
        new Float: vCoreVel[3] = { 0.0, 0.0, 14.0 }
        CreateGasSmoke(centerPos, vCoreVel, color, .insideCloud = true)
    }

    // 2. Inner Ring (Radius 19 units: 6 points at z + 20) with outward bloom velocity
    static Float: vAngles[3], Float: vForward[3], Float: vRight[3], Float: vUp[3]
    new Float: stepInner = 360.0 / 6.0
    for (new Float: fAngle = 0.0; fAngle < 360.0; fAngle += stepInner) {
        vAngles[XS_YAW] = fAngle
        engfunc(EngFunc_AngleVectors, vAngles, vForward, vRight, vUp)
        xs_vec_normalize(vForward, vForward)

        new Float: pos[3], Float: vel[3]
        pos[0] = origin[0] + (vForward[0] * 12.0)
        pos[1] = origin[1] + (vForward[1] * 12.0)
        pos[2] = origin[2] + 20.0

        vel[0] = vForward[0] * 18.0
        vel[1] = vForward[1] * 18.0
        vel[2] = 8.0

        CreateGasSmoke(pos, vel, color, .insideCloud = true)
    }

    // 3. Perimeter Ring (Radius 34 units: 8 points at z + 26) with outward bloom velocity
    new Float: stepMid = 360.0 / 8.0
    for (new Float: fAngle = 0.0; fAngle < 360.0; fAngle += stepMid) {
        vAngles[XS_YAW] = fAngle + (stepMid * 0.5)
        engfunc(EngFunc_AngleVectors, vAngles, vForward, vRight, vUp)
        xs_vec_normalize(vForward, vForward)

        new Float: pos[3], Float: vel[3]
        pos[0] = origin[0] + (vForward[0] * 18.0)
        pos[1] = origin[1] + (vForward[1] * 18.0)
        pos[2] = origin[2] + 26.0

        vel[0] = vForward[0] * 32.0
        vel[1] = vForward[1] * 32.0
        vel[2] = 10.0

        CreateGasSmoke(pos, vel, color, .insideCloud = true)
    }
}

static Create_ConVars(const bool: createConfigFile = true) {
    bind_pcvar_num(
        create_cvar(
            "amx_smokegren_replacemode", "2",
            .has_min = true, .min_val = 0.0,
            .has_max = true, .max_val = 3.0,
            .description = "Replacement method. ^n\
                            0 - disabled (does not change client smoke); ^n\
                            1 - main cloud on over client smoke cloud; ^n\
                            2 - main cloud + volumetric pop (dense & natural); ^n\
                            3 - fully recreated (2x load)."
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

    bind_pcvar_float(
        create_cvar(
            "amx_smokegren_pieces", "8",
            .has_min = true, .min_val = 2.0,
            .has_max = true, .max_val = 16.0,
            .description = "Number of smoke particles for one smoke cloud."
        ),
        amx_smokegren_pieces
    )

    hook_cvar_change(
        create_cvar(
            "amx_smokegren_color", "255 255 255 255",
            .description = "The color of the smoke cloud is in the format [R G B A]. ^n\
                            `-1 -1 -1` - random color.^n\
                            `A` - is the opacity (transparency)"
        ),
        "CVarChange_amx_smokegren_color"
    )
    CVarChange_amx_smokegren_color(0, "", "255 255 255 255")

    bind_pcvar_float(
        create_cvar(
            "amx_smokegren_lifetime", "20.0",
            .has_min = true, .min_val = 6.0,
            .has_max = true, .max_val = 60.0,
            .description = "Smoke cloud lifetime (in seconds)."
        ),
        amx_smokegren_lifetime
    )

    if (createConfigFile) {
        AutoExecConfig()
    }
}

/**
 * Parses a color buffer into an array of RGBA values.
 *
 * This function parses a color buffer (e.g., "255 0 0 128") into an array of RGBA values.
 *
 * @param buffer    The color buffer to parse.
 * @return          Returns an array of RGBA values [R, G, B, A].
 */
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

static stock entityCount(const add = 0) {
    static count
    count += add

    return count
}


// ============================================================================
// 100% OPAQUE ANTI-SEE-THROUGH RAYCAST OCCLUSION & INSIDE-SMOKE SCREEN BLINDING
// ============================================================================

stock Float:DistancePointToSegment(const Float:p[3], const Float:a[3], const Float:b[3]) {
    static Float:ab[3], Float:ap[3]
    xs_vec_sub(b, a, ab)
    xs_vec_sub(p, a, ap)

    new Float:abLenSq = xs_vec_dot(ab, ab)
    if (abLenSq <= 0.0)
        return get_distance_f(p, a)

    new Float:t = xs_vec_dot(ap, ab) / abLenSq
    t = floatclamp(t, 0.0, 1.0)

    static Float:closest[3]
    closest[0] = a[0] + (ab[0] * t)
    closest[1] = a[1] + (ab[1] * t)
    closest[2] = a[2] + (ab[2] * t)

    return get_distance_f(p, closest)
}

stock bool:DoesSegmentIntersectSphere(const Float:p1[3], const Float:p2[3], const Float:center[3], const Float:radius) {
    static Float:d[3], Float:m[3]
    xs_vec_sub(p2, p1, d)
    xs_vec_sub(p1, center, m)

    new Float:dist = xs_vec_len(d)
    new Float:c = xs_vec_dot(m, m) - (radius * radius)

    if (c <= 0.0) {
        // Host (p1) is inside the smoke cloud:
        // Allow close-quarter combat if enemy is near (< 120 units)
        if (dist < 120.0)
            return false
        return true // Far enemy is blocked by dense smoke fog
    }

    new Float:b = xs_vec_dot(m, d)
    if (b > 0.0)
        return false // Sphere is behind the ray

    new Float:a = xs_vec_dot(d, d)
    if (a == 0.0)
        return false

    new Float:discr = (b * b) - (a * c)
    if (discr < 0.0)
        return false // Ray misses sphere completely

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

    // In CS: 1 = Terrorist, 2 = CT. Never block teammates!
    if (get_user_team(ent) == get_user_team(host))
        return FMRES_IGNORED

    static Float: vHostEye[3], Float: vHostOrigin[3], Float: vHostViewOfs[3]
    pev(host, pev_origin, vHostOrigin)
    pev(host, pev_view_ofs, vHostViewOfs)
    xs_vec_add(vHostOrigin, vHostViewOfs, vHostEye)

    static Float: vTargetOrigin[3]
    pev(ent, pev_origin, vTargetOrigin)
    vTargetOrigin[2] += 12.0 // Center of chest

    new Float: gametime = get_gametime()

    // 1. CS2-Style Bullet Tunnel Peeking:
    // If a bullet recently pierced through the smoke near the enemy, reveal them for that split second!
    for (new t = 0; t < MAX_BULLET_TUNNELS; t++) {
        if (gametime < g_fTunnelExpire[t]) {
            if (DistancePointToSegment(vTargetOrigin, g_vecTunnelSrc[t], g_vecTunnelEnd[t]) < 44.0) {
                return FMRES_IGNORED
            }
        }
    }

    // 2. Smoke Occlusion Spheres
    const Float: smokeRadius = 132.0

    for (new i = 0; i < g_iActiveSmokeCount; i++) {
        if (gametime > g_fSmokeExpireTime[i])
            continue

        // If this smoke cloud was recently cleaved by an HE Grenade, line of sight is 100% open!
        if (gametime < g_fSmokeClearedUntil[i])
            continue

        if (DoesSegmentIntersectSphere(vHostEye, vTargetOrigin, g_vecActiveSmokes[i], smokeRadius)) {
            // Block enemy model rendering completely - 100% impenetrable anti-see-through!
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
    const Float: insideRadius = 98.0 // +15% from 88.0

    for (new p = 1; p <= MaxClients; p++) {
        if (!is_user_connected(p) || !is_user_alive(p)) {
            g_bInsideSmoke[p] = false
            continue
        }

        pev(p, pev_origin, pOrigin)
        new bool: bIsInside = false

        for (new i = 0; i < g_iActiveSmokeCount; i++) {
            // If smoke is currently cleaved by HE blast, don't blind the player with fog
            if (gametime < g_fSmokeClearedUntil[i])
                continue

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
    if (!id || !is_user_connected(id))
        return

    message_begin(MSG_ONE_UNRELIABLE, g_iMsgScreenFade, _, id)
    if (bInside) {
        // Realistic volumetric white misty fog (dense atmosphere, but NOT 100% pitch-white blinded)
        // Player can see weapon model, crosshair, and immediately adjacent floor/walls
        write_short(1 << 12)        // Duration (1.0s)
        write_short(1 << 12)        // Hold time
        write_short(0x0004)         // FFADE_STAYOUT
        write_byte(245)             // R (White)
        write_byte(245)             // G (White)
        write_byte(245)             // B (White)
        write_byte(192)             // Alpha (75% opacity - balanced misty fog!)
    } else {
        // Clear fade smoothly
        write_short(1 << 11)        // Duration (0.5s)
        write_short(0)              // Hold time
        write_short(0x0001)         // FFADE_IN
        write_byte(245)             // R
        write_byte(245)             // G
        write_byte(245)             // B
        write_byte(0)               // Alpha
    }
    message_end()
}
