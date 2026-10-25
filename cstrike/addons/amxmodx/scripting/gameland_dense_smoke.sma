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
    _pev_spawnInside    = pev_iuser1,
    _pev_popCreated     = pev_iuser2,

    _pev_targetScale    = pev_fuser2,
    _pev_dieTime        = pev_fuser3,
    _pev_timeCreated    = pev_fuser4,
}

static        amx_smokegren_replacemode
static        amx_smokegren_fix_waterrender
static Float: amx_smokegren_color[4]
static Float: amx_smokegren_pieces
static Float: amx_smokegren_lifetime

#define MAX_ACTIVE_SMOKES 20
static Float: g_vecActiveSmokes[MAX_ACTIVE_SMOKES][3]
static Float: g_fSmokeExpireTime[MAX_ACTIVE_SMOKES]
static g_iActiveSmokeCount = 0

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
    RegisterHam(Ham_Think, g_baseClassname, "CNullEntity_Think", .Post = false)

    g_iMsgScreenFade = get_user_msgid("ScreenFade")
    set_task(0.1, "Task_SmokePlayerCheck", .flags = "b")

    Create_ConVars(.createConfigFile = true)

    if (amx_smokegren_fix_waterrender)
        ChangeRenderMode("func_water", kRenderNormal)
}

public client_putinserver(id) {
    if (id >= 1 && id <= 32 && is_user_connected(id) && !is_user_bot(id)) {
        // Enforce true 3D volumetric smoke rendering on client engine (fastsprites 0 = 3D volumetric, NOT flat 2D)
        client_cmd(id, "fastsprites 0")
        client_cmd(id, "max_smokepuffs 300")
    }
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
    arrayset(g_bInsideSmoke, false, sizeof(g_bInsideSmoke))

    new entity = MaxClients
    while ((entity = engfunc(EngFunc_FindEntityByString, entity, "classname", g_className))) {
        set_pev(entity, pev_flags, pev(entity, pev_flags) | FL_KILLME)

        #if (defined DEBUG)
            entityCount(-1)
        #endif
    }
}

static CPartSmokeGrenade_Create(const Float: origin[3], const Float: velocity[3],
                        const model[], const Float: scale,
                        const Float: color[4] = { 255.0, 255.0, 255.0, 242.0 }) {

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

    // ------------------------------------------------------------------------
    // CS2-Style Volumetric Bloom / Billowing Animation Phase (First 1.25s)
    // ------------------------------------------------------------------------
    if (age < 1.25) {
        // Drag deceleration on outward velocity (creates mushrooming volumetric bloom)
        static Float: velocity[3]
        pev(entity, pev_velocity, velocity)
        if (velocity[0] != 0.0 || velocity[1] != 0.0 || velocity[2] != 0.0) {
            xs_vec_mul_scalar(velocity, 0.87, velocity)
            set_pev(entity, pev_velocity, velocity)
        }

        // Smooth exponential easing expansion: fast initial blossom, then gentle cushion
        if (scale < targetScale) {
            scale += (targetScale - scale) * 0.17
            if (scale > targetScale)
                scale = targetScale
            set_pev(entity, pev_scale, scale)
        }
    } else {
        // Mature cloud: ensure scale has reached full target
        if (scale < targetScale) {
            set_pev(entity, pev_scale, targetScale)
        }
    }

    // Dense Opacity Curve with 5% natural translucency (242.0 / 255.0):
    // Softens the over-solid chalky look while keeping perfect volumetric density!
    // Dissipates smoothly only in the final 3.5 seconds!
    if (remainingTime > 3.5) {
        set_pev(entity, pev_renderamt, 242.0)
    } else if (remainingTime > 0.0) {
        new Float: fadeRatio = remainingTime / 3.5
        set_pev(entity, pev_renderamt, 242.0 * fadeRatio)
    } else {
        // Lifetime expired: Cleanly remove particle
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

    // Initial scale starts compact (~1.6 to 2.1) to allow the volumetric bloom expansion
    new Float: flInitialScale = random_float(1.6, 2.1)
    new Float: flTargetScale = random_float(3.75, 4.15) // Natural tournament scale

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

    const Float: maxRotateVelocity = 12.0

    // Random rotational velocity gives continuous 3D angular movement so particles never look like flat static discs
    avelocity[0] = 0.0
    avelocity[1] = 0.0
    avelocity[2] = random_float(-maxRotateVelocity, maxRotateVelocity)

    set_pev(entity, _pev_targetScale, flTargetScale)
    set_pev(entity, _pev_dieTime, dieTime)
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
        for (new i = 0; i < 3; i++) {
            velocity[i] = (vForward[i] * 46.0) + (vUp[i] * 18.0)
        }

        CreateGasSmoke(origin, velocity, color, .insideCloud = false)
    }
}

static CreateGasInside(const Float: origin[3], Float: color[4]) {
    // ========================================================================
    // TRUE 3D VOLUMETRIC SPHERICAL SMOKE CLOUD (6-Tier Spatial Geometry)
    // Distributed in 3D (X, Y, Z) so the smoke has spherical depth from all angles
    // ========================================================================

    // 1. Vertical Spine (Central Core Column - 5 puffs spanning z: 6 to 86)
    static const Float: flSpineHeights[5] = { 6.0, 22.0, 42.0, 64.0, 86.0 }
    for (new h = 0; h < 5; h++) {
        new Float: pos[3]
        pos[0] = origin[0] + random_float(-4.0, 4.0)
        pos[1] = origin[1] + random_float(-4.0, 4.0)
        pos[2] = origin[2] + flSpineHeights[h]

        new Float: vel[3]
        vel[0] = random_float(-4.0, 4.0)
        vel[1] = random_float(-4.0, 4.0)
        vel[2] = 9.0 + random_float(0.0, 4.0)

        CreateGasSmoke(pos, vel, color, .insideCloud = true)
    }

    static Float: vAngles[3], Float: vForward[3], Float: vRight[3], Float: vUp[3]

    // 2. Base Tier (6 puffs, hugging ground at z + 12, radius ~20 units)
    new Float: stepBase = 360.0 / 6.0
    for (new Float: fAngle = 0.0; fAngle < 360.0; fAngle += stepBase) {
        vAngles[XS_YAW] = fAngle
        engfunc(EngFunc_AngleVectors, vAngles, vForward, vRight, vUp)
        xs_vec_normalize(vForward, vForward)

        new Float: pos[3], Float: vel[3]
        pos[0] = origin[0] + (vForward[0] * 19.0)
        pos[1] = origin[1] + (vForward[1] * 19.0)
        pos[2] = origin[2] + 12.0

        vel[0] = vForward[0] * 15.0
        vel[1] = vForward[1] * 15.0
        vel[2] = 4.0

        CreateGasSmoke(pos, vel, color, .insideCloud = true)
    }

    // 3. Lower Dome Tier (8 puffs at z + 26, radius ~28 units)
    new Float: stepLower = 360.0 / 8.0
    for (new Float: fAngle = 0.0; fAngle < 360.0; fAngle += stepLower) {
        vAngles[XS_YAW] = fAngle + (stepLower * 0.25)
        engfunc(EngFunc_AngleVectors, vAngles, vForward, vRight, vUp)
        xs_vec_normalize(vForward, vForward)

        new Float: pos[3], Float: vel[3]
        pos[0] = origin[0] + (vForward[0] * 27.0)
        pos[1] = origin[1] + (vForward[1] * 27.0)
        pos[2] = origin[2] + 26.0

        vel[0] = vForward[0] * 21.0
        vel[1] = vForward[1] * 21.0
        vel[2] = 7.5

        CreateGasSmoke(pos, vel, color, .insideCloud = true)
    }

    // 4. Mid Equator Tier (10 puffs, widest spherical cross-section at z + 44, radius ~36 units)
    new Float: stepEquator = 360.0 / 10.0
    for (new Float: fAngle = 0.0; fAngle < 360.0; fAngle += stepEquator) {
        vAngles[XS_YAW] = fAngle + (stepEquator * 0.5)
        engfunc(EngFunc_AngleVectors, vAngles, vForward, vRight, vUp)
        xs_vec_normalize(vForward, vForward)

        new Float: pos[3], Float: vel[3]
        pos[0] = origin[0] + (vForward[0] * 35.0)
        pos[1] = origin[1] + (vForward[1] * 35.0)
        pos[2] = origin[2] + 44.0

        vel[0] = vForward[0] * 27.0
        vel[1] = vForward[1] * 27.0
        vel[2] = 9.5

        CreateGasSmoke(pos, vel, color, .insideCloud = true)
    }

    // 5. Upper Dome Tier (8 puffs at z + 62, radius ~26 units)
    new Float: stepUpper = 360.0 / 8.0
    for (new Float: fAngle = 0.0; fAngle < 360.0; fAngle += stepUpper) {
        vAngles[XS_YAW] = fAngle + (stepUpper * 0.75)
        engfunc(EngFunc_AngleVectors, vAngles, vForward, vRight, vUp)
        xs_vec_normalize(vForward, vForward)

        new Float: pos[3], Float: vel[3]
        pos[0] = origin[0] + (vForward[0] * 25.0)
        pos[1] = origin[1] + (vForward[1] * 25.0)
        pos[2] = origin[2] + 62.0

        vel[0] = vForward[0] * 19.0
        vel[1] = vForward[1] * 19.0
        vel[2] = 13.0

        CreateGasSmoke(pos, vel, color, .insideCloud = true)
    }

    // 6. Crown Tier (4 puffs at z + 78, radius ~14 units)
    new Float: stepCrown = 360.0 / 4.0
    for (new Float: fAngle = 0.0; fAngle < 360.0; fAngle += stepCrown) {
        vAngles[XS_YAW] = fAngle + 45.0
        engfunc(EngFunc_AngleVectors, vAngles, vForward, vRight, vUp)
        xs_vec_normalize(vForward, vForward)

        new Float: pos[3], Float: vel[3]
        pos[0] = origin[0] + (vForward[0] * 13.0)
        pos[1] = origin[1] + (vForward[1] * 13.0)
        pos[2] = origin[2] + 78.0

        vel[0] = vForward[0] * 11.0
        vel[1] = vForward[1] * 11.0
        vel[2] = 16.5

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
            "amx_smokegren_color", "255 255 255 242",
            .description = "The color of the smoke cloud is in the format [R G B A]. ^n\
                            `-1 -1 -1` - random color.^n\
                            `A` - is the opacity (transparency)"
        ),
        "CVarChange_amx_smokegren_color"
    )
    CVarChange_amx_smokegren_color(0, "", "255 255 255 242")

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
// INSIDE-SMOKE ATMOSPHERIC MIST SCREENFADE (No artificial model hiding!)
// ============================================================================

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
    const Float: insideRadius = 96.0 // Balanced -5% size adjustment

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
        write_byte(170)             // Alpha (~67% opacity - soft, natural white misty fog)
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
